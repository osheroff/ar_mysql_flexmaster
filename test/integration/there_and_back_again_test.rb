require_relative "../integration_helper"

class ThereAndBackAgain < Minitest::Test
  def test_there_and_back
    $mysql_master.connection.query("set GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("set GLOBAL READ_ONLY=1")

    puts "testing first cutover..."

    system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p '' -r -s"
    assert_ro($mysql_master.connection, 'original master', true)
    assert_ro($mysql_slave.connection, 'original slave', false)

    assert "Yes" == $mysql_master.connection.query("show slave status").first['Slave_IO_Running']

    system "#{master_cut_script} 127.0.0.1:#{$mysql_slave.port} 127.0.0.1:#{$mysql_master.port} root -p '' -r"
    assert_ro($mysql_master.connection, 'original master', false)
    assert_ro($mysql_slave.connection, 'original slave', true)

    assert "No" == $mysql_slave.connection.query("show slave status").first['Slave_IO_Running']
  end
end
