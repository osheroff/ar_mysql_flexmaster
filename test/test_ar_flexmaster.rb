require 'bundler/setup'
require 'ar_mysql_flexmaster'
require 'active_record'
require_relative 'boot_mysql_env'
require 'test/unit'

class User < ActiveRecord::Base
end

# $mysql_master and $mysql_slave are separate references to the master and slave that we
# use to send control-channel commands on

class TestArFlexmaster < Test::Unit::TestCase
  def setup
    write_database_yaml
    ActiveRecord::Base.configurations = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
    ActiveRecord::Base.establish_connection("test")

    $mysql_master.set_rw(true)
    $mysql_slave.set_rw(false)
  end

  def test_should_raise_without_a_rw_master
    [$mysql_master, $mysql_slave].each do |m|
      m.set_rw(false)
    end

    assert_raises(ActiveRecord::ConnectionAdapters::MysqlFlexmasterAdapter::NoActiveMasterException) do
      ActiveRecord::Base.connection
    end
  end

  def test_should_select_the_master_on_boot
    assert main_connection_is_master?
  end

  def test_should_hold_txs_until_timeout_then_abort
    ActiveRecord::Base.connection

    $mysql_master.set_rw(false)
    start_time = Time.now.to_i
    assert_raises(ActiveRecord::ConnectionAdapters::MysqlFlexmasterAdapter::NoActiveMasterException) do
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
    assert !main_connection_is_master?
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
    assert !main_connection_is_master?
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
    User.connection
    $mysql_master.set_rw(false)
    $mysql_slave.set_rw(true)
    assert main_connection_is_master?
    100.times do
      u = User.first
    end
    assert !main_connection_is_master?
  end

  def test_altering_on_the_slave
    User.create!(:name => "foo")
    $mysql_slave.connection.query("ALTER TABLE flexmaster_test.users add column xtra int(10)")
    assert !User.column_names.include?("xtra")
    $mysql_master.set_rw(false)
    $mysql_slave.set_rw(true)

    # pick up the new connection and column info
    User.create!(:name => "foo")

    # now we should be able to use it.
    assert User.create!(:name => "foobar", :xtra => 5)

    # teardown
    $mysql_slave.connection.query("ALTER TABLE flexmaster_test.users drop column xtra")
    User.reset_column_information
  end

  private
  def write_database_yaml
    File.open(File.dirname(File.expand_path(__FILE__)) + "/database.yml", "w+") do |f|
      f.write <<-EOL
test:
  adapter: mysql_flexmaster
  username: flex
  hosts: ["127.0.0.1:#{$mysql_master.port}", "127.0.0.1:#{$mysql_slave.port}"]
  password:
  database: flexmaster_test
      EOL
    end
  end

  def main_connection_is_master?
    port = ActiveRecord::Base.connection.execute("show global variables like 'port'").first.last.to_i
    port == $mysql_master.port
  end
end
