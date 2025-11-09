// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BasePolicy} from "./BasePolicy.sol";
import {Types} from "../libraries/Types.sol";

contract ScopedPolicy is BasePolicy {
    struct PolicyConfig {
        uint256 chainId;
        address[] allowedContracts;
        bytes4[] allowedSelectors;
        uint256 maxValue;
        uint64 maxExpiry;
    }
    
    mapping(bytes32 => PolicyConfig) public policies;
    mapping(bytes32 => mapping(uint256 => bool)) public usedNonces;
    
    event PolicySet(bytes32 indexed policyId, PolicyConfig config);
    
    function setPolicy(
        bytes32 policyId,
        PolicyConfig calldata config
    ) external {
        policies[policyId] = config;
        emit PolicySet(policyId, config);
    }
    
    function validate(
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls
    ) external view override returns (bool ok, uint256 code) {
        // scopeId를 policyId로 사용
        bytes32 policyId = auth.scopeId;
        PolicyConfig memory config = policies[policyId];
        
        // Policy가 설정되지 않았으면 거부
        if (config.chainId == 0) {
            return (false, 1); // POLICY_NOT_FOUND
        }
        
        // 체인ID 검증
        if (auth.chainId != config.chainId || auth.chainId != block.chainid) {
            return (false, 2); // CHAIN_ID_MISMATCH
        }
        
        // 만료 시간 검증
        if (auth.expiry < block.timestamp) {
            return (false, 3); // EXPIRED
        }
        
        // 최대 만료 시간 검증
        if (auth.expiry > block.timestamp + config.maxExpiry) {
            return (false, 4); // EXPIRY_TOO_LONG
        }
        
        // Nonce 재생 방지
        if (usedNonces[policyId][auth.opNonce]) {
            return (false, 5); // NONCE_REUSED
        }
        
        // Call 검증
        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call memory call = calls[i];
            
            // Value 검증
            if (call.value > config.maxValue) {
                return (false, 6); // VALUE_EXCEEDED
            }
            
            // 화이트리스트 검증
            bool contractAllowed = false;
            for (uint256 j = 0; j < config.allowedContracts.length; j++) {
                if (config.allowedContracts[j] == call.target) {
                    contractAllowed = true;
                    break;
                }
            }
            
            if (!contractAllowed) {
                return (false, 7); // CONTRACT_NOT_ALLOWED
            }
            
            // 함수 셀렉터 검증
            if (call.data.length >= 4) {
                bytes memory dataCopy = call.data;
                bytes4 selector;
                assembly {
                    selector := mload(add(dataCopy, 32))
                }
                bool selectorAllowed = false;
                for (uint256 j = 0; j < config.allowedSelectors.length; j++) {
                    if (config.allowedSelectors[j] == selector) {
                        selectorAllowed = true;
                        break;
                    }
                }
                
                if (!selectorAllowed) {
                    return (false, 8); // SELECTOR_NOT_ALLOWED
                }
            }
        }
        
        return (true, 0);
    }
    
    function markNonceUsed(bytes32 policyId, uint256 nonce) external {
        usedNonces[policyId][nonce] = true;
    }
}

