require 'tmpdir'
require 'socket'
require 'mysql2'

class MysqlIsolatedServer
  attr_reader :pid, :base, :port
  MYSQL_BASE_DIR="/usr"

  def initialize(params = nil, master_info = nil)
    @base = Dir.mktmpdir("mysql_isolated")
    @mysql_data_dir="#{@base}/mysqld"
    @mysql_socket="#{@mysql_data_dir}/mysqld.sock"
    @master_info = master_info
    @params = params
  end

  def connection
    @cx ||= Mysql2::Client.new(:host => "127.0.0.1", :port => @port, :username => "root", :password => "", :database => "mysql")
  end

  def set_rw(rw)
    ro = rw ? 0 : 1
    connection.query("SET GLOBAL READ_ONLY=#{ro}")
  end


  def boot!
    @port = grab_free_port
    system("rm -Rf #{@mysql_data_dir}")
    system("mkdir #{@mysql_data_dir}")

    mysql_install_db = `which mysql_install_db`
    idb_path = File.dirname(mysql_install_db)
    system("(cd #{idb_path}/..; mysql_install_db --datadir=#{@mysql_data_dir}) >/dev/null 2>&1")

    exec_server <<-EOL
        mysqld --no-defaults --default-storage-engine=innodb \
                --datadir=#{@mysql_data_dir} --pid-file=#{@base}/mysqld.pid --port=#{@port} \
                #{@params} --socket=#{@mysql_data_dir}/mysql.sock
    EOL

    while !system("mysql -h127.0.0.1 --port=#{@port} --database=mysql -u root -e 'select 1' >/dev/null 2>&1")
      sleep(0.1)
    end

    system("mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | mysql --database=mysql --port=#{@port} -u root mysql >/dev/null")

    system(%Q(mysql --port=#{@port} --database=mysql -u root -e "SET GLOBAL time_zone='UTC'"))
    system(%Q(mysql --port=#{@port} --database=mysql -u root -e "GRANT SELECT ON *.* to 'zdslave'@'localhost'"))
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

  def exec_server(cmd)
    cmd.strip!
    cmd.gsub!(/\\\n/, ' ')
    devnull = File.open("/dev/null", "w")
    system("mkdir -p #{base}/tmp")
    system("chmod 0777 #{base}/tmp")
    pid = fork do
      ENV["TMPDIR"] = "#{base}/tmp"
      STDOUT.reopen(devnull)
      STDERR.reopen(devnull)
      exec(cmd)
    end
    at_exit { Process.kill("TERM", pid) }
    devnull.close
  end

  def kill!
    return unless @pid
    system("kill -KILL #{@pid}")
  end
end
