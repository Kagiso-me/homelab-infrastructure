# Claude Phone — Phil Voice Interface

> **Status:** Planning — 2026-03-17
> **Reference:** [github.com/theNetworkChuck/claude-phone](https://github.com/theNetworkChuck/claude-phone)

A voice interface for the homelab. Call a SIP extension on 3CX, speak a command, and Phil (Claude Code) responds in natural speech. Phil can also call *you* proactively when a pod crashes, disk fills, or a service goes down.

---

## Architecture

```
Your phone
    │  (SIP/VoIP — local network, no telephony costs)
    ▼
3CX PBX  (self-hosted on docker-vm)
    │
    ▼
voice-app  (Docker — Drachtio + FreeSWITCH + STT/TTS)
    │  Whisper STT ──► text
    │  text ◄── ElevenLabs TTS
    ▼
claude-api-server  (HTTP :3333)
    │
    ▼
Claude Code CLI  (system prompt + MCP tools)
    ├── kubectl       ──► k3s cluster (tywin/jaime/tyrion)
    ├── docker        ──► docker-vm containers
    ├── Proxmox API   ──► NUC VMs
    ├── TrueNAS API   ──► pool/disk health
    ├── Prometheus    ──► PromQL queries
    ├── Gatus         ──► service uptime
    ├── Ansible       ──► run playbooks
    └── Slack API     ──► DMs / channel posts

Proactive alerts:
    Gatus/Alertmanager webhook ──► claude-api-server ──► 3CX outbound call ──► your phone
```

---

## Stack Decisions

| Component | Choice | Reason |
|-----------|--------|--------|
| PBX | 3CX self-hosted | Free tier, SIP standard, no per-minute cost |
| STT | OpenAI Whisper API | Best accuracy; negligible cost at homelab volume |
| TTS | ElevenLabs | Natural voice; free tier covers homelab use |
| LLM | Claude Code CLI | Full tool-use + Claude Max already paid |
| Deployment | All-in-one on docker-vm | bran (RPi 3B+) incompatible with Claude Code |

---

## Deployment Target

All containers run on **docker-vm** (`10.0.10.21`) inside Proxmox on the NUC.

```
docker-vm  10.0.10.21
├── 3CX container        (SIP PBX)
├── voice-app container  (STT/TTS/SIP bridge)
└── claude-api-server    (HTTP :3333 — Claude Code CLI)
```

> After the NUC RAM upgrade (~2026-03-23), bump docker-vm to 8 GB to give Phil headroom alongside the media stack.

---

## Prerequisites

- [ ] docker-vm running and accessible at `10.0.10.21`
- [ ] Claude Code CLI installed on docker-vm and authenticated (`claude login`)
- [ ] Claude Max subscription (required by claude-phone)
- [ ] OpenAI API key (Whisper STT)
- [ ] ElevenLabs API key (TTS)
- [ ] Softphone registered to 3CX (Linphone or Zoiper on mobile)
- [ ] `kubectl` configured on docker-vm pointing at k3s cluster
- [ ] Ansible accessible from docker-vm (via SSH to bran or installed locally)

---

## Step 1 — Install 3CX

### Option A: Docker on docker-vm (start here)

```bash
# 3CX provides a Debian install script — run inside docker-vm
bash <(curl -s https://downloads.3cx.com/downloads/3cxpbx/install-debian-12.sh)
```

Access web console at `http://10.0.10.21:5001` after install.

### Option B: Dedicated Proxmox VM

Create a Debian 12 VM (1 vCPU, 2 GB RAM) on the NUC solely for 3CX. Useful if 3CX resource usage affects the media stack — revisit after observing actual load.

### 3CX initial setup

1. Complete setup wizard — choose self-hosted
2. Create extension `9000` for Phil
3. Note SIP credentials for voice-app config

---

## Step 2 — Deploy voice-app + claude-api-server

```bash
# SSH into docker-vm
ssh user@10.0.10.21

# Install claude-phone CLI
curl -sSL https://raw.githubusercontent.com/theNetworkChuck/claude-phone/main/install.sh | bash

# Run setup wizard
claude-phone setup
# Prompts: 3CX SIP address, extension/password, OpenAI key, ElevenLabs key
# Device name → Phil

# Start the stack
claude-phone start
claude-phone doctor
```

The generated `docker-compose.yml` lives at `~/.claude-phone/docker-compose.yml` — copy it into this directory for version control.

---

## Step 3 — Phil's System Prompt

Edit `~/.claude-phone/config.json`, extension `9000`, `systemPrompt` field:

```
You are Phil, the intelligent assistant for this homelab.
You have access to tools to query and manage:
- k3s Kubernetes cluster (nodes: tywin 10.0.10.11, jaime .12, tyrion .13)
- Docker containers on docker-vm (10.0.10.21)
- Proxmox hypervisor on the NUC (10.0.10.20) — VMs: docker-vm, staging-k3s
- TrueNAS NAS (10.0.10.80) — pools: core (SSD mirror), archive (HDD mirror), tera (media)
- Prometheus metrics via kube-prometheus-stack
- Gatus uptime monitoring at status.kagiso.me
- Ansible playbooks (control node: bran 10.0.10.10)
Keep responses concise — this is a voice interface. Avoid lists; speak in sentences.
```

---

## Step 4 — Homelab Tool Scripts

Shell scripts in `tools/` that Claude Code can invoke. Register each as an allowed command.

```bash
# tools/k3s-status.sh
kubectl get nodes && kubectl get pods -A --field-selector=status.phase!=Running

# tools/proxmox-vms.sh
ssh root@10.0.10.20 "pvesh get /nodes/pve/qemu --output-format=json" \
  | jq '.[] | {name:.name, status:.status}'

# tools/nas-health.sh
ssh root@10.0.10.80 "zpool status -x"

# tools/docker-status.sh
docker ps --format "table {{.Names}}\t{{.Status}}"

# tools/gatus-check.sh
curl -s http://status.kagiso.me/api/v1/endpoints/statuses \
  | jq '.[] | select(.results[-1].success==false) | .name'

# tools/slack-notify.sh
curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"$1\"}" "$SLACK_WEBHOOK_URL"
```

---

## Step 5 — Proactive Outbound Calls

Configure Gatus and Alertmanager to POST to the claude-api-server webhook:

```yaml
# In Gatus config
alerting:
  custom:
    url: http://10.0.10.21:3333/webhook/alert
    method: POST
    body: |
      {"service":"[ENDPOINT_NAME]","condition":"[CONDITION_RESULTS]","success":"[ALERT_TRIGGERED]"}
```

```yaml
# Alertmanager receiver
receivers:
  - name: claude-phone
    webhook_configs:
      - url: http://10.0.10.21:3333/webhook/alert
```

Phil receives the webhook, assesses severity, and either:
- **Calls your extension** for critical alerts (pod crashloop, node NotReady, disk >90%)
- **Sends a Slack message** for informational alerts (backup complete, disk >80% warning)

> Outbound call initiation is a custom extension beyond NetworkChuck's repo. The anticipated approach is FreeSWITCH ESL (Event Socket Layer), which is already embedded in the voice-app container. The claude-api-server opens a TCP connection to FreeSWITCH's ESL port (`:8021`) and issues a `bgapi originate` command — no 3CX API required. Exact ESL config depends on how Drachtio exposes it; confirm against the running stack at implementation time.

---

## Validation

```bash
# Stack health
claude-phone doctor

# Test inbound call
# Dial 9000 from softphone
# "Phil, what's the status of my k3s cluster?"
# "Phil, how much space is left on the tera pool?"
# "Phil, are all Gatus services healthy?"

# Test proactive webhook
curl -X POST http://10.0.10.21:3333/webhook/alert \
  -H 'Content-Type: application/json' \
  -d '{"service":"test-svc","condition":"[STATUS] == 503","success":"false"}'
```

---

## Cost

| Item | Cost |
|------|------|
| 3CX self-hosted | Free |
| OpenAI Whisper | ~$0.006/min → <$1/month at homelab volume |
| ElevenLabs | Free tier (10k chars/month) covers homelab use |
| Claude Max | Already paid |
| Telephony | $0 (local SIP, no PSTN) |
| **New monthly cost** | **< $1** |

---

## Future

- [ ] Bump docker-vm to 8 GB after NUC RAM upgrade (2026-03-23)
- [ ] Local TTS fallback (Piper) for internet outage resilience
- [ ] Multiple extensions: Phil `9000` + read-only guest `9001`
- [ ] Call recording to `/mnt/archive/backups/voice-logs/`
- [ ] Tailscale-accessible SIP — call Phil from outside the home network
