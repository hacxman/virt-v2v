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
end

