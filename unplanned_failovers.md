Here's a logic flow I've been thinking about for dealing with master outages.  In plain english, I'm generally 
thinking:

- inside a transaction, we will never attempt to recover from a master failure or attempt to ensure proper connections
- outside a transaction, we'll try to be liberal about recovering from bad states and limp along in a read-only mode
  as best we can.

guard:
  begin
    yield
  rescue 'server gone away', "can't connect to server"
    retry-once
  end

hard_verify(INSERTs) == verify correct connection, try for 5 seconds, crash and unset connection if you can't

soft_verify(SELECTs) == every N requests, try to verify that your connection is the right one.

If you're running a SELECT targeted at the master, and no master is online, it's acceptable to use either
the old master (your existing connection) or a slave connection for the purposes of reads (until the next
verify)

This will allow us to limp along in read-only mode for a short time until a new master can be promoted. 
The downside of this approach is that in a pathological case we could be making decisions based on stale 
or incorrect data.  I feel that the odds of this are long and are probably made up for by having a 
halfway decent read-only mode.

```
switch incoming_sql:
  BEGIN:
    - in transaction? 
     -> do not verify, do not guard.

    - guard { hard-verify }
    - execute BEGIN statement (without guard).  hard to reconnect here because of side effects

  INSERT/UPDATE/DELETE:
    - in transaction?
      -> do not verify, do not guard 
    -> guard { hard-verify, execute }

  SELECT:
    - in transaction? 
      -> no verify, no guard
    -> guard { soft-verify / execute } 
``` 

