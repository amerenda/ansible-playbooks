# ansible-playbooks

Ansible playbooks for provisioning and managing a high-availability k3s cluster on Raspberry Pi nodes.

## Cluster Inventory

| Host | Role | IP |
|------|------|----|
| rpi5-0 | Controller | 10.100.20.10 |
| rpi5-1 | Controller | 10.100.20.11 |
| rpi4-0 | Controller | 10.100.20.12 |
| rpi3-0 | Agent (worker) + storage-only | 10.100.20.13 |

All nodes are accessed as user `alex` with SSH key `~/.ssh/alex_id_ed25519`.

## Prerequisites

- Ansible installed on your control machine
- SSH access to all Raspberry Pi nodes (key-based)
- `K3S_TOKEN` environment variable set for cluster join token

## Directory Structure

```
ansible-playbooks/
├── all.yml                          Master playbook (runs everything)
├── inventory/
│   └── inventory.ini                Node inventory with groups and vars
├── group_vars/                      Group-level variables
├── playbooks/
│   ├── infrastructure/
│   │   ├── setup-rpi.yml            OS-level Raspberry Pi preparation
│   │   ├── k3s-controller.yml       Install k3s server on controller nodes
│   │   ├── k3s-agent.yml            Install k3s agent on worker nodes
│   │   ├── longhorn-storage.yml     Configure Longhorn storage labels/taints
│   │   ├── post-k3s.yml             Post-install cluster configuration
│   │   └── templates/               Jinja2 templates for config files
│   └── applications/
│       └── post-k3s-setup.yml       Final verification and summary
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

| Playbook | Description |
|----------|-------------|
| `setup-rpi.yml` | Configures static IP, DNS, required packages, iSCSI for Longhorn, and storage labels |
| `k3s-controller.yml` | Installs k3s server with etcd HA, creates kubeconfig with all controller endpoints, installs ArgoCD |
| `k3s-agent.yml` | Installs k3s agent and joins workers to the cluster |
| `longhorn-storage.yml` | Applies taints, labels, and node selectors for Longhorn components |
| `post-k3s.yml` | Post-installation cluster configuration |

### Applications

| Playbook | Description |
|----------|-------------|
| `post-k3s-setup.yml` | Cluster verification and setup summary |

## High Availability

The kubeconfig is automatically configured with all controller endpoints for round-robin load balancing. If one controller goes down, kubectl falls through to the next available controller.

## Notes

- All playbooks use `become: no` for kubectl operations to avoid sudo prompts
- Longhorn storage labels are applied to all nodes for simplified scheduling
- The `storage_only` group (`rpi3-0`) identifies nodes dedicated to storage workloads
- After Ansible completes, apply the bootstrap secrets and root application from the `k3s-dean-gitops` repo to finish cluster setup
