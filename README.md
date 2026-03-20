# Ansible K3s Cluster Setup

This directory contains Ansible playbooks for setting up a high-availability K3s cluster on Raspberry Pi nodes.

## 📁 Directory Structure

```
ansible/
├── playbooks/                    # Main playbooks
│   ├── infrastructure/          # Infrastructure setup
│   │   ├── setup-rpi.yml       # Raspberry Pi node preparation
│   │   ├── k3s-controller.yml  # K3s controller setup
│   │   ├── k3s-worker.yml      # K3s worker setup
│   │   └── longhorn-storage.yml # Longhorn storage configuration
│   └── applications/            # Application deployment
│       └── post-k3s-setup.yml  # Post-K3s setup tasks
├── roles/                       # Reusable Ansible roles
├── group_vars/                  # Group variables
├── inventory/                   # Inventory files
│   └── inventory.ini
├── templates/                   # Jinja2 templates
└── all.yml                     # Master playbook
```

## 🚀 Quick Start

### Prerequisites
- Ansible installed on your control machine
- SSH access to all Raspberry Pi nodes
- K3S_TOKEN environment variable set

### Run the Complete Setup
```bash
# Run the entire cluster setup
ansible-playbook -i inventory/inventory.ini all.yml

# Run specific components
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/setup-rpi.yml
ansible-playbook -i inventory/inventory.ini playbooks/infrastructure/k3s-controller.yml
```

## 📋 Playbook Descriptions

### Infrastructure Playbooks

#### `setup-rpi.yml`
- Prepares Raspberry Pi nodes for K3s
- Configures static IP and DNS
- Installs required packages
- Sets up iSCSI for Longhorn
- Applies Longhorn storage labels

#### `k3s-controller.yml`
- Installs K3s on controller nodes
- Sets up etcd for HA
- Creates HA kubeconfig with all controller endpoints
- Installs ArgoCD for GitOps

#### `k3s-worker.yml`
- Installs K3s agent on worker nodes
- Joins workers to the cluster

#### `longhorn-storage.yml`
- Applies Longhorn taints and labels to storage nodes
- Configures node selectors for Longhorn components

### Application Playbooks

#### `post-k3s-setup.yml`
- Post-installation tasks
- Cluster verification
- Summary display

## 🔧 Configuration

### Environment Variables
```bash
export K3S_TOKEN="your-k3s-token-here"
```

### Inventory
Edit `inventory/inventory.ini` to configure your nodes:
```ini
[controllers]
rpi5-0 ansible_host=10.100.20.10
rpi5-1 ansible_host=10.100.20.11
rpi5-2 ansible_host=10.100.20.12

[workers]
rpi4-0 ansible_host=10.100.20.20
rpi3-0 ansible_host=10.100.20.30

[longhorn_storage]
rpi4-0 ansible_host=10.100.20.20
```

## 🏷️ Tags

Use tags to run specific parts of the setup:

```bash
# Network configuration only
ansible-playbook -i inventory/inventory.ini all.yml --tags network

# K3s installation only
ansible-playbook -i inventory/inventory.ini all.yml --tags k3s

# Longhorn setup only
ansible-playbook -i inventory/inventory.ini all.yml --tags longhorn
```

## 🔄 High Availability

The kubeconfig is automatically configured with all controller endpoints for round-robin load balancing. If one controller goes offline, kubectl will automatically try the next available controller.

## 📝 Notes

- All playbooks use `become: no` for kubectl operations to avoid sudo prompts
- Longhorn storage labels are applied to all nodes for simplified scheduling
- The setup includes static IP configuration for reliable networking