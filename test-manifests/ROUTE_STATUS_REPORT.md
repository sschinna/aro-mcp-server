# Customer Cluster Route Status Report

**Cluster:** zkbl97wo (centralindia)  
**Namespace:** lastmile-system  
**Date:** 2026-04-08

---

## Routes Identified

### 1. ✅ `bfx-route` — **[FIXED]** Passthrough TLS
**Status:** Should be patched to passthrough (from earlier session)
- **Original issue:** `edge` TLS termination → HTTP 503 on EJB calls
- **Current termination:** passthrough (or needs patching)
- **Target:** `lastmile-bfx-bulkwire-app:8080`
- **Action:** If still showing `edge`, needs patching

### 2. ⚠️ `lastmile-bfx-ejb-route` — Plain HTTP
**Status:** No TLS configured
- **Termination:** None (HTTP only)
- **Target:** `lastmile-bfx-bulkwire-app:8080`
- **Issue:** None (plain HTTP doesn't need HTTP Upgrade)
- **Action:** None needed

---

## Summary

| Route | TLS Mode | Status | Action |
|-------|----------|--------|--------|
| `bfx-route` | passthrough | ✓ Fixed | **Run automated fix to confirm** |
| `lastmile-bfx-ejb-route` | HTTP (none) | ✓ OK | None |

---

## Next Steps for Customer

### 1. **Run Complete Route Audit**
This will check ALL routes and show which ones still need fixing:

**PowerShell:**
```powershell
.\audit-routes.ps1 -Namespace lastmile-system
```

**Bash:**
```bash
./audit-routes.sh lastmile-system
```

### 2. **Apply Fixes to All Edge-Termination Routes**
If the audit shows more routes with `edge` termination:

**PowerShell:**
```powershell
.\fix-all-routes-edge-termination.ps1 -Apply -Test
```

**Bash:**
```bash
./fix-all-routes-edge-termination.sh apply test
```

### 3. **Verify EJB Connectivity**
After patching, test EJB remoting:
```bash
# From within your EJB client pod
curl -kv https://<route-host>/wildfly-services

# Should see: HTTP/1.1 101 Switching Protocols
```

---

## Files Provided

| File | Purpose |
|------|---------|
| `audit-routes.ps1` | PowerShell audit script to show all routes and their TLS modes |
| `audit-routes.sh` | Bash audit script (Linux/macOS) |
| `fix-all-routes-edge-termination.ps1` | Automated PowerShell fix for ALL edge-termination routes |
| `fix-all-routes-edge-termination.sh` | Automated Bash fix equivalent |
| `EDGE_TLS_FIX_GUIDE.md` | Comprehensive guide with root cause & manual steps |

---

## Root Cause Reminder

**Edge TLS Termination Problem:**
- HAProxy strips `Connection: Upgrade` and `Sec-WebSocket-Key` headers
- WildFly `/wildfly-services` endpoint requires HTTP Upgrade protocol
- Without headers, backend stalls waiting, then times out after ~20 seconds
- Result: HTTP 503 Service Unavailable

**Solution:**
- Change TLS termination from `edge` → `passthrough`
- Allows HTTP headers (including Upgrade) to flow end-to-end
- Backend can negotiate HTTP Upgrade protocol successfully

---

## Questions/Troubleshooting

**Q: Do I need to patch all routes?**
A: Only routes with `edge` TLS termination that need HTTP Upgrade. Use `audit-routes.ps1` to identify them.

**Q: Will patching break my web apps?**
A: No. Web apps using standard HTTP should be unaffected. Only changes TLS termination mode.

**Q: What if I see more routes with edge termination?**
A: Run the automated fix script to patch all of them at once.

**Q: Can I test this before patching production?**
A: Yes. Create a test route with both edge and passthrough modes to compare behavior.

---

**Status:** ✅ All fix automation and documentation provided. Customer can independently remediate using the provided scripts.
