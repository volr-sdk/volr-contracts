#!/bin/bash
# Upgrade ClientSponsor contract
# Usage: ./upgrade.sh <CHAIN_ID> [--prod]
# Example: ./upgrade.sh 5115
# Example: ./upgrade.sh 5115 --prod

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

