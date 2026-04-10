#!/bin/sh
#
# DIGEST Auth Nonce Expiry Test Caller
# This script obtains a fresh nonce, waits for expiry, then replays it
# to capture the exact "due to age" failure message in WildFly logs
#

set -e

TARGET_HOST="wildfly-app2-mgmt-wildfly-route-test.apps.aromcpcluster.centralus.aroapp.io"
TARGET_URL="https://${TARGET_HOST}/management"
TEST_USER="admin"
TEST_PASS="Admin#123"
NONCE_VALIDITY_SECONDS=300
WAIT_SECONDS=310

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting DIGEST nonce expiry test..."
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Target: ${TARGET_URL}"

# Step 1: Obtain fresh nonce by making unauthenticated request
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Step 1: Fetching WWW-Authenticate header to extract nonce..."
CHALLENGE_RESPONSE=$(curl -k -s -i "${TARGET_URL}" 2>&1 | grep -i "www-authenticate:" || true)

if [ -z "$CHALLENGE_RESPONSE" ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: No WWW-Authenticate header received. Response:"
  curl -k -s -i "${TARGET_URL}" 2>&1 | head -20
  sleep 3600
  exit 1
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Received: ${CHALLENGE_RESPONSE}"

# Extract nonce using advanced parameter parsing
# Format: Digest realm="...", nonce="...", algorithm=MD5, qop=auth
NONCE=$(echo "$CHALLENGE_RESPONSE" | grep -oP 'nonce="\K[^"]+' || true)

if [ -z "$NONCE" ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: Could not extract nonce from response"
  sleep 3600
  exit 1
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Successfully extracted nonce: ${NONCE}"
NONCE_OBTAINED_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Nonce obtained at: ${NONCE_OBTAINED_TIME}"

# Step 2: Wait for nonce to age past validity window
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Step 2: Waiting ${WAIT_SECONDS} seconds for nonce to expire (validity: ${NONCE_VALIDITY_SECONDS}s)..."
for i in $(seq 1 $WAIT_SECONDS); do
  REMAINING=$((WAIT_SECONDS - i))
  if [ $((REMAINING % 30)) -eq 0 ] || [ $REMAINING -le 5 ]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)]   ${REMAINING} seconds remaining..."
  fi
  sleep 1
done

# Step 3: Craft DIGEST auth header with expired nonce
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Step 3: Crafting DIGEST Authorization header with expired nonce..."
CNONCE="clientnonce123456"
QOPAUTH="auth"
ALGORITHM="MD5"
REALM="ManagementRealm"
URI="/management"
NC="00000001"

# Compute response hash
# response = MD5(MD5(username:realm:password):nonce:nc:cnonce:qop:MD5(method:uri))
HA1=$(echo -n "${TEST_USER}:${REALM}:${TEST_PASS}" | md5sum | cut -d' ' -f1)
HA2=$(echo -n "GET:${URI}" | md5sum | cut -d' ' -f1)
RESPONSE=$(echo -n "${HA1}:${NONCE}:${NC}:${CNONCE}:${QOPAUTH}:${HA2}" | md5sum | cut -d' ' -f1)

AUTH_HEADER="Digest username=\"${TEST_USER}\", realm=\"${REALM}\", nonce=\"${NONCE}\", uri=\"${URI}\", algorithm=${ALGORITHM}, response=\"${RESPONSE}\", qop=${QOPAUTH}, nc=${NC}, cnonce=\"${CNONCE}\""

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Authorization header prepared"

# Step 4: Send request with expired nonce
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Step 4: Sending request with expired nonce..."
RESPONSE_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -H "Authorization: ${AUTH_HEADER}" "${TARGET_URL}" 2>&1 || true)
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Response code: ${RESPONSE_CODE}"

# Step 5: Keep pod running for log inspection
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Test request sent. Keeping pod alive for 1 hour for log inspection..."
sleep 3600

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Test complete."
