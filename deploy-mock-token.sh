#!/bin/bash
# Deploy MockERC20Permit contract only
# Usage: ./deploy-mock-token.sh <CHAIN_ID> [--prod]
# Example: ./deploy-mock-token.sh 5115        # Uses .env (development/testnet)
# Example: ./deploy-mock-token.sh 5115 --prod # Uses .env.prod (production/mainnet)
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
#   - TOKEN_NAME: Token name (defaults to "Mock USDC")
#   - TOKEN_SYMBOL: Token symbol (defaults to "MUSDC")

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

echo "🚀 Deploying MockERC20Permit to Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo ""

# Set environment variables
export PRIVATE_KEY
export FOUNDRY_PROFILE=default

# Export optional variables if set
if [ -n "$TOKEN_NAME" ]; then
    export TOKEN_NAME
fi
if [ -n "$TOKEN_SYMBOL" ]; then
    export TOKEN_SYMBOL
fi

TEMP_OUTPUT=$(mktemp)
forge script script/DeployMockERC20Permit.s.sol \
    --rpc-url "$RPC_URL" \
    --broadcast \
    --slow \
    -vvv 2>&1 | tee "$TEMP_OUTPUT"

# Extract token address from output
TOKEN_ADDRESS=$(grep "Token Address :" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)

# Fallback to other patterns
if [ -z "$TOKEN_ADDRESS" ]; then
    TOKEN_ADDRESS=$(grep "MockERC20Permit:" "$TEMP_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi

if [ -z "$TOKEN_ADDRESS" ]; then
    echo ""
    echo "⚠️  Warning: Token address could not be extracted."
    rm "$TEMP_OUTPUT"
    exit 1
fi

rm "$TEMP_OUTPUT"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ MockERC20Permit deployment completed! (Chain ID: ${CHAIN_ID})"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Contract Address:"
echo "  MockERC20Permit: ${TOKEN_ADDRESS}"
echo ""
echo "Token Details:"
echo "  Decimals: 6 (USDC-like)"
echo "  Mint Amount: 100 tokens (per mintTo call)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📝 Usage:"
echo "   Call token.mintTo(address) to mint 100 tokens to any address"
echo "   Example: cast send ${TOKEN_ADDRESS} \"mintTo(address)\" 0xYourAddress --rpc-url $RPC_URL --private-key \$PRIVATE_KEY"
echo "═══════════════════════════════════════════════════════════════"

