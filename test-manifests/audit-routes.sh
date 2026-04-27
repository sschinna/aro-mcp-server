#!/bin/bash
# ============================================================================
# Audit ARO Routes for TLS Configuration Issues
# ============================================================================
# Lists ALL routes and highlights which ones have problems:
# - "edge" termination → needs fix (breaks HTTP Upgrade)
# - HTTP (no TLS) → OK for simple HTTP traffic
# - "passthrough" → OK for HTTP Upgrade protocols
# - "reencrypt" → OK for backend TLS
#

NAMESPACE="${1:-lastmile-system}"

echo "========================================================================"
echo "Route Audit Report for Namespace: $NAMESPACE"
echo "========================================================================"
echo ""

# Get all routes with their configurations
oc -n "$NAMESPACE" get routes -o json | python3 << 'EOF'
import sys, json

data = json.load(sys.stdin)
items = data.get('items', [])

print(f"{'Route Name':<40} {'TLS Mode':<15} {'Port':<10} {'Status':<10}")
print("-" * 80)

edge_routes = []
ok_routes = []
no_tls_routes = []

for route in items:
    name = route['metadata']['name']
    host = route['spec'].get('host', 'N/A')
    
    # Check TLS config
    tls = route['spec'].get('tls', {})
    
    if not tls:
        termination = "HTTP (none)"
        status = "OK"
        no_tls_routes.append(name)
    else:
        termination = tls.get('termination', 'unknown')
        if termination == 'edge':
            status = "BROKEN ⚠️ "
            edge_routes.append(name)
        else:
            status = "OK"
            ok_routes.append(name)
    
    target_port = route['spec'].get('port', {}).get('targetPort', 'N/A')
    
    print(f"{name:<40} {termination:<15} {str(target_port):<10} {status:<10}")

print("")
print("=" * 80)
print("Summary:")
print(f"  ✓ HTTP (no TLS):        {len(no_tls_routes)} route(s)")
for r in no_tls_routes:
    print(f"    - {r}")

print(f"  ✓ Passthrough/Reencrypt: {len(ok_routes)} route(s)")
for r in ok_routes:
    print(f"    - {r}")

print(f"  ⚠️  Edge TLS (BROKEN):   {len(edge_routes)} route(s) - NEED FIX")
for r in edge_routes:
    print(f"    - {r}")

if len(edge_routes) > 0:
    print("")
    print("ACTION REQUIRED:")
    print("  Run: ./fix-all-routes-edge-termination.ps1 -Apply -Test")
    print("  Or:  ./fix-all-routes-edge-termination.sh apply test")
else:
    print("")
    print("✓ All routes are properly configured!")
EOF
