# 2026-03 — DEPLOY: Add Cloudflare API token secret management and update Ansible configuration

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** Cloudflare · Ansible · cert-manager · SOPS
**Commit:** —
**Downtime:** None

---

## What Changed

Extended the Cloudflare API token secret management to support rotation — added an Ansible task to update the token in the Kubernetes secret without a full cluster reprovisioning. Also updated `ansible.cfg` to enable fact caching and set default inventory path.

---

## Why

The initial bootstrap created the Cloudflare token secret once but there was no procedure for rotating it. API tokens should be rotatable without manual kubectl commands on the node. The Ansible task makes rotation a one-liner from any machine with Ansible and the vault password.

`ansible.cfg` improvements reduce command verbosity — not specifying `-i inventory/hosts.yml` on every command is a small quality-of-life improvement that matters when running playbooks frequently.

---

## Details

- **Rotation task**: `ansible/playbooks/rotate-cloudflare-token.yml` — deletes and recreates the secret, triggers cert-manager `ClusterIssuer` reconcile
- **ansible.cfg additions**:
  ```ini
  [defaults]
  inventory = ansible/inventory/hosts.yml
  fact_caching = jsonfile
  fact_caching_connection = /tmp/ansible-facts
  fact_caching_timeout = 3600
  ```
- **Fact caching**: speeds up subsequent playbook runs on the same hosts — avoids re-gathering facts on every run

---

## Outcome

- Token rotation procedure documented and tested ✓
- ansible.cfg set as default configuration ✓
- Fact caching reducing playbook run time by ~15s ✓

---

## Related

- ansible.cfg: `ansible/ansible.cfg`
- Token rotation playbook: `ansible/playbooks/rotate-cloudflare-token.yml`
