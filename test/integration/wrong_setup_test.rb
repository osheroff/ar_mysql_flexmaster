# frozen_string_literal: true
require_relative "../integration_helper"
class WrongSetupTest < Minitest::Test
  def assert_script_failed
    assert(!system("#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p ''"))
  end

  def test_wrong
    puts "testing cutover with incorrect master config..."
    $mysql_master.connection.query("set GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("set GLOBAL READ_ONLY=0")
    assert_script_failed

    puts "testing cutover with incorrect slave config..."
    $mysql_master.connection.query("set GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("set GLOBAL READ_ONLY=0")
    assert_script_failed

    puts "testing cutover with stopped slave"
    $mysql_master.connection.query("set GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("set GLOBAL READ_ONLY=1")
    $mysql_slave.connection.query("slave stop")
    assert_script_failed
  end
end
