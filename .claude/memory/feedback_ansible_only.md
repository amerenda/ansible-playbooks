---
name: feedback_ansible_only
description: All Mac Mini changes must go through ansible playbooks, never direct SSH commands
type: feedback
---

All modifications to the Mac Mini must be done through ansible playbooks.
Do not run direct SSH commands to install, configure, or modify the Mac Mini.

**Why:** User wants to be able to set up the Mac Mini from scratch using only ansible.
Every manual SSH command is a step that won't be reproduced on a fresh setup.

**How to apply:** When making changes to the Mac Mini, update the ansible playbook first,
push it, then tell the user to pull and run the playbook. Never `ssh mini` to make changes directly.
