// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IInvoker} from "../interfaces/IInvoker.sol";
import {IPolicy} from "../interfaces/IPolicy.sol";
import {Types} from "../libraries/Types.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {Signature} from "../libraries/Signature.sol";
import {CallValidator} from "../libraries/CallValidator.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VolrInvoker is IInvoker, ReentrancyGuard {
    IPolicy public immutable policy;
    mapping(address => uint256) public opNonces;
    
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
    
    constructor(address _policy) {
        policy = IPolicy(_policy);
    }
    
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
        
        // Policy 검증
        (bool policyOk, uint256 policyCode) = policy.validate(auth, calls);
        require(policyOk, "Policy validation failed");
        
        // opNonce 검증 및 업데이트
        require(auth.opNonce > opNonces[signer], "Invalid nonce");
        opNonces[signer] = auth.opNonce;
        
        // Call 실행
        bool success = _executeCalls(calls, auth.revertOnFail);
        
        emit BatchExecuted(signer, auth.opNonce, auth.callsHash, success);
    }
    
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
        
        // Policy 검증
        (bool policyOk, uint256 policyCode) = policy.validate(auth, calls);
        require(policyOk, "Policy validation failed");
        
        // opNonce 검증 및 업데이트
        require(auth.opNonce > opNonces[signer], "Invalid nonce");
        opNonces[signer] = auth.opNonce;
        
        // Call 실행
        bool success = _executeCalls(calls, auth.revertOnFail);
        
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
        
        // y-parity 검증
        require(Signature.validateYParity(v), "Invalid y-parity");
        
        // r, s 검증
        require(Signature.validateRS(r, s), "Invalid r or s");
        
        // low-S 검증
        require(EIP712.validateLowS(s), "Invalid s (high-S)");
        
        // EIP-712 해시 계산
        bytes32 hash = EIP712.hashTypedDataV4(address(this), auth);
        
        // 서명 복구
        address signer = Signature.recoverSigner(hash, v, r, s);
        require(signer != address(0), "Invalid signature");
        
        return signer;
    }
    
    function _executeCalls(
        Types.Call[] calldata calls,
        bool revertOnFail
    ) internal returns (bool) {
        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call memory call = calls[i];
            (bool success, ) = call.target.call{value: call.value}(call.data);
            
            if (!success && revertOnFail) {
                revert("Call execution failed");
            }
        }
        
        return true;
    }
}

