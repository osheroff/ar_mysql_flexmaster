require 'bundler/setup'
require 'mysql2'
require_relative '../boot_mysql_env'
master_cut_script = File.expand_path(File.dirname(__FILE__)) + "/../../bin/master_cut"

$mysql_master.connection.query("set GLOBAL READ_ONLY=0")
$mysql_slave.connection.query("set GLOBAL READ_ONLY=1")

puts "testing basic cutover..."

system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p ''"
if $mysql_master.connection.query("select @@read_only as ro").first['ro'] != 1
  puts "Master is not readonly!"
  exit 1
end

if $mysql_slave.connection.query("select @@read_only as ro").first['ro'] != 0
  puts "Slave is not readwrite!"
  exit 1
end

puts "everything seemed to go ok..."

