# Copyright (C) 2013-2014 Red Hat Inc.
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

require('gtk2') if !(Kernel.const_defined?(:NOGUI) && NOGUI == true)

if Kernel.const_defined?(:NOGUI) && NOGUI == true
  module VirtP2V
  module UI
    class NeverMind
      def method_missing(m, *args, &block)
        self
      end

      def self.method_missing(m, *args, &block)
        self
      end

      def eigen
        class << self
          self
        end
      end

      def initialize(main = nil, name=nil, *args)
        @name = name
        @main = main
      end
    end
  end
  end

  module Gtk
    Builder = VirtP2V::UI::NeverMind
    STATE_NORMAL = 0
    SELECTION_SINGLE = 1
    TreeRowReference = VirtP2V::UI::NeverMind

    def Gtk.timeout_add(timeout, &block)
      while true
        sleep(timeout/1000.0)
        block.call
      end
    end

    def Gtk.main_quit
      exit(0)
    end
  end

  module Gdk
    Color = VirtP2V::UI::NeverMind
    Cursor = VirtP2V::UI::NeverMind
    Cursor::Type = VirtP2V::UI::NeverMind
    Cursor::Type::X_CURSOR = VirtP2V::UI::NeverMind
  end

  module VirtP2V
  module UI
    class SomeListW < NeverMind
      def append(*args)
        @items ||= []
        @items << []
        self
      end

      def _items
        @items ||= []
        @items
      end

      def _select(idx)
        @idx = idx
      end

      def _selection
        @idx ||= 0
        @idx
      end

      def []=(idx, item)
        @items.last[idx] = item
        self
      end

      def clear
        @items.clear
      end

      def _set_checked(dev_name, check)
        @items.each do |item|
          if item[VirtP2V::UI::Convert::CONVERT_FIXED_DEVICE] == dev_name then
            item[VirtP2V::UI::Convert::CONVERT_FIXED_CONVERT] = check
          end
        end
      end

      def _uncheck_all
        @items.each do |item|
          item[VirtP2V::UI::Convert::CONVERT_FIXED_CONVERT] = false
        end
      end

      def each(&block)
        @items.each do |item|
          # block accepts three params:
          # model, path, iter
          # since we know nothing about model and path
          # we'll fill only item as iter
          block.call(nil, nil, item)
        end
      end

      def get_iter(path)
        self
      end
    end

    class ConvertProfileW < NeverMind
      def active_iter
        cpl = @main.get_object("convert_profile_list")
        cpl._items[cpl._selection]
      end
    end

    class NetworkDeviceListViewW < NeverMind
      def selection
        self
      end

      def selected
        # TODO: this needs a proper selection
        # now it's only for a testing purpouse
        # but later we need to reflect reality
        # and not blindly return first device
        @main.get_object("network_device_list")._items.first
      end
    end

    class ConnectErrorW < NeverMind
      def text
        @text || ''
      end

      def text=(str)
        @text = str
        unless str == ''
          puts "Error connecting: '#{str}'"
          puts "Giving up."
          exit(3)
        end
      end
    end

    class ConvertStatusW < NeverMind
      def text
        @text || ''
      end

      def text=(str)
        @text = str
        puts "conversion status changed to: '#{str}'"
        STDOUT.flush
        if str =~ /failure|error|no\ root/i
          puts "Giving up."
          exit(4)
        end
      end
    end

    class SomeTextFieldW < NeverMind
      def text
        @text || ""
      end

      def text=(str)
        @text = str
      end

      def secondary_icon_tooltip_text=(str)
        puts "Error in '#{@name}': '#{str}'"
      end
    end

    def self.widget_class_factory(widget_name)
      widgets = Hash[ *(["network_device_list",
            "convert_profile_list", "convert_network_list",
            "convert_fixed_list", "convert_removable_list"].flat_map do |_l|
              [_l, SomeListW]
            end) ]
      .merge(
      Hash[ *(["server_hostname", "server_username", "server_password",
              "convert_name", "convert_cpus", "convert_memory",
              "ip_manual", "ip_address", "ip_prefix", "ip_gateway",
              "ip_dns", "server_hostname", "server_username",
              "server_password"].flat_map do |_l|
                [_l, SomeTextFieldW]
              end) ]
            ).merge({
          "convert_profile" => ConvertProfileW,
          "network_device_list_view" => NetworkDeviceListViewW,
          "convert_status" => ConvertStatusW,
          "connect_error" => ConnectErrorW
      })

      if widgets.has_key? widget_name
        widgets[widget_name]
      else
        NeverMind
      end
    end
  end
  end
end

