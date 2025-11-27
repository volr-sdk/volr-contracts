// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";

/**
 * @title SignatureHelper
 * @notice Helper library for generating EIP-712 signatures in tests
 */
library SignatureHelper {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    
    /**
     * @notice Sign a session auth for executeBatch
     * @param privateKey Signer's private key
     * @param invoker Invoker contract address (verifyingContract)
     * @param auth Session auth struct
     * @param calls Array of calls
     * @param revertOnFail Whether to revert on failure
     * @param callsHash Hash of calls
     * @return signature 65-byte signature
     */
    function signSessionAuth(
        uint256 privateKey,
        address invoker,
        Types.SessionAuth memory auth,
        Types.Call[] memory calls,
        bool revertOnFail,
        bytes32 callsHash
    ) internal pure returns (bytes memory signature) {
        bytes32 digest = EIP712.hashSignedBatch(
            auth.chainId,
            invoker,
            auth.sessionKey,
            auth.sessionId,
            auth.nonce,
            auth.expiresAt,
            auth.policyId,
            auth.policySnapshotHash,
            auth.gasLimitMax,
            auth.maxFeePerGas,
            auth.maxPriorityFeePerGas,
            auth.totalGasCap,
            calls,
            revertOnFail,
            callsHash
        );
        
        (uint8 v, bytes32 r, bytes32 s) = VM.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
    
    /**
     * @notice Sign a sponsor voucher (F5 fix: with domain binding)
     * @param privateKey Sponsor's private key
     * @param chainId Chain ID for domain binding
     * @param verifyingContract Verifying contract for domain binding (Invoker)
     * @param sponsor Sponsor address
     * @param policyId Policy ID
     * @param policySnapshotHash Policy snapshot hash
     * @param sessionId Session ID
     * @param nonce Nonce
     * @param expiresAt Expiration timestamp
     * @param gasLimitMax Maximum gas limit
     * @param maxFeePerGas Maximum fee per gas
     * @param maxPriorityFeePerGas Maximum priority fee per gas
     * @param totalGasCap Total gas cap
     * @return signature 65-byte signature
     */
    function signSponsorVoucher(
        uint256 privateKey,
        uint256 chainId,
        address verifyingContract,
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
    ) internal pure returns (bytes memory signature) {
        bytes32 digest = EIP712.hashSponsorVoucher(
            chainId,
            verifyingContract,
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
        );
        
        (uint8 v, bytes32 r, bytes32 s) = VM.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
    
    /**
     * @notice Create a basic session auth struct with sensible defaults
     * @param chainId Chain ID
     * @param sessionKey Session key address
     * @param policyId Policy ID
     * @param policySnapshotHash Policy snapshot hash
     * @return auth Session auth struct
     */
    function createDefaultAuth(
        uint256 chainId,
        address sessionKey,
        bytes32 policyId,
        bytes32 policySnapshotHash
    ) internal view returns (Types.SessionAuth memory auth) {
        auth = Types.SessionAuth({
            chainId: chainId,
            sessionKey: sessionKey,
            sessionId: 0,
            nonce: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 1 hours),
            policyId: policyId,
            policySnapshotHash: policySnapshotHash,
            gasLimitMax: 1_000_000,
            maxFeePerGas: 100 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 2_000_000
        });
    }
    
    /**
     * @notice Create a simple call to a target
     * @param target Target address
     * @param data Call data
     * @return call Call struct
     */
    function createCall(
        address target,
        bytes memory data
    ) internal pure returns (Types.Call memory call) {
        call = Types.Call({
            target: target,
            value: 0,
            data: data,
            gasLimit: 100_000
        });
    }
    
    /**
     * @notice Create a call with value
     * @param target Target address
     * @param data Call data
     * @param value ETH value
     * @param gasLimit Gas limit
     * @return call Call struct
     */
    function createCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        uint256 gasLimit
    ) internal pure returns (Types.Call memory call) {
        call = Types.Call({
            target: target,
            value: value,
            data: data,
            gasLimit: gasLimit
        });
    }
}

