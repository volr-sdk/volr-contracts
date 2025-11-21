// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Types} from "./Types.sol";

library EIP712 {
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // New EIP-712 type hashes aligned with SDK (single spec, version "1")
    bytes32 public constant CALL_TYPEHASH =
        keccak256("Call(address target,bytes data,uint256 value,uint256 gasLimit)");
    bytes32 public constant SESSION_AUTH_TYPEHASH =
        keccak256(
            "SessionAuth(uint256 chainId,address sessionKey,uint64 sessionId,uint64 nonce,uint64 expiresAt,bytes32 policyId,bytes32 policySnapshotHash,uint256 gasLimitMax,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,uint256 totalGasCap)"
        );
    bytes32 public constant SIGNED_BATCH_TYPEHASH =
        keccak256(
            "SignedBatch(SessionAuth auth,Call[] calls,bool revertOnFail,bytes32 callsHash)"
            "Call(address target,bytes data,uint256 value,uint256 gasLimit)"
            "SessionAuth(uint256 chainId,address sessionKey,uint64 sessionId,uint64 nonce,uint64 expiresAt,bytes32 policyId,bytes32 policySnapshotHash,uint256 gasLimitMax,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,uint256 totalGasCap)"
        );
    bytes32 public constant SPONSOR_VOUCHER_TYPEHASH =
        keccak256(
            "SponsorVoucher(address sponsor,bytes32 policyId,bytes32 policySnapshotHash,uint64 sessionId,uint64 nonce,uint64 expiresAt,uint256 gasLimitMax,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,uint256 totalGasCap)"
        );
    
    bytes32 public constant DOMAIN_NAME = keccak256("volr");
    bytes32 public constant DOMAIN_VERSION = keccak256("1");
    
    uint256 private constant SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    
    function domainSeparator(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
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
    
    // Hashing aligned with SDK's SignedBatch typed data (single spec)
    function hashSignedBatch(
        uint256 chainId,
        address verifyingContract,
        address sessionKey,
        uint64 sessionId,
        uint64 nonce,
        uint64 expiresAt,
        bytes32 policyId,
        bytes32 policySnapshotHash,
        uint256 gasLimitMax,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint256 totalGasCap,
        Types.Call[] memory calls,
        bool revertOnFail,
        bytes32 callsHash
    ) internal pure returns (bytes32) {
        bytes32 authHash = keccak256(
            abi.encode(
                SESSION_AUTH_TYPEHASH,
                chainId,
                sessionKey,
                sessionId,
                nonce,
                expiresAt,
                policyId,
                policySnapshotHash,
                gasLimitMax,
                maxFeePerGas,
                maxPriorityFeePerGas,
                totalGasCap
            )
        );
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
        bytes32 callsArrayHash = keccak256(abi.encodePacked(callHashes));
        bytes32 batchHash = keccak256(
            abi.encode(
                SIGNED_BATCH_TYPEHASH,
                authHash,
                callsArrayHash,
                revertOnFail,
                callsHash
            )
        );
        bytes32 domain = domainSeparator(chainId, verifyingContract);
        return keccak256(abi.encodePacked("\x19\x01", domain, batchHash));
    }

    function hashSponsorVoucher(
        address sponsor,
        bytes32 policyId,
        bytes32 policySnapshotHash,
        uint64 sessionId,
        uint64 nonce,
        uint64 expiresAt,
        uint256 gasLimitMax,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint256 totalGasCap
    ) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SPONSOR_VOUCHER_TYPEHASH,
                sponsor,
                policyId,
                policySnapshotHash,
                sessionId,
                nonce,
                expiresAt,
                gasLimitMax,
                maxFeePerGas,
                maxPriorityFeePerGas,
                totalGasCap
            )
        );
        // Sponsor voucher is domain-less to allow off-chain signing tied to voucher semantics only
        // If you want domain separation, pass chainId+verifyingContract here instead.
        return keccak256(abi.encodePacked("\x19\x01", bytes32(0), structHash));
    }
    
    function validateLowS(bytes32 s) internal pure returns (bool) {
        uint256 sValue = uint256(s);
        uint256 halfOrder = SECP256K1_ORDER / 2;
        return sValue <= halfOrder;
    }
}

