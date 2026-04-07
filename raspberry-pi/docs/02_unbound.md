# Unbound — Recursive DNS Resolver

**Host:** `hodor` (Raspberry Pi)
**Listens on:** `127.0.0.1:5335`
**Role:** Upstream recursive resolver for Pi-hole

---

## Why Unbound Instead of a Forwarding DNS

The default Pi-hole setup forwards DNS queries to an upstream provider (Cloudflare, Google, etc.). This means:

- The upstream provider sees every domain every device on your network queries.
- You're trusting a third party for DNS accuracy and privacy.
- Your ISP can't see the queries (if using DoH/DoT), but Cloudflare can.

**Unbound is a recursive resolver** — it resolves DNS from first principles:

1. Queries the root DNS servers directly.
2. Follows referrals to authoritative nameservers.
3. Returns the answer — no third party involved.

Nobody outside the home network sees your DNS queries. This is the cleanest privacy model possible.

**Trade-off:** First-time queries for uncached domains are slightly slower (~50–200ms vs ~10ms for a cached forwarder). After the first lookup, Unbound caches the result for the TTL duration. In practice this is imperceptible.

---

## Installation

```bash
sudo apt install unbound -y
```

---

## Configuration

Create the Pi-hole-specific Unbound config file:

```bash
sudo nano /etc/unbound/unbound.conf.d/pi-hole.conf
```

```conf
server:
    # Listen on localhost only — Pi-hole is the only client.
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    # Disable IPv6 — not used in this network.
    do-ip6: no

    # Logging — minimal. Enable verbosity: 2 for debugging.
    verbosity: 0

    # DNSSEC validation
    auto-trust-anchor-file: "/var/lib/unbound/root.key"

    # Harden against common attacks.
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: no   # Causes issues with some TLDs if enabled.
    harden-algo-downgrade: no

    # Privacy — minimise the information sent in queries.
    # Sends only the part of the name necessary to resolve, not the full QNAME.
    qname-minimisation: yes

    # Use EDNS0 large buffer to avoid fragmentation.
    edns-buffer-size: 1232

    # Prefetch popular entries before they expire — keeps cache warm.
    prefetch: yes
    prefetch-key: yes

    # Cache settings.
    cache-min-ttl: 300
    cache-max-ttl: 86400
    msg-cache-slabs: 4
    rrset-cache-slabs: 4
    infra-cache-slabs: 4
    key-cache-slabs: 4
    rrset-cache-size: 256m
    msg-cache-size: 128m

    # Allow queries from localhost only.
    access-control: 127.0.0.0/8 allow

    # Hide version and identity strings — minor hardening.
    hide-identity: yes
    hide-version: yes

    # Root hints — where to start recursive resolution.
    root-hints: "/var/lib/unbound/root.hints"

    # Serve stale cache entries for up to 1 hour if upstream is unreachable.
    serve-expired: yes
    serve-expired-ttl: 3600
```

---

## Root Hints

Unbound needs the list of root nameservers to bootstrap recursive resolution. Download it:

```bash
sudo curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
```

Add a monthly cron job to keep it current:

```bash
sudo crontab -e
# Add:
0 3 1 * * curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.root && systemctl restart unbound
```

---

## Enable and Start

```bash
sudo systemctl enable unbound
sudo systemctl start unbound
```

---

## Verify

Test that Unbound is resolving correctly on port 5335:

```bash
# Basic resolution
dig github.com @127.0.0.1 -p 5335

# DNSSEC validation — should show 'ad' flag in response
dig sigok.verteiltesysteme.net @127.0.0.1 -p 5335

# DNSSEC failure — should return SERVFAIL
dig sigfail.verteiltesysteme.net @127.0.0.1 -p 5335
```

Expected output for the DNSSEC test:
- `sigok` → `ANSWER: 1` with `flags: ... ad` (authenticated data)
- `sigfail` → `ANSWER: 0`, `status: SERVFAIL`

---

## Point Pi-hole at Unbound

In the Pi-hole admin UI:

```
Settings → DNS → Upstream DNS Servers
  Custom 1: 127.0.0.1#5335
```

Remove all other upstream entries. Unbound handles everything from here.

---

## Systemd Conflict Resolution

On Debian Bookworm, `systemd-resolved` may occupy port 53. Unbound uses port 5335 so there's no conflict. If you see port conflicts on 53:

```bash
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
```

---

## Maintenance

```bash
# Check status
sudo systemctl status unbound

# View stats
unbound-control stats_noreset

# Flush cache
unbound-control flush_all

# Update root hints (also done by monthly cron)
sudo curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
sudo systemctl restart unbound
```

---

## Related

- [01_pihole.md](01_pihole.md) — Pi-hole setup (uses Unbound as upstream)
- [ADR-014: Pi-hole + Unbound DNS Architecture](../../docs/adr/ADR-014-pihole-unbound-dns.md)
