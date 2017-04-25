#!/usr/bin/env ruby
# frozen_string_literal: true

require "mysql_isolated_server"

threads = []
threads << Thread.new do
  $mysql_master = MysqlIsolatedServer.new(allow_output: false)
  $mysql_master.boot!

  puts "mysql master booted on port #{$mysql_master.port} -- access with mysql -uroot -h127.0.0.1 --port=#{$mysql_master.port} mysql"
end

threads << Thread.new do
  $mysql_slave = MysqlIsolatedServer.new
  $mysql_slave.boot!

  puts "mysql slave booted on port #{$mysql_slave.port} -- access with mysql -uroot -h127.0.0.1 --port=#{$mysql_slave.port} mysql"
end

threads << Thread.new do
  $mysql_slave_2 = MysqlIsolatedServer.new
  $mysql_slave_2.boot!

  puts "mysql chained slave booted on port #{$mysql_slave_2.port} -- access with mysql -uroot -h127.0.0.1 --port=#{$mysql_slave_2.port} mysql"
end

threads.each(&:join)

$mysql_master.connection.query("CHANGE MASTER TO master_host='127.0.0.1', master_user='root', master_password=''")
$mysql_slave.make_slave_of($mysql_master)
$mysql_slave_2.make_slave_of($mysql_slave)

$mysql_master.connection.query("GRANT ALL ON flexmaster_test.* to flex@localhost")
$mysql_master.connection.query("CREATE DATABASE flexmaster_test")
$mysql_master.connection.query("CREATE TABLE flexmaster_test.users (id INT(10) NOT NULL AUTO_INCREMENT PRIMARY KEY, name varchar(20))")
$mysql_master.connection.query("INSERT INTO flexmaster_test.users set name='foo'")
$mysql_slave.set_rw(false)
$mysql_slave_2.set_rw(false)

# let replication for the grants and such flow down.  bleh.
repl_sync = false
while !repl_sync
  repl_sync = [[$mysql_master, $mysql_slave], [$mysql_slave, $mysql_slave_2]].all? do |master, slave|
    master_pos = master.connection.query("show master status").to_a.first["Position"]
    slave.connection.query("show slave status").to_a.first["Exec_Master_Log_Pos"] == master_pos
  end
  sleep 1
end

sleep if __FILE__ == $0
