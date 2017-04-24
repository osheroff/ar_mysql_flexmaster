# frozen_string_literal: true
require 'active_record'
require 'active_record/connection_adapters/mysql2_adapter'
require 'timeout'

module ActiveRecord
  class Base
    def self.mysql_flexmaster_connection(config)
      config = config.symbolize_keys

      # fallback to :host or :localhost
      config[:hosts] ||= config.key?(:host) ? [config[:host]] : ['localhost']
      config[:username] = 'root' if config[:username].nil?

      if Mysql2::Client.const_defined? :FOUND_ROWS
        config[:flags] = Mysql2::Client::FOUND_ROWS
      end

      ConnectionAdapters::MysqlFlexmasterAdapter.new(logger, config)
    end
  end

  module ConnectionAdapters
    class MysqlFlexmasterAdapter < Mysql2Adapter
      class NoActiveMasterException < StandardError; end
      class TooManyMastersException < StandardError; end
      class NoServerAvailableException < StandardError; end

      CHECK_EVERY_N_SELECTS    = 10
      DEFAULT_CONNECT_TIMEOUT  = 1
      DEFAULT_CONNECT_ATTEMPTS = 3
      DEFAULT_TX_HOLD_TIMEOUT  = 5

      def initialize(logger, config)
        @select_counter = 0
        @config = config
        @rw = config[:slave] ? :read : :write
        @tx_hold_timeout     = @config[:tx_hold_timeout]     || DEFAULT_TX_HOLD_TIMEOUT
        @connection_timeout  = @config[:connection_timeout]  || DEFAULT_CONNECT_TIMEOUT
        @connection_attempts = @config[:connection_attempts] || DEFAULT_CONNECT_ATTEMPTS

        connection = find_correct_host(@rw)

        raise_no_server_available! unless connection
        super(connection, logger, [], config)
      end

      def begin_db_transaction
        if !in_transaction?
          with_lost_cx_guard { hard_verify }
        end
        super
      end

      def execute(sql, name = nil)
        if in_transaction?
          super # no way to rescue any lost cx or wrong-host errors at this point.
        else
          with_lost_cx_guard do
            if has_side_effects?(sql)
              hard_verify
            else
              soft_verify
            end

            super
          end
        end
      end

      # after a cluster recovers from a bad state, an insert or SELECT will bring us back
      # into sanity, but sometimes would we never get there and would get stuck crashing in this function instead.
      def quote(*args)
        if !@connection
          soft_verify
        end
        super
      end

      def quote_string(*args)
        if !@connection
          soft_verify
        end
        super
      end

      def current_host
        @connection.query_options[:host]
      end

      def current_port
        @connection.query_options[:port]
      end

      private

      def in_transaction?
        open_transactions > 0
      end

      # never try to carry on if inside a transaction
      # otherwise try to detect when the master/slave has crashed and retry stuff.
      def with_lost_cx_guard
        retried = false

        begin
          yield
        rescue Mysql2::Error, ActiveRecord::StatementInvalid => e
          if retryable_error?(e) && !retried
            retried = true
            @connection = nil
            retry
          else
            raise e
          end
        end
      end

      AR_MESSAGES = [ /^Mysql2::Error: MySQL server has gone away/,
                      /^Mysql2::Error: Can't connect to MySQL server/ ]
      def retryable_error?(e)
        case e
        when Mysql2::Error
          # 2006 is gone-away, 2003 is can't-connect (applicable when reconnect is true)
          [2006, 2003].include?(e.errno)
        when ActiveRecord::StatementInvalid
          AR_MESSAGES.any? { |m| e.message.match(m) }
        end
      end

      # when either doing BEGIN or INSERT/UPDATE/DELETE etc, ensure a correct connection
      # and crash if wrong
      def hard_verify
        if !@connection || !cx_correct?
          refind_correct_host!
        end
      end

      # on select statements, check every 10 statements to see if we need to switch hosts,
      # but don't crash if the cx is wrong, and don't sleep trying to find a correct one.
      def soft_verify
        if !@connection
          @connection = find_correct_host(@rw)
        else
          @select_counter += 1
          return unless @select_counter % CHECK_EVERY_N_SELECTS == 0

          if !cx_correct?
            cx = find_correct_host(@rw)
            @connection = cx if cx
          end
        end

        if @rw == :write && !@connection
          # desperation mode: we've been asked for the master, but it's just not available.
          # we'll go ahead and return a connection to the slave, understanding that it'll never work
          # for writes. (we'll call hard_verify and crash)
          @connection = find_correct_host(:read)
        end
      end

      def has_side_effects?(sql)
        sql =~ /^\s*(INSERT|UPDATE|DELETE|ALTER|CHANGE|REPLACE)/i
      end

      def connect
        @connection = find_correct_host(@rw)
        raise_no_server_available! unless @connection
      end

      def raise_no_server_available!
        raise NoServerAvailableException.new(errors_to_message)
      end

      def collected_errors
        @collected_errors ||= []
      end

      def clear_collected_errors!
        @collected_errors = []
      end

      def errors_to_message
        "Errors encountered while trying #{@config[:hosts].inspect}: " +
          collected_errors.map { |e| "#{e.class.name}: #{e.message}" }.uniq.join(",")
      end

      def refind_correct_host!
        clear_collected_errors!

        sleep_interval = 0.1
        timeout_at = Time.now.to_f + @tx_hold_timeout

        loop do
          @connection = find_correct_host(@rw)
          return if @connection

          sleep(sleep_interval)

          break unless Time.now.to_f < timeout_at
        end

        raise_no_server_available!
      end

      def hosts_and_ports
        @hosts_and_ports ||= @config[:hosts].map do |hoststr|
          host, port = hoststr.split(':')
          port = port.to_i unless port.nil?
          [host, port]
        end
      end

      def find_correct_host(rw)
        cxs = hosts_and_ports.map do |host, port|
          initialize_connection(host, port)
        end.compact

        correct_cxs = cxs.select { |cx| cx_correct?(cx) }

        chosen_cx = nil
        case rw
        when :write
          # for master connections, we make damn sure that we have just one master
          if correct_cxs.size == 1
            chosen_cx = correct_cxs.first
          else
            # nothing read-write, or too many read-write
            if correct_cxs.size > 1
              collected_errors << TooManyMastersException.new("found #{correct_cxs.size} read-write servers")
            else
              collected_errors << NoActiveMasterException.new("no read-write servers found")
            end

            chosen_cx = nil
          end
        when :read
          # for slave connections (or master-gone-away scenarios), we just return a random RO candidate or the master if none are available
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
        attempts = 1
        begin
          Timeout::timeout(@connection_timeout) do
            cfg = @config.merge(:host => host, :port => port)
            Mysql2::Client.new(cfg).tap do |cx|
              cx.query_options.merge!(:as => :array)
            end
          end
        rescue Mysql2::Error, Timeout::Error => e
          if attempts < @connection_attempts
            attempts += 1
            retry
          else
            collected_errors << e
            nil
          end
        end
      end

      def cx_correct?(cx = @connection)
        res = cx.query("SELECT @@read_only as ro").first

        if @rw == :write
          res.first == 0
        else
          res.first == 1
        end
      end
    end
  end
end
