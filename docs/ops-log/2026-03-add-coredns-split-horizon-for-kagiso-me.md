# 2026-03 — DEPLOY: Add CoreDNS split-horizon for kagiso.me

**Operator:** Kagiso
**Type:** `DEPLOY`
**Components:** CoreDNS · k3s · DNS · Traefik · split-horizon DNS
**Commit:** —
**Downtime:** None

---

## What Changed

Configured CoreDNS in k3s to resolve `*.kagiso.me` to the internal Traefik LoadBalancer IP (`10.0.10.110`) instead of the public Cloudflare IP. This is split-horizon DNS — LAN clients and cluster pods resolve the same hostname to different IPs depending on where they are.

---

## Why

Without split-horizon, requests from inside the cluster to `*.kagiso.me` hairpin out through Cloudflare and back in — adding ~50ms of latency and relying on Cloudflare being available for internal cluster-to-cluster communication. Worse, some home routers and firewalls block NAT hairpinning entirely, causing complete breakage for services that call other services by their public hostname.

With split-horizon, in-cluster requests to `nextcloud.kagiso.me` resolve directly to the Traefik internal IP, never leaving the LAN.

---

## Details

- CoreDNS ConfigMap patched in `kube-system` namespace via Flux HelmRelease values override
- Added rewrite rule: `rewrite name suffix .kagiso.me traefik.apps.svc.cluster.local` — not used; instead added a `hosts` block:
  ```
  hosts {
    10.0.10.110 nextcloud.kagiso.me
    10.0.10.110 immich.kagiso.me
    10.0.10.110 vault.kagiso.me
    # ... all external services
    fallthrough
  }
  ```
- Pi-hole on LAN also configured with same split-horizon entries for non-cluster clients (laptops, phones)
- External DNS (Cloudflare) unchanged — public resolution still works correctly

---

## Outcome

- Cluster-internal requests to `*.kagiso.me` resolve to local IP ✓
- No more Cloudflare hairpin for inter-service calls ✓
- LAN clients also benefit via Pi-hole ✓

---

## Related

- CoreDNS config: patched via k3s HelmChartConfig in `platform/networking/coredns/`
- Pi-hole local DNS: managed via Ansible on bran
