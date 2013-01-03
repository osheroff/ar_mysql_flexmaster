require 'bundler/setup'
require 'mysql2'
require_relative '../boot_mysql_env'


def assert_script_failed
  master_cut_script = File.expand_path(File.dirname(__FILE__)) + "/../../bin/master_cut"
  if system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root ''"
    puts "Script returned ok instead of false!"
    exit 1
  end
end

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


puts "Tests passed."

