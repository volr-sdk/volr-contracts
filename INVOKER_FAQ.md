# Invoker와 ERC-7702에 대한 질문과 답변

## 0. Authorization Tuple이 뭐야?

**Authorization Tuple**은 ERC-7702 표준의 핵심 개념으로, EOA(Externally Owned Account)가 특정 스마트 컨트랙트(Invoker)에 권한을 위임하는 서명입니다.

### Authorization Tuple 구조

```typescript
type AuthorizationTuple = {
  chainId: number;        // 체인 ID (예: 8453 for Base)
  address: `0x${string}`; // Invoker 컨트랙트 주소
  nonce: bigint;          // EOA의 트랜잭션 nonce
  yParity: 0 | 1;         // 서명의 y-parity (v 대신 사용)
  r: `0x${string}`;       // 서명의 r 값 (32 bytes)
  s: `0x${string}`;       // 서명의 s 값 (32 bytes, low-S 필수)
};
```

### Authorization Tuple의 역할

1. **권한 위임**: EOA가 Invoker 컨트랙트에 "이 트랜잭션을 내 대신 실행해도 돼"라고 서명하는 것
2. **서명 메시지**: `keccak256(chainId || address || nonce)`를 서명
3. **체인 레벨 처리**: 트랜잭션의 `authorizationList` 필드에 포함되어 EVM이 처리

### 배치 트랜잭션과의 관계

**Authorization Tuple과 배치 트랜잭션은 밀접하게 연관되어 있습니다:**

```
1. Authorization Tuple 생성
   ↓
   "EOA가 Invoker에 권한 위임"
   ↓
2. Session Signature 생성 (EIP-712)
   ↓
   "어떤 호출들을 실행할지 서명"
   ↓
3. 배치 트랜잭션 실행
   ↓
   "Invoker가 위임받은 권한으로 여러 호출 실행"
```

**핵심 포인트:**
- **Authorization Tuple**: Invoker에 권한을 위임 (1번만 필요)
- **Session Signature**: 어떤 호출들을 실행할지 지정 (배치마다 필요)
- **배치 트랜잭션**: 위임받은 권한으로 여러 호출을 원자적으로 실행

### 예시

```typescript
// 1. Authorization Tuple 생성 (Invoker에 권한 위임)
const authorizationTuple = await signAuthorization({
  signer: mySigner,
  chainId: 8453,
  address: invokerAddress, // Invoker 컨트랙트 주소
  nonce: 0n,
});

// 2. Session Signature 생성 (배치 호출 서명)
const sessionSig = await signSession({
  signer: mySigner,
  from: userAddress,
  auth: {
    chainId: 8453,
    sessionKey: userAddress,
    expiresAt: Date.now() + 900,
    nonce: 0n,
    policyId: '0x' + '0'.repeat(64),
  },
  calls: [
    { target: '0x...', data: '0x...', value: 0n, gasLimit: 0n },
    { target: '0x...', data: '0x...', value: 0n, gasLimit: 0n },
  ],
});

// 3. 배치 트랜잭션 실행
// 트랜잭션에 authorizationList와 sessionSig가 포함됨
// Invoker가 위임받은 권한으로 여러 호출을 원자적으로 실행
```

**결론**: Authorization Tuple은 Invoker에 권한을 위임하는 것이고, 배치 트랜잭션은 그 위임받은 권한을 사용하여 여러 호출을 실행하는 것입니다. **배치 트랜잭션을 실행하려면 반드시 Authorization Tuple이 필요합니다.**

## 1. ERC-7702 가스 대납 실행은 중간 컨트랙트 없어도 되나요?

**부분적으로 맞습니다.** 하지만 Volr의 고급 기능을 사용하려면 Invoker가 필요합니다.

### ERC-7702 기본 기능만 사용하는 경우

ERC-7702 표준 자체는 **authorization tuple**을 통해 직접 위임할 수 있습니다:
- 사용자가 서명한 authorization tuple을 트랜잭션에 포함
- Relayer가 가스를 대납하여 트랜잭션 실행
- **중간 컨트랙트 없이도 가능** (단, 단일 트랜잭션만 가능)

하지만 **배치 트랜잭션**을 실행하려면 Invoker 컨트랙트가 필요합니다.

### Volr의 Invoker가 필요한 경우

다음 기능들을 사용하려면 Invoker 컨트랙트가 **필수**입니다:

1. **배치 트랜잭션 (Batch Transactions)**
   - 여러 트랜잭션을 원자적으로 실행
   - 하나라도 실패하면 모두 롤백
   - Invoker의 `executeBatch()` 함수 필요
   - **Authorization Tuple로 권한 위임 후 실행**

2. **정책 기반 검증 (Policy-based Validation)**
   - 화이트리스트 검증
   - 가스 한도 검증
   - 만료 시간 검증
   - 금액 한도 검증
   - PolicyRegistry와 연동 필요

3. **Session Key 관리**
   - opNonce를 통한 replay 공격 방지
   - 세션 만료 시간 관리
   - Invoker가 nonce를 관리

4. **Gas Sponsorship 추적**
   - ClientSponsor와 연동하여 가스 사용량 추적
   - VolrSponsor와 연동하여 보조금 계산
   - 이벤트 기반 정산

**결론**: 단순한 ERC-7702 가스 대납만 필요하다면 Invoker 없이도 가능하지만, **배치 트랜잭션**을 실행하려면 Authorization Tuple로 Invoker에 권한을 위임해야 하므로 **Invoker가 필수**입니다.

## 2. Invoker 배포 후 가스 충전은 Invoker에 하나요?

**아니요.** Invoker는 가스를 받지 않습니다. 가스 관리는 **ClientSponsor**에서 합니다.

### 가스 관리 구조

```
User (서명)
  ↓
Client (Relayer) → ClientSponsor (예산 관리)
  ↓
Invoker (실행만 담당)
```

1. **Invoker**: 
   - 트랜잭션 실행만 담당
   - 가스를 받지 않음
   - 가스 추적만 수행 (`gasUsed` 계산)

2. **ClientSponsor**:
   - Client별 예산(`budget`) 관리
   - 일일 한도(`dailyLimit`) 관리
   - 트랜잭션당 한도(`perTxLimit`) 관리
   - 가스 사용량 차감 및 추적

3. **VolrSponsor**:
   - Client 가스비 일부 보조
   - 정책 기반 보조금 비율 설정

### 가스 충전 방법

```solidity
// ClientSponsor에 예산 설정
clientSponsor.setBudget(clientAddress, amount);
```

**결론**: Invoker는 가스를 받지 않습니다. 가스 충전은 **ClientSponsor** 컨트랙트에 예산을 설정하는 방식으로 이루어집니다.

## 3. 정책 ID (Policy ID)란 무엇이고 어떻게 설정하나요?

**Policy ID**는 PolicyRegistry에 등록된 정책을 식별하는 32바이트(64 hex chars) 식별자입니다.

### Policy ID 구조

```typescript
type PolicyId = `0x${string}`; // 32 bytes = 64 hex chars + 0x prefix
```

### Policy ID 설정 방법

#### 1. 기본 정책 (Default Policy)

가장 간단한 방법은 모두 0으로 설정:

```typescript
const defaultPolicyId = '0x' + '0'.repeat(64) as `0x${string}`;
```

이 정책은 배포 시 PolicyRegistry에 자동으로 등록됩니다.

#### 2. 커스텀 Policy ID 생성

```typescript
import { keccak256, toHex } from 'viem';

// 문자열로부터 Policy ID 생성
const policyId = keccak256(toHex('my-custom-policy')) as `0x${string}`;

// 또는 직접 지정
const policyId = '0x1234...' as `0x${string}`; // 64 hex chars
```

#### 3. PolicyRegistry에 정책 등록

```solidity
// PolicyRegistry에 정책 등록 (timelock 또는 multisig만 가능)
policyRegistry.register(
    policyId,           // bytes32 policyId
    policyAddress,      // address policy implementation
    "Policy metadata"   // string metadata
);
```

#### 4. 정책 설정 (ScopedPolicy 예시)

```solidity
// ScopedPolicy에 정책 설정
scopedPolicy.setPolicy(policyId, PolicyConfig({
    chainId: 8453,
    allowedContracts: [0x...],  // 허용할 컨트랙트 주소들
    allowedSelectors: [0xa9059cbb], // 허용할 함수 셀렉터들
    maxValue: 1000000000000000000,   // 최대 전송 금액
    maxExpiry: 86400                 // 최대 만료 시간 (초)
}));
```

### 사용 예시

```typescript
// 트랜잭션 전송 시 policyId 지정
await evm(8453).sendTransaction(
  {
    to: '0x...',
    data: '0x...',
  },
  {
    policyId: '0x' + '0'.repeat(64), // 기본 정책 사용
  }
);
```

**결론**: Policy ID는 정책을 식별하는 32바이트 식별자입니다. 기본값은 모두 0이며, 커스텀 정책을 사용하려면 PolicyRegistry에 등록하고 정책을 설정해야 합니다.

