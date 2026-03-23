
# ADR-010 — Discord over Slack for Alert Notifications

**Status:** Accepted
**Date:** 2026-03-23
**Deciders:** Platform team

---

## Context

Alertmanager requires a notification channel for alert delivery. The initial
design referenced Slack. Before any Slack app was created or credentials
committed, the decision was revisited.

Two options were evaluated:

1. **Slack** — industry-standard team messaging. Requires creating a Slack app,
   configuring incoming webhooks, and managing the app through Slack's developer
   portal.
2. **Discord** — community-oriented messaging platform with native webhook support
   and a Slack-compatible API endpoint.

---

## Decision

**Discord is used for all Alertmanager notifications.**

Two Discord channels are used:
- `#homelab-alerts` — warning-severity alerts (default receiver)
- `#homelab-critical` — critical-severity alerts (dedicated receiver)

Each channel has its own Discord webhook URL. Discord's `/slack` suffix on the
webhook URL makes it accept Slack-formatted payloads, so the Alertmanager
`slackConfigs` receiver type is used unchanged. No custom receiver code needed.

Webhook URL format: `https://discord.com/api/webhooks/<id>/<token>/slack`

---

## Rationale

| Criterion | Slack | Discord |
|-----------|-------|---------|
| Message history (free tier) | 90 days — history deleted after limit | Unlimited |
| Setup complexity | Create Slack app, configure scopes, install to workspace | Right-click channel → Integrations → New Webhook |
| Alertmanager integration | Native `slackConfigs` support | Native via `/slack` endpoint (same config) |
| Already in use | No | Yes — existing personal server |
| External dependency | Slack SaaS | Discord SaaS |
| Cost | Free tier sufficient | Free tier sufficient |

The decisive factors:

**Message history:** Slack's free tier limits searchable history to 90 days and
caps storage at 10,000 messages. Alert history older than 90 days is deleted.
For incident retrospectives or pattern analysis, this is a hard limitation.
Discord has no such cap — alerts from months ago remain searchable.

**Setup friction:** A Discord webhook takes under 2 minutes to create with zero
app registration. Slack requires creating and maintaining an app with OAuth
scopes, keeping the app installed in the workspace, and managing the app through
Slack's developer portal.

**Zero code change:** Discord's `/slack` endpoint accepts the identical payload
format. The `slackConfigs` receiver type in `alertmanager-config.yaml` requires
no modification beyond the URL. The pivot is purely a credentials change.

---

## Consequences

- `alertmanager-config.yaml` uses `slackConfigs` with Discord webhook URLs
  (this is correct — Discord's `/slack` endpoint accepts this payload format)
- The `channel` field in each receiver is a required Alertmanager field but is
  **ignored by Discord** — routing to the correct channel is determined entirely
  by which webhook URL is used. Each receiver has its own URL.
- Two Discord webhook secrets are stored in `alertmanager-secret.yaml`:
  `discord-alerts-url` and `discord-critical-url`
- If Discord is ever unavailable, alert delivery fails silently to that channel.
  The healthchecks.io Watchdog is the backstop that detects a broken pipeline.

## Setup

In your Discord server:

```
1. Create two channels: #homelab-alerts and #homelab-critical
2. For each channel:
   - Right-click the channel → Edit Channel → Integrations → Webhooks
   - Click "New Webhook", give it a name (e.g. "Alertmanager")
   - Click "Copy Webhook URL"
   - Append /slack to the URL
3. Store both URLs in alertmanager-secret.yaml (SOPS-encrypted)
```
