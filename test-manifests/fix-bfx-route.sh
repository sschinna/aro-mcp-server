#!/bin/bash
# Route Fix Deployment Guide
# Fixes EJB remoting 503 errors by changing TLS termination from edge → passthrough

set -e

NAMESPACE="lastmile-system"
ROUTE_NAME="bfx-route"
CLUSTER_NAME="zkbl97wo"
REGION="centralindia"

echo "═══════════════════════════════════════════════════════════════"
echo "BFX Route TLS Fix: edge → passthrough"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Step 1: Backup current route
echo "[1/4] Backing up current route configuration..."
oc -n $NAMESPACE get route $ROUTE_NAME -o yaml > bfx-route-backup-$(date +%s).yaml
echo "  ✓ Backup saved: bfx-route-backup-*.yaml"
echo ""

# Step 2: Check current termination mode
echo "[2/4] Current route configuration:"
CURRENT_TERMINATION=$(oc -n $NAMESPACE get route $ROUTE_NAME -o jsonpath='{.spec.tls.termination}')
echo "  Current TLS termination: $CURRENT_TERMINATION"
if [ "$CURRENT_TERMINATION" = "edge" ]; then
  echo "  ⚠️  PROBLEM: edge termination breaks EJB HTTP Upgrade protocol"
else
  echo "  ✓ Termination is already: $CURRENT_TERMINATION"
fi
echo ""

# Step 3: Apply patched route with passthrough
echo "[3/4] Patching route to use passthrough TLS termination..."
oc -n $NAMESPACE patch route $ROUTE_NAME \
  -p '{"spec":{"tls":{"termination":"passthrough"}}}' \
  --type=merge

# Add timeout annotations if missing
oc -n $NAMESPACE annotate route $ROUTE_NAME \
  haproxy.router.openshift.io/timeout="120s" \
  haproxy.router.openshift.io/timeout-tunnel="1h" \
  --overwrite 2>/dev/null || true

echo "  ✓ Route patched successfully"
echo ""

# Step 4: Verify the fix
echo "[4/4] Verifying fix..."
UPDATED_TERMINATION=$(oc -n $NAMESPACE get route $ROUTE_NAME -o jsonpath='{.spec.tls.termination}')
TIMEOUT_ANNOTATION=$(oc -n $NAMESPACE get route $ROUTE_NAME -o jsonpath='{.metadata.annotations.haproxy\.router\.openshift\.io/timeout}')

echo "  New TLS termination: $UPDATED_TERMINATION"
echo "  HAProxy timeout: $TIMEOUT_ANNOTATION"

if [ "$UPDATED_TERMINATION" = "passthrough" ]; then
  echo "  ✓ Fix applied successfully!"
else
  echo "  ✗ Fix failed - termination is still: $UPDATED_TERMINATION"
  exit 1
fi
echo ""

# Step 5: Test connectivity
echo "═══════════════════════════════════════════════════════════════"
echo "Testing EJB endpoint connectivity..."
echo "═══════════════════════════════════════════════════════════════"
echo ""

ROUTE_HOST="bfx-route-lastmile-system.apps.${CLUSTER_NAME}.${REGION}.aroapp.io"
echo "Testing: https://$ROUTE_HOST/wildfly-services"
echo ""

# Get a test pod to run curl from
TEST_POD=$(oc -n $NAMESPACE get pods -l app=wildfly 2>/dev/null | grep -v NAME | head -1 | awk '{print $1}')
if [ -z "$TEST_POD" ]; then
  echo "⚠️  No WildFly pods found for testing. Manual test needed."
  echo "Run from any pod in cluster:"
  echo "  curl -k -v https://$ROUTE_HOST/wildfly-services"
else
  echo "Test pod: $TEST_POD"
  echo ""
  echo "Running curl with verbose output (should show HTTP Upgrade headers)..."
  echo ""
  
  # Run curl and capture output - look for Upgrade and 101 response
  OUTPUT=$(oc -n $NAMESPACE exec $TEST_POD -- \
    curl -k -v --connect-timeout 5 \
    https://$ROUTE_HOST/wildfly-services 2>&1 || true)
  
  echo "$OUTPUT" | head -30
  
  # Check for success indicators
  if echo "$OUTPUT" | grep -q "HTTP Upgrade\|101 Switching\|Connection: Upgrade"; then
    echo ""
    echo "✓ SUCCESS: HTTP Upgrade protocol working!"
    echo "  EJB remote calls should now work without 503 errors"
  elif echo "$OUTPUT" | grep -q "503\|Service Unavailable"; then
    echo ""
    echo "✗ ERROR: Still receiving 503 - route fix may not have propagated"
    echo "  Wait 30-60 seconds for router to reload, then retry"
  else
    echo ""
    echo "⚠️  Inconclusive result - check output above"
  fi
fi
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "Summary:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Route: $ROUTE_NAME"
echo "Namespace: $NAMESPACE"
echo "TLS Termination: $UPDATED_TERMINATION (was: $CURRENT_TERMINATION)"
echo ""
echo "Next steps:"
echo "1. Wait 30-60 seconds for OpenShift router to reload configuration"
echo "2. Retry EJB client connections"
echo "3. Monitor /opt/jboss/wildfly/standalone/log/server.log for errors"
echo "4. If issues persist, check:"
echo "   - Service endpoints: oc -n $NAMESPACE get endpoints lastmile-bfx-bulkwire-app"
echo "   - Pod logs: oc -n $NAMESPACE logs -l app=wildfly --tail=100"
echo ""
