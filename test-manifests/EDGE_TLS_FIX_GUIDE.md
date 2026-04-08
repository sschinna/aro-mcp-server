# EJB/WildFly Remoting HTTP 503 Root Cause & Fix Guide

**Status:** Root cause identified and fix provided (ready for customer implementation)

**Impact:** EJB client calls to `/wildfly-services` endpoint return `HTTP 503 Service Unavailable` with ~20-second timeout

---

## Problem Analysis

### Symptoms
- EJB remoting invocations fail with `WFHTTP000005: Invalid response code 503`
- Timeout occurs **exactly ~20 seconds** after request initiation
- Error in logs: `java.nio.channels.ClosedChannelException`
- TLS handshake succeeds (visible in curl/tcpdump), but HTTP stream stalls

### Root Cause: HAProxy + Edge TLS Termination
The customer's external routes are configured with **`edge` TLS termination mode**.

In HAProxy with edge termination:
1. **HAProxy terminates the TLS connection** (decrypts HTTPS → HTTP)
2. **HAProxy inspects the HTTP headers** (looking for certain patterns)
3. **HAProxy strips critical headers**: `Connection: Upgrade`, `Sec-WebSocket-Key`, `Upgrade`
4. **HAProxy proxies plain HTTP** to the backend service
5. **WildFly backend receives HTTP POST** without Upgrade headers
6. **WildFly expects HTTP Upgrade negotiation** (required for EJB remoting protocol)
7. **Backend stalls indefinitely** waiting for upgrade (which never comes)
8. **HAProxy timeout fires** after ~20-30 seconds (default server timeout)
9. **HAProxy returns synthetic HTTP/1.0 503** to the client

**The fix:** Change TLS termination mode from `edge` → `passthrough`.

With **`passthrough` termination**:
- HAProxy does **NOT** decrypt the TLS connection
- HAProxy **does NOT** inspect HTTP headers
- HAProxy **does NOT** modify the HTTP stream
- All data (including HTTP Upgrade headers) flows **end-to-end** from client → backend TLS tunnel
- Backend performs its own TLS termination
- HTTP Upgrade protocol negotiates successfully
- EJB remoting works

---

## Solution: Patch Routes to Passthrough TLS Termination

### Option 1: Automated Patching (Recommended)

#### PowerShell (Windows)
```powershell
# Connect to your cluster first
oc login https://api.<your-cluster>.<region>.aroapp.io:6443

# Run the automated fix script
.\fix-all-routes-edge-termination.ps1 -Apply -Test
```

#### Bash (Linux/macOS)
```bash
# Connect to your cluster first
oc login https://api.<your-cluster>.<region>.aroapp.io:6443

# Run the automated fix script
chmod +x fix-all-routes-edge-termination.sh
./fix-all-routes-edge-termination.sh apply test
```

### Option 2: Manual Patching (Individual Routes)

For each route using `edge` termination:

#### Step 1: Identify the Route
```bash
# List all routes with edge termination
oc -n lastmile-system get routes -o json | \
  jq '.items[] | select(.spec.tls.termination=="edge") | {name:.metadata.name, termination:.spec.tls.termination}'
```

#### Step 2: Backup the Route (Safety)
```bash
oc -n lastmile-system get route <route-name> -o yaml > <route-name>-backup.yaml
```

#### Step 3: Patch the Route TLS Termination
```bash
oc -n lastmile-system patch route <route-name> \
  -p '{"spec":{"tls":{"termination":"passthrough"}}}' \
  --type=merge
```

#### Step 4: Add HAProxy Timeout Annotations (Recommended)
```bash
oc -n lastmile-system annotate route <route-name> \
  haproxy.router.openshift.io/timeout="120s" \
  haproxy.router.openshift.io/timeout-tunnel="1h" \
  --overwrite
```

#### Step 5: Verify the Change
```bash
oc -n lastmile-system get route <route-name> -o jsonpath='{.spec.tls.termination}'
# Should output: passthrough
```

---

## Verification

### 1. Confirm TLS Termination Mode
```bash
# All routes should show "passthrough" for TLS termination
oc -n lastmile-system get routes -o custom-columns=NAME:.metadata.name,TERMINATION:.spec.tls.termination
```

Expected output:
```
NAME                TERMINATION
bfx-route           passthrough
other-route         passthrough
```

### 2. Test EJB Remoting Connectivity
From inside your WildFly pod, test the /wildfly-services endpoint:
```bash
# From within the pod
curl -kv https://<route-host>/wildfly-services -H "Connection: Upgrade"

# Should see:
# HTTP/1.1 101 Switching Protocols  ← This is SUCCESS
# Connection: Upgrade              ← HTTP Upgrade negotiation successful
```

### 3. Test from EJB Client
Run your EJB invocation test. It should complete successfully (not timeout after 20 seconds).

---

## Comparison: Edge vs Passthrough

| Aspect | Edge Termination | Passthrough Termination |
|--------|-----------------|------------------------|
| **TLS handling** | HAProxy terminates TLS, inspects HTTP | HAProxy only proxies encrypted bytes |
| **HTTP Upgrade headers** | ❌ Stripped by HAProxy | ✅ Passed through intact |
| **EJB Remoting (HTTP Upgrade)** | ❌ FAILS (no upgrade headers) | ✅ WORKS (headers preserved) |
| **Timeout behavior** | ~20s (HAProxy server timeout) | None (direct TLS tunnel) |
| **Backend TLS load** | Lower (HAProxy handles TLS) | Higher (backend handles TLS) |
| **Best for** | Web apps (HTTP only) | gRPC, WebSockets, EJB remoting |
| **Security** | HAProxy can inspect/modify traffic | End-to-end encryption maintained |

---

## Rollback (If Needed)

The scripts automatically create backups before patching.

### Using PowerShell
```powershell
.\fix-all-routes-edge-termination.ps1 -Rollback -BackupDir "./route-backups-2026-04-08-120000"
```

### Using Bash
```bash
./fix-all-routes-edge-termination.sh rollback ./route-backups-2026-04-08-120000
```

Or manually restore from backup:
```bash
oc -n lastmile-system apply -f <route-name>-backup.yaml
```

---

## FAQ

**Q: Will this affect my other applications?**
A: No. This only changes the TLS termination mode for routes explicitly patched. Web applications using regular HTTP should be unaffected.

**Q: What if passthrough doesn't work for my use case?**
A: You can rollback using the backup files. Reach out if you encounter issues.

**Q: Do I need to restart my pods?**
A: No. The route change is applied immediately by the OpenShift router.

**Q: How long does this take?**
A: Route patch is near-instantaneous (~1-2 seconds per route).

**Q: Can I test this in a dev environment first?**
A: Yes. Create a test route with passthrough termination and validate HTTP Upgrade works before patching production routes.

---

## Technical Details

### Why HAProxy Strips Upgrade Headers (Edge Termination)
- Edge termination requires HAProxy to **fully inspect the HTTP/1.1 protocol** to handle persistence, routing, etc.
- When HAProxy doesn't see an `Upgrade: websocket` or similar upgrade request in its configuration, it strips these headers to prevent unexpected behavior
- This is a security/stability feature, but breaks protocols like HTTP Upgrade for EJB remoting

### Why Passthrough Works
- Passthrough termination treats HAProxy as a **transparent proxy** for TLS
- HAProxy doesn't decrypt or inspect HTTP; it just forwards encrypted TLS records
- The backend can negotiate any protocol inside the TLS tunnel (including HTTP Upgrade)
- Client and backend perform protocol negotiation directly (end-to-end)

---

## Support

If issues persist after patching:
1. Verify the route TLS mode is actually `passthrough`
2. Check HAProxy logs: `oc logs -n openshift-ingress ds/router-default`
3. Run curl test from inside cluster: Verify HTTP 101 response
4. Contact Azure support with:
   - Current route configuration (from `oc get route -o yaml`)
   - HAProxy router logs
   - Network trace showing TLS handshake + HTTP stream

---

**Created:** 2026-04-08 | **Fix Version:** 1.0
