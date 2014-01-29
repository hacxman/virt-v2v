# Copyright (C) 2013 Red Hat Inc.
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

require 'virt-p2v/ui/main'
require 'virt-p2v/ui/network'
require 'virt-p2v/ui/connect'
require 'virt-p2v/ui/convert'
require 'virt-p2v/ui/success'

require 'virt-p2v/converter'
require 'virt-p2v/netdevice'

WD = File.expand_path File.dirname(__FILE__)
CMDLINE_TEST_PARAMS = File.join(WD, "cmdline_test_params")
CMDLINE_DEFAULT = File.join(WD, "cmdline_default")

class TestNewMainIntegration < MiniTest::Unit::TestCase
  def setup
  end

  def make_converter
    cvt = VirtP2V::UI::NeverMind.new
    con = VirtP2V::UI::NeverMind.new
    VirtP2V::Connection.send(:define_method, :connect) do |&block|
      p 'connect called'
      block.call(true)
      p 'lala'
      cvt.run_on_connection
    end
    con.eigen.send(:define_method, :connected?) do
      p ':connected?'
      true
    end
    con.eigen.send(:define_method, :on_connect) do |&block|
      p ':on_connect'
      # block takes 'cb' as argument
      block.call(VirtP2V::UI::NeverMind.new)
    end
    con.eigen.send(:define_method, :list_profiles) do |&block|
      p ':list_profiles'
      block.call(['fakeprofile'])
    end
    cvt.eigen.send(:define_method, :name) do
      'name'
    end
    cvt.eigen.send(:define_method, :cpus) do
      '3'
    end
    cvt.eigen.send(:define_method, :memory) do
      1
    end
    cvt.eigen.send(:define_method, :connection) do
      p ':connection'
      con
    end
    cvt.eigen.send(:define_method, :convert) do |status, progress, &block|
      p 'called convert on fake converter'
      # block takes one argument - result
      # call it and pretend successful conversion
      block.call(true)
    end
    cvt.eigen.send(:define_method, :on_connection) do |&block|
      p ":on_connection" # #{caller.class.to_s}"
      # block takes one argument - conn
      @on_con = block
      run_on_connection
    end
    cvt.eigen.send(:define_method, :run_on_connection) do
      p ':run_on_connection'
      # block takes one argument - conn
      @on_con.call(con)
    end

    con.eigen.send(:define_method, :connect) do |&block|
      p ':connect'
      # block takes 'result' as argument
      block.call(true)
    end
    cvt
  end

  def test_toothlees_launch
    # lets try to start up thing in a similar
    # way as usual
    converter = make_converter
    # Initialise the wizard UI
    ui = VirtP2V::UI::NewMain.new
    ui.class.send(:define_method, :cmdline_filename) do
      CMDLINE_TEST_PARAMS
    end

    # Initialize wizard pages
    VirtP2V::UI::Network.init(ui)
    VirtP2V::UI::Connect.init(ui, converter)
    VirtP2V::UI::Convert.init(ui, converter)
    VirtP2V::UI::Success.init(ui)

    ui.show
    begin
      ui.main_loop
    rescue SystemExit
    end
  end
end

#class TestWithConverterNewMainIntegration < TestNewMainIntegration
#  def setup
#  end
#
#  def make_converter
#    VirtP2V::Converter.new
#  end
#
#  def test_blockdevice_lookup
#    devs = VirtP2V::FixedBlockDevice.all_devices
#    refute_empty devs
#  end
#
#  def test_launch_with_converter
#   test_toothlees_launch
#  end
#end
