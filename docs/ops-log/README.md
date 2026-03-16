# Ops Log

A journal of every meaningful change made to this infrastructure. Not a guide. Not a tutorial.
A living record of what changed, when, why, and what happened.

---

## Why This Exists

Configuration files show the current state. Git history shows what changed. Neither tells you
**why** a decision was made, what the impact was, or how a problem was resolved. This log fills
that gap.

---

## Structure

```
docs/ops-log/
├── README.md             # This file
├── template.md           # Copy this for every new entry
└── YYYY-MM-DD-slug.md    # One file per change event
```

The root [`CHANGELOG.md`](../../CHANGELOG.md) is a rolling summary — one line per event, linked
to the detail entry here.

---

## Entry Types

| Tag | When to use |
|-----|-------------|
| `DEPLOY` | New application or service goes live |
| `UPGRADE` | Version bump of an existing service |
| `CONFIG` | Configuration change to an existing service |
| `NETWORK` | IP addresses, DNS, firewall, load balancer, VLANs |
| `STORAGE` | ZFS datasets, pools, NFS exports, MinIO |
| `SCALE` | Resource limits, replica counts, node capacity |
| `INCIDENT` | Something broke — what happened, how it was resolved |
| `MAINTENANCE` | ZFS scrubs, snapshots, node reboots, certificate renewal |
| `SECURITY` | Secrets rotation, certificate changes, key management |
| `HARDWARE` | Physical changes to any node or network device |

---

## Writing a Good Entry

**Write it while the change is fresh.** Even rough notes are better than nothing.

**Be honest about incidents.** If something broke, say what broke, what you tried, and what
actually fixed it. Future-you will thank present-you.

**Link everything.** Commit hashes, file paths, guide references. The entry should be a
navigation hub for that change.

**Note the outcome.** Did it work first time? Was there a surprise? Did you have to roll back?

---

## How to Add an Entry

1. Copy `template.md` to a new file: `YYYY-MM-DD-short-description.md`
2. Fill in all sections — delete sections that don't apply
3. Add a one-line summary to the root `CHANGELOG.md` with a link to your new file
4. Commit both files together

---

## Naming Convention

```
YYYY-MM-DD-type-description.md
```

Examples:
```
2026-03-16-deploy-platform-stack.md
2026-04-02-incident-traefik-crashloop.md
2026-05-10-upgrade-k3s-v1.32.md
2026-06-01-hardware-rpi4-upgrade.md
```
