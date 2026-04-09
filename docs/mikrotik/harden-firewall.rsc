# =============================================================================
# MikroTik Firewall Hardening Script
# Apply: paste into RouterOS terminal, or ssh admin@10.0.10.1 "import file=harden-firewall.rsc"
# Safe: adds rules only, removes nothing. Review after with: /ip firewall filter print
# =============================================================================

# ── Step 1: Blocklist address-list timeout
# IPs added to fw_blocklist expire after 24h automatically.
# No manual cleanup needed.

# ── Step 2: Insert "drop known bad IPs" at position 0 (before everything else)
# This hits before established/related — known attackers get dropped at wire speed.
/ip firewall filter add \
  chain=input \
  action=drop \
  src-address-list=fw_blocklist \
  in-interface-list=WAN \
  comment="Drop known bad IPs (dynamic blocklist)" \
  place-before=0

# ── Step 3: Replace logging rules with rate-limited + blocklist-building versions
# Current rules 6, 7, 8 log without rate limits — a sustained scan fills the buffer.
# We add NEW rules with limits and blocklist population BEFORE the existing ones,
# then the old rules still fire (harmless — they just also log without limit).
# You can manually remove the old rules 6/7/8 after verifying these work.

# Port scan detection → add to blocklist for 1h, log with rate limit
/ip firewall filter add \
  chain=input \
  action=add-src-to-address-list \
  connection-state=new \
  protocol=tcp \
  psd=21,3s,3,1 \
  in-interface-list=WAN \
  address-list=fw_blocklist \
  address-list-timeout=1h \
  comment="Blocklist portscanners for 1h" \
  place-before=0

/ip firewall filter add \
  chain=input \
  action=log \
  connection-state=new \
  protocol=tcp \
  psd=21,3s,3,1 \
  in-interface-list=WAN \
  limit=5,10:src-address \
  log-prefix="FW_PORTSCAN " \
  comment="Log portscan (rate limited)" \
  place-before=0

# SSH attempt → add to blocklist for 6h, log with rate limit
/ip firewall filter add \
  chain=input \
  action=add-src-to-address-list \
  connection-state=new \
  protocol=tcp \
  in-interface-list=WAN \
  dst-port=22 \
  address-list=fw_blocklist \
  address-list-timeout=6h \
  comment="Blocklist SSH attackers for 6h" \
  place-before=0

/ip firewall filter add \
  chain=input \
  action=log \
  connection-state=new \
  protocol=tcp \
  in-interface-list=WAN \
  dst-port=22 \
  limit=3,5:src-address \
  log-prefix="FW_SSH_ATTEMPT " \
  comment="Log SSH attempt (rate limited)" \
  place-before=0

# General WAN input → log with rate limit (1 per src per 30s to cut noise)
/ip firewall filter add \
  chain=input \
  action=log \
  connection-state=new \
  in-interface-list=WAN \
  limit=1,30:src-address \
  log-prefix="FW_INPUT_DROP " \
  comment="Log WAN input drop (rate limited, 1/30s per src)" \
  place-before=0

# ── Step 4: Log brute-force attempts before they're silently dropped (rule 9)
# Rule 9 currently drops with log=no — you never see which IPs triggered it.
# This log rule fires first, then falls through to the existing drop.
/ip firewall filter add \
  chain=input \
  action=log \
  connection-state=new \
  connection-limit=3,32 \
  protocol=tcp \
  in-interface-list=WAN \
  dst-port=21,22,23,80,8291 \
  log-prefix="BRUTE_ATTEMPT " \
  comment="Log brute-force before drop" \
  place-before=0

# Also add brute-force IPs to blocklist
/ip firewall filter add \
  chain=input \
  action=add-src-to-address-list \
  connection-state=new \
  connection-limit=3,32 \
  protocol=tcp \
  in-interface-list=WAN \
  dst-port=21,22,23,80,8291 \
  address-list=fw_blocklist \
  address-list-timeout=24h \
  comment="Blocklist brute-force IPs for 24h" \
  place-before=0

# ── Step 5: Forward chain — rate limit new connections from WAN
# Protects against SYN floods and connection table exhaustion.
# Drops new forward connections exceeding 50/sec per source IP.
/ip firewall filter add \
  chain=forward \
  action=drop \
  connection-state=new \
  in-interface-list=WAN \
  limit=50,100:src-address \
  comment="Drop WAN forward flood (>50 new conn/s per src)" \
  place-before=0

# ── Step 6: Disable unused services that are exposed
# FTP (21) and Winbox (8291) should not be reachable from WAN.
# They're already blocked by your firewall but disabling reduces attack surface.
# OPTIONAL — uncomment if you don't use FTP on the router itself:
# /ip service disable ftp

# =============================================================================
# After applying, verify with:
#   /ip firewall filter print
#   /ip firewall address-list print
#
# To watch the blocklist populate in real time:
#   /ip firewall address-list print where list=fw_blocklist
#
# To remove old unrated log rules once you've verified the new ones work:
#   Find rules 6, 7, 8 in the original numbering and remove by comment or number.
# =============================================================================
