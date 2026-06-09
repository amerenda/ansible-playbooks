# ansible-playbooks — Agent Rules

## What Ansible is for

Server provisioning only:
- Installing OS packages and configuring system settings
- Adding users and SSH keys
- Bootstrapping new nodes (k3s join, Docker install)
- Correcting configuration drift on existing servers

## What Ansible is NOT for

- **Ansible does not deploy services.** Deployment is Komodo (stateful) or ArgoCD (stateless).
- **Ansible does not create Docker volumes.** Volumes are created by Docker on first compose start.
- **Ansible does not create PostgreSQL databases.** Databases are created by Tofu via `provision_app`.
- **Ansible is never called by an AI agent.** It is always run by a human.

## One secret input: BWS_ACCESS_TOKEN

Every playbook reads exactly one secret from the environment: `BWS_ACCESS_TOKEN`. No other secrets are accepted as playbook inputs — all other credentials are fetched from BWS at runtime using this token.

## Idempotency requirement

All tasks must be idempotent. Running a playbook twice must produce the same result as running it once. Use `state: present`, `creates:`, `changed_when: false`, and Ansible modules (not raw shell) wherever possible.

## Playbook template

```yaml
---
- name: <Describe what this provisions>
  hosts: <target>
  become: true
  vars:
    bws_token: "{{ lookup('env', 'BWS_ACCESS_TOKEN') }}"
  tasks:
    - name: Fail fast if BWS token is missing
      ansible.builtin.fail:
        msg: "BWS_ACCESS_TOKEN must be set in the environment"
      when: bws_token == ""

    # Fetch secrets from BWS at runtime
    - name: Fetch secret
      ansible.builtin.command:
        cmd: bws secret get <key> --output json
      environment:
        BWS_ACCESS_TOKEN: "{{ bws_token }}"
      register: secret_result
      changed_when: false

    # ... your tasks here
```

## Inventory

- `inventory/` — host groups and connection details
- `group_vars/` — group-level variables (no secrets)
- `all.yml` — cluster-wide variables

## Running playbooks

Playbooks are run manually by a human with:
```bash
BWS_ACCESS_TOKEN=<token> ansible-playbook -i inventory/ playbooks/<name>.yml
```

Never run playbooks in CI pipelines or from agent code.
