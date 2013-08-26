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
      puts "Never mind call '#{m} #{args}'. ON #{@name || self.inspect}"
      self
    end

    def self.method_missing(m, *args, &block)
      puts "Never mind class call '#{m} #{args}'. ON #{@name || self.inspect}"
      self
    end

    def initialize(name=nil, *args)
      @name = name
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
    if name == "network_win" then
      n = NeverMind.new name
#      n.define_method : do
#
#      end
    else
      NeverMind.new name
    end
  end

  def main_loop
    # and this is the program flow entry point,
    # basic idea is to 'proceed with actions
    # as would user do' based on parameters passed
    # through kernel command line
    puts "this is the main loop"
  end

  def register_handler(signal, handler)
    super(signal, handler)
    puts "#{handler} for #{signal} action registered"
  end

  def initialize dry=nil
    super() unless dry
    @builder = NeverMind.new
  end
end

end # UI
end # VirtP2V
