
# ADR-001 — k3s over kubeadm

**Status:** Accepted
**Date:** 2026-01-15
**Deciders:** Platform team

---

## Context

The platform requires a Kubernetes distribution for a three-node homelab cluster (1 control-plane, 2 workers). The nodes are physical machines with modest resources running Ubuntu Server. The cluster must be fully rebuildable from automation.

Evaluated options:

1. **kubeadm** — the official upstream Kubernetes installation tool
2. **k3s** — Rancher's lightweight, production-ready Kubernetes distribution
3. **microk8s** — Canonical's single-package Kubernetes

## Decision

**k3s was selected.**

## Rationale

| Criterion | kubeadm | k3s | microk8s |
|-----------|---------|-----|----------|
| Installation complexity | High (etcd, CNI, CRI all separate) | Low (single binary) | Low |
| Resource footprint | High | Low (~512MB RAM baseline) | Medium |
| Embedded etcd | No (must deploy separately) | Yes | No |
| Ansible automation maturity | Good | Good | Limited |
| Full Kubernetes API compatibility | Yes | Yes | Yes |
| Production use cases | Large-scale enterprise | Edge, IoT, homelab, small prod | Developer workstations |
| ARM64 support | Yes | Yes | Yes |

k3s packages all Kubernetes components (apiserver, scheduler, controller-manager, etcd) into a single binary. This dramatically reduces operational complexity for a single-operator platform.

The embedded etcd removes the need to manage a separate etcd cluster, which is one of the most operationally complex components of a kubeadm deployment.

k3s is used in production by many organisations for edge deployments and is maintained by Rancher (SUSE). It is not a toy.

## Consequences

- Node preparation and installation use the existing Ansible role (`roles/k3s_install/`).
- k3s bundles Traefik and local-path-provisioner by default. The bundled Traefik is disabled in favour of a Flux-managed deployment for full version control and configuration management.
- k3s-specific etcd snapshot tooling (`k3s etcd-snapshot`) is used for cluster state backups. This is a positive consequence — the tool produces consistent snapshots with a single command.
- Upgrades are performed via the k3s System Upgrade Controller, which is a Kubernetes-native upgrade mechanism.

---
