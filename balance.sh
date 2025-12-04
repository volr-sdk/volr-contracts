#!/bin/bash
# Check native token balance for deployer wallet
# Usage: ./balance.sh <CHAIN_ID> [--prod]
# Example: ./balance.sh 5115
# Example: ./balance.sh 5115 --prod

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

# Derive address from private key
ADDRESS=$(cast wallet address "$PRIVATE_KEY")

echo "Chain ID : $CHAIN_ID"
echo "RPC URL  : $RPC_URL"
echo "Address  : $ADDRESS"
echo ""

# Get balance
BALANCE_WEI=$(cast balance "$ADDRESS" --rpc-url "$RPC_URL")
BALANCE_ETH=$(cast from-wei "$BALANCE_WEI")

echo "Balance  : $BALANCE_ETH"

