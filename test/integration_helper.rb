# frozen_string_literal: true
require 'bundler/setup'
require 'mysql2'
require 'minitest/autorun'

if !defined?(Minitest::Test)
  Minitest::Test = MiniTest::Unit::TestCase
end

require_relative 'boot_mysql_env'

def assert_ro(cx, str, bool)
  expected = bool ? 1 : 0
  assert_equal expected, cx.query("select @@read_only as ro").first['ro'], "#{str} is #{bool ? 'read-write' : 'read-only'} but I expected otherwise!"
end

def master_cut_script
  File.expand_path(File.dirname(__FILE__)) + "/../bin/master_cut"
end
