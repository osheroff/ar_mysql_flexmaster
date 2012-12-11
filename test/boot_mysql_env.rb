#!/usr/bin/env ruby

require_relative "mysql_isolated_server"
require 'debugger'

mysql_master = MysqlIsolatedServer.new("--log-bin")
mysql_master.boot!

puts "mysql master booted on port #{mysql_master.port} -- access with mysql -uroot -h127.0.0.1 --port=#{mysql_master.port} mysql"
mysql_master.connection.query("set global server_id=1")

mysql_slave = MysqlIsolatedServer.new
mysql_slave.boot!

mysql_slave.connection.query("set global server_id=2")
puts "mysql slave booted on port #{mysql_slave.port} -- access with mysql -uroot -h127.0.0.1 --port=#{mysql_slave.port} mysql"

master_binlog_info = mysql_master.connection.query("show master status").first

mysql_master.connection.query("GRANT ALL ON flexmaster_test.* to flex@localhost")
mysql_master.connection.query("CREATE DATABASE flexmaster_test")
mysql_master.connection.query("CREATE TABLE flexmaster_test.users (id INT(10) NOT NULL AUTO_INCREMENT PRIMARY KEY, name varchar(20))")
mysql_master.connection.query("INSERT INTO flexmaster_test.users set name='foo'")

mysql_slave.connection.query(<<-EOL
  change master to master_host='127.0.0.1',
                   master_port=#{mysql_master.port},
                   master_user='root', master_password='',
                   master_log_file='#{master_binlog_info['File']}',
                   master_log_pos=#{master_binlog_info['Position']}

EOL
)
mysql_slave.connection.query("SLAVE START")

$mysql_master = mysql_master
$mysql_slave = mysql_slave

