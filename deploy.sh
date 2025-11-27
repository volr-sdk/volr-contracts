#!/bin/bash
# Deploy all Volr contracts and update database
# Usage: ./deploy.sh <CHAIN_ID> [--skip-db]
# Example: ./deploy.sh 5115

set -e

CHAIN_ID=$1
SKIP_DB=false

if [ "$2" == "--skip-db" ]; then
    SKIP_DB=true
fi

if [ -z "$CHAIN_ID" ]; then
    echo "Usage: $0 <CHAIN_ID> [--skip-db]"
    echo "Example: $0 5115"
    exit 1
fi

# Load .env file from volr-contracts
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Get RPC URL
RPC_ENV_VAR="RPC_URL_${CHAIN_ID}"
RPC_URL=$(eval echo \$$RPC_ENV_VAR)

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL_${CHAIN_ID} not found in .env"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not found in .env"
    exit 1
fi

echo "🚀 Deploying to Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo ""

# Deploy contracts

export PRIVATE_KEY
export FOUNDRY_PROFILE=default

TEMP_OUTPUT=$(mktemp)
forge script script/DeployAll.s.sol \
    --rpc-url "$RPC_URL" \
    --broadcast \
    -vvv 2>&1 | tee "$TEMP_OUTPUT"

# Extract addresses from Deployment Summary section
# Match patterns from actual log output:
#   PolicyRegistry (Proxy): 0x...
#   VolrInvoker           : 0x... (NOT a proxy - direct contract for EIP-7702)
#   ScopedPolicy (Impl)   : 0x...
#   ClientSponsor (Proxy) : 0x...
#   VolrSponsor (Proxy)   : 0x...

POLICY_REGISTRY=$(grep "PolicyRegistry (Proxy):" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
VOLR_INVOKER=$(grep "VolrInvoker           :" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
SCOPED_POLICY_IMPL=$(grep "ScopedPolicy (Impl)" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
CLIENT_SPONSOR=$(grep "ClientSponsor (Proxy)" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
VOLR_SPONSOR=$(grep "VolrSponsor (Proxy)" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)

# Fallback to individual log lines (from === sections)
if [ -z "$POLICY_REGISTRY" ]; then
    POLICY_REGISTRY=$(grep "Registry Proxy:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi
if [ -z "$VOLR_INVOKER" ]; then
    # VolrInvoker is NOT a proxy - direct contract deployment for EIP-7702
    VOLR_INVOKER=$(grep "VolrInvoker:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi
if [ -z "$SCOPED_POLICY_IMPL" ]; then
    SCOPED_POLICY_IMPL=$(grep "ScopedPolicy Impl:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi
if [ -z "$CLIENT_SPONSOR" ]; then
    CLIENT_SPONSOR=$(grep "ClientSponsor Proxy:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi
if [ -z "$VOLR_SPONSOR" ]; then
    VOLR_SPONSOR=$(grep "VolrSponsor Proxy:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi

if [ -z "$POLICY_REGISTRY" ] || [ -z "$VOLR_INVOKER" ] || [ -z "$SCOPED_POLICY_IMPL" ] || [ -z "$CLIENT_SPONSOR" ] || [ -z "$VOLR_SPONSOR" ]; then
    echo ""
    echo "⚠️  Warning: Some addresses could not be extracted."
    echo "   POLICY_REGISTRY: ${POLICY_REGISTRY:-NOT_FOUND}"
    echo "   VOLR_INVOKER: ${VOLR_INVOKER:-NOT_FOUND}"
    echo "   SCOPED_POLICY_IMPL: ${SCOPED_POLICY_IMPL:-NOT_FOUND}"
    echo "   CLIENT_SPONSOR: ${CLIENT_SPONSOR:-NOT_FOUND}"
    echo "   VOLR_SPONSOR: ${VOLR_SPONSOR:-NOT_FOUND}"
    rm "$TEMP_OUTPUT"
    exit 1
fi

# Create deployment directory in backend if it doesn't exist
mkdir -p ../volr-backend/prisma/deployment

cat > "../volr-backend/prisma/deployment/deployment-addresses-${CHAIN_ID}.json" <<EOF
{
  "chainId": "${CHAIN_ID}",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "addresses": {
    "policyRegistry": "${POLICY_REGISTRY}",
    "volrInvoker": "${VOLR_INVOKER}",
    "scopedPolicyImpl": "${SCOPED_POLICY_IMPL}",
    "clientSponsor": "${CLIENT_SPONSOR}",
    "volrSponsor": "${VOLR_SPONSOR}"
  }
}
EOF

rm "$TEMP_OUTPUT"

echo ""
echo "✅ Deployment completed!"
echo "   PolicyRegistry   : ${POLICY_REGISTRY}"
echo "   VolrInvoker      : ${VOLR_INVOKER}"
echo "   ScopedPolicy Impl: ${SCOPED_POLICY_IMPL}"
echo "   ClientSponsor   : ${CLIENT_SPONSOR}"
echo "   VolrSponsor     : ${VOLR_SPONSOR}"

cd ..

echo ""
echo "📝 Next steps:"
echo "   1. Upsert chain in backend DB:"
echo "      cd volr-backend && yarn upsert-chain dev ${CHAIN_ID}"
echo "      (or: yarn upsert-chain local ${CHAIN_ID} / yarn upsert-chain prod ${CHAIN_ID})"
echo "   2. Restart backend server"

