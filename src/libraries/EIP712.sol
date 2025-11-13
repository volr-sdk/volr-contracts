// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Types} from "./Types.sol";

library EIP712 {
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    
    // Legacy (not used in new path)
    bytes32 public constant SESSION_AUTH_TYPEHASH =
        keccak256("SessionAuth(bytes32 callsHash,bool revertOnFail,uint256 chainId,uint256 opNonce,uint64 expiry,bytes32 scopeId,bytes32 policyId,uint256 totalGasCap)");

    // New EIP-712 type hashes aligned with SDK
    bytes32 public constant CALL_TYPEHASH =
        keccak256("Call(address target,bytes data,uint256 value,uint256 gasLimit)");
    bytes32 public constant SESSION_AUTH_V2_TYPEHASH =
        keccak256("SessionAuth(uint256 chainId,address sessionKey,uint64 expiresAt,uint64 nonce,bytes32 policyId,uint256 totalGasCap)");
    bytes32 public constant SIGNED_BATCH_TYPEHASH =
        keccak256(
            "SignedBatch(SessionAuth auth,Call[] calls,bool revertOnFail,bytes32 callsHash)"
            "Call(address target,bytes data,uint256 value,uint256 gasLimit)"
            "SessionAuth(uint256 chainId,address sessionKey,uint64 expiresAt,uint64 nonce,bytes32 policyId,uint256 totalGasCap)"
        );
    
    bytes32 public constant DOMAIN_NAME = keccak256("volr");
    bytes32 public constant DOMAIN_VERSION = keccak256("1");
    
    uint256 private constant SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    
    function domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                DOMAIN_NAME,
                DOMAIN_VERSION,
                block.chainid,
                verifyingContract
            )
        );
    }
    
    function domainSeparatorV2(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                DOMAIN_NAME,
                DOMAIN_VERSION,
                chainId,
                verifyingContract
            )
        );
    }
    
    function hashTypedDataV4(
        address verifyingContract,
        Types.SessionAuth memory auth
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SESSION_AUTH_TYPEHASH,
                auth.callsHash,
                auth.revertOnFail,
                auth.chainId,
                auth.opNonce,
                auth.expiry,
                auth.scopeId,
                auth.policyId,
                auth.totalGasCap
            )
        );
        
        bytes32 domainSeparator_ = domainSeparator(verifyingContract);
        
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator_, structHash));
    }
    
    // New hashing aligned with SDK's SignedBatch typed data
    function hashSignedBatch(
        uint256 chainId,
        address sessionKey,
        uint64 expiresAt,
        uint64 nonce,
        bytes32 policyId,
        uint256 totalGasCap,
        Types.Call[] memory calls,
        bool revertOnFail,
        bytes32 callsHash
    ) internal pure returns (bytes32) {
        // Hash auth struct
        bytes32 authHash = keccak256(
            abi.encode(
                SESSION_AUTH_V2_TYPEHASH,
                chainId,
                sessionKey,
                expiresAt,
                nonce,
                policyId,
                totalGasCap
            )
        );
        
        // Hash calls array
        bytes32[] memory callHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            bytes32 dataHash = keccak256(calls[i].data);
            callHashes[i] = keccak256(
                abi.encode(
                    CALL_TYPEHASH,
                    calls[i].target,
                    dataHash,
                    calls[i].value,
                    calls[i].gasLimit
                )
            );
        }
        // EIP-712 array hashing: keccak256(concat(element struct hashes))
        bytes32 callsArrayHash = keccak256(abi.encodePacked(callHashes));
        
        // SignedBatch struct hash
        bytes32 batchHash = keccak256(
            abi.encode(
                SIGNED_BATCH_TYPEHASH,
                authHash,
                callsArrayHash,
                revertOnFail,
                callsHash
            )
        );
        
        // Domain
        bytes32 domain = domainSeparatorV2(chainId, sessionKey);
        return keccak256(abi.encodePacked("\x19\x01", domain, batchHash));
    }
    
    function validateLowS(bytes32 s) internal pure returns (bool) {
        uint256 sValue = uint256(s);
        uint256 halfOrder = SECP256K1_ORDER / 2;
        return sValue <= halfOrder;
    }
}

