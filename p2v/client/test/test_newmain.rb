require 'minitest/autorun'
require 'virt-p2v/ui/main'

WD = File.expand_path File.dirname(__FILE__)
CMDLINE_TEST = File.join(WD, "cmdline_test")
CMDLINE_DEFAULT = File.join(WD, "cmdline_default")
CMDLINE_TEST_PARAMS = File.join(WD, "cmdline_test_params")
CMDLINE_TEST_PARAMS_BAD = File.join(WD, "cmdline_test_params_bad")
CMDLINE_TEST_PARAMS_OPTIONAL = File.join(WD, "cmdline_test_params_optional")

class TestNewMainDry < MiniTest::Unit::TestCase
  def setup
    @nm = VirtP2V::UI::NewMain.new dry=true
  end

  def test_cmdline_parse_d
    params = @nm.parse_cmdline(CMDLINE_DEFAULT)
    assert_equal params, {}
  end

  def test_cmdline_parse_t
    params = @nm.parse_cmdline(CMDLINE_TEST)
    assert_equal params, {"test" => "foo"}
  end

  def test_cmdline_parse_noval
    params = @nm.parse_cmdline
    assert_equal params, {}
  end
end

class TestNewMainValidateParams < MiniTest::Unit::TestCase
  def setup
    @nm = VirtP2V::UI::NewMain.new dry=true
  end

  def test_validate_params_ok
    params = @nm.parse_cmdline(CMDLINE_TEST_PARAMS)
    assert @nm.validate_params(params)
  end

  def test_validate_params_opt
    params = @nm.parse_cmdline(CMDLINE_TEST_PARAMS_OPTIONAL)
    assert @nm.validate_params(params)
  end

  def test_validate_params_bad
    params = @nm.parse_cmdline(CMDLINE_TEST_PARAMS_BAD)
    refute @nm.validate_params(params)
  end
end

class TestNewMain < TestNewMainDry
  def setup
    @nm = VirtP2V::UI::NewMain.new
  end
end


