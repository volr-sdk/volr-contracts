# 배포 성공 확인 및 다음 단계

## ✅ 배포 완료!

Citrea Testnet (Chain ID: 5115)에 성공적으로 배포되었습니다.

### 배포된 컨트랙트 주소

| 컨트랙트 | 주소 | 설명 |
|---------|------|------|
| **VolrInvoker** ⭐ | `0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa` | 가장 중요! 트랜잭션 실행 엔진 |
| PolicyRegistry Proxy | `0x58FA10188d87335EC67f7f26698c9fDFaB1b7868` | 정책 레지스트리 (업그레이드 가능) |
| PolicyRegistry Impl | `0xd9129d92C654fd65aC8a54D39D47D9fdCca4e873` | 정책 레지스트리 구현체 |
| WhitelistPolicy | `0x2128e6C678F63519F1e96D4C51BA3a918450fd74` | 화이트리스트 정책 |

### Explorer에서 확인

- VolrInvoker: https://explorer.testnet.citrea.xyz/address/0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa
- PolicyRegistry: https://explorer.testnet.citrea.xyz/address/0x58FA10188d87335EC67f7f26698c9fDFaB1b7868
- WhitelistPolicy: https://explorer.testnet.citrea.xyz/address/0x2128e6C678F63519F1e96D4C51BA3a918450fd74

---

## 다음 단계

### 1. Backend 설정

`volr-backend/.env` 파일에 추가:

```bash
INVOKER_ADDRESS_MAP={"5115":"0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa"}
```

### 2. Frontend 설정

```typescript
import { VolrUIProvider } from '@volr/react-ui';

<VolrUIProvider
  config={{
    apiBaseUrl: 'https://api.volr.io',
    defaultChainId: 5115,
    projectApiKey: 'your-api-key',
    invokerAddressMap: {
      5115: '0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa', // ⭐ 중요!
    },
    rpcOverrides: {
      '5115': 'https://rpc.testnet.citrea.xyz',
    },
  }}
  keyStorageType="passkey"
>
  {/* ... */}
</VolrUIProvider>
```

### 3. WhitelistPolicy 설정 (필수!)

WhitelistPolicy는 기본적으로 모든 호출을 거부합니다. 사용할 컨트랙트 주소를 화이트리스트에 추가해야 합니다:

```bash
# cast를 사용하여 타겟 추가
cast send 0x2128e6C678F63519F1e96D4C51BA3a918450fd74 \
  "addTarget(address)" \
  0xYourContractAddress \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --private-key $PRIVATE_KEY
```

또는 `script/ConfigureWhitelist.s.sol` 스크립트를 수정해서 실행:

```bash
WHITELIST_POLICY_ADDRESS=0x2128e6C678F63519F1e96D4C51BA3a918450fd74 \
forge script script/ConfigureWhitelist.s.sol:ConfigureWhitelist \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --broadcast \
  -vvvv
```

---

## 배포 검증

배포가 제대로 되었는지 확인:

```bash
# Invoker의 registry 주소 확인
cast call 0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa \
  "registry()(address)" \
  --rpc-url https://rpc.testnet.citrea.xyz

# PolicyRegistry에서 기본 정책 확인
cast call 0x58FA10188d87335EC67f7f26698c9fDFaB1b7868 \
  "get(bytes32)(address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url https://rpc.testnet.citrea.xyz
```

---

## 중요 사항

1. **Invoker 주소**: `0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa` - 이 주소를 Backend와 Frontend에 설정해야 합니다.
2. **WhitelistPolicy 설정**: 트랜잭션을 전송하기 전에 반드시 화이트리스트에 컨트랙트 주소를 추가해야 합니다.
3. **RPC URL**: `https://rpc.testnet.citrea.xyz`
4. **Chain ID**: `5115`

---

## 트러블슈팅

### 트랜잭션이 거부되는 경우

WhitelistPolicy에 컨트랙트 주소가 추가되었는지 확인:

```bash
cast call 0x2128e6C678F63519F1e96D4C51BA3a918450fd74 \
  "whitelisted(address)(bool)" \
  0xYourContractAddress \
  --rpc-url https://rpc.testnet.citrea.xyz
```

### Backend에서 Invoker를 찾지 못하는 경우

`.env` 파일의 `INVOKER_ADDRESS_MAP` 형식이 올바른지 확인:

```bash
# 올바른 형식
INVOKER_ADDRESS_MAP={"5115":"0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa"}

# 잘못된 형식 (작은따옴표 사용 X)
INVOKER_ADDRESS_MAP={'5115':'0x5eae9f6E0f77Aa0f6086552ebe7cD0cd5A4bBefa'}
```

