require 'bundler/setup'
require 'mysql2'
require_relative '../boot_mysql_env'
master_cut_script = File.expand_path(File.dirname(__FILE__)) + "/../../bin/master_cut"

puts "testing with long running queries..."

$mysql_master.connection.query("set GLOBAL READ_ONLY=0")
$mysql_slave.connection.query("set GLOBAL READ_ONLY=1")
$mysql_master.connection.send(:reconnect=, true)
$mysql_slave.connection.send(:reconnect=, true)

thread = Thread.new {
  begin
    $mysql_master.connection.query("update flexmaster_test.users set name=sleep(600)")
    puts "Query did not get killed!  Bad."
    exit 1
  rescue Exception => e
    puts e
  end
}

system "#{master_cut_script} 127.0.0.1:#{$mysql_master.port} 127.0.0.1:#{$mysql_slave.port} root -p ''"

thread.join

if $mysql_master.connection.query("select @@read_only as ro").first['ro'] != 1
  puts "Master is not readonly!"
  exit 1
end

if $mysql_slave.connection.query("select @@read_only as ro").first['ro'] != 0
  puts "Slave is not readwrite!"
  exit 1
end

puts "everything seemed to go ok..."
