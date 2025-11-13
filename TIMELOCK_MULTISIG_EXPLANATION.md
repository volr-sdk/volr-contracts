# Timelock과 Multisig 설명 (쉬운 말로)

## 요약

**맞습니다!** 지금은 owner 주소만 있고 timelock과 multisig가 없으니까, 배포 스크립트에서 **둘 다 owner 주소로 설정**했습니다.

```solidity
registry.setTimelock(deployer);  // owner를 timelock으로 설정
registry.setMultisig(deployer);  // owner를 multisig로 설정
```

이렇게 하면 owner가 정책을 등록할 수 있게 됩니다.

---

## Timelock이란?

### 쉬운 설명

**Timelock**은 "시간 잠금"이라는 뜻입니다. 즉시 실행되지 않고, **일정 시간이 지난 후에만** 실행되도록 하는 장치입니다.

### 비유로 설명하면

**은행의 예금 인출**을 생각해보세요:
- 일반 계좌: 즉시 인출 가능
- 정기 예금: 만기일이 지나야 인출 가능 (시간 잠금)

**Timelock**도 마찬가지입니다:
- 일반 트랜잭션: 즉시 실행됨
- Timelock 트랜잭션: 설정한 시간이 지나야 실행됨

### 왜 필요한가요?

**보안상의 이유**:
1. **실수 방지**: 급하게 결정한 변경사항을 되돌릴 시간을 줌
2. **공격 방지**: 해커가 권한을 탈취해도 즉시 실행되지 않음
3. **검토 시간**: 변경사항을 커뮤니티가 검토할 시간을 줌

### 예시

```
1. 정책 변경 요청
   ↓
2. Timelock에 등록 (예: 3일 후 실행)
   ↓
3. 3일 동안 커뮤니티가 검토
   ↓
4. 문제가 있으면 취소 가능
   ↓
5. 3일 후 자동 실행
```

### 실제 사용 예시

```solidity
// Timelock을 사용한 정책 등록
timelock.schedule(
    address(registry),
    0,  // value
    abi.encodeWithSelector(
        PolicyRegistry.register.selector,
        policyId,
        policyAddress,
        "New policy"
    ),
    bytes32(0),  // salt
    3 days  // delay (3일 후 실행)
);

// 3일 후에만 실행됨
timelock.execute(...);
```

---

## Multisig란?

### 쉬운 설명

**Multisig**는 "다중 서명"이라는 뜻입니다. **여러 사람의 서명**이 있어야만 실행되는 장치입니다.

### 비유로 설명하면

**은행의 공동 계좌**를 생각해보세요:
- 일반 계좌: 한 사람만 서명하면 인출 가능
- 공동 계좌: 여러 사람이 모두 서명해야 인출 가능 (예: 3명 중 2명 서명 필요)

**Multisig**도 마찬가지입니다:
- 일반 트랜잭션: 한 사람만 서명하면 실행됨
- Multisig 트랜잭션: 여러 사람이 서명해야 실행됨 (예: 5명 중 3명 서명 필요)

### 왜 필요한가요?

**보안상의 이유**:
1. **단일 실패점 제거**: 한 사람이 해킹당해도 즉시 실행되지 않음
2. **의사결정 투명성**: 여러 사람이 검토하고 승인해야 함
3. **권한 분산**: 한 사람에게 모든 권한을 주지 않음

### 예시

```
정책 변경 요청
   ↓
Multisig에 제출
   ↓
5명의 관리자 중 3명이 서명 필요
   ↓
관리자 1: ✅ 서명
관리자 2: ✅ 서명
관리자 3: ✅ 서명
   ↓
3명이 서명했으므로 실행됨!
```

### 실제 사용 예시

```solidity
// Multisig를 사용한 정책 등록
// 5명의 관리자 중 3명이 서명해야 함

multisig.submitTransaction(
    address(registry),
    0,
    abi.encodeWithSelector(
        PolicyRegistry.register.selector,
        policyId,
        policyAddress,
        "New policy"
    )
);

// 관리자들이 하나씩 서명
multisig.confirmTransaction(txId);  // 관리자 1
multisig.confirmTransaction(txId);  // 관리자 2
multisig.confirmTransaction(txId);  // 관리자 3

// 3명이 서명했으므로 실행됨
multisig.executeTransaction(txId);
```

---

## Timelock vs Multisig 비교

| 특징 | Timelock | Multisig |
|------|----------|----------|
| **목적** | 시간 지연 | 다중 승인 |
| **실행 조건** | 시간이 지나면 자동 실행 | 여러 사람이 서명해야 실행 |
| **보안** | 실수/공격 방지 (시간 버퍼) | 단일 실패점 제거 (권한 분산) |
| **사용 시나리오** | 급한 결정 방지 | 중요한 결정에 다수 승인 필요 |

---

## 현재 배포 스크립트에서는?

### 테스트넷 배포

```solidity
// 편의를 위해 owner를 timelock과 multisig로 설정
registry.setTimelock(deployer);  // owner = timelock
registry.setMultisig(deployer);  // owner = multisig
```

**의미**:
- Timelock: owner가 정책을 등록할 수 있음 (시간 지연 없음)
- Multisig: owner가 정책을 등록할 수 있음 (다중 서명 없음)
- **실질적으로는 owner가 바로 실행 가능**

### 프로덕션 배포

```solidity
// 실제 운영에서는 별도의 주소로 설정
registry.setTimelock(timelockContractAddress);  // 별도의 Timelock 컨트랙트
registry.setMultisig(multisigWalletAddress);     // 별도의 Multisig 지갑
```

**의미**:
- Timelock: 정책 변경이 즉시 실행되지 않고, 일정 시간 후에만 실행됨
- Multisig: 여러 관리자가 서명해야만 정책 변경이 실행됨
- **더 안전하지만, 실행이 느림**

---

## 요약

### Timelock
- **뜻**: 시간 잠금
- **역할**: 트랜잭션을 일정 시간 후에만 실행
- **목적**: 실수 방지, 공격 방지, 검토 시간 확보

### Multisig
- **뜻**: 다중 서명
- **역할**: 여러 사람의 서명이 있어야만 실행
- **목적**: 권한 분산, 단일 실패점 제거, 투명한 의사결정

### 현재 상황
- 테스트넷: owner를 timelock과 multisig로 설정 (즉시 실행 가능)
- 프로덕션: 별도의 timelock과 multisig 주소 설정 (더 안전하지만 느림)

