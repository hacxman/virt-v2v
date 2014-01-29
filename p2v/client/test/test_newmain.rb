# Copyright (C) 2013, 2014 Red Hat Inc.
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

require 'minitest/autorun'
NOGUI = true
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


