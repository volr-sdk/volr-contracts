#!/bin/bash
# Deploy all Volr contracts
# Usage: ./deploy.sh <CHAIN_ID> [--prod]
# Example: ./deploy.sh 5115
# Example: ./deploy.sh 5115 --prod

set -e

CHAIN_ID=$1
ENV_FLAG=$2

if [ -z "$CHAIN_ID" ]; then
    echo "Usage: $0 <CHAIN_ID> [--prod]"
    echo "Example: $0 5115        # Uses .env"
    echo "Example: $0 5115 --prod # Uses .env.prod"
    exit 1
fi

# Determine which env file to use
if [ "$ENV_FLAG" = "--prod" ]; then
    ENV_FILE=".env.prod"
    echo "🔴 PRODUCTION MODE"
else
    ENV_FILE=".env"
    echo "🟢 Development mode"
fi

# Load env file
if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '^#' | xargs)
    echo "📁 Loaded: $ENV_FILE"
else
    echo "Error: $ENV_FILE not found"
    exit 1
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

rm "$TEMP_OUTPUT"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Deployment completed! (Chain ID: ${CHAIN_ID})"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Contract Addresses:"
echo "  Invoker Address          : ${VOLR_INVOKER}"
echo "  Policy Registry Address  : ${POLICY_REGISTRY}"
echo "  Client Sponsor Address   : ${CLIENT_SPONSOR}"
echo "  Volr Sponsor Address     : ${VOLR_SPONSOR}"
echo "  Scoped Policy Impl       : ${SCOPED_POLICY_IMPL}"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📝 Next step: Register this network in Volr Dashboard"
echo "   Admin > Manage Networks > Add Network"
echo "═══════════════════════════════════════════════════════════════"
