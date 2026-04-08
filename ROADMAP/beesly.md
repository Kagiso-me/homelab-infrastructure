# Beesly — Personal AI Assistant

> **Status:** Active — 2026-03-30
> **Host:** varys (`10.0.10.10`)
> **Stack:** OpenClaw · Claude API · Discord

---

## What Is Beesly

Beesly is a personal AI assistant — the homelab's Siri. She lives on varys, connects via Discord, remembers context across sessions, and has direct access to every layer of the infrastructure.

The interaction model is simple: open Discord on any device, ask Beesly something, get a useful answer. No SSH, no dashboards, no digging through logs. "Beesly, are all my pods healthy?" "Beesly, what's filling up the tera pool?" "Beesly, what does my Monday look like?" She handles all of it.

Beesly is not just an infra tool. The scope is a full personal assistant — calendar, reminders, general queries — with infrastructure awareness as one capability among many.

---

## Why OpenClaw

Beesly was originally designed around a SIP/voice stack: 3CX PBX, FreeSWITCH, Whisper STT, ElevenLabs TTS, and a custom beesly-server bridging everything to Claude. That architecture was shelved for the following reasons:

- **Build cost.** The voice-app container (Drachtio + FreeSWITCH + STT/TTS bridge) is non-trivial to build and maintain. Most of the engineering effort would go into telephony plumbing, not the assistant itself.
- **3CX friction.** Enterprise PBX software in a homelab introduces real operational overhead — SIP configuration, licensing quirks, and complex failure modes.
- **Limited reach.** A SIP extension is only useful on the local LAN (or with Tailscale SIP configured separately). Discord works from anywhere.

OpenClaw solves the build problem. It ships with a full agent framework: memory, skill system, multi-channel routing, and LLM integration out of the box. The result is an assistant that is operational in an afternoon rather than several weekends, with lower ongoing maintenance.

Voice interaction via VoiceClaw (Whisper STT + ElevenLabs TTS) is planned as a future phase and will layer on top of the existing OpenClaw deployment without replacing anything.

---

## Value

| Without Beesly | With Beesly |
|---|---|
| SSH into varys → run kubectl commands → parse output | "Beesly, which pods are not running?" |
| Open TrueNAS UI → navigate to storage → check pool status | "Beesly, how much space is left on tera?" |
| Open Grafana → find the right dashboard → read metrics | "Beesly, what's the CPU usage on tywin?" |
| Open Google Calendar on phone | "Beesly, what does my Thursday look like?" |
| Manually check Gatus at status.kagiso.me | "Beesly, are all my services up?" |

The compounding value is memory. OpenClaw remembers context across sessions. After telling Beesly once that the archive pool is only used for backups, she factors that into every future storage question. After noting that SABnzbd has been slow lately, she connects that context when you ask about download speeds three days later.

---

## Architecture

```
Discord (any device, anywhere)
        │
        ▼
┌───────────────────────────────────────────┐
│  OpenClaw  —  varys (10.0.10.10)          │
│                                           │
│  Gateway   ──  Discord bot                │
│  Brain     ──  Claude API (Sonnet 4.6)    │
│  Memory    ──  local Markdown             │
│  Skills    ──  infra + personal tools     │
│  Heartbeat ──  scheduled tasks            │
└───────────────────────────────────────────┘
        │
        ├── kubectl ──────────► k3s cluster (tywin/jaime/tyrion)
        ├── SSH ─────────────► docker host (10.0.10.20)
        ├── TrueNAS API ─────► NAS (10.0.10.80)
        ├── Prometheus API ──► kube-prometheus-stack
        ├── Gatus API ───────► status.kagiso.me
        └── Google Calendar API
```

**Future — VoiceClaw (Phase 2):**

```
Laptop / phone microphone
        │  Whisper STT
        ▼
VoiceClaw (local Node.js process)
        │  WebSocket
        ▼
OpenClaw on varys  ──  same skills, same memory
        │  ElevenLabs TTS
        ▼
Speaker output
```

VoiceClaw runs on the client device (laptop, phone), not on varys. Varys remains headless. The voice layer is additive — it uses the same OpenClaw instance with no changes to the server deployment.

---

## Infrastructure Skills

These are the tools Beesly can invoke. Each is a shell script or API call registered as an OpenClaw skill.

### k3s cluster status

```bash
#!/bin/bash
# skills/k3s-status.sh
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running
```

### TrueNAS pool health

```bash
#!/bin/bash
# skills/nas-health.sh
# Queries ZFS pool status across all three pools: core, archive, tera
ssh root@10.0.10.80 "zpool status -x && zpool list"
```

### Docker host containers

```bash
#!/bin/bash
# skills/docker-status.sh
ssh kagiso@10.0.10.20 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
```

### Gatus uptime check

```bash
#!/bin/bash
# skills/gatus-check.sh
curl -s "https://status.kagiso.me/api/v1/endpoints/statuses" \
  | jq '.[] | select(.results[-1].success==false) | .name'
```

### Prometheus query

```bash
#!/bin/bash
# skills/prometheus-query.sh — usage: ./prometheus-query.sh '<promql>'
QUERY="$1"
curl -s "http://10.0.10.11:9090/api/v1/query" \
  --data-urlencode "query=${QUERY}" \
  | jq '.data.result'
```

### Ansible playbook runner

```bash
#!/bin/bash
# skills/ansible-run.sh — usage: ./ansible-run.sh <playbook>
cd ~/ansible
ansible-playbook "$1" --diff
```

All skill scripts live at `~/.openclaw/skills/` on varys and must be executable (`chmod +x`).

---

## Personal Assistant Skills

OpenClaw's community skill library covers most of these. Install via the OpenClaw skill registry:

- **Google Calendar** — read schedule, create/update events
- **Reminders** — create, list, complete tasks
- **Web search** — general knowledge queries via configured search provider

---

## Security

Running an AI assistant with direct access to infrastructure introduces real attack surface. The following controls are in place.

### Threat model

| Threat | Likelihood | Impact |
|--------|-----------|--------|
| Prompt injection via Discord message | Medium | High — could trigger skill execution |
| Leaked API keys from `.env` | Low | High — full LLM + Discord access |
| Unauthorised Discord user sending commands | Low | High — full infra access |
| OpenClaw supply chain compromise | Low | High |
| Beesly used to exfiltrate data | Low | Medium |

### Mitigations

**Discord access control**

OpenClaw supports an allowlist of Discord user IDs. Only your user ID is permitted to send commands. Any message from an unlisted user is silently ignored — Beesly does not respond, does not acknowledge, and does not execute skills.

Configure in `~/.openclaw/config/openclaw.json`:

```json
{
  "channels": {
    "discord": {
      "allowed_users": ["YOUR_DISCORD_USER_ID"]
    }
  }
}
```

**Prompt injection hardening**

- Use `"api": "anthropic-messages"` to enable native Anthropic tool-calling. Claude's tool-use format is more resistant to injection than text-parsing approaches.
- The system prompt explicitly instructs Beesly never to execute destructive actions (node deletion, data wipe, volume removal) without a confirmation phrase.
- Skills that make write/mutate operations (Ansible playbooks, kubectl apply) are separated from read-only skills. Mutating skills require explicit confirmation in the conversation before executing.

**API key isolation**

- All secrets live in `~/.openclaw/.env` with `chmod 600` — readable only by the running user.
- The `.env` file is never committed to version control. `.gitignore` covers it.
- Anthropic API key is scoped to Claude API only — no admin console access.
- Discord bot token is scoped to the single Beesly server only.

**Skill execution scope**

- Read-only skills (kubectl get, zpool status, docker ps, Prometheus query) are unrestricted.
- Write skills (kubectl apply, ansible-playbook, docker restart) require the user to include a confirmation phrase in the same message: `"confirm: yes"`.
- No skill has permission to delete Kubernetes resources, drop ZFS pools, or modify TrueNAS configuration.

**Network**

- OpenClaw binds only to localhost and the Docker bridge — not exposed on `0.0.0.0`.
- The web UI (`beesly.kagiso.me`) is proxied via NPM and sits behind the `*.kagiso.me` wildcard cert. It is LAN-only — no public exposure. Cloudflare DNS record points to `10.0.10.10`, DNS-only (no proxy).
- Discord communication travels outbound only — OpenClaw connects to Discord's gateway via WebSocket. No inbound ports are opened for Discord.

**Updates**

- Pin OpenClaw to a specific image tag in `docker-compose.yml`. Do not run `latest` in production.
- Review the OpenClaw changelog before pulling a new version — the project is young and breaking changes are possible.
- Keep `docker compose pull` behind a manual review step, not an automated cron.

---

## Deployment on varys

### Prerequisites

- varys (`10.0.10.10`) running Ubuntu Server with Docker and Docker Compose v2 installed
- `kubectl` configured on varys pointing at `10.0.10.11:6443`
- SSH keys in place for `root@10.0.10.80` (TrueNAS) and `kagiso@10.0.10.20` (Docker host)
- Anthropic API key (Claude Max — already paid)
- Discord bot token (see Step 1)
- NPM running on `10.0.10.20` for reverse proxy

---

### Step 1 — Create the Discord Bot

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → **New Application** → name it `Beesly`.
2. Navigate to **Bot** → **Add Bot**.
3. Under **Privileged Gateway Intents**, enable:
   - Message Content Intent
   - Server Members Intent
4. Click **Reset Token** → copy the token. This is `DISCORD_BOT_TOKEN`.
5. Navigate to **OAuth2 → URL Generator**:
   - Scopes: `bot`, `applications.commands`
   - Bot permissions: `Send Messages`, `Read Message History`, `Use Slash Commands`
6. Open the generated URL to invite Beesly to your Discord server.
7. In Discord, go to **Settings → Advanced → Developer Mode** → right-click your username → **Copy User ID**. This is your `DISCORD_USER_ID` for the allowlist.

---

### Step 2 — Deploy OpenClaw on varys

```bash
ssh kagiso@10.0.10.10
```

**Clone OpenClaw:**

```bash
git clone https://github.com/openclaw/openclaw ~/.openclaw
cd ~/.openclaw
```

**Create the `.env` file:**

```bash
cat > ~/.openclaw/.env <<'EOF'
ANTHROPIC_API_KEY=sk-ant-...
DISCORD_BOT_TOKEN=...
EOF
chmod 600 ~/.openclaw/.env
```

**Run the setup script:**

```bash
./scripts/docker/setup.sh
```

The setup script prompts for API keys (already set in `.env`) and generates a gateway token. Accept defaults unless prompted otherwise.

**Start OpenClaw:**

```bash
docker compose up -d
docker compose ps
```

All services should show `Up`. If anything is unhealthy:

```bash
docker compose logs -f
```

---

### Step 3 — Configure Claude as the LLM

Edit `~/.openclaw/config/openclaw.json` (create from template if it doesn't exist):

```json
{
  "model": "claude-sonnet-4-6",
  "api": "anthropic-messages"
}
```

`"api": "anthropic-messages"` enables native Anthropic tool-calling format — required for skills to work correctly and for prompt injection resilience.

---

### Step 4 — Configure Discord allowlist

In `~/.openclaw/config/openclaw.json`, add your Discord user ID:

```json
{
  "model": "claude-sonnet-4-6",
  "api": "anthropic-messages",
  "channels": {
    "discord": {
      "allowed_users": ["YOUR_DISCORD_USER_ID"]
    }
  }
}
```

---

### Step 5 — Set Beesly's system prompt

Create `~/.openclaw/config/system-prompt.txt`:

```
You are Beesly, a personal AI assistant.

Infrastructure you can query:
- k3s Kubernetes cluster: tywin (10.0.10.11, control plane), jaime (10.0.10.12), tyrion (10.0.10.13)
- Docker host: bronn (10.0.10.20) — runs Plex, Sonarr, Radarr, Lidarr, SABnzbd, Overseerr, Navidrome
- TrueNAS NAS: 10.0.10.80 — pools: core (SSD mirror, k8s PVCs), archive (HDD mirror, backups), tera (8TB single, media)
- Prometheus + Grafana: kube-prometheus-stack on k3s
- Gatus uptime: status.kagiso.me
- Ansible control node: varys (10.0.10.10)

You are also a personal assistant — calendar, reminders, and general queries are in scope.

Rules:
- Never execute destructive actions (delete resources, drop pools, wipe data) without the user including "confirm: yes" in their message.
- Keep responses concise. You are in Discord — markdown is fine, long prose is not.
- When infrastructure queries return no issues, say so clearly and briefly.
```

---

### Step 6 — Install infra skills

```bash
mkdir -p ~/.openclaw/skills
```

Create each skill script from the [Infrastructure Skills](#infrastructure-skills) section above. Then:

```bash
chmod +x ~/.openclaw/skills/*.sh
```

Verify SSH access works from varys before relying on any skill that SSH's to another host:

```bash
ssh root@10.0.10.80 "zpool status -x"
ssh kagiso@10.0.10.20 "docker ps"
```

---

### Step 7 — Reverse proxy via NPM

Expose the OpenClaw web UI at `beesly.kagiso.me`:

1. Open NPM on `10.0.10.20` → **Proxy Hosts** → **Add Proxy Host**
2. Domain: `beesly.kagiso.me`
3. Forward hostname: `10.0.10.10`
4. Forward port: `3000` (confirm the actual port from `docker compose ps`)
5. SSL: select the `*.kagiso.me` wildcard cert, enable **Force SSL**
6. In Cloudflare: add DNS A record `beesly` → `10.0.10.20` — DNS-only (grey cloud, no proxy)

---

### Step 8 — Add OpenClaw to varys backup

The `~/.openclaw/` directory contains Beesly's memory, config, and skills. Add it to the varys backup script so it's included in the daily encrypted backup to TrueNAS archive.

Edit `/usr/local/bin/varys-backup.sh` — add `.openclaw/config` and `.openclaw/skills` to the `tar` command:

```bash
tar --create \
    --gzip \
    --file=- \
    --ignore-failed-read \
    -C "${HOME}" \
      .kube/config \
      .config/sops/age/keys.txt \
      .ssh/id_ed25519 \
      .ssh/id_ed25519.pub \
      .ssh/config \
      .ssh/known_hosts \
      .openclaw/config \
      .openclaw/skills \
    2>>"${LOG_FILE}" \
```

> OpenClaw's memory store (conversation history) does not need to be backed up — it is useful but not critical. Config and skills are the things that take time to rebuild.

---

## Validation

**Confirm OpenClaw is running:**

```bash
ssh kagiso@10.0.10.10
docker compose -f ~/.openclaw/docker-compose.yml ps
```

**Test via Discord — send these messages to Beesly:**

```
@Beesly are all my k3s pods healthy?
@Beesly how much space is left on the tera pool?
@Beesly what containers are running on the docker host?
@Beesly are all services showing up in Gatus?
@Beesly what does my calendar look like tomorrow?
```

**Test the allowlist — from a different Discord account:**
Beesly should not respond at all.

**Test the confirmation guard:**
```
@Beesly run the full-update ansible playbook
```
Beesly should ask for confirmation and refuse to proceed without `confirm: yes`.

---

## Updating OpenClaw

```bash
ssh kagiso@10.0.10.10
cd ~/.openclaw
git pull                      # review changelog before proceeding
docker compose pull
docker compose up -d
docker compose ps
```

Always review the changelog between versions. OpenClaw is a young project — breaking config changes are possible.

---

## Roadmap

### v1 — Discord assistant (current)
- [ ] OpenClaw deployed on varys
- [ ] Discord bot connected with user allowlist
- [ ] Claude Sonnet 4.6 configured with native tool-calling
- [ ] Infra skills: kubectl, TrueNAS, Docker host, Prometheus, Gatus
- [ ] Personal skills: Google Calendar, reminders, web search
- [ ] System prompt and confirmation guard in place
- [ ] Beesly added to varys backup

### v2 — Voice (VoiceClaw)
- [ ] VoiceClaw installed on laptop
- [ ] Whisper STT + ElevenLabs TTS configured
- [ ] Wake word activation
- [ ] Same OpenClaw instance on varys — no server changes needed

---

## Related

- [varys control hub](../../varys/README.md)
- [varys backup script](../../varys/scripts/backup_varys.sh)
- [Guide 09 — Monitoring & Observability](../../docs/guides/09-Monitoring-Observability.md)
- [Guide 10 — Backups & Disaster Recovery](../../docs/guides/10-Backups-Disaster-Recovery.md)

> The full Beesly deployment will live in its own dedicated repository. This README is the canonical reference from the homelab-infrastructure repo.