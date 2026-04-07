# varys — Control Hub

**Hostname:** `varys`
**IP:** `10.0.10.10`
**OS:** Ubuntu Server
**Hardware:** Intel NUC i3-5010U

---

## The Character

<div align="center">

<!-- Photo placeholder: Lord Varys (Conleth Hill) from Game of Thrones -->
> _📸 Photo coming soon — Lord Varys_

</div>

**Varys** — *The Spider* — is the Master of Whisperers in the Small Council of King's Landing. He operates an intelligence network that spans the entire known world, gathers information from everywhere, and pulls strings from the shadows. He knows everything happening across all the kingdoms without anyone knowing he's watching.

**Why this machine:** `varys` is the homelab's eyes and ears. It has `kubectl` access to every node, runs Ansible against the entire inventory, holds the age encryption key, fires CI/CD pipelines, and receives all alerts. Like the character, it is the quiet hub through which all control flows — and if you need something done in the homelab, you go through varys.

---

## Role

`varys` is the homelab control hub. It is the machine from which day-to-day
operations run:

- `kubectl`, `flux`, and `helm`
- Ansible control node
- GitHub Actions self-hosted runner
- Pi-hole (primary DNS)
- Grafana and Alertmanager
- `cloudflared` and Headscale

This is the administrative entry point for the platform. If `varys` is down,
the k3s cluster continues running, but interactive operations, CI jobs, and key
material access become much harder.

---

## Backups

Critical operator material on `varys` is backed up daily by
[`backup_varys.sh`](scripts/backup_varys.sh).

The backup protects:

- `~/.kube/config`
- `~/.config/sops/age/keys.txt`
- `~/.ssh/id_ed25519`
- `~/.ssh/id_ed25519.pub`
- `~/.ssh/config`
- `~/.ssh/known_hosts`

The script writes the standard textfile metrics with `job="varys-keys"` so the
existing backup dashboards and alert rules can treat `varys` the same way as
other backup targets.

---

## Directory Layout

```text
varys/
|-- README.md
`-- scripts/
    `-- backup_varys.sh
```

Deploy the backup script to `/usr/local/bin/varys-backup.sh` on the host and
schedule it from root's crontab.

---

## Related Docs

- [Repository overview](../README.md)
- [Guide 01 - Node Preparation & Hardening](../docs/guides/01-Node-Preparation-Hardening.md)
- [Guide 09 - Monitoring & Observability](../docs/guides/09-Monitoring-Observability.md)
- [Guide 10 - Backups & Disaster Recovery](../docs/guides/10-Backups-Disaster-Recovery.md)
- [hodor appliance docs](../hodor/README.md)
