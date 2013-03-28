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
      class TooManyMastersException < Exception; end
      class NoServerAvailableException < Exception; end

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

        raise_no_server_available! unless connection
        super(connection, logger, [], config)
      end

      def begin_db_transaction
        if !cx_correct? && open_transactions == 0
          refind_correct_host!
        end
        super
      end

      def execute(sql, name = nil)
        if open_transactions == 0 && sql =~ /^(INSERT|UPDATE|DELETE|ALTER|CHANGE)/ && !cx_correct?
          refind_correct_host!
        else
          @select_counter += 1
          if (@select_counter % CHECK_EVERY_N_SELECTS == 0) && !cx_correct?
            # on select statements, check every 10 times to see if we need to switch masters,
            # but don't sleep, and if existing connection isn't correct, go ahead anyway.
            cx = find_correct_host
            @connection = cx if cx
          end
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

      def connect
        @connection = find_correct_host
        raise NoActiveMasterException unless @connection
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
        tries = @tx_hold_timeout.to_f / sleep_interval

        tries.to_i.times do
          cx = find_correct_host
          if cx
            @connection = cx
            return
          end
          sleep(sleep_interval)
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
            if correct_cxs.size > 1
              collected_errors << TooManyMastersException.new("found #{correct_cxs.size} read-write servers")
            else
              collected_errors << NoActiveMasterException.new("no read-write servers found")
            end

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
        rescue Mysql2::Error => e
          collected_errors << e
          nil
        rescue Timeout::Error => e
          collected_errors << e
          nil
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
