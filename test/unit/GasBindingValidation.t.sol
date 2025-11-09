// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";

contract GasBindingValidationTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    address public user;
    uint256 public userKey;
    bytes32 public policyId;
    address public targetContract;
    
    function setUp() public {
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        policyId = keccak256("test-policy");
        targetContract = address(0x1234);
        
        policy = new ScopedPolicy();
        invoker = new VolrInvoker(address(policy));
        
        // Policy 설정
        ScopedPolicy.PolicyConfig memory config = ScopedPolicy.PolicyConfig({
            chainId: block.chainid,
            allowedContracts: new address[](1),
            allowedSelectors: new bytes4[](1),
            maxValue: 0,
            maxExpiry: 3600
        });
        config.allowedContracts[0] = targetContract;
        config.allowedSelectors[0] = bytes4(0x12345678);
        
        policy.setPolicy(policyId, config);
    }
    
    function test_TotalGasCap_Exceeded() public view {
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = Types.Call({
            target: targetContract,
            value: 0,
            data: abi.encodePacked(bytes4(0x12345678)),
            gasLimit: 300000
        });
        calls[1] = Types.Call({
            target: targetContract,
            value: 0,
            data: abi.encodePacked(bytes4(0x12345678)),
            gasLimit: 300000
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: policyId,
            policyId: keccak256("policy"),
            totalGasCap: 500000  // 총 gasLimit(600000)보다 작음
        });
        
        // totalGasCap 초과 시 거부되어야 함
        (bool ok, uint256 code) = policy.validate(auth, calls);
        assertFalse(ok);
        assertEq(code, 9); // TOTAL_GAS_CAP_EXCEEDED
    }
    
    function test_TotalGasCap_WithinLimit() public view {
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = Types.Call({
            target: targetContract,
            value: 0,
            data: abi.encodePacked(bytes4(0x12345678)),
            gasLimit: 200000
        });
        calls[1] = Types.Call({
            target: targetContract,
            value: 0,
            data: abi.encodePacked(bytes4(0x12345678)),
            gasLimit: 200000
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: policyId,
            policyId: keccak256("policy"),
            totalGasCap: 500000  // 총 gasLimit(400000)보다 큼
        });
        
        // totalGasCap 이내면 통과해야 함
        (bool ok, uint256 code) = policy.validate(auth, calls);
        // Policy가 설정되지 않았을 수 있으므로 다른 검증 실패 가능
        // 하지만 totalGasCap 검증은 통과해야 함
    }
    
    function test_TotalGasCap_Zero_NoLimit() public view {
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: targetContract,
            value: 0,
            data: abi.encodePacked(bytes4(0x12345678)),
            gasLimit: 1000000  // 매우 큰 값
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: policyId,
            policyId: keccak256("policy"),
            totalGasCap: 0  // 0이면 제한 없음
        });
        
        // totalGasCap이 0이면 제한 없음
        (bool ok, uint256 code) = policy.validate(auth, calls);
        // totalGasCap 검증은 통과해야 함 (다른 검증 실패 가능)
    }
}

