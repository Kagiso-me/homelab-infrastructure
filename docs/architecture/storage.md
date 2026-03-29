# Architecture - Storage

## Storage Design Reference

This document summarises the storage model used by the cluster and points back to the detailed guide.

---

## Core Principle

The platform uses **two storage lanes**, not one:

- `nfs-truenas` for shared and portable application state
- `local-path` for latency-sensitive or lock-sensitive workloads such as PostgreSQL, Redis, and Prometheus

That split is deliberate. It avoids forcing database workloads onto NFS while still keeping most application PVCs portable and easy to recover.

---

## StorageClasses

| Name | Provisioner | Reclaim | Binding | Use case |
|---|---|---|---|---|
| `nfs-truenas` | nfs-subdir-external-provisioner | `Retain` | `Immediate` | Shared app PVCs, portable state, general application storage |
| `local-path` | rancher.io/local-path | `Delete` | `WaitForFirstConsumer` | PostgreSQL, Redis, Prometheus, other node-local state |

`nfs-truenas` is the default because most workloads in this repo are applications, not databases.

---

## Topology

```text
Kubernetes cluster
|
|-- nfs-truenas
|   `-- TrueNAS 10.0.10.80:/mnt/core/k8s-volumes
|
`-- local-path
    `-- /var/lib/rancher/k3s/storage on the selected node
```

---

## What Runs Where

| Storage lane | Typical workloads |
|---|---|
| `nfs-truenas` | Grafana, Loki, app config PVCs, Nextcloud, Immich, Sonarr, Radarr |
| `local-path` | PostgreSQL, Redis, Prometheus TSDB |

For the reasoning behind this split, see:

- [Guide 08 - Storage Architecture](../guides/08-Storage-Architecture.md)
- [ADR-009 - Prometheus Local Storage](../adr/ADR-009-prometheus-local-storage.md)
- [ADR-011 - Central Databases](../adr/ADR-011-central-databases.md)
