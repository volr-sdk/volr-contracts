cd /Users/danny/strartups/volr/volr-project/volr-contracts

# 1. .env 파일 생성 및 PRIVATE_KEY 설정
# volr-contracts 폴더에 .env 파일을 만들고 다음 내용을 추가하세요:
#
# PRIVATE_KEY=your_private_key_here_without_0x_prefix
#
# 검증용 (선택사항):
# CITREA_EXPLORER_API_KEY=your_citrea_explorer_api_key
#
# 예시:
# PRIVATE_KEY=1234567890abcdef...
# CITREA_EXPLORER_API_KEY=your_api_key_from_citrea_explorer

# 2. Foundry 설정
export FOUNDRY_DISABLE_NATURAL_ORDERING=1

# 검증을 원한다면 Citrea Explorer API key를 받아서 .env에 추가하세요
# CITREA_EXPLORER_API_KEY=your_api_key_here
# 그리고 foundry.toml에서 etherscan 설정 주석을 해제하세요

unset FOUNDRY_ETHERSCAN_API_KEY  # 현재는 검증하지 않음

# 3. 배포 실행 (.env에서 PRIVATE_KEY 자동 읽기)
forge script script/DeployAll.s.sol --rpc-url https://rpc.testnet.citrea.xyz --broadcast --skip-simulation

# 검증을 원한다면 --verify 플래그 추가:
# forge script script/DeployAll.s.sol --rpc-url https://rpc.testnet.citrea.xyz --broadcast --verify
