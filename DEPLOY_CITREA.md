# Citrea Testnet 배포 가이드

## 사전 준비

### 1. 환경 변수 설정

`.env` 파일을 생성하고 다음을 설정하세요:

```bash
PRIVATE_KEY=your_deployer_private_key_without_0x_prefix
CITREA_EXPLORER_API_KEY=your_explorer_api_key_if_needed
```

### 2. Citrea Testnet 정보

- **Chain ID**: 5115
- **RPC URL**: `https://rpc.testnet.citrea.xyz`
- **Explorer**: `https://explorer.testnet.citrea.xyz`
- **Currency**: BTC (Bitcoin)

### 3. 테스트넷 BTC 받기

Citrea testnet faucet에서 테스트 BTC를 받아야 합니다:
- Faucet URL: (Citrea 공식 문서 확인 필요)

## 배포 방법

### 1. 빌드

```bash
cd volr-contracts
forge build
```

### 2. 배포 실행

```bash
forge script script/DeployCitrea.s.sol:DeployVolrContracts \
  --rpc-url citrea_testnet \
  --broadcast \
  --verify \
  -vvvv
```

또는 간단하게:

```bash
forge script script/DeployCitrea.s.sol:DeployVolrContracts \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --broadcast \
  -vvvv
```

### 3. 배포 후 설정

배포가 완료되면 콘솔에 출력된 주소들을 사용하여 설정하세요:

#### Backend 설정 (.env)

```bash
INVOKER_ADDRESS_MAP={"5115":"0x..."}
```

#### Frontend 설정

```typescript
import { VolrProvider } from '@volr/react';

<VolrProvider
  config={{
    apiBaseUrl: 'https://api.volr.io',
    defaultChainId: 5115,
    projectApiKey: 'your-api-key',
    invokerAddressMap: {
      5115: '0x...', // 배포된 Invoker 주소
    },
    rpcOverrides: {
      '5115': 'https://rpc.testnet.citrea.xyz',
    },
  }}
>
  {/* ... */}
</VolrProvider>
```

## 배포되는 컨트랙트

1. **PolicyRegistry Implementation** - 정책 레지스트리 구현체
2. **PolicyRegistry Proxy** - UUPS 업그레이드 가능 프록시
3. **ScopedPolicy** - 범위 기반 정책 구현체
4. **VolrInvoker** - 메인 실행 엔진 (가장 중요!)

## 배포 순서

1. PolicyRegistry Implementation 배포
2. PolicyRegistry Proxy 배포 및 초기화
3. ScopedPolicy 배포
4. 기본 정책 등록 (policyId = 0x00...)
5. **정책 설정** (배포 후 필수!)
6. VolrInvoker 배포 (PolicyRegistry 주소 전달)

## 배포 후 정책 설정 (필수!)

ScopedPolicy는 기본적으로 모든 호출을 거부합니다. 배포 후 반드시 정책을 설정해야 합니다:

```bash
# cast를 사용하여 정책 설정
cast send <SCOPED_POLICY_ADDRESS> \
  "setPolicy(bytes32,(uint256,address[],bytes4[],uint256,uint64))" \
  "0x0000000000000000000000000000000000000000000000000000000000000000" \
  "$(cast abi-encode "f(uint256,address[],bytes4[],uint256,uint64)" \
    5115 \
    "[0xYourContractAddress1,0xYourContractAddress2]" \
    "[0xa9059cbb,0x23b872dd]" \
    1000000000000000000 \
    86400)" \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --private-key $PRIVATE_KEY
```

또는 Foundry script로:

```solidity
// script/ConfigurePolicy.s.sol
ScopedPolicy scopedPolicy = ScopedPolicy(0x...); // 배포된 주소
bytes32 policyId = bytes32(0);
address[] memory allowedContracts = new address[](1);
allowedContracts[0] = 0xYourContractAddress;
bytes4[] memory allowedSelectors = new bytes4[](1);
allowedSelectors[0] = 0xa9059cbb; // transfer selector

ScopedPolicy.PolicyConfig memory config = ScopedPolicy.PolicyConfig({
    chainId: 5115,
    allowedContracts: allowedContracts,
    allowedSelectors: allowedSelectors,
    maxValue: type(uint256).max,
    maxExpiry: 86400
});

scopedPolicy.setPolicy(policyId, config);
```

## 검증

배포 후 다음을 확인하세요:

```bash
# Invoker 주소 확인
cast call <INVOKER_ADDRESS> "registry()(address)" --rpc-url https://rpc.testnet.citrea.xyz

# PolicyRegistry에서 기본 정책 확인
cast call <REGISTRY_ADDRESS> "get(bytes32)(address)" 0x0000...0000 --rpc-url https://rpc.testnet.citrea.xyz
```

## 트러블슈팅

### 가스 부족

Citrea testnet faucet에서 더 많은 BTC를 받으세요.

### 배포 실패

1. RPC 연결 확인: `cast block-number --rpc-url https://rpc.testnet.citrea.xyz`
2. Private key 확인: `.env` 파일의 `PRIVATE_KEY`가 올바른지 확인
3. 잔액 확인: `cast balance <DEPLOYER_ADDRESS> --rpc-url https://rpc.testnet.citrea.xyz`

### 검증 실패

검증이 필요 없다면 `--verify` 플래그를 제거하세요:

```bash
forge script script/DeployCitrea.s.sol:DeployVolrContracts \
  --rpc-url citrea_testnet \
  --broadcast \
  -vvvv
```

