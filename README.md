# volr-contracts

> Smart contracts for Volr’s passkey-based, ERC-7702-powered payments.
> 
> 
> Enables gas sponsorship, batch transactions, and scoped session keys — with a two-tier sponsor model (Client + Volr).
> 

---

## 🧭 Abstract (TL;DR)

**volr-contracts** lets users pay on-chain **without gas or wallets.**

They sign in with a **passkey**, while:

- The **Client (merchant)** sponsors the gas,
- **Volr** can cover part of that cost for promotions or events.

Everything runs through an **ERC-7702 “Invoker”** —

so multiple blockchain actions happen in one secure, atomic batch.


**Smooth Web2 UX, fully Web3 under the hood.**

(Korean)
**volr-contracts**는 **Passkey 로그인**을 기반으로,

유저가 지갑이나 가스 없이도 **멀티체인 결제**를 할 수 있도록 하는 **스마트 컨트랙트 모듈**입니다.

- **User**: 패스키로 로그인해 트랜잭션을 승인 (가스는 직접 내지 않음)
- **Client**: 자사 유저의 가스비를 스폰서 (1차 Sponsor)
- **Volr**: 이벤트나 프로모션 시, Client의 가스비를 일부 보조 (2차 Sponsor)

모든 실행은 **ERC-7702 위임 기반 Invoker**를 통해 이뤄지며,

한 번의 승인으로 **여러 트랜잭션(batch)**을 안전하게 처리합니다.


### 💡 Example flow

1. User logs in with passkey → gets a session key
2. Client sends a transaction batch (gas paid by client)
3. Invoker contract checks policy and executes
4. Volr optionally reimburses part of the gas fee

결과: 유저는 클릭 한 번, 클라이언트는 안전한 대납, Volr은 이벤트로 지원.

---

## 🧩 System Overview

| 계층 | 역할 | 설명 |
| --- | --- | --- |
| **User** | 최종 사용자 | Passkey로 로그인, 세션 서명 (EIP-712) |
| **Client (사업자)** | 1차 Sponsor | 자사 유저의 트랜잭션을 relayer로 실행, 가스비 선납 |
| **Volr** | 2차 Sponsor | Client 가스비 일부를 후원(이벤트/프로모션) |
| **Network** | 체인 (예: Base, Arbitrum 등) | 실제 가스 소비 및 정산 |

---

## 🏗 Architecture

```
          ┌──────────────────────────────┐
          │        Volr Backend          │
          │ (off-chain policy, events)   │
          └──────────────▲───────────────┘
                         │ (off-chain settlement)
                         │
┌────────────┐       ┌──────────────┐       ┌─────────────────┐
│   User     │──────▶│   Client     │──────▶│  ClientSponsor  │
│ (Passkey)  │ EIP712│  Relayer     │ call  │ (1st sponsor)   │
└────────────┘       └──────────────┘       │ gasUsed calc.   │
                                             │ event emit      │
                                             └─────────▲───────┘
                                                       │
                                                       │ on-chain subsidy
                                             ┌──────────┴─────────┐
                                             │   VolrSponsor      │
                                             │ (2nd sponsor)      │
                                             └──────────┬─────────┘
                                                        │
                                                        ▼
                                                ┌────────────┐
                                                │  Invoker    │
                                                │ (ERC-7702)  │
                                                └────────────┘

```

---

## ⚙️ Core Components

### 1. **Invoker (ERC-7702 compatible)**

- User의 session key(EIP-712 Authorization)를 검증
- 여러 호출(`Call[]`)을 한 번에 실행 (`executeBatch`)
- 실행 전후로 **ClientSponsor**와 **VolrSponsor** 훅 호출
- 정책(`Policy`)을 참조하여 체인/토큰/한도/TTL 등을 검증

```solidity
function executeBatch(
    Call[] calldata calls,
    SessionAuth calldata auth,
    bytes calldata sig
) external payable;

```

---

### 2. **Policy Engine (Scoped Session Keys)**

- 체인ID, 허용 컨트랙트, 함수 셀렉터, 금액 상한, 만료(세션 TTL) 관리
- `validate()` 호출을 통해 Invoker 실행을 승인/거부
- 모든 세션은 **nonce 기반**으로 리플레이 방지

```solidity
function validate(SessionAuth calldata auth, Call[] calldata calls)
  external view returns (bool ok, uint256 code);

```

---

### 3. **ClientSponsor (1차 스폰서)**

- 실제 가스를 선납하는 **relayer 역할**
- 각 client별 **예산(budget)**, **정책(policyId)**, **1일/1회 한도**를 관리
- 실행 후 `gasUsed`를 계산하고, **VolrSponsor**에 보조금 요청 이벤트 발행

```solidity
function handleSponsorship(address user, uint256 gasUsed, bytes32 policyId) external;
event SponsorshipUsed(address indexed client, address indexed user, uint256 gasUsed, bytes32 policyId);

```

---

### 4. **VolrSponsor (2차 스폰서)**

- Volr이 Client 가스비 일부를 보조 (예: 이벤트/프로모션)
- `policyId` 기반으로 비율 계산: 20%, 50%, 100% 등
- 실제 on-chain 보조금 지급 or 오프체인 정산 이벤트 로그 발행

```solidity
function compensateClient(address client, uint256 gasUsed, bytes32 policyId) external;

```

---

## 💸 Gas Sponsorship Flow

### 기본 흐름

1. **User** → 세션 서명 (EIP-712, 만료·한도·policyId 포함)
2. **Client** → `executeBatch()` 호출 (가스 대납)
3. **Invoker**
    - EIP-712 검증
    - Policy 체크 (화이트리스트, TTL, 한도 등)
    - Calls 실행 + gasUsed 계산
4. **ClientSponsor**
    - Client 예산 차감
    - `SponsorshipUsed` 이벤트 발생
    - VolrSponsor에게 보조금 요청
5. **VolrSponsor**
    - 정책에 따라 Client에게 보조금 송금 (on-chain)
    - 또는 Off-chain 정산 로그 남김

---

### 예시 정책 테이블

| 조건 | Client 부담 | Volr 부담 | policyId |
| --- | --- | --- | --- |
| 일반 결제 | 100% | 0% | `BASE_1` |
| 신규 유저 첫 거래 | 80% | 20% | `PROMO_2025A` |
| 프로모션 캠페인 | 0% | 100% | `VOLR_FULL_SPONSOR` |

모든 트랜잭션은 `policyId`가 EIP-712 메시지 및 이벤트에 포함되어

**정산·감사 투명성**을 확보합니다.

---

## 🔐 Security Model

- **권한 최소화:** 세션키는 TTL·한도·화이트리스트로 제한
- **Reentrancy 방지:** Invoker 내 단일 실행 플로우 보장
- **Chain-bound domain:** `chainId` 포함으로 리플레이 방지
- **Gas griefing 방지:** ClientSponsor 정책에 가스 상한·가스가격 캡
- **Event auditing:** 모든 sponsor·policy 적용은 이벤트로 기록
- **Upgradeable Policy:** 정책 컨트랙트는 독립 버전으로 교체 가능

---

## 🧪 Development Setup

```bash
forge install OpenZeppelin/openzeppelin-contracts --no-commit
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

---

## 🧱 Directory Layout

```
src/
 ├─ invoker/         # VolrInvoker + interfaces
 ├─ policy/          # Policy engines (client, volr)
 ├─ sponsor/         # ClientSponsor, VolrSponsor
 ├─ libraries/       # EIP712, validation utils
 └─ test/            # Foundry tests (unit, fuzz, gas)

```

---

## 🧾 Events & Off-chain Settlement

```solidity
event SponsorshipUsed(
    address indexed client,
    address indexed user,
    uint256 gasUsed,
    bytes32 policyId,
    uint256 timestamp
);

```

Volr 백엔드는 이 이벤트를 수집하여

- Client별 월간 가스 사용량,
- Volr 보조금 비율,
- 정산 데이터(USDC 기준)
    
    을 오프체인 회계 시스템으로 기록합니다.
    

---

## 🚀 Roadmap (MVP → Beta)

- [ ]  Minimal `VolrInvoker` + `Policy` + `ClientSponsor`
- [ ]  Off-chain settlement pipeline (event indexer)
- [ ]  On-chain `VolrSponsor` prototype (optional)
- [ ]  Permit2 / CCTP / Token routing guard
- [ ]  Audit prep: property tests, invariant checks

---

## 🧠 FAQ

**Q. Client가 가스비를 다 내야 하나요?**

A. 기본적으로는 예, 하지만 Volr이 정책에 따라 일부를 자동 보조할 수 있습니다.

**Q. Volr이 보조금을 줄 기준은?**

A. 정책(`policyId`) 기반입니다. 프로모션·신규유저·캠페인 등으로 유연하게 확장 가능합니다.

**Q. Sponsor 구조는 ERC-4337 Paymaster와 호환되나요?**

A. 네. 필요 시 EntryPoint 호출로 대체하거나, 7702 기반 relayer 모델과 병행할 수 있습니다.

**Q. Passkey 유저는 키를 직접 관리하나요?**

A. 아니요. Passkey는 seed를 파생하는 게이트일 뿐, 실제 서명은 EVM 개인키로 안전하게 수행됩니다.