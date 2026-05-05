# Ceph Operations Lab - Exercise Guide

## How to use this guide

Every exercise follows the same rhythm: **observe, break, observe, fix, observe**.
You always check the cluster state before and after each action. This builds
the most important skill in Ceph operations: reading the cluster health and
understanding what it is telling you.

Run all commands from the **admin node** unless otherwise stated.

---

## The Instrument Panel

Before breaking anything, get fluent with these commands. Run each one now
and study the output.

### The Big Five

```bash
# 1. Overall cluster health (the single most important command)
ceph -s

# 2. Why is the cluster unhappy? (details behind any warnings)
ceph health detail

# 3. Where are the OSDs? (CRUSH topology - host/rack/OSD mapping)
ceph osd tree

# 4. How full are the disks?
ceph osd df

# 5. Placement group summary
ceph pg stat
```

### Supporting Cast

```bash
# Pool list with replication settings
ceph osd pool ls detail

# Overall capacity
ceph df

# Recent cluster log events
ceph log last 50

# Watch cluster events in real time (keep a terminal open with this)
ceph -w

# Daemon versions
ceph tell osd.* version
ceph tell mon.* version
```

### Key things to notice in `ceph -s`

- **health**: HEALTH_OK / HEALTH_WARN / HEALTH_ERR
- **mon**: quorum membership (need majority for writes)
- **osd**: X osds, Y up, Z in (up = daemon running, in = participating in data placement)
- **pools**: number of pools and total PGs
- **data**: stored, used, available
- **pgs**: should all say "active+clean" when healthy

---

## Exercise 1: OSD Goes Down (Simulating a Disk Failure)

**Goal**: Understand what happens when one OSD stops, how PGs degrade and
recover, and the difference between "out" and "down".

### 1.1 Baseline

```bash
ceph -s              # Note: all PGs active+clean
ceph osd tree        # Note which OSDs are on which hosts
ceph osd df          # Note data distribution
```

### 1.2 Break it

Pick an OSD (say osd.0) and stop it. `ceph orch` is an orchestrator command —
the admin node dispatches it to whichever host runs that OSD, so you do not
need to SSH anywhere. (The OSD hosts do not have `cephadm` installed; only
the admin and MON nodes do.)

```bash
# (Optional) See which host osd.0 lives on
ceph osd find 0

# Stop the daemon (from the admin node)
ceph orch daemon stop osd.0
```

### 1.3 Observe the damage

```bash
ceph -s              # You will see HEALTH_WARN, degraded PGs
ceph health detail   # Lists exactly which PGs are degraded
ceph osd tree        # osd.0 shows as "down" but still "in"
```

**Key concept**: "down" means the daemon is not running. "in" means the OSD is
still part of the CRUSH map and data is expected to live there. After 10 minutes
(configurable via `mon_osd_down_out_interval`), Ceph will automatically mark it
"out" and start rebalancing data to surviving OSDs.

### 1.4 Watch the 10-minute timer

```bash
# Watch in real time
ceph -w

# Or check the timer
ceph osd dump | grep "osd.0"
```

After the OSD is marked "out", you will see recovery I/O as Ceph rebuilds the
missing replicas on the remaining OSDs.

### 1.5 Fix it

```bash
# Restart the OSD (from the admin node)
ceph orch daemon start osd.0

# Watch recovery
ceph -w
ceph osd tree        # osd.0 should come back as "up" and "in"
```

### 1.6 Key takeaways

- One OSD going down does NOT mean data loss (replication protects you)
- There is a grace period before rebalancing starts
- Recovery happens automatically once the OSD comes back or is marked out
- `ceph health detail` tells you exactly what is wrong

---

## Exercise 2: Full Node Failure

**Goal**: Simulate losing an entire server. Understand that the cluster stays
available and learn about the `noout` flag.

### 2.1 Break it

Shut down one entire OSD node:

```bash
ssh ubuntu@<OSD1_IP> sudo shutdown now
```

### 2.2 Observe

```bash
ceph -s              # HEALTH_WARN, degraded PGs, one or more OSDs down
ceph osd tree        # All OSDs on that host are down
```

The cluster is still serving I/O because the other two replicas are intact.

### 2.3 The noout flag (maintenance mode)

If you KNOW you are doing maintenance and the node is coming back, you can
prevent the 10-minute rebalance with `noout`:

```bash
# Set the flag BEFORE taking the node down
ceph osd set noout

# Verify
ceph osd dump | grep noout
ceph -s              # You will see "noout flag(s) set" in health

# When maintenance is done, unset it
ceph osd unset noout
```

**Why this matters**: Rebalancing moves terabytes of data. If the node is coming
back in 20 minutes, rebalancing is wasteful and doubles the risk (you are
running degraded AND doing I/O-heavy recovery simultaneously).

### 2.4 Fix it

Boot the node back up from OpenStack console or:

```bash
openstack server start ceph-lab-osd-1
```

Watch recovery:

```bash
ceph -w
```

### 2.5 All the OSD flags

```bash
# View current flags
ceph osd dump | grep ^flags

# The important maintenance flags:
ceph osd set noout        # Don't mark OSDs out when they go down
ceph osd set noin         # Don't mark new/returning OSDs in
ceph osd set norebalance  # Don't rebalance when OSDs go in/out
ceph osd set nobackfill   # Don't backfill (a type of recovery)
ceph osd set norecover    # Don't start recovery
ceph osd set noscrub      # Don't scrub (verification)
ceph osd set nodeep-scrub # Don't deep-scrub

# Typical maintenance workflow:
ceph osd set noout
# ... do maintenance ...
ceph osd unset noout
```

---

## Exercise 3: CRUSH Map and Data Placement

**Goal**: Understand how CRUSH determines where data lives.

### 3.1 View the CRUSH map

```bash
# Human-readable CRUSH tree
ceph osd crush tree

# Detailed CRUSH rules
ceph osd crush rule ls
ceph osd crush rule dump replicated_rule

# Which OSDs hold data for a specific PG?
ceph pg map 1.0
```

### 3.2 Understand the hierarchy

```
root (default)
  host (ceph-lab-osd-1)
    osd.0
  host (ceph-lab-osd-2)
    osd.1
  host (ceph-lab-osd-3)
    osd.2
```

The default `replicated_rule` says: "for each replica, pick a different host".
This is why losing one host does not lose data.

### 3.3 Test: What if CRUSH is wrong?

```bash
# Move osd.1 to osd-1's host in the CRUSH map (simulating a mistake)
ceph osd crush move osd.1 host=ceph-lab-osd-1

# Check what happens
ceph -s              # You may see warnings about PG placement
ceph osd tree        # Two OSDs under one host

# Fix it
ceph osd crush move osd.1 host=ceph-lab-osd-2
```

---

## Exercise 4: Nearfull and Full OSDs

**Goal**: Learn how Ceph protects itself when disks fill up, and how to recover.

### 4.1 Check current ratios

```bash
ceph osd dump | grep -E "full_ratio|nearfull_ratio|backfillfull_ratio"
# Default: nearfull 0.85, backfillfull 0.90, full 0.95
```

### 4.2 Simulate nearfull (lower the threshold temporarily)

```bash
# DANGER: Only do this in a lab!
# Temporarily lower the nearfull ratio
ceph osd set-nearfull-ratio 0.3

# Check
ceph -s    # You will likely see HEALTH_WARN about nearfull OSDs

# Reset
ceph osd set-nearfull-ratio 0.85
```

### 4.3 Simulate full (carefully!)

```bash
# Lower the full ratio so we trigger it without filling the disk
ceph osd set-full-ratio 0.35

# Now try to write
rados -p test-pool put testfile /etc/hostname
# This SHOULD be blocked if any OSD is past 35%

# IMMEDIATELY reset the ratio
ceph osd set-full-ratio 0.95
```

### 4.4 Real-world full OSD recovery

When an OSD is truly full in production:

1. `ceph osd set-full-ratio 0.97` (temporarily raise to allow rebalance)
2. Delete unnecessary data or pools
3. Add more OSDs
4. `ceph osd reweight-by-utilization` (even out data distribution)
5. Reset ratio: `ceph osd set-full-ratio 0.95`

### 4.5 Monitor capacity proactively

```bash
# Per-OSD utilization
ceph osd df tree

# Which pools use the most space?
ceph df detail

# Utilization variance (are OSDs balanced?)
ceph osd df tree | tail -1    # Check the TOTAL line
```

---

## Exercise 5: Pool Management

**Goal**: Create, configure, and destroy pools. Understand replication vs PG count.

### 5.1 Create a pool

```bash
# Replicated pool with 32 PGs, 3 replicas
ceph osd pool create lab-pool 32 32 replicated
ceph osd pool set lab-pool size 3
ceph osd pool set lab-pool min_size 2
ceph osd pool application enable lab-pool rbd

# Verify
ceph osd pool ls detail
```

### 5.2 Write some data

```bash
# Using rados directly
rados -p lab-pool put object1 /etc/hostname
rados -p lab-pool put object2 /etc/hosts
rados -p lab-pool ls

# Using RBD (block device)
rbd create lab-pool/disk1 --size 512
rbd ls lab-pool
rbd info lab-pool/disk1
```

### 5.3 Change replication

```bash
# Drop to 2 replicas (saves space but less protection)
ceph osd pool set lab-pool size 2

# Watch PGs adjust
ceph -w

# Raise back to 3
ceph osd pool set lab-pool size 3
```

### 5.4 Pool snapshots

```bash
ceph osd pool mksnap lab-pool snap1
rados -p lab-pool put object3 /etc/resolv.conf
ceph osd pool lssnap lab-pool

# Rollback is per-object with rados, or use RBD snapshots for block:
rbd snap create lab-pool/disk1@before-test
rbd snap ls lab-pool/disk1
```

### 5.5 Delete a pool (with safety)

```bash
# Ceph requires you to type the name twice and pass a flag
ceph osd pool delete lab-pool lab-pool --yes-i-really-really-mean-it

# If this fails, you need to enable deletion first:
ceph tell mon.* config set mon_allow_pool_delete true
```

---

## Exercise 6: Replace / Add an OSD

**Goal**: The bread-and-butter maintenance operation. Remove a failed OSD cleanly,
add a new one.

### 6.1 Remove an OSD

```bash
# Mark it out (start data migration away from it)
ceph osd out osd.0

# Wait for recovery to complete
ceph -w
# Wait until all PGs are active+clean

# Stop the daemon (from the admin node)
ceph orch daemon stop osd.0

# Remove from CRUSH map
ceph osd crush remove osd.0

# Delete auth key
ceph auth del osd.0

# Remove the OSD entry
ceph osd rm osd.0

# Verify
ceph osd tree
```

### 6.2 Add a new OSD

```bash
# If the old disk was replaced, the new one should appear as available:
ceph orch device ls

# Add it
ceph orch daemon add osd <hostname>:/dev/vdb

# Or let the orchestrator find it
ceph orch apply osd --all-available-devices

# Watch it join
ceph -w
ceph osd tree
```

---

## Exercise 7: Network Partition (MON Quorum)

**Goal**: Understand MON quorum and what happens when it breaks.

### 7.1 Check current quorum

```bash
ceph quorum_status -f json-pretty | jq '.quorum_names'
ceph mon stat
```

### 7.2 Add extra MONs first (so we have 3 for a real quorum test)

```bash
# Add MON daemons to OSD hosts (in production you want 3 or 5 MONs)
ceph orch apply mon 3
# Or explicitly:
ceph orch daemon add mon ceph-lab-osd-1
ceph orch daemon add mon ceph-lab-osd-2

# Wait and verify
ceph mon stat    # Should show 3 monitors
```

### 7.3 Break it with iptables

```bash
# On one MON host, block the MON port (3300 and 6789)
ssh ubuntu@<OSD1_IP> sudo iptables -A INPUT -p tcp --dport 3300 -j DROP
ssh ubuntu@<OSD1_IP> sudo iptables -A INPUT -p tcp --dport 6789 -j DROP
ssh ubuntu@<OSD1_IP> sudo iptables -A OUTPUT -p tcp --dport 3300 -j DROP
ssh ubuntu@<OSD1_IP> sudo iptables -A OUTPUT -p tcp --dport 6789 -j DROP
```

### 7.4 Observe

```bash
ceph -s              # May be slow - MON quorum is degraded
ceph mon stat        # One fewer in quorum
ceph health detail   # Will warn about MON being down
```

With 3 MONs, losing 1 still gives you a majority (2/3). Losing 2 would break
the cluster (no quorum = no new writes).

### 7.5 Fix it

```bash
ssh ubuntu@<OSD1_IP> sudo iptables -F
```

---

## Exercise 8: Scrubbing and Inconsistent PGs

**Goal**: Understand how Ceph verifies data integrity.

### 8.1 Check scrub schedule

```bash
ceph pg dump | grep -i scrub | head
ceph config get osd osd_scrub_begin_hour
ceph config get osd osd_scrub_end_hour
```

### 8.2 Trigger a manual scrub

```bash
# Light scrub (metadata check)
ceph pg scrub 1.0

# Deep scrub (reads and checksums all data)
ceph pg deep-scrub 1.0

# Watch the result
ceph pg 1.0 query | jq '.info.stats.last_scrub_stamp'
```

### 8.3 Repair an inconsistent PG

If a scrub finds inconsistency (unlikely in lab, but in production this happens):

```bash
# Check for inconsistent PGs
ceph health detail | grep inconsistent

# Repair
ceph pg repair <PG_ID>
```

---

## Exercise 9: Performance Investigation

**Goal**: Learn to diagnose slow operations.

### 9.1 Check for slow ops

```bash
# Any operations taking too long?
ceph daemon osd.0 ops
ceph daemon osd.0 dump_historic_ops

# Blocked requests
ceph health detail | grep -i slow
ceph health detail | grep -i blocked
```

### 9.2 OSD performance stats

```bash
# OSD perf counters
ceph osd perf

# Per-OSD latency
ceph osd df tree   # Check the columns carefully

# Benchmark a pool
rados bench -p test-pool 30 write --no-cleanup
rados bench -p test-pool 30 seq
rados bench -p test-pool 30 rand

# Clean up benchmark objects
rados -p test-pool cleanup
```

### 9.3 Reweight for balance

```bash
# If some OSDs are hotter than others:
ceph osd reweight-by-utilization 110

# Or manually (weight 0.0 to 1.0):
ceph osd reweight osd.0 0.8
```

---

## Mental Models for Ceph Operations

### The Data Path

```
Client write
  -> Pool (replication rules)
    -> PG (placement group, determined by hash of object name)
      -> OSD set (determined by CRUSH algorithm)
        -> Primary OSD writes, then replicates to secondaries
```

### When to Panic (and When Not To)

| Situation                        | Panic level | Why                                          |
|----------------------------------|-------------|----------------------------------------------|
| HEALTH_WARN, some PGs degraded   | Low         | Data still has replicas, recovery is coming   |
| One OSD down                     | Low         | Expected in normal operations                 |
| HEALTH_ERR, PGs stuck peering    | Medium      | Investigate - likely a host or network issue  |
| nearfull warning                 | Medium      | Act soon - add capacity or delete data        |
| Multiple OSDs down same time     | High        | Check for common cause (network, power, rack) |
| full flag set                    | High        | Cluster stopped writes, immediate action      |
| No MON quorum                    | Critical    | Cluster cannot process new operations          |
| PGs inconsistent after scrub     | Medium      | Run pg repair, investigate hardware            |

### The Golden Rules

1. **Always check `ceph -s` first.** It is your dashboard.
2. **Set `noout` before planned maintenance.** Always.
3. **Never remove more OSDs than your replication allows.** With size=3 and
   min_size=2, losing 2 replicas of any PG means that PG is unavailable.
4. **PG count matters.** Too few PGs = uneven distribution. Too many = overhead.
   Rule of thumb: ~100 PGs per OSD in total across all pools.
5. **CRUSH is your friend.** Understand the failure domains. If all OSDs are on
   one host, host failure = total data loss regardless of replication.
6. **Capacity planning**: With 3x replication, you need 3x the raw capacity.
   And Ceph stops writes at 95% full, not 100%.
7. **Time sync is critical.** If NTP drifts, you will get MON quorum issues.
   Always verify chrony/NTP on all nodes.
8. **Read the health detail.** `ceph health detail` tells you exactly what to do
   in most cases. Ceph is remarkably good at explaining its own problems.
