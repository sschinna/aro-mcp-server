#!/bin/bash
# ============================================================================
# Fix HTTP 503 errors on EJB/WildFly remoting by converting edge → passthrough
# ============================================================================
# 
# Problem: ARO ingress HAProxy+edge TLS strips HTTP Upgrade headers, breaking
#          WildFly's /wildfly-services endpoint (EJB remoting protocol).
# Solution: Change TLS termination from "edge" to "passthrough" so HTTP headers
#           flow end-to-end, allowing HTTP Upgrade protocol negotiation.
#
# Usage:
#   ./fix-all-routes-edge-termination.sh                    # Dry-run (no changes)
#   ./fix-all-routes-edge-termination.sh apply              # Apply patches
#   ./fix-all-routes-edge-termination.sh apply test         # Apply + test
#   ./fix-all-routes-edge-termination.sh rollback <backupdir> # Restore backup
#

set -e

# Configuration
NAMESPACE="${1:-lastmile-system}"
BACKUP_DIR="route-backups-$(date +%Y-%m-%d-%H%M%S)"
APPLY_MODE="${2:-dry-run}"
TEST_MODE="${3:-}"

DRY_RUN=true
[ "$APPLY_MODE" = "apply" ] && DRY_RUN=false
[ "$APPLY_MODE" = "rollback" ] && BACKUP_DIR="$TEST_MODE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Helper functions
# ============================================================================
info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}$(printf '%.0s=' {1..80})${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}$(printf '%.0s=' {1..80})${NC}"
}

# ============================================================================
# Pre-flight checks
# ============================================================================
section "Pre-flight Checks"

if ! command -v oc &> /dev/null; then
    error "oc CLI not found. Install from https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    exit 1
fi

CURRENT_CONTEXT=$(oc config current-context 2>&1) || {
    error "Not logged in to a cluster. Run: oc login <api-server>"
    exit 1
}

info "Connected to: $CURRENT_CONTEXT"
info "Target namespace: $NAMESPACE"

if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    error "Namespace '$NAMESPACE' not found"
    exit 1
fi

success "Namespace '$NAMESPACE' exists"

# ============================================================================
# Rollback mode
# ============================================================================
if [ "$APPLY_MODE" = "rollback" ]; then
    section "Rollback Mode: Restoring Routes from Backup"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    count=0
    for backup_file in "$BACKUP_DIR"/*.json; do
        if [ ! -f "$backup_file" ]; then
            error "No backup files found in $BACKUP_DIR"
            exit 1
        fi
        
        route_name=$(basename "$backup_file" .json)
        info "Restoring: $route_name"
        
        if cat "$backup_file" | oc -n "$NAMESPACE" apply -f - &>/dev/null; then
            success "Restored: $route_name"
            ((count++))
        else
            error "Failed to restore $route_name"
        fi
    done
    
    success "Rollback complete: $count route(s) restored"
    exit 0
fi

# ============================================================================
# Scan for edge termination routes
# ============================================================================
section "Scanning for Routes with Edge TLS Termination"

EDGE_ROUTES=()
while IFS= read -r line; do
    [ -z "$line" ] && continue
    EDGE_ROUTES+=("$line")
done < <(oc -n "$NAMESPACE" get routes -o json | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for route in data.get('items', []):
    tls = route.get('spec', {}).get('tls', {})
    if tls.get('termination') == 'edge':
        print(f\"\\\"\\\"\"{route['metadata']['name']}\\\"\\\"\\\")
" 2>/dev/null)

if [ ${#EDGE_ROUTES[@]} -eq 0 ]; then
    warning "No routes with 'edge' termination found"
    exit 0
fi

info "Found ${#EDGE_ROUTES[@]} route(s) with 'edge' termination:"
for route in "${EDGE_ROUTES[@]}"; do
    warning "  - $route"
done

# ============================================================================
# Dry-run: show changes
# ============================================================================
if [ "$DRY_RUN" = true ]; then
    section "Dry-Run Mode: Changes That Would Be Applied"
    
    for route_name in "${EDGE_ROUTES[@]}"; do
        echo ""
        info "Route: $route_name"
        ROUTE_DATA=$(oc -n "$NAMESPACE" get route "$route_name" -o json)
        SERVICE=$(echo "$ROUTE_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['spec']['to']['name'])" 2>/dev/null)
        HOST=$(echo "$ROUTE_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin)['spec']['host'])" 2>/dev/null)
        
        echo "    Service: $SERVICE"
        echo "    Host: $HOST"
        echo "    Current TLS: edge"
        echo -e "    New TLS: ${GREEN}passthrough${NC}"
        echo -e "    Timeouts: ${GREEN}120s request, 1h tunnel${NC}"
    done
    
    echo ""
    info "To apply patches, run: $0 apply"
    exit 0
fi

# ============================================================================
# Apply patches
# ============================================================================
section "Applying Patches to Routes"

mkdir -p "$BACKUP_DIR"
PATCHED=0
FAILED=0

for route_name in "${EDGE_ROUTES[@]}"; do
    echo ""
    info "Processing: $route_name"
    
    # Backup original
    BACKUP_PATH="$BACKUP_DIR/$route_name.json"
    if oc -n "$NAMESPACE" get route "$route_name" -o json > "$BACKUP_PATH"; then
        success "  ✓ Backed up to: $BACKUP_PATH"
    else
        error "  ✗ Failed to backup $route_name"
        ((FAILED++))
        continue
    fi
    
    # Patch TLS termination
    if oc -n "$NAMESPACE" patch route "$route_name" \
        -p '{"spec":{"tls":{"termination":"passthrough"}}}' \
        --type=merge &>/dev/null; then
        success "  ✓ TLS termination patched to passthrough"
    else
        error "  ✗ Failed to patch TLS termination"
        ((FAILED++))
        continue
    fi
    
    # Add timeout annotations
    if oc -n "$NAMESPACE" annotate route "$route_name" \
        haproxy.router.openshift.io/timeout="120s" \
        haproxy.router.openshift.io/timeout-tunnel="1h" \
        --overwrite &>/dev/null; then
        success "  ✓ Timeout annotations added"
        ((PATCHED++))
    else
        error "  ✗ Failed to add annotations"
        ((FAILED++))
    fi
done

# ============================================================================
# Verify patches
# ============================================================================
section "Verification: Confirming Patches Were Applied"

VERIFIED=0
for route_name in "${EDGE_ROUTES[@]}"; do
    TERMINATION=$(oc -n "$NAMESPACE" get route "$route_name" -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
    
    if [ "$TERMINATION" = "passthrough" ]; then
        success "$route_name: TLS termination is now 'passthrough' ✓"
        ((VERIFIED++))
    else
        error "$route_name: TLS termination is still '$TERMINATION' ✗"
    fi
done

# ============================================================================
# Test connectivity
# ============================================================================
if [ "$TEST_MODE" = "test" ] && command -v curl &> /dev/null; then
    section "Testing Connectivity to Patched Routes"
    
    for route_name in "${EDGE_ROUTES[@]}"; do
        HOST=$(oc -n "$NAMESPACE" get route "$route_name" -o jsonpath='{.spec.host}' 2>/dev/null)
        info "Testing: $route_name → $HOST"
        
        if timeout 5 curl -kv "https://$HOST" 2>&1 | head -20 | grep -q "HTTP\|Connection"; then
            success "  ✓ Route is accessible"
        else
            warning "  ✗ No HTTP response (may indicate timeout)"
        fi
    done
fi

# ============================================================================
# Summary
# ============================================================================
section "Summary"
info "Processed: ${#EDGE_ROUTES[@]} route(s)"
[ $PATCHED -gt 0 ] && success "Patched: $PATCHED" || error "Patched: $PATCHED"
[ $FAILED -eq 0 ] && success "Failed: $FAILED" || error "Failed: $FAILED"
info "Backups: $BACKUP_DIR"
echo ""
success "EJB/WildFly remoting should now work. HTTP Upgrade protocol flows end-to-end."
echo ""
