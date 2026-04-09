# =============================================================================
# MikroTik Firewall Hardening Script — v2
# Apply: paste into RouterOS terminal directly (do not use bash/sh)
# Safe: adds rules only, removes nothing. Review after with: /ip firewall filter print
# =============================================================================

# ── Drop known bad IPs at wire speed (before everything else)
/ip firewall filter add chain=input action=drop src-address-list=fw_blocklist in-interface-list=WAN comment="Drop known bad IPs (dynamic blocklist)" place-before=0

# ── Blocklist portscanners for 1h
/ip firewall filter add chain=input action=add-src-to-address-list connection-state=new protocol=tcp psd=21,3s,3,1 in-interface-list=WAN address-list=fw_blocklist address-list-timeout=1h comment="Blocklist portscanners for 1h" place-before=0

# ── Log portscan (rate limited to 5 per 10s globally)
/ip firewall filter add chain=input action=log connection-state=new protocol=tcp psd=21,3s,3,1 in-interface-list=WAN limit=5,10 log-prefix="FW_PORTSCAN " comment="Log portscan (rate limited)" place-before=0

# ── Blocklist SSH attackers for 6h
/ip firewall filter add chain=input action=add-src-to-address-list connection-state=new protocol=tcp in-interface-list=WAN dst-port=22 address-list=fw_blocklist address-list-timeout=6h comment="Blocklist SSH attackers for 6h" place-before=0

# ── Log SSH attempts (rate limited to 3 per 5s globally)
/ip firewall filter add chain=input action=log connection-state=new protocol=tcp in-interface-list=WAN dst-port=22 limit=3,5 log-prefix="FW_SSH_ATTEMPT " comment="Log SSH attempt (rate limited)" place-before=0

# ── Log general WAN input drops (rate limited to 1 per 30s globally — cuts noise)
/ip firewall filter add chain=input action=log connection-state=new in-interface-list=WAN limit=1,30 log-prefix="FW_INPUT_DROP " comment="Log WAN input drop (rate limited)" place-before=0

# ── Log brute-force before silent drop (rule 9 was dropping without logging)
/ip firewall filter add chain=input action=log connection-state=new connection-limit=3,32 protocol=tcp in-interface-list=WAN dst-port=21,22,23,80,8291 log-prefix="BRUTE_ATTEMPT " comment="Log brute-force before drop" place-before=0

# ── Blocklist brute-force IPs for 24h
/ip firewall filter add chain=input action=add-src-to-address-list connection-state=new connection-limit=3,32 protocol=tcp in-interface-list=WAN dst-port=21,22,23,80,8291 address-list=fw_blocklist address-list-timeout=24h comment="Blocklist brute-force IPs for 24h" place-before=0

# ── Drop WAN forward flood (rate limit new connections, 50 per 100s globally)
/ip firewall filter add chain=forward action=drop connection-state=new in-interface-list=WAN limit=50,100 comment="Drop WAN forward flood" place-before=0

# =============================================================================
# After applying, verify with:
#   /ip firewall filter print
#
# Watch blocklist populate in real time:
#   /ip firewall address-list print where list=fw_blocklist
#
# Once confirmed working, remove the old unrated rules 6, 7, 8 (original numbering)
# by finding them in /ip firewall filter print and using /ip firewall filter remove numbers=X
# =============================================================================
