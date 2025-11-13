# Citrea Testnet Invoker 배포 체크리스트

## ✅ 단계별 배포 가이드

### 1단계: 환경 변수 설정

`volr-contracts` 디렉토리에 `.env` 파일을 생성하세요:

```bash
cd volr-contracts
cat > .env << EOF
PRIVATE_KEY=your_private_key_without_0x_prefix
EOF
```

**주의**: 
- `0x` 접두사 없이 입력하세요
- 테스트넷용이지만 실제 자금이 있는 키는 사용하지 마세요
- `.env` 파일은 `.gitignore`에 포함되어 있어 Git에 커밋되지 않습니다

### 2단계: 테스트넷 BTC 받기

Citrea testnet faucet에서 테스트 BTC를 받아야 합니다:
- RPC: `https://rpc.testnet.citrea.xyz`
- Chain ID: `5115`
- Explorer: `https://explorer.testnet.citrea.xyz`

Faucet URL은 Citrea 공식 문서를 확인하세요.

### 3단계: 빌드

```bash
cd volr-contracts
forge build
```

### 4단계: 배포 실행

```bash
forge script script/DeployCitrea.s.sol:DeployVolrContracts \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --broadcast \
  -vvvv
```

**배포되는 컨트랙트:**
1. PolicyRegistry Implementation
2. PolicyRegistry Proxy
3. WhitelistPolicy
4. VolrInvoker ⭐ (가장 중요!)

배포가 완료되면 콘솔에 각 컨트랙트 주소가 출력됩니다.

### 5단계: 배포 결과 확인

배포 후 출력된 주소들을 기록하세요:
- `VolrInvoker`: `0x...` ⭐
- `PolicyRegistry Proxy`: `0x...`
- `WhitelistPolicy`: `0x...`

### 6단계: Backend 설정

`volr-backend/.env` 파일에 추가:

```bash
INVOKER_ADDRESS_MAP={"5115":"0x..."}
```

`0x...` 부분을 배포된 VolrInvoker 주소로 교체하세요.

### 7단계: Frontend 설정

`VolrProvider` 또는 `VolrUIProvider` 설정에 추가:

```typescript
<VolrUIProvider
  config={{
    apiBaseUrl: 'https://api.volr.io',
    defaultChainId: 5115,
    projectApiKey: 'your-api-key',
    invokerAddressMap: {
      5115: '0x...', // 배포된 VolrInvoker 주소
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

### 8단계: WhitelistPolicy 설정 (필수!)

WhitelistPolicy는 기본적으로 모든 호출을 거부합니다. 사용할 컨트랙트 주소를 화이트리스트에 추가해야 합니다:

```bash
# cast를 사용하여 타겟 추가
cast send <WHITELIST_POLICY_ADDRESS> \
  "addTarget(address)" \
  0xYourContractAddress \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --private-key $PRIVATE_KEY
```

또는 Foundry script로:

```solidity
// script/ConfigureWhitelist.s.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WhitelistPolicy} from "../src/policy/WhitelistPolicy.sol";

contract ConfigureWhitelist is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address whitelistPolicyAddress = vm.envAddress("WHITELIST_POLICY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        WhitelistPolicy whitelistPolicy = WhitelistPolicy(whitelistPolicyAddress);
        
        // 허용할 컨트랙트 주소들 추가
        whitelistPolicy.addTarget(0xYourContractAddress1);
        whitelistPolicy.addTarget(0xYourContractAddress2);
        // ... 더 추가
        
        console.log("Whitelist configured successfully");
        
        vm.stopBroadcast();
    }
}
```

실행:
```bash
WHITELIST_POLICY_ADDRESS=0x... forge script script/ConfigureWhitelist.s.sol:ConfigureWhitelist \
  --rpc-url https://rpc.testnet.citrea.xyz \
  --broadcast \
  -vvvv
```

### 9단계: 검증

배포가 제대로 되었는지 확인:

```bash
# Invoker의 registry 주소 확인
cast call <INVOKER_ADDRESS> "registry()(address)" \
  --rpc-url https://rpc.testnet.citrea.xyz

# PolicyRegistry에서 기본 정책 확인
cast call <REGISTRY_ADDRESS> "get(bytes32)(address)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url https://rpc.testnet.citrea.xyz
```

## 🚨 트러블슈팅

### RPC 연결 확인
```bash
cast block-number --rpc-url https://rpc.testnet.citrea.xyz
```

### 잔액 확인
```bash
cast balance <DEPLOYER_ADDRESS> --rpc-url https://rpc.testnet.citrea.xyz
```

### 배포 실패 시
1. `.env` 파일의 `PRIVATE_KEY` 확인
2. 테스트넷 BTC 잔액 확인
3. RPC 연결 확인

## 📝 다음 단계

배포가 완료되면:
1. ✅ Backend `.env`에 `INVOKER_ADDRESS_MAP` 설정
2. ✅ Frontend에 `invokerAddressMap` 설정
3. ✅ WhitelistPolicy에 사용할 컨트랙트 주소 추가
4. ✅ 테스트 트랜잭션 전송

## 📚 참고 문서

- [DEPLOY_CITREA.md](./DEPLOY_CITREA.md) - 상세 배포 가이드
- [INVOKER_FAQ.md](./INVOKER_FAQ.md) - Invoker 관련 FAQ
- [WHY_INVOKER_NEEDED.md](./WHY_INVOKER_NEEDED.md) - Invoker 필요성 설명

