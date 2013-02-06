#!/usr/bin/env ruby

require_relative "mysql_isolated_server"
require 'debugger'

mysql_master = MysqlIsolatedServer.new
mysql_master.boot!
mysql_master.connection.query("set global server_id=1")

puts "mysql master booted on port #{mysql_master.port} -- access with mysql -uroot -h127.0.0.1 --port=#{mysql_master.port} mysql"

mysql_slave = MysqlIsolatedServer.new
mysql_slave.boot!
mysql_slave.connection.query("set global server_id=2")

puts "mysql slave booted on port #{mysql_slave.port} -- access with mysql -uroot -h127.0.0.1 --port=#{mysql_slave.port} mysql"

mysql_slave_2 = MysqlIsolatedServer.new
mysql_slave_2.boot!
mysql_slave_2.connection.query("set global server_id=3")

puts "mysql chained slave booted on port #{mysql_slave_2.port} -- access with mysql -uroot -h127.0.0.1 --port=#{mysql_slave_2.port} mysql"

mysql_master.connection.query("CHANGE MASTER TO master_host='127.0.0.1', master_user='root', master_password=''")
mysql_slave.make_slave_of(mysql_master)
mysql_slave_2.make_slave_of(mysql_slave)

mysql_master.connection.query("GRANT ALL ON flexmaster_test.* to flex@localhost")
mysql_master.connection.query("CREATE DATABASE flexmaster_test")
mysql_master.connection.query("CREATE TABLE flexmaster_test.users (id INT(10) NOT NULL AUTO_INCREMENT PRIMARY KEY, name varchar(20))")
mysql_master.connection.query("INSERT INTO flexmaster_test.users set name='foo'")

$mysql_master = mysql_master
$mysql_slave = mysql_slave
$mysql_slave_2 = mysql_slave_2
