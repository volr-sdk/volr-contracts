#!/bin/bash
# Estimate gas cost for deploying all Volr contracts
# Usage: ./estimate.sh <CHAIN_ID> [--prod]
# Example: ./estimate.sh 5115
# Example: ./estimate.sh 8453 --prod

set -e

CHAIN_ID=$1
ENV_FLAG=$2

if [ -z "$CHAIN_ID" ]; then
    echo "Usage: $0 <CHAIN_ID> [--prod]"
    echo "Example: $0 5115        # Uses .env"
    echo "Example: $0 8453 --prod # Uses .env.prod"
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

# Derive address from private key
DEPLOYER=$(cast wallet address "$PRIVATE_KEY")

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "⛽ Gas Estimation for Volr Contracts Deployment"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Chain ID     : $CHAIN_ID"
echo "RPC URL      : $RPC_URL"
echo "Deployer     : $DEPLOYER"
echo ""

# Get current gas price
echo "📊 Fetching current gas prices..."
GAS_PRICE_WEI=$(cast gas-price --rpc-url "$RPC_URL")
GAS_PRICE_GWEI=$(cast from-wei "$GAS_PRICE_WEI" gwei)
echo "Current Gas Price: $GAS_PRICE_GWEI Gwei"
echo ""

# Get deployer balance
BALANCE_WEI=$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")
BALANCE_ETH=$(cast from-wei "$BALANCE_WEI")
echo "Deployer Balance: $BALANCE_ETH"
echo ""

# Run simulation (dry-run)
echo "🔄 Running deployment simulation..."
echo ""

export PRIVATE_KEY
export FOUNDRY_PROFILE=default

TEMP_OUTPUT=$(mktemp)

# Use --dry-run to simulate without broadcasting
forge script script/DeployAll.s.sol \
    --rpc-url "$RPC_URL" \
    -vvv 2>&1 | tee "$TEMP_OUTPUT"

# Extract gas information from output
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "⛽ Gas Estimation Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Parse gas used from forge output
# Look for "Gas used:" in the output
TOTAL_GAS=$(grep -i "gas used" "$TEMP_OUTPUT" | grep -oE '[0-9]+' | tail -1)

if [ -n "$TOTAL_GAS" ]; then
    # Calculate estimated cost
    COST_WEI=$(echo "$TOTAL_GAS * $GAS_PRICE_WEI" | bc)
    COST_ETH=$(cast from-wei "$COST_WEI" 2>/dev/null || echo "N/A")
    
    echo "Estimated Total Gas : $TOTAL_GAS"
    echo "Current Gas Price   : $GAS_PRICE_GWEI Gwei"
    echo "Estimated Cost      : $COST_ETH"
    echo ""
    
    # Check if balance is sufficient
    if [ "$BALANCE_WEI" -ge "$COST_WEI" ] 2>/dev/null; then
        REMAINING=$(echo "$BALANCE_WEI - $COST_WEI" | bc)
        REMAINING_ETH=$(cast from-wei "$REMAINING" 2>/dev/null || echo "N/A")
        echo "✅ Sufficient balance!"
        echo "   Remaining after deploy: $REMAINING_ETH"
    else
        NEEDED=$(echo "$COST_WEI - $BALANCE_WEI" | bc)
        NEEDED_ETH=$(cast from-wei "$NEEDED" 2>/dev/null || echo "N/A")
        echo "❌ Insufficient balance!"
        echo "   Need additional: $NEEDED_ETH"
    fi
else
    echo "⚠️  Could not extract gas estimate from simulation."
    echo "   Check the output above for details."
    echo ""
    echo "Typical deployment costs approximately:"
    echo "   - ~5,000,000 gas units"
    echo "   - At $GAS_PRICE_GWEI Gwei, that's roughly:"
    ROUGH_COST=$(echo "5000000 * $GAS_PRICE_WEI" | bc)
    ROUGH_COST_ETH=$(cast from-wei "$ROUGH_COST" 2>/dev/null || echo "N/A")
    echo "   - $ROUGH_COST_ETH (rough estimate)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"

rm "$TEMP_OUTPUT"











