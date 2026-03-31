# ansible-playbooks

Ansible playbooks for provisioning and managing a high-availability k3s cluster on Raspberry Pi nodes.

## Cluster Inventory

| Host | Role | IP |
|------|------|----|
| rpi5-0 | Controller | 10.100.20.10 |
| rpi5-1 | Controller | 10.100.20.11 |
| rpi4-0 | Controller | 10.100.20.12 |
| rpi3-0 | Agent (worker) + storage-only | 10.100.20.13 |
| murderbot | GPU host (bare metal) | 10.100.20.19 |
| archlinux | GPU host (bare metal) | 10.100.20.25 |
| mac-mini-m4 | Docker host (OrbStack) | 10.100.20.18 |

All nodes are accessed as user `alex` with SSH key `~/.ssh/alex_id_ed25519`.

## Secrets Policy

**All secrets MUST live in Bitwarden Secrets Manager (BWS). No exceptions.**

- BWS is the single source of truth for every secret used by this repo
- Never pass secrets via environment variables, command-line args, or manual file edits
- Playbooks fetch secrets from BWS at runtime using a single `bws_access_token`
- Secret UUIDs are defined in `group_vars/k3s.yml` (`bws_secrets` dict)
- If a playbook needs a new secret, create it in BWS first, then add the UUID to `group_vars/k3s.yml`

The only manual input is the BWS access token itself:

```bash
ansible-playbook -i inventory/inventory.ini all.yml -e bws_access_token=<TOKEN>
```

> **Status (2026-03-30):** `fetch-secrets.yml` implemented and wired into
> `k3s-recover.yml`. BWS UUID for `k3s-dean-etcd-token` populated. The `bws`
> CLI auto-installs on first run. Some playbooks still accept `k3s_token`
> directly as a transitional fallback. Remaining: wire BWS into
> `k3s-controller.yml`, `k3s-agent.yml`, and `post-k3s-setup.yml`. The
> auto-recovery service (`k3s-etcd-recovery.service`) is written but not yet
> deployed to any controller — run `k3s-recover.yml` to deploy it.

## Prerequisites

- Ansible installed on your control machine
- SSH access to all Raspberry Pi nodes (key-based)
- BWS access token (read-only) from Bitwarden Secrets Manager

## Directory Structure

```
ansible-playbooks/
├── all.yml                          Master playbook (runs everything)
├── inventory/
│   └── inventory.ini                Node inventory with groups and vars
├── group_vars/                      Group-level variables (incl. BWS secret IDs)
├── tasks/                           Reusable task files
│   ├── check-cluster-health.yml     Health gate — aborts if any node is NotReady
│   ├── wait-for-node-ready.yml      Poll until a node rejoins the cluster
│   └── confirm-destructive.yml      Human confirmation for dangerous operations
├── playbooks/
│   ├── infrastructure/
│   │   ├── setup-rpi.yml            OS-level Raspberry Pi preparation
│   │   ├── k3s-controller.yml       Install k3s server on controller nodes
│   │   ├── k3s-agent.yml            Install k3s agent on worker nodes
│   │   ├── longhorn-storage.yml     Configure Longhorn storage labels/taints
│   │   ├── post-k3s.yml             Post-install cluster configuration
│   │   ├── etcd-tmpfs.yml           Migrate etcd to tmpfs (RAM disk)
│   │   ├── k3s-recover.yml          Cluster recovery (token rotation, snapshot restore)
│   │   ├── enable-etcd-metrics.yml  Expose etcd metrics
│   │   ├── fetch-secrets.yml         Fetch all secrets from BWS
│   │   ├── docker-storage.yml       Move Docker data root to /mnt/storage
│   │   ├── smoke-test.yml           End-to-end cluster health validation
│   │   └── templates/               Jinja2 templates for config files
│   └── applications/
│       └── post-k3s-setup.yml       ArgoCD bootstrap and GitOps setup
```

## Usage

### Full cluster setup

```bash
ansible-playbook -i inventory/inventory.ini all.yml
```

### Run individual playbooks

```bash
# Prepare Raspberry Pi nodes (networking, packages, iSCSI)
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/setup-rpi.yml

# Install k3s on controllers (HA with etcd)
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-controller.yml

# Join worker nodes
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-agent.yml

# Configure Longhorn storage
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/longhorn-storage.yml

# Post-install tasks and verification
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/post-k3s.yml
ansible-playbook -i inventory/inventory.ini playbooks/applications/post-k3s-setup.yml
```

### Use tags to run specific stages

```bash
ansible-playbook -i inventory/inventory.ini all.yml --tags network
ansible-playbook -i inventory/inventory.ini all.yml --tags k3s
ansible-playbook -i inventory/inventory.ini all.yml --tags longhorn
```

## Playbook Descriptions

### Infrastructure

| Playbook | Description | Safety |
|----------|-------------|--------|
| `setup-rpi.yml` | Configures static IP, DNS, required packages, iSCSI for Longhorn | Non-disruptive |
| `k3s-controller.yml` | Installs k3s server with etcd HA, creates kubeconfig | `serial: 1` + health gate |
| `k3s-agent.yml` | Installs k3s agent and joins workers to the cluster | `serial: 1` + health gate |
| `longhorn-storage.yml` | Applies taints, labels, and node selectors for Longhorn | Non-disruptive |
| `post-k3s.yml` | Post-installation cluster configuration (labels, taints) | Non-disruptive |
| `etcd-tmpfs.yml` | Migrate etcd to tmpfs for performance | `serial: 1` + health gate |
| `k3s-recover.yml` | Recovery: token rotation, snapshot restore, auto-recovery | Human confirmation required |
| `enable-etcd-metrics.yml` | Expose etcd metrics on port 2381 | `serial: 1` + health gate |
| `docker-storage.yml` | Move Docker data root to /mnt/storage on GPU hosts | Non-disruptive |
| `smoke-test.yml` | End-to-end cluster health validation (read-only) | Safe to run anytime |

### Applications

| Playbook | Description |
|----------|-------------|
| `post-k3s-setup.yml` | ArgoCD bootstrap, repo secrets, root-app sync |

## Cluster Safety

Playbooks that restart k3s or take nodes offline enforce these invariants:

- **`serial: 1`** — one node at a time, never parallel
- **Pre-flight health gate** — if any node is already NotReady, the playbook aborts rather than risking quorum loss
- **Post-flight health gate** — waits for the node to rejoin and verifies cluster health before moving to the next node
- **Human confirmation** — recovery and destructive playbooks (force restore, token rotation) require typing `yes` before proceeding

The 3-controller etcd cluster tolerates 1 node down. Losing 2 = quorum loss = cluster down. The health gate prevents this by refusing to touch a second node while the first is unhealthy.

## High Availability

- etcd runs on tmpfs (1G RAM disk) for performance, with staggered snapshots to SD card
- Staggered snapshots: each controller offsets by its inventory index (e.g. :00, :01, :02) so a snapshot exists somewhere in the cluster every ~100 seconds
- Auto-recovery service (`k3s-etcd-recovery.service`) runs before k3s on every boot
- On reboot: node rejoins from peers (no restore needed)
- On full power loss: priority-based leader election (rpi5-1 > rpi5-0 > rpi4-0) restores from the most recent snapshot automatically
- The kubeconfig is configured with all controller endpoints for round-robin failover

## Notes

- Longhorn storage labels are applied to all nodes for simplified scheduling
- The `storage_only` group (`rpi3-0`) identifies nodes dedicated to storage workloads
- GPU hosts (murderbot, archlinux) are bare metal Docker hosts, not part of k3s
- After Ansible completes, apply the bootstrap secrets and root application from the `k3s-dean-gitops` repo to finish cluster setup
