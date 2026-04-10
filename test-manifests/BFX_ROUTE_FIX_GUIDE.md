# Quick Fix Commands for BFX Route 503 Issue

## Problem
- Route TLS termination: `edge` ❌
- HAProxy strips HTTP Upgrade headers → breaks EJB /wildfly-services endpoint
- Client receives: `WFHTTP000005: Invalid response code 503` after ~20 second timeout

## Root Cause
```
edge TLS termination = TLS proxy + HTTP proxy
↓
HAProxy stops "Connection: Upgrade" header flow
↓
WildFly expects HTTP Upgrade negotiation, hangs
↓
Timeout → synthetic 503 (HTTP/1.0 from HAProxy, not backend)
```

## Solution: One-Command Fix

```bash
# Single command to patch the route
oc -n lastmile-system patch route bfx-route \
  -p '{"spec":{"tls":{"termination":"passthrough"}}}' \
  --type=merge && \
oc -n lastmile-system annotate route bfx-route \
  haproxy.router.openshift.io/timeout="120s" \
  --overwrite
```

Or apply the corrected YAML:

```bash
oc apply -f bfx-route-passthrough.yaml
```

## Verify the Fix

**Check route configuration:**
```bash
oc -n lastmile-system get route bfx-route -o jsonpath='{.spec.tls.termination}'
# Expected output: passthrough
```

**Test EJB connectivity from inside the cluster:**
```bash
# From any pod in the cluster
curl -k -v https://bfx-route-lastmile-system.apps.zkbl97wo.centralindia.aroapp.io/wildfly-services
```

**Look for success indicators:**
- `Connection: Upgrade` header in response
- `HTTP/1.1 101 Switching Protocols` (or similar upgrade response)
- NO `503 Service Unavailable`

**Monitor for errors:**
```bash
# Watch WildFly logs for HTTP Upgrade success
oc -n lastmile-system logs -l app=wildfly -f | grep -i "upgrade\|WFHTTP\|remoting"

# Check ingress router logs
oc -n openshift-ingress logs -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default | \
  grep "bfx-route\|503" | tail -20
```

## Timeline

| Time | Action | Result |
|---|---|---|
| T+0 | Apply patch | Route notified |
| T+5-30s | HAProxy reloads config | New TLS mode active |
| T+30s | First EJB retry | HTTP Upgrade negotiation succeeds ✓ |

## Rollback (if needed)

```bash
# Restore previous edge termination
oc -n lastmile-system patch route bfx-route \
  -p '{"spec":{"tls":{"termination":"edge"}}}' \
  --type=merge
```

Or restore from backup:
```bash
oc apply -f bfx-route-backup-*.yaml
```

## Why This Works

| Parameter | edge ❌ | passthrough ✓ |
|---|---|---|
| TLS termination location | HAProxy | Pod |
| HTTP header handling | Proxied (modified) | Pass-through (untouched) |
| HTTP Upgrade support | ❌ Broken (headers stripped) | ✓ Works (headers preserved) |
| EJB remoting (/wildfly-services) | 503 timeout | ✓ Works |
| Client ← → Backend protocol | HTTP 1.1 | TLS 1.3 + HTTP/upgrade |
| Latency | Lower | Slightly higher (TLS on pod) |
| Security | TLS at LB + pod | TLS at pod only |

---

## Expected Changes

**Before (edge):**
```
EJB Client
  ↓ HTTPS + HTTP Upgrade headers
  ↓ (HAProxy intercepts, strips headers)
  ↓ Plain HTTP POST without Upgrade
WildFly pod → 503 (stalls, timeout)
```

**After (passthrough):**
```
EJB Client
  ↓ HTTPS + HTTP Upgrade headers
  ↓ (HAProxy: pass-through, no modification)
  ↓ TLS encrypted flow to pod
WildFly pod → 101 Switching Protocols ✓
```

---

## Support Info

**Customer cluster:**
- Region: centralindia
- Route: bfx-route-lastmile-system.apps.zkbl97wo.centralindia.aroapp.io
- Service: lastmile-bfx-bulkwire-app
- Namespace: lastmile-system

**Related errors:**
- `WFHTTP000005: Invalid response code 503`
- HTTP response: `HTTP/1.0 503 Service Unavailable` (from HAProxy, not backend)
- Timeout: ~20 seconds (HAProxy default server timeout)
- EJB client logs: "Transitioning ... from WAITING to CONSUMING"

---
