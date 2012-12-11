require 'bundler/setup'
require 'ar_mysql_flexmaster'
require 'active_record'
require_relative 'boot_mysql_env'
require 'test/unit'

class TestArFlexmaster < Test::Unit::TestCase
  def setup
    write_database_yaml
    ActiveRecord::Base.configurations = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
    ActiveRecord::Base.establish_connection("test")

    $mysql_master.connection.query("SET GLOBAL READ_ONLY=0")
    $mysql_slave.connection.query("SET GLOBAL READ_ONLY=1")
  end

  def test_should_raise_without_a_rw_master
    [$mysql_master, $mysql_slave].each do |m|
      m.connection.query("SET GLOBAL READ_ONLY=1")
    end

    assert_raises(ActiveRecord::ConnectionAdapters::MysqlFlexmasterAdapter::NoActiveMasterException) do
      ActiveRecord::Base.connection
    end
  end

  def test_empty_test
    ActiveRecord::Base.connection
    assert(true)
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
end
