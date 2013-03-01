require 'tmpdir'
require 'socket'
require 'mysql2'

class MysqlIsolatedServer
  attr_reader :pid, :base, :port
  MYSQL_BASE_DIR="/usr"

  def initialize(options = {})
    @base = Dir.mktmpdir("/tmp/mysql_isolated")
    @mysql_data_dir="#{@base}/mysqld"
    @mysql_socket="#{@mysql_data_dir}/mysqld.sock"
    @params = options[:params]
    @load_data_path = options[:data_path]
    @port = options[:port]
    @allow_output = options[:allow_output]
  end

  def make_slave_of(master)
    master_binlog_info = master.connection.query("show master status").first
    connection.query(<<-EOL
      change master to master_host='127.0.0.1',
                       master_port=#{master.port},
                       master_user='root', master_password='',
                       master_log_file='#{master_binlog_info['File']}',
                       master_log_pos=#{master_binlog_info['Position']}
      EOL
    )
    connection.query("SLAVE START")
  end

  def connection
    @cx ||= Mysql2::Client.new(:host => "127.0.0.1", :port => @port, :username => "root", :password => "", :database => "mysql")
  end

  def set_rw(rw)
    ro = rw ? 0 : 1
    connection.query("SET GLOBAL READ_ONLY=#{ro}")
  end


  def locate_executable(*candidates)
    output = `which #{candidates.join(' ')}`
    return nil if output == "\n"
    output.split("\n").first
  end

  def boot!
    @port ||= grab_free_port
    system("rm -Rf #{@mysql_data_dir}")
    system("mkdir #{@mysql_data_dir}")
    if @load_data_path
      system("cp -a #{@load_data_path}/* #{@mysql_data_dir}")
      system("rm -f #{@mysql_data_dir}/relay-log.info")
    else
      mysql_install_db = `which mysql_install_db`
      idb_path = File.dirname(mysql_install_db)
      system("(cd #{idb_path}/..; mysql_install_db --datadir=#{@mysql_data_dir} --user=`whoami`) >/dev/null 2>&1")
      system("cp #{File.expand_path(File.dirname(__FILE__))}/user.* #{@mysql_data_dir}/mysql")
    end

    exec_server <<-EOL
        mysqld --no-defaults --default-storage-engine=innodb \
                --datadir=#{@mysql_data_dir} --pid-file=#{@base}/mysqld.pid --port=#{@port} \
                #{@params} --socket=#{@mysql_data_dir}/mysql.sock --log-bin --log-slave-updates
    EOL

    while !system("mysql -h127.0.0.1 --port=#{@port} --database=mysql -u root -e 'select 1' >/dev/null 2>&1")
      sleep(0.1)
    end

    tzinfo_to_sql = locate_executable("mysql_tzinfo_to_sql5", "mysql_tzinfo_to_sql")
    raise "could not find mysql_tzinfo_to_sql" unless tzinfo_to_sql
    system("#{tzinfo_to_sql} /usr/share/zoneinfo 2>/dev/null | mysql -h127.0.0.1 --database=mysql --port=#{@port} -u root mysql ")

    system(%Q(mysql -h127.0.0.1 --port=#{@port} --database=mysql -u root -e "SET GLOBAL time_zone='UTC'"))
    system(%Q(mysql -h127.0.0.1 --port=#{@port} --database=mysql -u root -e "GRANT SELECT ON *.* to 'zdslave'@'localhost'"))
  end

  def grab_free_port
    while true
      candidate=9000 + rand(50_000)

      begin
        socket = Socket.new(:INET, :STREAM, 0)
        socket.bind(Addrinfo.tcp("127.0.0.1", candidate))
        socket.close
        return candidate
      rescue Exception => e
        puts e
      end
    end
  end

  attr_reader :pid
  def exec_server(cmd)
    cmd.strip!
    cmd.gsub!(/\\\n/, ' ')
    devnull = File.open("/dev/null", "w")
    system("mkdir -p #{base}/tmp")
    system("chmod 0777 #{base}/tmp")
    pid = fork do
      ENV["TMPDIR"] = "#{base}/tmp"
      if !@allow_output
        STDOUT.reopen(devnull)
        STDERR.reopen(devnull)
      end

      exec(cmd)
    end
    at_exit {
      Process.kill("TERM", pid)
      system("rm -Rf #{base}")
    }
    @pid = pid
    devnull.close
  end

  def kill!
    return unless @pid
    system("kill -KILL #{@pid}")
  end
end
