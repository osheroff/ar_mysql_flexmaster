require 'bundler/setup'
require 'mysql2'
require 'test/unit/assertions'

include Test::Unit::Assertions
require_relative '../boot_mysql_env'
master_cut_script = File.expand_path(File.dirname(__FILE__)) + "/../../bin/master_cut"

$mysql_master.connection.query("set GLOBAL READ_ONLY=0")
$mysql_slave.connection.query("set GLOBAL READ_ONLY=1")

def assert_ro(cx, str, bool)
  expected = bool ? 1 : 0
  if expected != cx.query("select @@read_only as ro").first['ro']
    $stderr.puts("#{str} is #{bool ? 'read-write' : 'read-only'} but I expected otherwise!")
    exit 1
  end
end
puts "testing first cutover..."

system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p '' -r -s"
assert_ro($mysql_master.connection, 'original master', true)
assert_ro($mysql_slave.connection, 'original slave', false)

assert "Yes" == $mysql_master.connection.query("show slave status").first['Slave_IO_Running']

system "#{master_cut_script} 127.0.0.1:#{$mysql_slave.port} 127.0.0.1:#{$mysql_master.port} root -p '' -r"
assert_ro($mysql_master.connection, 'original master', false)
assert_ro($mysql_slave.connection, 'original slave', true)

assert "No" == $mysql_slave.connection.query("show slave status").first['Slave_IO_Running']

puts "everything went real nice."

