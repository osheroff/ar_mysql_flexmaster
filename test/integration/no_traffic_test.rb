# frozen_string_literal: true
require_relative "../integration_helper"

class NoTrafficTest < Minitest::Test
  def test_basic_cutover
    $mysql_master.connection.query("set GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("set GLOBAL READ_ONLY=1")

    puts "testing basic cutover..."

    system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p ''"
    assert_ro($mysql_master.connection, 'master', true)
    assert_ro($mysql_slave.connection, 'master', false)
  end
end
