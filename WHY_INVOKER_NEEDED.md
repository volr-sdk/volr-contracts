# Invoker가 필요한 이유

## Invoker란?

**Invoker**는 Volr 시스템의 핵심 스마트 컨트랙트로, **ERC-7702 호환 실행 엔진**입니다. 사용자의 세션 서명을 검증하고 트랜잭션을 실행하는 역할을 합니다.

## 왜 Invoker가 필요한가?

### 1. **ERC-7702 세션 키 위임**

Invoker는 ERC-7702 표준을 사용하여 사용자의 세션 키를 위임받아 트랜잭션을 실행합니다:

```typescript
// useRelay.ts에서 확인 가능
const invokerAddress = config.invokerAddressMap?.[input.chainId];
if (!invokerAddress) {
  throw new Error(`Invoker address not configured for chainId ${input.chainId}`);
}

// ERC-7702 authorization tuple 생성
const authorizationTuple = await signAuthorization({
  signer: opts.signer,
  chainId: input.chainId,
  address: invokerAddress, // ← Invoker 주소 필요!
  nonce: authNonce,
});
```

**Invoker 없이는 ERC-7702 위임이 불가능**하므로 트랜잭션을 실행할 수 없습니다.

### 2. **정책 기반 검증**

Invoker는 PolicyRegistry를 통해 정책을 조회하고 검증합니다:

```solidity
// VolrInvoker.sol
address policyAddr = registry.get(auth.policyId);
IPolicy policy = IPolicy(policyAddr);
(bool policyOk, uint256 policyCode) = policy.validate(auth, calls);
if (!policyOk) {
    revert PolicyViolation(policyCode);
}
```

- 화이트리스트 검증
- 가스 한도 검증
- 만료 시간 검증
- 금액 한도 검증

### 3. **배치 트랜잭션 실행**

여러 트랜잭션을 원자적으로 실행합니다:

```solidity
function executeBatch(
    Types.Call[] calldata calls,
    Types.SessionAuth calldata auth,
    bytes calldata sig
) external payable nonReentrant
```

- 모든 호출이 성공하거나 모두 실패 (원자성 보장)
- 가스 비용 절감 (여러 트랜잭션을 하나로 묶음)

### 4. **Replay 공격 방지**

각 사용자별 `opNonce`를 관리하여 재사용 공격을 방지합니다:

```solidity
require(auth.opNonce > opNonces[signer], "Invalid nonce");
opNonces[signer] = auth.opNonce;
```

### 5. **Gas Sponsorship 지원**

Client와 Volr이 가스를 대납할 수 있는 구조를 제공합니다:

```solidity
function sponsoredExecute(
    Types.Call[] calldata calls,
    Types.SessionAuth calldata auth,
    bytes calldata sig,
    address sponsor
) external nonReentrant
```

## Invoker 없이는 불가능한 것들

1. ❌ **트랜잭션 실행 불가**: `useVolrWallet().evm(chainId).sendTransaction()` 호출 시 에러 발생
2. ❌ **ERC-7702 위임 불가**: Authorization tuple 생성 시 Invoker 주소 필요
3. ❌ **정책 검증 불가**: PolicyRegistry와 연동하여 보안 정책 적용 불가
4. ❌ **배치 실행 불가**: 여러 트랜잭션을 원자적으로 실행 불가

## 결론

**Invoker는 반드시 필요합니다!** 

- 각 체인마다 Invoker를 배포해야 합니다
- `invokerAddressMap`에 체인별 Invoker 주소를 설정해야 합니다
- Invoker 없이는 Volr의 핵심 기능인 가스리스 트랜잭션 실행이 불가능합니다

