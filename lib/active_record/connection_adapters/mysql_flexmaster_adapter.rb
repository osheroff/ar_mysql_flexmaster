require 'active_record'
require 'active_record/connection_adapters/mysql2_adapter'
require 'timeout'

module ActiveRecord
  class Base
    def self.mysql_flexmaster_connection(config)
      config = config.symbolize_keys

      # fallback to :host or :localhost
      config[:hosts] ||= config.key?(:host) ? [config[:host]] : ['localhost']

      hosts = config[:hosts] || [config[:host]]

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

      CHECK_EVERY_N_SELECTS = 10
      DEFAULT_CONNECT_TIMEOUT = 5
      DEFAULT_TX_HOLD_TIMEOUT = 5

      def initialize(logger, config)
        @select_counter = 0
        @config = config
        @is_master = !config[:slave]
        @tx_hold_timeout = @config[:tx_hold_timeout] || DEFAULT_TX_HOLD_TIMEOUT
        @connection_timeout = @config[:connection_timeout] || DEFAULT_CONNECT_TIMEOUT
        connection = find_correct_host
        raise NoActiveMasterException unless connection
        super(connection, logger, [], config)
      end

      def begin_db_transaction
        if !in_transaction?
          verify_current_connection!(true)
        end
        with_lost_cx_guard do
          super
        end
      end

      def execute(sql, name = nil)
        for_update = starting_implicit_transaction?(sql)
        verify_current_connection!(for_update)
        with_lost_cx_guard do
          super
        end
      end

      private
      def in_transaction?
        open_transactions > 0
      end

      # never try to save the call when in a transaction
      # otherwise try to detect when the master/slave has crashed and retry stuff.
      def with_lost_cx_guard
        if !defined?(should_retry)
          should_retry = !in_transaction?
        end

        begin
          yield
        rescue Mysql2::Error => e
          case e.errno
          when 2006 # gone away -- throw away the connection and retry once
            raise e unless should_retry
            should_retry = false
            @connection = nil
            retry
          else
            raise e
          end
        end
      end


      def verify_current_connection!(for_update)
        with_lost_cx_guard do
          if !@connection
            refind_correct_host
          else
            if for_update
              refind_correct_host unless cx_correct?
            else
              # on select statements, check every 10 times to see if we need to switch hosts,
              # but don't sleep long on it.

              @select_counter += 1
              return unless @select_counter % CHECK_EVERY_N_SELECTS == 0
              refind_correct_host(1, 0) unless cx_correct?
            end
          end
        end
      end

      def starting_implicit_transaction?(sql)
        !in_transaction? && sql =~ /^(INSERT|UPDATE|DELETE|ALTER|CHANGE)/
      end

      def connect
        @connection = find_correct_host
        raise NoActiveMasterException unless @connection
      end

      def refind_correct_host(tries = nil, sleep_interval = nil)
        tries ||= @tx_hold_timeout.to_f / 0.1
        sleep_interval ||= 0.1
        tries.to_i.times do
          @connection = find_correct_host
          return if @connection

          sleep(sleep_interval)
        end
        raise NoActiveMasterException
      end

      def hosts_and_ports
        @hosts_and_ports ||= @config[:hosts].map do |hoststr|
          host, port = hoststr.split(':')
          port = port.to_i unless port.nil?
          [host, port]
        end
      end

      def find_correct_host
        cxs = hosts_and_ports.map do |host, port|
          initialize_connection(host, port)
        end.compact

        correct_cxs = cxs.select { |cx| cx_correct?(cx) }

        chosen_cx = nil
        if @is_master
          # for master connections, we make damn sure that we have just one master
          if correct_cxs.size == 1
            chosen_cx = correct_cxs.first
          else
            # nothing read-write, or too many read-write
            # (should we manually close the connections?)
            chosen_cx = nil
          end
        else
          # for slave connections, we just return a random RO candidate or the master if none are available
          if correct_cxs.empty?
            chosen_cx = cxs.first
          else
            chosen_cx = correct_cxs.shuffle.first
          end
        end
        cxs.each { |cx| cx.close unless chosen_cx == cx }
        chosen_cx
      end

      def initialize_connection(host, port)
        begin
          Timeout::timeout(@connection_timeout) do
            cfg = @config.merge(:host => host, :port => port)
            Mysql2::Client.new(cfg).tap do |cx|
              cx.query_options.merge!(:as => :array)
            end
          end
        rescue Mysql2::Error
        rescue Timeout::Error
        end
      end

      def cx_correct?(cx = @connection)
        res = cx.query("SELECT @@read_only as ro").first

        if @is_master
          res.first == 0
        else
          res.first == 1
        end
      end
    end
  end
end
