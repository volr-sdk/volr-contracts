// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library Types {
    struct Call {
        address target;
        uint256 value;
        bytes data;
        uint256 gasLimit;  // 0이면 제한 없음
    }
    
    struct SessionAuth {
        bytes32 callsHash;
        bool revertOnFail;
        uint256 chainId;
        uint256 opNonce;
        uint64 expiry;
        bytes32 scopeId;
        bytes32 policyId;  // PolicyRegistry에서 조회할 정책 ID
        uint256 totalGasCap;  // 0이면 제한 없음
    }
}

