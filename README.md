[![Build Status](https://travis-ci.org/osheroff/ar_mysql_flexmaster.svg?branch=master)](https://travis-ci.org/osheroff/ar_mysql_flexmaster)

# Flexmaster

Flexmaster is an adapter for ActiveRecord and mysql that allows an application node to find a master
among a list of potential masters at runtime.  It trades some properties of a more traditional
HA solution (load balancing, middleware) for simplicity of operation.

## Configuration:

Your environment should be configured with 1 active master and N replicas.  Each replica should have mysql's
global "READ_ONLY" flag set to true (this is really best practices for your replicas anyway, but flexmaster 
depends on it).

database.yml should contain a list of hosts -- all of them potential masters, all of them potential replicas.
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

In this example, we've configured two diferent connections for rails to use.  Note that they're identicle except for the `slave:true` key in the production_slave yaml block.
Adding `slave:true` indicates to flexmaster that this connection should prefer a read-only slave wherever possible.

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
that is read-write (SET GLOBAL READ\_ONLY=0).

If it finds more than one node where READ_ONLY == 0, it will abort.

For slave configurations (slave: true specified):

The application will choose a replica at random from amongst those where READ_ONLY == 1.  If no active replicas are found, 
it will fall back to the master.

### run time

Before each transaction is opened on the master, the application checks the status of the READ_ONLY variable.
If READ\_ONLY == 0 (our active connection is still to the current master), it will proceed with the 
transaction as normal.  If READ\_ONLY == 1 (the master has been demoted), it will drop the current connection 
and re-poll the cluster, sleeping for up to a default of 5 seconds for 
a new master to be promoted.  When it finds the new master, it will continue playing the transaction on it.

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
1. record the master-bin-log position of the candidate master (if you want to re-use the old master as a replica)
1. set the new master to READ_ONLY = 0 

The application nodes will, in time, find that the old master is inactive and will move their connections to the 
new master. 

The application will also eventually shift slave traffic to another node in the cluster.

### caveats, gotchas

- Any explicit ( BEGIN ... END ) transaction that are in-flight when the old master goes READ_ONLY
  will crash.  In theory there's a workaround for this problem, in pratice it's rather unwieldy due
  to a lack of shared global variables in mysql.

- Connection variables are unsupported, due to the connection being able to go away at any time.

## Installation

Do a little dance.  Drink a little water.  Or:
Add this line to your application's Gemfile:

    gem 'ar_mysql_flexmaster'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ar_mysql_flexmaster

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request


