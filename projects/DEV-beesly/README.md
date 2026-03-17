# Beesly — Personal AI Assistant

> **Status:** Planning — 2026-03-17

Beesly is a personal AI assistant with a voice interface. Call a SIP extension, speak naturally, and Beesly responds. She can also call *you* proactively — when a pod crashes, a disk fills, or a service goes down.

But Beesly is not just an infrastructure tool. The vision is a full personal assistant — the kind that can run you through your schedule for next Monday, remind you to cancel a gym membership, or handle anything else you'd ask a real assistant to do. Infrastructure awareness is one capability among many.

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
beesly-server  (HTTP :3333)
    │
    ▼
Claude API  (system prompt + MCP tools)
    ├── Infrastructure
    │   ├── kubectl       ──► k3s cluster (tywin/jaime/tyrion)
    │   ├── docker        ──► docker-vm containers
    │   ├── Proxmox API   ──► NUC VMs
    │   ├── TrueNAS API   ──► pool/disk health
    │   ├── Prometheus    ──► PromQL queries
    │   ├── Pulse         ──► service uptime
    │   └── Ansible       ──► run playbooks
    └── Personal
        ├── Google Calendar ──► schedule queries + event creation
        ├── Reminders       ──► create/read/complete tasks
        ├── Slack API       ──► DMs / channel posts
        └── Web search      ──► general knowledge queries

Proactive alerts:
    Pulse/Alertmanager webhook ──► beesly-server ──► 3CX outbound call ──► your phone
```

---

## Stack Decisions

| Component | Choice | Reason |
|-----------|--------|--------|
| PBX | 3CX self-hosted | Free tier, SIP standard, no per-minute cost |
| STT | OpenAI Whisper API | Best accuracy; negligible cost at homelab volume |
| TTS | ElevenLabs | Natural voice; free tier covers homelab use |
| LLM | Claude API | Full tool-use; Claude Max already paid |
| Deployment | All-in-one on docker-vm | bran (RPi 3B+) incompatible with Claude Code |

---

## Deployment Target

All containers run on **docker-vm** (`10.0.10.21`) inside Proxmox on the NUC.

```
docker-vm  10.0.10.21
├── 3CX container         (SIP PBX)
├── voice-app container   (STT/TTS/SIP bridge)
└── beesly-server         (HTTP :3333 — Claude API)
```

> After the NUC RAM upgrade (~2026-03-23), bump docker-vm to 8 GB to give Beesly headroom alongside the media stack.

---

## Prerequisites

- [ ] docker-vm running and accessible at `10.0.10.21`
- [ ] Claude API key configured
- [ ] OpenAI API key (Whisper STT)
- [ ] ElevenLabs API key (TTS)
- [ ] Softphone registered to 3CX (Linphone or Zoiper on mobile)
- [ ] `kubectl` configured on docker-vm pointing at k3s cluster
- [ ] Ansible accessible from docker-vm (via SSH to bran or installed locally)
- [ ] Google Calendar API credentials (for personal assistant features)

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
2. Create extension `9000` for Beesly
3. Note SIP credentials for voice-app config

---

## Step 2 — Deploy voice-app + beesly-server

```bash
ssh kagiso@10.0.10.21

# Clone and configure
git clone https://github.com/Kagiso-me/beesly ~/.beesly
cd ~/.beesly

cp .env.example .env
# Fill in: 3CX SIP address, extension/password, Anthropic key, OpenAI key, ElevenLabs key

# Start the stack
docker compose up -d
docker compose ps
```

---

## Step 3 — Beesly's System Prompt

Edit `config/system-prompt.txt`:

```
You are Beesly, an intelligent personal assistant.

Infrastructure access — you can query and manage:
- k3s Kubernetes cluster (nodes: tywin 10.0.10.11, jaime .12, tyrion .13)
- Docker containers on docker-vm (10.0.10.21)
- Proxmox hypervisor on the NUC (10.0.10.20) — VMs: docker-vm, staging-k3s
- TrueNAS NAS (10.0.10.80) — pools: core (SSD mirror), archive (HDD mirror), tera (media)
- Prometheus metrics via kube-prometheus-stack
- Pulse uptime monitoring at status.kagiso.me
- Ansible playbooks (control node: bran 10.0.10.10)

Personal access — you can:
- Read and create Google Calendar events
- Create and complete reminders
- Send Slack messages

Keep responses concise — this is a voice interface. Avoid bullet points; speak in sentences.
When asked about your schedule or personal tasks, be specific with dates and times.
```

---

## Step 4 — Homelab Tool Scripts

Shell scripts in `tools/` that Beesly can invoke:

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

# tools/pulse-check.sh
curl -s http://status.kagiso.me/api/v1/endpoints/statuses \
  | jq '.[] | select(.results[-1].success==false) | .name'
```

---

## Step 5 — Proactive Outbound Calls

Configure Pulse and Alertmanager to POST to the beesly-server webhook:

```yaml
# In Pulse config
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
  - name: beesly
    webhook_configs:
      - url: http://10.0.10.21:3333/webhook/alert
```

Beesly receives the webhook, assesses severity, and either:
- **Calls your extension** for critical alerts (pod crashloop, node NotReady, disk >90%)
- **Sends a Slack message** for informational alerts (backup complete, disk >80% warning)

> Outbound call initiation uses FreeSWITCH ESL (Event Socket Layer). Beesly-server opens a TCP connection to FreeSWITCH's ESL port (`:8021`) and issues a `bgapi originate` command.

---

## Validation

```bash
# Stack health
docker compose ps

# Test inbound call — dial 9000 from softphone
# "Beesly, what's the status of my k3s cluster?"
# "Beesly, how much space is left on the tera pool?"
# "Beesly, what does my Monday look like next week?"
# "Beesly, remind me to cancel my gym membership on Friday"

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

## Roadmap

### v1 — Infrastructure assistant
- [ ] Bump docker-vm to 8 GB after NUC RAM upgrade (2026-03-23)
- [ ] Inbound call: query k3s, Docker, TrueNAS, Proxmox, Pulse
- [ ] Proactive outbound calls for critical alerts
- [ ] Slack notification fallback for non-critical alerts

### v2 — Personal assistant
- [ ] Google Calendar — read schedule, create events
- [ ] Reminders — create, list, complete
- [ ] Tailscale-accessible SIP — call Beesly from outside the home network

### v3 — Extended
- [ ] Local TTS fallback (Piper) for internet outage resilience
- [ ] Multiple extensions: Beesly `9000` + read-only guest `9001`
- [ ] Call recording to `/mnt/archive/backups/voice-logs/`
- [ ] Web search for general knowledge queries
