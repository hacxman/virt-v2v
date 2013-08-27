require 'minitest/autorun'

require 'virt-p2v/ui/main'
require 'virt-p2v/ui/network'
require 'virt-p2v/ui/connect'
require 'virt-p2v/ui/convert'
require 'virt-p2v/ui/success'

require 'virt-p2v/converter'
require 'virt-p2v/netdevice'

class TestNewMainIntegration < MiniTest::Unit::TestCase
  def setup
  end

  def make_converter
    VirtP2V::UI::NeverMind.new
  end

  def test_toothlees_launch
    # lets try to start up thing in a similar
    # way as usual
    converter = make_converter
    # Initialise the wizard UI
    ui = VirtP2V::UI::NewMain.new

    # Initialize wizard pages
    VirtP2V::UI::Network.init(ui)
    VirtP2V::UI::Connect.init(ui, converter)
    VirtP2V::UI::Convert.init(ui, converter)
    VirtP2V::UI::Success.init(ui)

    ui.show
    ui.main_loop
  end
end

class TestWithConverterNewMainIntegration < TestNewMainIntegration
  def setup
  end

  def make_converter
    VirtP2V::Converter.new
  end
end
