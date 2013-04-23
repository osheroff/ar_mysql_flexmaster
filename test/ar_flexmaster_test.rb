require 'bundler/setup'
require 'ar_mysql_flexmaster'
require 'active_record'
require_relative 'boot_mysql_env'
require 'test/unit'
require 'debugger'

File.open(File.dirname(File.expand_path(__FILE__)) + "/database.yml", "w+") do |f|
      f.write <<-EOL
test:
  adapter: mysql_flexmaster
  username: flex
  hosts: ["127.0.0.1:#{$mysql_master.port}", "127.0.0.1:#{$mysql_slave.port}"]
  password:
  database: flexmaster_test

test_slave:
  adapter: mysql_flexmaster
  username: flex
  slave: true
  hosts: ["127.0.0.1:#{$mysql_master.port}", "127.0.0.1:#{$mysql_slave.port}", "127.0.0.1:#{$mysql_slave_2.port}"]
  password:
  database: flexmaster_test
      EOL
end

ActiveRecord::Base.configurations = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
ActiveRecord::Base.establish_connection("test")

class User < ActiveRecord::Base
end

class UserSlave < ActiveRecord::Base
  establish_connection(:test_slave)
  self.table_name = "users"
end

# $mysql_master and $mysql_slave are separate references to the master and slave that we
# use to send control-channel commands on

$original_master_port = $mysql_master.port

class TestArFlexmaster < Test::Unit::TestCase
  def setup
    ActiveRecord::Base.establish_connection("test")

    $mysql_master.set_rw(true) if $mysql_master
    $mysql_slave.set_rw(false) if $mysql_slave
    $mysql_slave_2.set_rw(false) if $mysql_slave_2
  end

  def test_should_raise_without_a_rw_master
    [$mysql_master, $mysql_slave].each do |m|
      m.set_rw(false)
    end

    e = assert_raises(ActiveRecord::ConnectionAdapters::MysqlFlexmasterAdapter::NoServerAvailableException) do
      ActiveRecord::Base.connection
    end

    assert e.message =~ /NoActiveMasterException/
  end

  def test_should_select_the_master_on_boot
    assert main_connection_is_original_master?
  end

  def test_should_hold_txs_until_timeout_then_abort
    ActiveRecord::Base.connection

    $mysql_master.set_rw(false)
    start_time = Time.now.to_i
    e = assert_raises(ActiveRecord::ConnectionAdapters::MysqlFlexmasterAdapter::NoServerAvailableException) do
      User.create(:name => "foo")
    end
    end_time = Time.now.to_i
    assert end_time - start_time >= 5
  end

  def test_should_hold_txs_and_then_continue
    ActiveRecord::Base.connection
    $mysql_master.set_rw(false)
    Thread.new do
      sleep 1
      $mysql_slave.set_rw(true)
    end
    User.create(:name => "foo")
    assert !main_connection_is_original_master?
    assert User.first(:conditions => {:name => "foo"})
  end

  def test_should_hold_implicit_txs_and_then_continue
    User.create!(:name => "foo")
    $mysql_master.set_rw(false)
    Thread.new do
      sleep 1
      $mysql_slave.set_rw(true)
    end
    User.update_all(:name => "bar")
    assert !main_connection_is_original_master?
    assert_equal "bar", User.first.name
  end

  def test_should_let_in_flight_txs_crash
    User.transaction do
      $mysql_master.set_rw(false)
      assert_raises(ActiveRecord::StatementInvalid) do
        User.update_all(:name => "bar")
      end
    end
  end

  def test_should_eventually_pick_up_new_master_on_selects
    ActiveRecord::Base.connection
    $mysql_master.set_rw(false)
    $mysql_slave.set_rw(true)
    assert main_connection_is_original_master?
    100.times do
      u = User.first
    end
    assert !main_connection_is_original_master?
  end

  # there's a small window in which the old master is read-only but the new slave hasn't come online yet.
  # Allow side-effect free statements to continue.
  def test_should_not_crash_selects_in_the_double_read_only_window
    ActiveRecord::Base.connection
    $mysql_master.set_rw(false)
    $mysql_slave.set_rw(false)
    assert main_connection_is_original_master?
    100.times do
      u = User.first
    end
  end

  def test_should_choose_a_random_slave_connection
    h = {}
    10.times do
      port = UserSlave.connection.execute("show global variables like 'port'").first.last.to_i
      h[port] = 1
      UserSlave.connection.reconnect!
    end
    assert_equal 2, h.size
  end

  def test_should_expose_the_current_master_and_port
    cx = ActiveRecord::Base.connection
    assert_equal "127.0.0.1", cx.current_host
    assert_equal $mysql_master.port, cx.current_port
  end

  def test_should_flip_the_slave_after_it_becomes_master
    UserSlave.first
    User.create!
    $mysql_master.set_rw(false)
    $mysql_slave.set_rw(true)
    20.times do
      UserSlave.connection.execute("select 1")
    end
    connected_port = port_for_class(UserSlave)
    assert [$mysql_slave_2.port, $mysql_master.port].include?(connected_port)
  end

  def test_xxx_non_responsive_master
    return if ENV['TRAVIS'] # something different about 127.0.0.2 in travis, I guess.
    ActiveRecord::Base.configurations["test"]["hosts"] << "127.0.0.2:1235"
    start_time = Time.now.to_i
    User.connection.reconnect!
    assert Time.now.to_i - start_time >= 5, "only took #{Time.now.to_i - start_time} to timeout"
  ensure
    ActiveRecord::Base.configurations["test"]["hosts"].pop
  end

  def test_shooting_the_master_in_the_head
    User.create!
    UserSlave.first

    $mysql_master.down!

    # protected against 'gone away' errors?
    assert User.first

    # test that when we throw an exception in a bad (no active master) situation we don't get stuck there
    #
    # put us into a bad state -- no @connection
    assert_raises(ActiveRecord::ConnectionAdapters::MysqlFlexmasterAdapter::NoServerAvailableException) do
      User.create!
    end

    $mysql_slave.set_rw(true)
    User.connection.execute("select 1")

    User.create!
    UserSlave.first
    assert !main_connection_is_original_master?
  ensure
    $mysql_master.up!
  end

  # test that when nothing else is available we can fall back to the master in a slave role
  # note that by the time this test runs, the 'yyy' test has already killed the master
  def test_zzz_shooting_the_other_slave_in_the_head
    $mysql_slave.set_rw(true)

    $mysql_slave_2.kill!
    $mysql_slave_2 = nil

    UserSlave.connection.reconnect!
    assert port_for_class(UserSlave) == $mysql_slave.port
  end

  def test_zzzz_recovery_after_crash
  end

  private

  def port_for_class(klass)
    klass.connection.execute("show global variables like 'port'").first.last.to_i
  end

  def main_connection_is_original_master?
    port = port_for_class(ActiveRecord::Base)
    port == $original_master_port
  end
end
