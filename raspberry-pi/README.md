# Raspberry Pi — Homelab Control Hub

**Hostname:** `bran` 
**IP:** `10.0.10.10` 
**OS:** Raspberry Pi OS Lite (64-bit, Debian Bookworm)
**Hardware:** Raspberry Pi 4 Model B (4GB RAM recommended)

---

## Role

The Raspberry Pi is the **central control node** for the entire homelab. It does not run any user workloads. Its function is operational: everything that requires interacting with the homelab is done from here.

```
Laptop / Remote Machine
        │
        ▼
  Raspberry Pi (control hub)
        │
        ├──► k3s cluster (tywin, jaime, tyrion) via kubectl / flux / helm
        │
        └──► Docker media server (via SSH) — never accessed directly
```

The design principle is that **no production node is accessed directly** from a personal machine. The RPi acts as a jump host and management plane.

---

## Installed Tools

| Tool | Purpose |
|------|---------|
| `kubectl` | Kubernetes cluster management |
| `flux` | FluxCD CLI — reconcile, diff, check |
| `helm` | Helm chart management |
| `k9s` | Terminal UI for Kubernetes |
| `age` / `sops` | Secret encryption/decryption (see Guide 11) |
| `velero` | Backup and restore CLI |
| `ansible` | Node automation for k3s cluster |
| `lazygit` | Terminal git UI |
| `htop` | System resource monitor |

---

## Access Model

```bash
# From laptop → RPi
ssh pi@10.0.10.10

# From RPi → k3s control plane (for direct node access)
ssh kagiso@10.0.10.11   # tywin

# From RPi → Docker media server
ssh kagiso@10.0.10.20    # docker host (update with actual IP)

# All kubectl commands run locally on the RPi
kubectl get nodes
flux get kustomizations
```

The kubeconfig is stored at `~/.kube/config` and points to the k3s API server at `10.0.10.11:6443`.

---

## Services Running on the RPi

The RPi is kept lean. The following lightweight services may run here:

| Service | Purpose | Status |
|---------|---------|--------|
| SSH server | Remote access | Active |
| `kubectl` proxy | Local k8s dashboard access | Optional |
| Ansible | Automation host for k3s nodes | Active |

> Additional services (e.g., Pi-hole, Uptime Kuma) may be added here in future. Any additions should be documented in `docs/01_setup.md` and their Ansible setup added to `ansible/playbooks/`.

---

## Bootstrap

The RPi is provisioned using Ansible. To set up a fresh RPi:

```bash
# From your laptop, run the setup playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/setup.yml
```

See [docs/01_setup.md](docs/01_setup.md) for the full setup walkthrough.

---

## Kubeconfig Setup

After k3s is installed (see [k8s Guide 02](../docs/guides/02-Kubernetes-Installation.md)), copy the kubeconfig to the RPi:

```bash
# On the k3s control plane (tywin)
cat /etc/rancher/k3s/k3s.yaml

# Copy to RPi, replacing 127.0.0.1 with 10.0.10.11
scp tywin:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/10.0.10.11/g' ~/.kube/config
chmod 600 ~/.kube/config
```

---

## Directory Structure

```
raspberry-pi/
├── README.md               # this file
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml       # RPi host definition
│   └── playbooks/
│       ├── setup.yml       # full RPi bootstrap
│       └── tools.yml       # install/update tools only
└── docs/
    └── setup.md            # setup walkthrough
```
