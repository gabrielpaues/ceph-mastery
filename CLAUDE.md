# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A throwaway, hands-on Ceph learning lab on Safespring OpenStack. There is no
application here — the artifacts are infrastructure (Terraform), a bootstrap
script, and a guided exercise document. Treat the cluster as ephemeral: it is
built up with `terraform apply`, broken in deliberate ways for the exercises,
and torn down with `terraform destroy`.

## Node roles (and where commands actually run)

Five nodes are provisioned, and the role split matters because the tooling is
not symmetric:

| Node                 | What it runs                              | Has `cephadm`? | Has `ceph` CLI? |
|----------------------|-------------------------------------------|----------------|-----------------|
| `ceph-lab-admin`     | bootstrap script + day-2 operator CLI     | yes            | yes (ceph-common installed, admin keyring copied here) |
| `ceph-lab-mon`       | MON + MGR + Dashboard                     | yes            | via `cephadm shell` |
| `ceph-lab-osd-{1,2,3}` | OSD daemons only                        | **no**         | no              |

Practical consequences:

- **All `ceph` and `ceph orch` commands run on the admin node.** This is the
  default assumption in `exercises/EXERCISES.md` — do not insert SSH-to-OSD
  steps for orchestrator commands. `ceph orch daemon stop osd.X` dispatches to
  the right host on its own.
- SSH into an OSD node only when the action *must* execute on that host
  (e.g. `shutdown`, `iptables`). Even then, `cephadm` is not available there.
- The Ceph cluster's own SSH key (used by the orchestrator) is distributed to
  `/root/.ssh/authorized_keys` on every node by `bootstrap-ceph.sh` step 4.
  This is separate from the OpenStack keypair used to log in as `ubuntu`.

## Common workflows

### Provision / destroy infrastructure

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars   # first time only; edit keypair etc.
terraform init
terraform apply
terraform output            # admin_ip, mon_ip, osd_ips
terraform destroy           # tear it all down
```

### Bootstrap Ceph onto fresh infrastructure

`scripts/bootstrap-ceph.sh` must run **on the admin node**, not from a laptop.
It SSHes out to the other nodes from there.

```bash
ssh ubuntu@<ADMIN_IP>
# Get the repo onto the admin node (clone or scp), then:
./scripts/bootstrap-ceph.sh <MON_IP> <OSD1_IP> <OSD2_IP> <OSD3_IP>
```

The script is mostly idempotent in spirit but not strictly re-runnable — if it
fails partway, the cleanest recovery is usually `terraform destroy` +
`terraform apply` + re-run.

### Verify cluster

From the admin node:

```bash
ceph -s
ceph osd tree
ceph health detail
```

The Dashboard is at `https://<MON_IP>:8443` (user `admin`, password
`ceph-lab-2024` — set in the bootstrap script and intentionally weak; this is
a lab).

## Architectural notes worth knowing before editing

- **Terraform modules are pinned to `github.com/safespring-community/terraform-modules`**
  (compute-instance, compute-security-group). Three security groups attach to
  nodes: `interconnect` (full mesh between cluster nodes), `ssh` (22 from
  anywhere), and `dashboard` (8443 from anywhere, admin only).
- **`cephadm bootstrap` runs with `--single-host-defaults` and
  `--skip-monitoring-stack`** in the script. This keeps resource use low for
  a small lab; it also means default pool sizes/replication settings are tuned
  for a single host and the Prometheus/Grafana stack is absent. Exercises
  override pool size explicitly when it matters.
- **Reef+ caveat (already handled in the script):** `cephadm` must be
  installed via `apt-get install cephadm` on the MON node. Do not switch to
  `scp`'ing the cephadm binary — it now depends on the `cephadmlib` package
  and breaks if installed standalone.
- **OSD data disks** are extra OpenStack volumes (default 30 GB, type `fast`)
  attached as `data_disks` in the `osd` module. `ceph orch apply osd
  --all-available-devices` picks them up.

## Style conventions for this repo

- Commit messages are short, imperative, no Claude/AI co-author trailer.
- The exercise doc (`exercises/EXERCISES.md`) follows a fixed
  "observe, break, observe, fix, observe" rhythm — preserve that structure
  when adding or editing exercises.
