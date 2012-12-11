require 'active_record/connection_adapters/mysql2_adapter'

module ActiveRecord
  class Base
    def self.mysql_flexmaster_connection(config)
      config = config.symbolize_keys
      hosts = config[:hosts]

      config[:username] = 'root' if config[:username].nil?

      if Mysql2::Client.const_defined? :FOUND_ROWS
        config[:flags] = Mysql2::Client::FOUND_ROWS
      end

      ConnectionAdapters::MysqlFlexmasterAdapter.new(logger, config)
    end
  end

  module ConnectionAdapters
    class MysqlFlexmasterAdapter < Mysql2Adapter
      class NoActiveMasterException < Exception; end

      def initialize(logger, config)
        @config = config
        connection = find_active_master
        raise NoActiveMasterException unless connection
        super(connection, logger, [], config)
      end

      private
      def find_active_master
        cxs = @config[:hosts].map do |hoststr|
          host, port = hoststr.split(':')
          port = port.to_i unless port.nil?

          cfg = @config.merge(:host => host, :port => port)
          cx = Mysql2::Client.new(cfg)
        end

        rw_cxs = cxs.select { |cx| cx_rw?(cx) }

        if rw_cxs.size == 1
          return rw_cxs.first
        else
          # nothing read-write, or too many read-write
          # (should we manually close the connections?)
          return nil
        end
      end

      def cx_rw?(cx = nil)
        cx ||= @connection
        res = cx.query("SELECT @@read_only as ro").first
        res["ro"] == 0
      end
    end
  end
end
