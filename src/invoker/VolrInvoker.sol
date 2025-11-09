// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IInvoker} from "../interfaces/IInvoker.sol";
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
contract VolrInvoker is IInvoker, ReentrancyGuard {
    IPolicyRegistry public immutable registry;
    mapping(address => uint256) public opNonces;
    
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
     * @notice Execute a batch of calls
     * @param calls Array of calls to execute
     * @param auth Session authorization data
     * @param sig EIP-712 signature
     */
    function executeBatch(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        bytes calldata sig
    ) external payable nonReentrant {
        // Call 검증
        require(CallValidator.validateCalls(calls), "Invalid calls");
        
        // callsHash 검증
        bytes32 expectedCallsHash = keccak256(abi.encode(calls));
        require(auth.callsHash == expectedCallsHash, "Calls hash mismatch");
        
        // EIP-712 서명 검증
        address signer = _verifySignature(auth, sig);
        
        // Policy 검증 via registry
        address policyAddr = registry.get(auth.policyId);
        IPolicy policy = IPolicy(policyAddr);
        (bool policyOk, uint256 policyCode) = policy.validate(auth, calls);
        if (!policyOk) {
            revert PolicyViolation(policyCode);
        }
        
        // opNonce 검증 및 업데이트
        require(auth.opNonce > opNonces[signer], "Invalid nonce");
        opNonces[signer] = auth.opNonce;
        
        // Gas tracking
        uint256 gasBefore = gasleft();
        
        // Call 실행
        bool success = _executeCalls(calls, auth.revertOnFail);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Policy hooks
        if (success) {
            try policy.onExecuted(msg.sender, auth, calls, gasUsed) {} catch {
                // Best-effort: ignore hook errors to maintain invariants
            }
        } else {
            bytes memory reason = "";
            try policy.onFailed(msg.sender, auth, calls, reason) {} catch {
                // Best-effort: ignore hook errors to maintain invariants
            }
        }
        
        emit BatchExecuted(signer, auth.opNonce, auth.callsHash, success);
    }
    
    /**
     * @notice Execute a batch of calls with sponsorship
     * @param calls Array of calls to execute
     * @param auth Session authorization data
     * @param sig EIP-712 signature
     * @param sponsor Sponsor address
     */
    function sponsoredExecute(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        bytes calldata sig,
        address sponsor
    ) external nonReentrant {
        // Call 검증
        require(CallValidator.validateCalls(calls), "Invalid calls");
        
        // callsHash 검증
        bytes32 expectedCallsHash = keccak256(abi.encode(calls));
        require(auth.callsHash == expectedCallsHash, "Calls hash mismatch");
        
        // EIP-712 서명 검증
        address signer = _verifySignature(auth, sig);
        
        // Policy 검증 via registry
        address policyAddr = registry.get(auth.policyId);
        IPolicy policy = IPolicy(policyAddr);
        (bool policyOk, uint256 policyCode) = policy.validate(auth, calls);
        if (!policyOk) {
            revert PolicyViolation(policyCode);
        }
        
        // opNonce 검증 및 업데이트
        require(auth.opNonce > opNonces[signer], "Invalid nonce");
        opNonces[signer] = auth.opNonce;
        
        // Gas tracking
        uint256 gasBefore = gasleft();
        
        // Call 실행
        bool success = _executeCalls(calls, auth.revertOnFail);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Policy hooks
        if (success) {
            try policy.onExecuted(msg.sender, auth, calls, gasUsed) {} catch {
                // Best-effort: ignore hook errors to maintain invariants
            }
        } else {
            bytes memory reason = "";
            try policy.onFailed(msg.sender, auth, calls, reason) {} catch {
                // Best-effort: ignore hook errors to maintain invariants
            }
        }
        
        emit SponsoredExecuted(signer, sponsor, auth.opNonce, auth.callsHash, success);
    }
    
    function _verifySignature(
        Types.SessionAuth calldata auth,
        bytes calldata sig
    ) internal view returns (address) {
        require(sig.length == 65, "Invalid signature length");
        
        bytes memory sigCopy = sig;
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(sigCopy, 32))
            s := mload(add(sigCopy, 64))
            v := byte(0, mload(add(sigCopy, 96)))
        }
        
        // y-parity 검증 (vm.sign은 27 또는 28을 반환하므로 변환 필요)
        // v가 27이면 0, 28이면 1로 변환
        uint8 vNormalized = v >= 27 ? uint8(v - 27) : v;
        require(Signature.validateYParity(vNormalized), "Invalid y-parity");
        
        // r, s 검증
        require(Signature.validateRS(r, s), "Invalid r or s");
        
        // low-S 검증
        require(EIP712.validateLowS(s), "Invalid s (high-S)");
        
        // EIP-712 해시 계산
        bytes32 hash = EIP712.hashTypedDataV4(address(this), auth);
        
        // 서명 복구 (recoverSigner는 v를 27 또는 28로 기대)
        address signer = Signature.recoverSigner(hash, v, r, s);
        require(signer != address(0), "Invalid signature");
        
        return signer;
    }
    
    function _executeCalls(
        Types.Call[] calldata calls,
        bool revertOnFail
    ) internal returns (bool) {
        bool allSuccess = true;
        
        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call memory call = calls[i];
            
            // gasLimit 검증 (0이면 제한 없음)
            uint256 gasBefore = gasleft();
            (bool success, ) = call.target.call{value: call.value}(call.data);
            uint256 gasUsed = gasBefore - gasleft();
            
            if (call.gasLimit > 0 && gasUsed > call.gasLimit) {
                revert("Gas limit exceeded");
            }
            
            if (!success) {
                allSuccess = false;
                if (revertOnFail) {
                    revert("Call execution failed");
                }
            }
        }
        
        return allSuccess;
    }
}

