# ansible-playbooks

Ansible playbooks for provisioning and managing a high-availability k3s cluster on Raspberry Pi nodes.

## Cluster Inventory

| Host | Role | IP | Notes |
|------|------|----|-------|
| rpi5-0 | Controller (cluster-init) | 10.100.20.10 | |
| rpi5-1 | Controller | 10.100.20.11 | Preferred restore leader |
| rpi4-0 | Controller | 10.100.20.12 | 4GB RAM, tight memory |
| rpi3-0 | Agent (storage-only) | 10.100.20.13 | Longhorn replica node |
| murderbot | GPU host (bare metal Docker) | 10.100.20.19 | Not part of k3s |
| archlinux | GPU host (bare metal Docker) | 10.100.20.25 | Not part of k3s |
| mac-mini-m4 | Docker host (OrbStack) | 10.100.20.18 | Not part of k3s |

All nodes are accessed as user `alex` with SSH key `~/.ssh/alex_id_ed25519`.

## Secrets Policy

**All secrets MUST live in Bitwarden Secrets Manager (BWS). No exceptions.**

- BWS is the single source of truth for every secret used by this repo
- Playbooks fetch secrets from BWS at runtime using a single `bws_access_token`
- Secret UUIDs are defined in `group_vars/k3s.yml` (`bws_secrets` dict)
- The `bws` CLI auto-installs on first run if not present

The only manual input is the BWS access token itself:

```bash
ansible-playbook -i inventory/inventory.ini all.yml -e bws_access_token=<TOKEN>
```

## Prerequisites

- Ansible installed on your control machine
- SSH access to all nodes (key-based, `~/.ssh/alex_id_ed25519`)
- BWS access token from Bitwarden Secrets Manager
- Ansible collections: `ansible-galaxy collection install -r requirements.yml`

## Directory Structure

```
ansible-playbooks/
├── all.yml                          Master playbook (full cluster setup)
├── requirements.yml                 Ansible collection dependencies
├── inventory/
│   └── inventory.ini                Node inventory with groups and host vars
├── group_vars/
│   ├── k3s.yml                      k3s cluster vars, BWS secret UUIDs, network config
│   ├── rpi.yml                      RPi common vars (packages, locale, timezone)
│   ├── macmini_hosts.yml            Mac Mini specific vars
│   └── rpi5_hosts.yml               RPi 5 specific vars (NVMe mount points)
├── host_vars/
│   └── rpi3-0.yml                   Storage-only node resource reservations
├── tasks/
│   ├── check-cluster-health.yml     Health gate — aborts if any node is NotReady
│   ├── wait-for-node-ready.yml      Poll until a node rejoins the cluster
│   └── confirm-destructive.yml      Human confirmation prompt for dangerous ops
└── playbooks/
    ├── infrastructure/
    │   ├── setup-rpi.yml            OS-level Raspberry Pi preparation
    │   ├── k3s-controller.yml       Install k3s server on controller nodes
    │   ├── k3s-agent.yml            Install k3s agent on worker nodes
    │   ├── longhorn-storage.yml     iSCSI/NFS prerequisites + Longhorn scheduling
    │   ├── post-k3s.yml             Node labels and taints
    │   ├── etcd-tmpfs.yml           Migrate etcd to tmpfs (RAM disk)
    │   ├── nvme-setup.yml           RPi 5 NVMe HAT+ configuration
    │   ├── k3s-recover.yml          Smart recovery (token rotation, snapshot restore)
    │   ├── k3s-full-recovery.yml    Break-glass: full cluster restore from snapshot
    │   ├── enable-etcd-metrics.yml  Expose etcd metrics for Prometheus
    │   ├── fetch-secrets.yml        Fetch all secrets from BWS
    │   ├── docker-storage.yml       Move Docker data root to /mnt/storage (GPU hosts)
    │   ├── setup-macmini.yml        Mac Mini M4 Docker host setup
    │   └── smoke-test.yml           End-to-end cluster health validation
    └── applications/
        └── post-k3s-setup.yml       ArgoCD bootstrap and GitOps setup
```

## Usage

### Full cluster setup (from scratch)

```bash
ansible-playbook -i inventory/inventory.ini all.yml -e bws_access_token=<TOKEN>
```

`all.yml` runs in order: secrets → RPi setup → k3s controllers → agents → Longhorn → labels/taints → etcd tmpfs → auto-recovery service → ArgoCD bootstrap → smoke test.

### Individual playbooks

```bash
# Prepare RPi nodes (networking, packages, cgroups)
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/setup-rpi.yml

# Install k3s on controllers (HA with etcd)
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-controller.yml \
  -e bws_access_token=<TOKEN>

# Join worker nodes
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-agent.yml \
  -e bws_access_token=<TOKEN>

# Configure Longhorn storage prerequisites
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/longhorn-storage.yml

# Apply node labels and taints
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/post-k3s.yml

# Migrate etcd to RAM disk
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/etcd-tmpfs.yml \
  -e bws_access_token=<TOKEN>

# Setup RPi 5 NVMe HAT+
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/nvme-setup.yml \
  --limit rpi5-0

# Bootstrap ArgoCD and GitOps
ansible-playbook -i inventory/inventory.ini playbooks/applications/post-k3s-setup.yml \
  -e bws_access_token=<TOKEN>

# Validate cluster health (read-only, safe anytime)
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/smoke-test.yml

# Setup Mac Mini Docker host
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/setup-macmini.yml \
  -e bws_access_token=<TOKEN>
```

## Playbook Descriptions

### Infrastructure

| Playbook | Description | Safety |
|----------|-------------|--------|
| `setup-rpi.yml` | Static IP, DNS, packages, cgroup config for k3s | Non-disruptive |
| `k3s-controller.yml` | Installs k3s server with etcd HA, pulls kubeconfig | `serial: [1, n-1]` + health gate |
| `k3s-agent.yml` | Installs k3s agent and joins workers | `serial: 1` + health gate |
| `longhorn-storage.yml` | iSCSI, NFS, kernel modules; Longhorn scheduling config | Non-disruptive |
| `post-k3s.yml` | Node labels (`longhorn-storage`, `rpi5-host`) and taints | Non-disruptive |
| `etcd-tmpfs.yml` | Migrates etcd to tmpfs (1G RAM disk) with snapshot pre-backup | `serial: 1` + health gate + confirmation |
| `nvme-setup.yml` | Enables PCIe Gen 2, formats + mounts NVMe for Longhorn | RPi 5 only; requires reboot |
| `k3s-recover.yml` | Smart recovery: fixes config, tmpfs, token; deploys auto-recovery service | `serial: 1`; destructive ops need confirmation |
| `k3s-full-recovery.yml` | Break-glass: restores all controllers from snapshot when cluster is fully down | Confirmation required; see [Cluster Recovery](#cluster-recovery) |
| `enable-etcd-metrics.yml` | Adds `--etcd-expose-metrics=true` to k3s config | `serial: 1` + health gate |
| `fetch-secrets.yml` | Fetches secrets from BWS and sets facts for subsequent plays | Non-disruptive |
| `docker-storage.yml` | Moves Docker data root to `/mnt/storage` on GPU hosts | GPU hosts only |
| `setup-macmini.yml` | OrbStack, Ollama, Komodo, Tailscale, BlueBubbles on Mac Mini | Mac Mini only |
| `smoke-test.yml` | Validates nodes, etcd, tmpfs, snapshots, Longhorn, ArgoCD | Read-only, safe anytime |

### Applications

| Playbook | Description |
|----------|-------------|
| `post-k3s-setup.yml` | Installs ArgoCD via Helm, creates repo + BWS secrets, applies root-app |

## Cluster Safety

Playbooks that restart k3s or take nodes offline enforce these invariants:

- **`serial: 1`** — one node at a time, never parallel
- **Pre-flight health gate** — if any node is NotReady, the playbook aborts before touching anything
- **Post-flight health gate** — waits for the node to rejoin and verifies cluster health before moving on
- **Human confirmation** — destructive operations (force restore, token rotation, full recovery) require typing `yes`

The 3-controller etcd cluster tolerates 1 node down. The health gate prevents touching a second node while the first is still recovering, avoiding quorum loss.

## High Availability

- **etcd on tmpfs**: etcd data runs on a 1G RAM disk for performance (SD card I/O is too slow). Data is wiped on every reboot — recovery depends on snapshots.
- **Snapshots**: Taken every 5 minutes to SD card (`/var/lib/rancher/k3s/server/db/snapshots/`), 12 retained. Each controller offsets by its inventory index (`:00`, `:01`, `:02`), so a snapshot exists somewhere in the cluster roughly every 100 seconds.
- **Auto-recovery service**: `k3s-etcd-recovery.service` runs before k3s on every boot. Handles both single-node reboots (rejoin from peers) and full power loss (leader election + snapshot restore). Deployed by `k3s-recover.yml`.
- **Restore priority**: rpi5-1 → rpi5-0 → rpi4-0 (by inventory index, weighted by snapshot freshness).

## Cluster Recovery

### Automatic (first — wait ~15 minutes)

`k3s-etcd-recovery.service` runs on boot and handles recovery without intervention:

- **Single node reboot**: detects peers are up, wipes local etcd, rejoins cluster. No data loss.
- **Full power loss**: waits up to 3 minutes for any peer, then the node with the freshest snapshot restores it and becomes leader. Others rejoin once the API is up. Data loss window: up to 5 minutes.

Check whether it worked:

```bash
ssh alex@10.100.20.10
sudo journalctl -u k3s-etcd-recovery.service --no-pager -n 30
sudo systemctl is-active k3s
curl -k https://localhost:6443/healthz
```

### Ansible — smart recovery (partial failures, config issues)

Use `k3s-recover.yml` when auto-recovery ran but left the cluster in a bad state, or for targeted fixes:

```bash
# Fix config/tmpfs issues and deploy auto-recovery service
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-recover.yml \
  -e bws_access_token=<TOKEN>

# Force restore from snapshot on a single node
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-recover.yml \
  -e bws_access_token=<TOKEN> -e force_restore=true --limit rpi5-1

# Rotate the k3s cluster token across all nodes
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-recover.yml \
  -e bws_access_token=<TOKEN> -e rotate_token=true
```

### Ansible — full cluster restore (all controllers down, auto-recovery failed)

`k3s-full-recovery.yml` is the break-glass playbook. It finds the most recent snapshot across all controllers, restores the leader, then rejoins the others.

```bash
# Dry run first
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-full-recovery.yml \
  -e bws_access_token=<TOKEN> --check

# Actual recovery
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-full-recovery.yml \
  -e bws_access_token=<TOKEN>
```

What it does:
1. Pre-flight: validates SSH access, finds snapshots, checks etcdctl
2. Elects restore leader (node with freshest snapshot)
3. Stops k3s on all controllers
4. Restores leader from snapshot (`--server ""` overrides the config's `server:` value so `--cluster-reset` works correctly)
5. Copies restored etcd data to tmpfs, starts leader
6. Cleans etcd on followers, starts them — they rejoin the leader
7. Waits for all nodes Ready, validates etcd health

### Verify after recovery

```bash
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/smoke-test.yml
```

Or manually:

```bash
kubectl get nodes
kubectl get --raw /healthz/etcd
kubectl get applications -A          # ArgoCD auto-syncs within 3-5 min
kubectl get volumes -A -n longhorn-system
```

## Notes

- GPU hosts (`murderbot`, `archlinux`) are bare metal Docker hosts, not part of k3s
- `rpi3-0` is storage-only: Longhorn replicas + DaemonSets only, `longhorn:NoSchedule` taint prevents other workloads
- After a full cluster reset, ArgoCD will auto-reconcile all applications from git within a few minutes
- After Ansible completes on a fresh cluster, apply bootstrap secrets and the root-app from `k3s-dean-gitops` to finish GitOps setup
