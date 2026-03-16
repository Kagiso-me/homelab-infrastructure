
# Runbook — Certificate Renewal Failure

**Scenario:** A TLS certificate has failed to renew, or a browser is showing a security warning for a cluster service.

> **Note:** Cloudflare handles TLS automatically for all public web services (Grafana, Sonarr, Nextcloud, Immich, etc.) via Cloudflare Tunnel. cert-manager certificates managed by this runbook are only used for **direct/VPN access** scenarios — primarily Plex accessed via Tailscale (which uses WireGuard under the hood) and any services using the internal CA. If a public-facing service shows a browser TLS error, check Cloudflare Tunnel status first before investigating cert-manager.

Certificate failures tend to surface at the worst time: they produce a hard user-visible error (browser security warning) rather than a soft degradation, and they happen at expiry — often outside business hours.

---

## Step 1 — Identify the Failing Certificate

List all certificates managed by cert-manager:

```bash
kubectl get certificates -A
```

Look for `READY: False` or `AGE` values that suggest a recently expired or pending certificate.

```bash
# Detailed status of a specific certificate
kubectl describe certificate <cert-name> -n <namespace>
```

Look at the `Events` and `Status.Conditions` sections. Common conditions:

- `Issuing` — currently being issued (may resolve on its own, wait 2 minutes)
- `False` with reason `Failed` — issuance has failed

---

## Step 2 — Check the CertificateRequest

cert-manager creates a `CertificateRequest` for each issuance attempt:

```bash
kubectl get certificaterequest -A
```

```bash
kubectl describe certificaterequest <name> -n <namespace>
```

Look for the failure reason. Common failures:

| Reason | Meaning |
|--------|---------|
| `Failed to create Order` | ACME order creation failed |
| `HTTP-01 challenge failed` | Let's Encrypt could not reach the challenge URL |
| `Rate limited` | Too many certificate requests to Let's Encrypt |
| `Invalid issuer` | The referenced ClusterIssuer does not exist or is misconfigured |

---

## Step 3 — Check the ClusterIssuer Status

```bash
kubectl describe clusterissuer letsencrypt
```

Check `Status.Conditions`. It should show `Ready: True`. If not, check the ACME account registration.

---

## Step 4 — Common Fixes

### Fix A — Force re-issuance

Delete the failing `Certificate` resource. cert-manager will recreate it and try again:

```bash
kubectl delete certificate <cert-name> -n <namespace>
```

Flux will reconcile the certificate back from Git within minutes. cert-manager will attempt issuance again.

### Fix B — HTTP-01 challenge cannot be reached

Let's Encrypt must reach `http://<domain>/.well-known/acme-challenge/<token>`.

Verify:

1. The domain resolves to the MetalLB IP (10.0.10.110).
2. Traefik is running and the ingress for the domain is present.
3. Port 80 is reachable from the internet (if using Let's Encrypt; not required for internal CA).

```bash
# Check Traefik is running
kubectl get pods -n ingress

# Check the ingress resource exists
kubectl get ingress -A
kubectl get ingressroute -A
```

If using a local domain (`home.lab`) with Let's Encrypt, this will always fail — Let's Encrypt cannot reach your local DNS. Use the internal CA for local-only services.

### Fix C — Rate limited

Let's Encrypt applies rate limits per domain per week. If you see rate limit errors:

1. **Do not retry immediately** — this will exhaust the rate limit further.
2. Wait for the rate limit window to expire (up to 1 week for the `certificates per registered domain` limit).
3. In the meantime, verify the configuration is correct by inspecting the Certificate and CertificateRequest resources without triggering a new issuance attempt.
4. Once the rate limit expires, force re-issuance using Fix A above.

### Fix D — Manually renew before expiry

If a certificate is within 30 days of expiry but has not renewed automatically:

```bash
# Check if cert-manager sees it as needing renewal
kubectl get certificate <cert-name> -n <namespace> -o yaml | grep renewalTime

# Force renewal by annotating the certificate
kubectl annotate certificate <cert-name> -n <namespace> \
  cert-manager.io/issue-temporary-certificate="true" --overwrite
```

Or delete the Secret containing the current certificate to force re-issuance:

```bash
# WARNING: this causes a brief outage while the new cert is issued (usually < 30 seconds)
kubectl delete secret <tls-secret-name> -n <namespace>
```

---

## Step 5 — Verify Certificate is Healthy

```bash
kubectl get certificate -A
```

All certificates should show `READY: True`.

Test the certificate from the automation host:

```bash
curl -v https://grafana.home.lab 2>&1 | grep -E "subject|issuer|expire"
```

---

## Step 6 — Alert Tuning

If this runbook was triggered by a certificate expiry alert, verify the alert threshold:

The alert should fire when a certificate is within **14 days** of expiry, giving 14 days to resolve before the certificate actually expires.

cert-manager begins renewal attempts at 30 days before expiry by default. A certificate that has been failing for 16 days without resolution will trigger the alert.

If the alert fired with more than 30 days remaining, check whether cert-manager itself is healthy:

```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager deployment/cert-manager | tail -50
```

---

## Prevention

- Monitor certificate expiry in Grafana. The kube-prometheus-stack includes cert-manager dashboards.
- Alert at 14 days to give ample time for investigation.
- Test issuance after any networking or DNS changes.
- Prefer internal CA for services that are never exposed externally (no ACME dependency).
