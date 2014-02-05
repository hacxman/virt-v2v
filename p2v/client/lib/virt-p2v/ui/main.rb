# Copyright (C) 2011, 2013, 2014 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'virt-p2v/ui/gtk'
require 'virt-p2v/gtk-queue'

module VirtP2V
module UI

class Main
    def get_object(name)
        o = @builder.get_object(name)
        raise "Object #{name} not found in ui" unless o != nil

        return o
    end

    def show
        @builder.connect_signals { |signal|
            raise "No hander for signal #{signal}" \
                unless @signal_handlers.has_key?(signal)

            @signal_handlers[signal]
        }

        # Display the main window
        main = self.get_object('main_window')
        main.show_all()

        # Explicitly set a cursor
        # This doesn't seem to happen automatically when the client is started
        # from xinit, leaving the user with no visible cursor.
        main.window.cursor = Gdk::Cursor.new(Gdk::Cursor::Type::X_CURSOR)
    end

    def register_handler(signal, handler)
        @signal_handlers[signal] = handler
    end

    def main_loop
        Gtk.main_with_queue 100
    end

    def active_page=(name)
        raise "Attempt to activate non-existent page #{name}" \
            unless @pages.has_key?(name)

        page = @pages[name]

        @page_vbox = self.get_object('page_vbox') unless defined? @page_vbox
        @page_vbox.remove(@selected) if defined? @selected
        @page_vbox.add(page)
        @selected = page
    end

    def active_page
        return @selected
    end

    def quit
        Gtk.main_quit()
    end

    private

    def initialize
        @builder = Gtk::Builder.new()

        # Find the UI definition in $LOAD_PATH
        i = $LOAD_PATH.index { |path|
            File.exists?(path + '/virt-p2v/ui/p2v.ui')
        }
        @builder.add_from_file($LOAD_PATH[i] + '/virt-p2v/ui/p2v.ui')

        @signal_handlers = {}
        self.register_handler('gtk_main_quit', method(:quit))

        # Configure the Wizard page frame
        # Can't change these colours from glade for some reason
        self.get_object('title_background').
           modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#86ABD9'))
        self.get_object('page_frame').
           modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#86ABD9'))

        # Load all pages from glade
        @pages = {}
        [ 'network_win', 'server_win',
          'conversion_win', 'success_win' ].each { |name|
            page = self.get_object(name)

            child = page.children[0]
            page.remove(child)
            @pages[name] = child
        }

        # Set a default first page
        self.active_page = 'network_win'
    end
end


class NewMain < Main
  def parse_cmdline(filename = nil)
    filename ||= '/proc/cmdline'
    cmdline = open(filename) do |f|
      f.read.strip.split
    end
    params = {}
    cmdline.each do |c|
      /p2v_([a-zA-Z0-9_]*)=([a-zA-Z0-9_\.\,]*)/ =~ c
      params.merge! $1 => $2 if $1
    end
    params
  end

  def get_object(name)
    # this is the entry point for returning our mocked
    # versions of gtk2 objects, very similar to what we'd
    # need to write tests

    @gui_objects ||= {}
    @gui_objects[name] ||= VirtP2V::UI::widget_class_factory(name).new self, name
    @gui_objects[name]
  end

  def cmdline_filename
    '/proc/cmdline'
  end

  def main_loop
    # and this is the program flow entry point,
    # basic idea is to 'proceed with actions
    # as would user do' based on parameters passed
    # through kernel command line

    params = parse_cmdline(cmdline_filename)
    unless validate_params(params)
      if params.has_key?('server_password')
        params['server_password'] = '*' * params['server_password'].length
      end
      puts "Not enough command line parameters or some not entered. Exitting."
      puts "Params are: #{params.map {|k,v| "p2v_#{k}=#{v}"}.join(' ') }, " +
           "read from #{cmdline_filename}"
      puts "Expected params are: #{expected_param_keys.map{|p| "p2v_#{p}"}.
                                   join(', ')}."
      exit(1)
    end
    @cmd_params = params

    fill_and_click_network

    # register ourselves as listener on activated connection
    # as VirtP2V::UI:Netowork does
    VirtP2V::NetworkDevice.add_listener( lambda { |dev|
      puts "interface #{dev.name} #{dev.mac}: #{dev.state}"
      if dev.connected && dev.activated then
        puts "connection ready, connecting to p2v server"
        fill_and_click_connect
      end
    })

    # let's try to recieve some more of NMs signals
    Thread.new {
      session_bus = DBus::SystemBus.instance

      db_main = DBus::Main.new
      db_main << session_bus
      db_main.run
    }

    Gtk.main_with_queue 100
  end

  def expected_param_keys
      ['ip_manual', 'ip_address', 'ip_prefix', 'ip_gateway', 'ip_dns',
            'server_hostname', 'server_username', 'server_password',
            'convert_name', 'disks']
  end

  def is_param_optional?(name)
      ['ip_address', 'ip_prefix', 'ip_gateway', 'ip_dns'].include?(name)
  end

  def validate_params(params)
    expected_param_keys.each do |k|
#      p "validate_params: '#{k}', '#{params[k]}'"
      if (!is_param_optional?(k)) &&
         ((!params.has_key?(k)) || params[k].nil?)
        return false
      end
    end
    if params['ip_manual'] == 'true'
      params['ip_manual'] = true
    else
      params['ip_manual'] = false
    end
    true
  end

  def fill_widgets_from_params(names)
      names.each do |p|
        get_object(p).text = @cmd_params[p]
      end
  end

  def show_widgets_from_params(names)
      # a little debug helper
      names.each do |p|
        puts "#{p} is '#{get_object(p).text}'"
      end
  end

  def call_actions_by_name(names)
      names.each do |n|
        @signal_handlers[n].call
      end
  end

  def fill_and_click_network
      fill_widgets_from_params(["ip_manual", "ip_address", "ip_prefix",
                                "ip_gateway", "ip_dns"])

      if get_object("ip_manual").text == true ||
          get_object("ip_manual").text == "true"
        call_actions_by_name(["ip_auto_toggled"])
      else
        call_actions_by_name(["ip_address_changed",
         "ip_prefix_changed", "ip_gateway_changed", "ip_dns_changed"])
      end

      # send a synthetic event, UI would think that we made a selection
      VirtP2V::UI::Network.event(VirtP2V::UI::Network::EV_SELECTION, true)
      # aaaand CLICK!
      call_actions_by_name(["network_button_clicked"])
  end

  def fill_and_click_connect
      fill_widgets_from_params(["server_hostname", "server_username",
                                "server_password"])

      call_actions_by_name(["server_hostname_changed",
          "server_username_changed", "server_password_changed",
          "connect_button_clicked"])
  end

  def fill_and_click_convert
      fill_widgets_from_params(['convert_name'])

      get_object('convert_fixed_list')._uncheck_all
      @cmd_params['disks'].split(',').each do |_dev|
        get_object('convert_fixed_list')._set_checked(_dev, true)
      end

      call_actions_by_name(['convert_name_changed', 'convert_cpus_changed',
                           'convert_memory_changed', 'convert_profile_changed',
                           'convert_button_clicked'])
  end

  def active_page=(name)
    puts "setting active page to #{name}"
    STDOUT.flush
    super(name)
    if name == 'conversion_win'
      fill_and_click_convert
    elsif name == 'success_win'
      call_actions_by_name(['poweroff_button_clicked'])
    end
  end

  def register_handler(signal, handler)
    super(signal, handler)
  end

  def initialize dry=nil
    super() unless dry
    @builder = NeverMind.new self
  end
end

end # UI
end # VirtP2V
