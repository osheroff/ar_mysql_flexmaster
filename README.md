# ArMysqlFlexmaster

Mysql Flexmaster is an adapter for ActiveRecord that allows an application node to choose
among a list of potential masters at runtime.  It trades some properties of a more traditional
HA solution (load balancing, middleware) for simplicity of operation.  

## Installation

Add this line to your application's Gemfile:

    gem 'ar_mysql_flexmaster'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ar_mysql_flexmaster

## Configuration:

database.yml contains a list of hosts -- all of them potential masters, all of them potential replicas.
It should look like this:

```
production:
  adapter: mysql_flexmaster
  username: flex
  hosts: ["db01:3306", "db02:3306"]

production_slave:
  adapter: mysql_flexmaster
  username: flex
  slave: true
  hosts: ["db01:3306", "db02:3306"]
```


## How it works

### Overview

The mysql "READ_ONLY" flag is used to indicate a current master amongst the cluster.  Only one member 
of the replication chain may be read-write at any given time.  The application picks in run time, based 
on the read_only flag, which host is correct.

### boot time

Your activerecord application will pick a correct mysql host for the given configuration by probing hosts until 
it finds the correct host.

For master configurations (slave: true is not specified):

The application will probe each host in turn, and find the mysql candidate among these nodes 
that is read-write (SET GLOBAL READ_ONLY=0).  If it finds more than one node where READ_ONLY == 0, it will 
abort.  

For slave configurations (slave: true specified):

The application will choose a replica at random from amongst those where READ_ONLY == 1. 

### run time

Before each transaction is begun on the master, the application checks the status of the READ_ONLY variable.
If READ_ONLY == 0, it will proceed with the transaction as normal.  If READ_ONLY == 1, it will drop the current 
connection and re-poll the cluster for the current master, sleeping up to a default of 5 seconds to wait for 
the new master to be promoted.  When it finds the new master, it will begin the transaction there. 

### promoting a new master

*The bin/master_cut script in this project will perform steps 3-5 for you.*

The process of promoting a new master to head the cluster should be as follows:

1. identify a new candidate master
1. ensure that all other replicas in the cluster are chained off the candidate master; you want the 
   chain to look like this: 
   
   ```
      <existing master> -> <candidate master> -> <other replicas>
                                              -> <other replicas> 
        
   ```

1. set the old master to READ_ONLY = 1
1. record the master-bin-log position of the candidate master (if you want to re-use the old master)
1. set the new master to READ_ONLY = 0 

The application will eventually shift slave traffic to another node in the cluster, if available, and
will drop their connection to the old master whenever a transaction is attempted, or after a certain 
number of queries.


### caveats, gotchas

- Any explicit ( BEGIN ... END ) transaction that are in-flight when the old master goes READ_ONLY
  will crash.  In theory there's a workaround for this problem, in pratice it's rather unwieldy due
  to a lack of shared global variables in mysql.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
