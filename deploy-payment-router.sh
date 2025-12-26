#!/bin/bash
# Deploy PaymentRouter contract only
# Usage: ./deploy-payment-router.sh <CHAIN_ID> [--prod]
# Example: ./deploy-payment-router.sh 5115        # Uses .env (development/testnet)
# Example: ./deploy-payment-router.sh 5115 --prod # Uses .env.prod (production/mainnet)
#
# Environment files:
#   - .env: Development/testnet deployment (default)
#   - .env.prod: Production/mainnet deployment
#
# Required env variables:
#   - PRIVATE_KEY: Deployer's private key (without 0x prefix)
#   - RPC_URL_<CHAIN_ID>: RPC URL for the target chain
#
# Optional env variables:
#   - PAYMENT_ROUTER_FEE_RECIPIENT: Address to receive fees (defaults to deployer)
#   - PAYMENT_ROUTER_OWNER: Contract owner address (defaults to deployer)

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
    echo "Error: RPC_URL_${CHAIN_ID} not found in $ENV_FILE"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not found in $ENV_FILE"
    exit 1
fi

echo "🚀 Deploying PaymentRouter to Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo ""

# Set environment variables for PaymentRouter
export PRIVATE_KEY
export FOUNDRY_PROFILE=default

# Export optional variables if set
if [ -n "$PAYMENT_ROUTER_FEE_RECIPIENT" ]; then
    export PAYMENT_ROUTER_FEE_RECIPIENT
fi
if [ -n "$PAYMENT_ROUTER_OWNER" ]; then
    export PAYMENT_ROUTER_OWNER
fi

TEMP_OUTPUT=$(mktemp)
forge script script/DeployPaymentRouter.s.sol \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --slow \
    -vvv 2>&1 | tee "$TEMP_OUTPUT"

# Extract PaymentRouter address from output
PAYMENT_ROUTER=$(grep "PaymentRouter :" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)

# Fallback to other patterns
if [ -z "$PAYMENT_ROUTER" ]; then
    PAYMENT_ROUTER=$(grep "PaymentRouter:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi

if [ -z "$PAYMENT_ROUTER" ]; then
    echo ""
    echo "⚠️  Warning: PaymentRouter address could not be extracted."
    rm "$TEMP_OUTPUT"
    exit 1
fi

rm "$TEMP_OUTPUT"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ PaymentRouter deployment completed! (Chain ID: ${CHAIN_ID})"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Contract Address:"
echo "  PaymentRouter Address: ${PAYMENT_ROUTER}"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📝 Next step: Update network configuration in Volr Dashboard"
echo "   Admin > Manage Networks > Edit Network > Payment Router Address"
echo "   Or update backend DB:"
echo "   UPDATE network SET payment_router_address = '${PAYMENT_ROUTER}' WHERE chain_id = ${CHAIN_ID};"
echo "═══════════════════════════════════════════════════════════════"

