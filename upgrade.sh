#!/bin/bash
# Upgrade ClientSponsor contract
# Usage: ./upgrade.sh <CHAIN_ID>
# Example: ./upgrade.sh 5115

set -e

CHAIN_ID=$1

if [ -z "$CHAIN_ID" ]; then
    echo "Usage: $0 <CHAIN_ID>"
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

# Read ClientSponsor proxy address from deployment file
DEPLOYMENT_FILE="../volr-backend/prisma/deployment/deployment-addresses-${CHAIN_ID}.json"

if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "Error: Deployment file not found: $DEPLOYMENT_FILE"
    echo "       Run ./deploy.sh $CHAIN_ID first to deploy contracts"
    exit 1
fi

CLIENT_SPONSOR_PROXY=$(cat "$DEPLOYMENT_FILE" | grep -o '"clientSponsor": "[^"]*"' | cut -d'"' -f4)

if [ -z "$CLIENT_SPONSOR_PROXY" ]; then
    echo "Error: Could not read clientSponsor address from $DEPLOYMENT_FILE"
    exit 1
fi

echo "🔄 Upgrading ClientSponsor on Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo "ClientSponsor Proxy: $CLIENT_SPONSOR_PROXY"
echo ""

export PRIVATE_KEY
export CLIENT_SPONSOR_PROXY
export FOUNDRY_PROFILE=default

# Run upgrade script
forge script script/UpgradeClientSponsor.s.sol \
    --rpc-url "$RPC_URL" \
    --broadcast \
    -vvvv

echo ""
echo "✅ Upgrade completed!"
echo ""
echo "📝 Next steps:"
echo "   1. Verify the new implementation on block explorer"
echo "   2. Test the upgraded contract"

