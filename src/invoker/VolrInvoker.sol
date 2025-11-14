// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IPolicy} from "../interfaces/IPolicy.sol";
import {IPolicyRegistry} from "../registry/PolicyRegistry.sol";
import {Types} from "../libraries/Types.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {Signature} from "../libraries/Signature.sol";
import {CallValidator} from "../libraries/CallValidator.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VolrInvoker
 * @notice ERC-7702 compatible invoker with policy-based validation
 * @dev Uses PolicyRegistry for strategy-based policy lookup
 */
contract VolrInvoker is ReentrancyGuard {
    IPolicyRegistry public immutable registry;
    mapping(address => uint256) public opNonces;
    
    // SessionAuth for EIP-712 SignedBatch
    struct SessionAuth {
        uint256 chainId;
        address sessionKey;
        uint64  expiresAt;
        uint64  nonce;
        bytes32 policyId;
        uint256 totalGasCap;
    }
    
    error PolicyViolation(uint256 code);
    
    event BatchExecuted(
        address indexed user,
        uint256 indexed opNonce,
        bytes32 indexed callsHash,
        bool success
    );
    
    event SponsoredExecuted(
        address indexed user,
        address indexed sponsor,
        uint256 indexed opNonce,
        bytes32 callsHash,
        bool success
    );
    
    /**
     * @notice Constructor
     * @param _registry PolicyRegistry address
     */
    constructor(address _registry) {
        registry = IPolicyRegistry(_registry);
    }
    
    
    /**
     * @notice Execute a batch of calls with sponsorship
     * @param calls Array of calls to execute
     * @param auth Session authorization
     * @param revertOnFail If true, revert entire batch on first failure
     * @param callsHash Keccak256 hash of ABI-encoded Call[]
     * @param sessionSig EIP-712 signature over SignedBatch
     * @param sponsor Sponsor address
     */
    function sponsoredExecute(
        Types.Call[] calldata calls,
        SessionAuth calldata auth,
        bool revertOnFail,
        bytes32 callsHash,
        bytes calldata sessionSig,
        address sponsor
    ) external nonReentrant {
        // 0. Validate calls
        require(CallValidator.validateCalls(calls), "Invalid calls");

        // 1. Validate callsHash matches provided calls
        bytes32 expectedCallsHash = keccak256(abi.encode(calls));
        require(callsHash == expectedCallsHash, "Calls hash mismatch");

        // 2. Verify EIP-712 signature (domain matches SDK: sessionKey as verifying contract)
        require(sessionSig.length == 65, "Invalid signature length");
        bytes memory sigCopy = sessionSig;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sigCopy, 32))
            s := mload(add(sigCopy, 64))
            v := byte(0, mload(add(sigCopy, 96)))
        }
        uint8 vNormalized = v >= 27 ? uint8(v - 27) : v;
        require(Signature.validateYParity(vNormalized), "Invalid y-parity");
        require(Signature.validateRS(r, s), "Invalid r or s");
        require(EIP712.validateLowS(s), "Invalid s (high-S)");

        // Copy calls to memory for hashing helper
        Types.Call[] memory mCalls = new Types.Call[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            mCalls[i] = calls[i];
        }

        bytes32 digest = EIP712.hashSignedBatch(
            auth.chainId,
            auth.sessionKey,
            auth.expiresAt,
            auth.nonce,
            auth.policyId,
            auth.totalGasCap,
            mCalls,
            revertOnFail,
            callsHash
        );

        address signer = Signature.recoverSigner(digest, v, r, s);
        require(signer != address(0), "Invalid signature");

        // 3. Policy validation (wrap V2 into legacy struct to reuse policies)
        Types.SessionAuth memory legacy = Types.SessionAuth({
            callsHash: callsHash,
            revertOnFail: revertOnFail,
            chainId: auth.chainId,
            opNonce: auth.nonce,
            expiry: auth.expiresAt,
            scopeId: bytes32(0),
            policyId: auth.policyId,
            totalGasCap: auth.totalGasCap
        });

        // TEMPORARY: Skip policy validation during development
        // TODO: Restore policy validation after proper setup
        /*
        address policyAddr = registry.get(auth.policyId);
        IPolicy policy = IPolicy(policyAddr);
        (bool policyOk, uint256 policyCode) = policy.validate(legacy, calls);
        if (!policyOk) {
            revert PolicyViolation(policyCode);
        }
        */

        // 4. Nonce check
        require(auth.nonce > opNonces[signer], "Invalid nonce");
        opNonces[signer] = auth.nonce;

        // 5. Execute
        uint256 gasBefore = gasleft();
        bool success = _executeCalls(calls, revertOnFail);
        uint256 gasUsed = gasBefore - gasleft();

        // 6. Policy hooks (temporarily disabled)
        /*
        if (success) {
            try policy.onExecuted(msg.sender, legacy, calls, gasUsed) {} catch {}
        } else {
            bytes memory reason = "";
            try policy.onFailed(msg.sender, legacy, calls, reason) {} catch {}
        }
        */

        emit SponsoredExecuted(signer, sponsor, auth.nonce, callsHash, success);
    }
    
    /**
     * @notice Execute a batch of calls
     * @param calls Array of calls to execute
     * @param auth Session authorization
     * @param revertOnFail If true, revert entire batch on first failure
     * @param callsHash Keccak256 hash of ABI-encoded Call[]
     * @param sessionSig EIP-712 signature over SignedBatch
     */
    function executeBatch(
        Types.Call[] calldata calls,
        SessionAuth calldata auth,
        bool revertOnFail,
        bytes32 callsHash,
        bytes calldata sessionSig
    ) external payable nonReentrant {
        // 0. Validate calls
        require(CallValidator.validateCalls(calls), "Invalid calls");
        
        // 1. Validate callsHash matches provided calls
        bytes32 expectedCallsHash = keccak256(abi.encode(calls));
        require(callsHash == expectedCallsHash, "Calls hash mismatch");
        
        // 2. Verify EIP-712 signature (domain matches SDK: sessionKey as verifying contract)
        require(sessionSig.length == 65, "Invalid signature length");
        bytes memory sigCopy = sessionSig;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sigCopy, 32))
            s := mload(add(sigCopy, 64))
            v := byte(0, mload(add(sigCopy, 96)))
        }
        uint8 vNormalized = v >= 27 ? uint8(v - 27) : v;
        require(Signature.validateYParity(vNormalized), "Invalid y-parity");
        require(Signature.validateRS(r, s), "Invalid r or s");
        require(EIP712.validateLowS(s), "Invalid s (high-S)");
        
        // Copy calls to memory for hashing helper
        Types.Call[] memory mCalls = new Types.Call[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            mCalls[i] = calls[i];
        }
        
        bytes32 digest = EIP712.hashSignedBatch(
            auth.chainId,
            auth.sessionKey,
            auth.expiresAt,
            auth.nonce,
            auth.policyId,
            auth.totalGasCap,
            mCalls,
            revertOnFail,
            callsHash
        );

        address signer = Signature.recoverSigner(digest, v, r, s);
        require(signer != address(0), "Invalid signature");

        // 3. Policy validation (wrap V2 into legacy struct to reuse policies)
        Types.SessionAuth memory legacy = Types.SessionAuth({
            callsHash: callsHash,
            revertOnFail: revertOnFail,
            chainId: auth.chainId,
            opNonce: auth.nonce,
            expiry: auth.expiresAt,
            scopeId: bytes32(0),
            policyId: auth.policyId,
            totalGasCap: auth.totalGasCap
        });

        // TEMPORARY: Skip policy validation during development
        // TODO: Restore policy validation after proper setup
        /*
        address policyAddr = registry.get(auth.policyId);
        IPolicy policy = IPolicy(policyAddr);
        (bool policyOk, uint256 policyCode) = policy.validate(legacy, calls);
        if (!policyOk) {
            revert PolicyViolation(policyCode);
        }
        */
        
        // 4. Nonce check
        require(auth.nonce > opNonces[signer], "Invalid nonce");
        opNonces[signer] = auth.nonce;
        
        // 5. Execute
        uint256 gasBefore = gasleft();
        bool success = _executeCalls(calls, revertOnFail);
        uint256 gasUsed = gasBefore - gasleft();
        
        // 6. Policy hooks (temporarily disabled)
        /*
        if (success) {
            try policy.onExecuted(msg.sender, legacy, calls, gasUsed) {} catch {}
        } else {
            bytes memory reason = "";
            try policy.onFailed(msg.sender, legacy, calls, reason) {} catch {}
        }
        */
        
        emit BatchExecuted(signer, auth.nonce, callsHash, success);
    }
    
    function _executeCalls(
        Types.Call[] calldata calls,
        bool revertOnFail
    ) internal returns (bool) {
        bool allSuccess = true;
        
        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call memory call = calls[i];
            
            // Guard: target must be a contract (prevent EOA no-op success)
            require(call.target.code.length > 0, "Target is not a contract");
            
            uint256 gasBefore = gasleft();
            
            // EIP-7702: 사용자 EOA가 Invoker 코드 실행
            // call 사용: msg.sender = 사용자 EOA (Invoker 코드를 실행 중인 주소)
            (bool success, bytes memory ret) = call.target.call{
                value: call.value,
                gas: call.gasLimit > 0 ? call.gasLimit : gasleft()
            }(call.data);
            
            uint256 gasUsed = gasBefore - gasleft();
            
            if (call.gasLimit > 0 && gasUsed > call.gasLimit) {
                revert("Gas limit exceeded");
            }
            
            if (!success) {
                allSuccess = false;
                if (revertOnFail) {
                    // Bubble up revert data if present
                    if (ret.length > 0) {
                        assembly {
                            revert(add(ret, 32), mload(ret))
                        }
                    } else {
                        revert("Call execution failed");
                    }
                }
            }
        }
        
        return allSuccess;
    }
}

