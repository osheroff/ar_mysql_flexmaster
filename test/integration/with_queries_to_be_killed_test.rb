# frozen_string_literal: true
require_relative "../integration_helper"
class WithKillableQueries < Minitest::Test
  def test_with_queries_to_be_killed
    puts "testing with long running queries..."

    $mysql_master.connection.query("set GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("set GLOBAL READ_ONLY=1")

    thread = Thread.new {
      begin
        $mysql_master.connection.query("update flexmaster_test.users set name=sleep(600)")
        assert false, "Query did not get killed!  Bad."
        exit 1
      rescue StandardError => e
        puts e
      end
    }

    system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p ''"

    thread.join

    $mysql_master.reconnect!
    assert_ro($mysql_master.connection, 'master', true)
    assert_ro($mysql_slave.connection, 'slave', false)
  end
end
