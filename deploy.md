# Volr Contracts Deployment

## Prerequisites

1. `.env` 파일 생성 (volr-contracts 폴더)

```bash
# Required
PRIVATE_KEY=your_private_key_here_without_0x_prefix

# RPC URLs (배포할 체인에 맞게 추가)
RPC_URL_5115=https://rpc.testnet.citrea.xyz
RPC_URL_1=https://eth.llamarpc.com
RPC_URL_42161=https://arb1.arbitrum.io/rpc
```

2. Foundry 설치 (https://getfoundry.sh)

## Deploy

```bash
cd volr-contracts
./deploy.sh <CHAIN_ID>

# Examples:
./deploy.sh 5115    # Citrea Testnet
./deploy.sh 42161   # Arbitrum One
```

## After Deployment

배포가 완료되면 콘솔에 Contract 주소들이 출력됩니다.  
**Volr Dashboard > Admin > Manage Networks**에서 해당 네트워크를 등록하세요.
