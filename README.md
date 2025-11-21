# volr-contracts

Smart contracts for Volr's passkey-based, ERC-7702-powered gas sponsorship platform.

## Overview

**volr-contracts** enables users to pay on-chain **without gas or wallets**.

Users sign in with a **passkey**, while:
- The **Client (merchant)** sponsors the gas,
- **Volr** can cover part of that cost for promotions or events.

All transactions run through an **ERC-7702 "Invoker"** — enabling multiple blockchain actions in one secure, atomic batch.

## Core Components

### 1. **VolrInvoker** (Immutable)
- Validates user session keys (EIP-712 Authorization)
- Executes multiple calls (`Call[]`) atomically (`executeBatch`)
- Calls **ClientSponsor** and **VolrSponsor** hooks before/after execution
- References **Policy** to validate chain/token/limits/TTL

### 2. **ScopedPolicy** (Implementation)
- Manages chain ID, allowed contracts, function selectors, value limits, session TTL
- `validate()` approves/rejects Invoker execution
- All sessions use **nonce-based** replay protection

### 3. **ClientSponsor** (Proxy, Upgradeable)
- First-tier sponsor: pays gas for client's users
- Manages per-client budgets, policies, daily/per-transaction limits
- Calculates `gasUsed` and emits `SponsorshipUsed` events

### 4. **VolrSponsor** (Proxy, Upgradeable)
- Second-tier sponsor: Volr can subsidize client gas costs
- Policy-based rate calculation (20%, 50%, 100%, etc.)
- On-chain reimbursement or off-chain settlement events

### 5. **PolicyRegistry** (Proxy, Upgradeable)
- Maps `policyId` → Policy implementation address
- Enables policy upgrades without breaking existing sessions

## Deployment

### Prerequisites

**`volr-contracts/.env`**:
```bash
PRIVATE_KEY="0x..."
RPC_URL_5115="https://rpc.testnet.citrea.xyz"  # Chain-specific RPC
```

### Steps

1. **Deploy contracts**:
   ```bash
   ./deploy.sh <CHAIN_ID>
   # Example: ./deploy.sh 5115
   ```

2. **Register chain in backend DB**:
   ```bash
   cd ../volr-backend
   yarn register-chain dev <CHAIN_ID>
   # or: yarn register-chain local <CHAIN_ID>
   # or: yarn register-chain prod <CHAIN_ID>
   ```

3. **Reset database (optional, for clean start)**:
   ```bash
   cd volr-backend
   npx prisma migrate reset --force
   ```

### Deployed Contracts

- `PolicyRegistry` (Proxy): Policy ID → Implementation mapping
- `VolrInvoker` (Immutable): Core execution engine
- `ScopedPolicy` (Implementation): Policy validation logic
- `ClientSponsor` (Proxy): Client gas sponsorship
- `VolrSponsor` (Proxy): Volr subsidy management

## Development

```bash
forge build
forge test -vvv
forge snapshot
```

**foundry.toml**

```toml
[profile.default]
solc_version = "0.8.24"
optimizer = true
optimizer_runs = 200
via_ir = true
src = "src"
test = "test"
libs = ["lib"]
bytecode_hash = "none"
cbor_metadata = false
```

## Directory Structure

```
src/
 ├─ invoker/         # VolrInvoker + interfaces
 ├─ policy/          # ScopedPolicy
 ├─ sponsor/         # ClientSponsor, VolrSponsor
 ├─ registry/        # PolicyRegistry
 ├─ libraries/       # EIP712, Types
 └─ interfaces/      # IPolicy, etc.
```

## Security

- **Least privilege**: Session keys restricted by TTL, limits, and whitelists
- **Reentrancy protection**: Single execution flow in Invoker
- **Chain-bound domain**: `chainId` included to prevent replay attacks
- **Gas griefing prevention**: Gas caps and limits in ClientSponsor
- **Event auditing**: All sponsor/policy applications logged as events
- **Upgradeable policies**: Policy contracts can be replaced independently
