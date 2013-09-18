# Copyright (C) 2011 Red Hat Inc.
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

#require 'gtk2'
#require 'virt-p2v/gtk-queue'

module VirtP2V
module UI
  class NeverMind
    def method_missing(m, *args, &block)
      _args = args.map {|_a| _a.class == NeverMind ? "NeverMind:"+
        self.__id__.to_s : _a}
      puts "Never mind call '#{m} #{_args}'. ON #{@name ||
        ("NeverMind:"+self.__id__.to_s)}"
      self
    end

    def self.method_missing(m, *args, &block)
      _args = args.map {|_a| _a.class == NeverMind ? "NeverMind:"+
        self.__id__.to_s : _a}
      #puts "Never mind class call '#{m} #{_args}'. ON #{@name || self.inspect}"
      puts "Never mind call '#{m} #{_args}'. ON #{@name ||
        ("NeverMind:"+self.__id__.to_s)}"
      self
    end

    def initialize(main = nil, name=nil, *args)
      @name = name
      @main = main
      puts "Hi, I'm #{@name || self.inspect}"
    end
  end
end
end

module Gtk
  Builder = VirtP2V::UI::NeverMind
  STATE_NORMAL = 0
  SELECTION_SINGLE = 1
  TreeRowReference = VirtP2V::UI::NeverMind

end

module Gdk
  Color = VirtP2V::UI::NeverMind
  Cursor = VirtP2V::UI::NeverMind
  Cursor::Type = VirtP2V::UI::NeverMind
  Cursor::Type::X_CURSOR = VirtP2V::UI::NeverMind
end

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

        p "trying to activate page #{name}"
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
      /p2v_([a-zA-Z0-9_]*)=([a-zA-Z0-9_]*)/ =~ c
      params.merge! $1 => $2 if $1
    end
    params
  end

  def get_object(name)
    # this is the entry point for returning our mocked
    # versions of gtk2 objects, very similar to what we'd
    # need to write tests
    puts "GET_OBJ #{name}"
    @gui_objects ||= {}
    @gui_objects[name] ||= if name == "network_device_list" then
      n = NeverMind.new self, name
      n.class.send(:define_method, :append) do |*args|
        @items ||= []
        @items << []
        self
      end
      n.class.send(:define_method, :_items) do
        #p @items
        @items
      end
      n.class.send(:define_method, :"[]=") do |idx, item|
        #p "called []= on #{name} with #{args}"
        @items.last[idx] = item
        #p @items
        self
      end
      n
    elsif name == "network_device_list_view"
      n = NeverMind.new self, name
      n.class.send(:define_method, :selection) do
        self
      end
      n.class.send(:define_method, :selected) do
        # TODO: this needs a proper selection
        # now it's only for a testing purpouse
        # but later we need to reflect reality
        # and not blindly return first device
        nejm = @main.get_object("network_device_list")._items.first
        p nejm
      end
      n
    elsif ["server_hostname", "server_username", "server_password",
            "convert_name", "convert_cpus", "convert_memory",
            "ip_manual", "ip_address", "ip_prefix", "ip_gateway",
            "ip_dns", "server_hostname", "server_username",
            "server_password"].any?{|m| m==name}
      # N.B. some of these are set by user
      p "GOTCHA, YOU'D LOVE TO GET #{name}"
      n = NeverMind.new self, name
      n.class.send(:define_method, :text) do
#        p "called text on #{name}"
        @text || ""
      end
      n.class.send(:define_method, :"text=") do |str|
        @text = str
        p "called text= #{str} on #{name}"
      end
#      p n
      n
    else
      NeverMind.new self, name
    end

    p "I'LL RETURN YOU #{@gui_objects[name].class}:#{@gui_objects[name].__id__} for #{name}"
    @gui_objects[name]
  end

  def main_loop
    # and this is the program flow entry point,
    # basic idea is to 'proceed with actions
    # as would user do' based on parameters passed
    # through kernel command line
    puts "this is the main loop"

    get_object("ip_manual").text=true
    get_object("ip_address").text="10.0.0.1"
    get_object("ip_prefix").text="24"
    get_object("ip_gateway").text="10.0.0.254"
    get_object("ip_dns").text="10.0.0.253"
    p "SO, THE IP IS #{get_object("ip_address").text}"
    @signal_handlers["ip_auto_toggled"].call
    @signal_handlers["ip_address_changed"].call
    @signal_handlers["ip_prefix_changed"].call
    @signal_handlers["ip_gateway_changed"].call
    @signal_handlers["ip_dns_changed"].call
    # send a synthetic event, UI would think that we made a selection
    VirtP2V::UI::Network.event(VirtP2V::UI::Network::EV_SELECTION, true)
    # aaaand CLICK!
    @signal_handlers["network_button_clicked"].call

    # register ourselves as listener on activated connection
    # as VirtP2V::UI:Netowork does
    VirtP2V::NetworkDevice.add_listener( lambda { |dev|
      p dev
      if dev.connected && dev.activated then
        p "we should now continue"
      end
    })

    # let's try to recieve some more of NMs signals
    session_bus = DBus::SystemBus.instance

    db_main = DBus::Main.new
    db_main << session_bus
    db_main.run

#    # TODO: this activation in NOT neccessary
#    # since it's done automatically in network module
#    # but well, not in "testing"
#    self.active_page='server_win'
#    get_object("server_hostname").text='localhost'
#    get_object("server_username").text='tak'
#    get_object("server_password").text='urcite'
#    @signal_handlers["server_hostname_changed"].call
#    @signal_handlers["server_username_changed"].call
#    @signal_handlers["server_password_changed"].call
#    @signal_handlers["connect_button_clicked"].call
#
#    # TODO: again, stupidly switch page and don't care about truth!
#    self.active_page='conversion_win'
#    p VirtP2V::UI::Connect.instance_variable_get(:@converter).connection.class

  end

  def register_handler(signal, handler)
    super(signal, handler)
    puts "#{handler} for #{signal} action registered"
  end

  def initialize dry=nil
    super() unless dry
    @builder = NeverMind.new self
  end
end

end # UI
end # VirtP2V
