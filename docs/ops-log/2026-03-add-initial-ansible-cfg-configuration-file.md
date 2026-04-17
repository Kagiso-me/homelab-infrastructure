# 2026-03 — DEPLOY: Add initial ansible.cfg configuration file

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Ansible · ansible.cfg
**Commit:** —
**Downtime:** None

---

## What Changed

Created the initial `ansible/ansible.cfg` configuration file establishing baseline Ansible settings for the homelab.

---

## Why

Without `ansible.cfg`, every ansible-playbook invocation required explicit flags for inventory path, SSH settings, and other options. `ansible.cfg` makes the correct settings the default — less typing, fewer mistakes.

---

## Details

```ini
[defaults]
inventory = inventory/hosts.yml
remote_user = ubuntu
private_key_file = ~/.ssh/homelab_ed25519
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
```

- `pipelining = True`: speeds up playbook execution by reducing SSH round-trips
- `ControlMaster/ControlPersist`: SSH connection multiplexing — reuse established connections
- `stdout_callback = yaml`: cleaner output than the default minimal callback
- `host_key_checking = False`: acceptable on a trusted LAN, avoids friction when reprovisioning nodes

---

## Outcome

- Ansible playbooks run with correct defaults ✓
- No more explicit inventory or SSH key flags needed ✓

---

## Related

- Ansible config: `ansible/ansible.cfg`
