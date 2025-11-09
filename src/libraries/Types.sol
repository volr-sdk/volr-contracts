// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library Types {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }
    
    struct SessionAuth {
        bytes32 callsHash;
        bool revertOnFail;
        uint256 chainId;
        uint256 opNonce;
        uint64 expiry;
        bytes32 scopeId;
    }
}

