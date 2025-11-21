// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library Types {
    struct Call {
        address target;
        uint256 value;
        bytes data;
        uint256 gasLimit;  // 0이면 제한 없음
    }
    
    // 단일 세션 인증 구조체 (EIP-712 v1 도메인, v2 네이밍 제거)
    // Invoker ↔ Policy 간 동일 타입 사용
    struct SessionAuth {
        uint256 chainId;
        address sessionKey;
        uint64  sessionId;
        uint64  nonce;
        uint64  expiresAt;
        bytes32 policyId;             // PolicyRegistry에서 조회할 정책 ID
        bytes32 policySnapshotHash;   // 스냅샷(config+codehash+version) 바인딩
        uint256 gasLimitMax;          // 개별 call gasLimit 상한
        uint256 maxFeePerGas;         // EIP-1559 상한
        uint256 maxPriorityFeePerGas; // EIP-1559 우선 수수료 상한
        uint256 totalGasCap;          // 배치 전체 가스 한도 (0이면 제한 없음)
    }
}

