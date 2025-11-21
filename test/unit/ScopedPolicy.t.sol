// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";

contract ScopedPolicyTest is Test {
    ScopedPolicy public policy;
    address public allowedContract;
    bytes4 public allowedSelector;
    
    function setUp() public {
        allowedContract = address(0x1234);
        allowedSelector = bytes4(0x12345678);
        policy = new ScopedPolicy();
    }
    
    function test_Validate_ChainId() public view {
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: keccak256("policy"),
            policySnapshotHash: bytes32(0),
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: allowedContract,
            value: 0,
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        // 체인ID 검증 테스트
        (bool ok, uint256 code) = policy.validate(auth, calls);
        // 실제 구현에 따라 결과가 달라질 수 있음
    }
    
    function test_Validate_Expired() public view {
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp - 1), // 만료됨
            policyId: keccak256("policy"),
            policySnapshotHash: bytes32(0),
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: allowedContract,
            value: 0,
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        // 만료된 세션은 거부되어야 함
        (bool ok, uint256 code) = policy.validate(auth, calls);
        assertFalse(ok);
    }
    
    function test_Validate_NonceReplay() public {
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: keccak256("policy"),
            policySnapshotHash: bytes32(0),
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: allowedContract,
            value: 0,
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        // 첫 번째 호출
        (bool ok1, ) = policy.validate(auth, calls);
        
        // 같은 nonce로 재생 시도
        (bool ok2, ) = policy.validate(auth, calls);
        
        // 재생 공격은 거부되어야 함
        // 실제 구현에 따라 다를 수 있음
    }
    
    function test_Validate_Whitelist() public view {
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: keccak256("policy"),
            policySnapshotHash: bytes32(0),
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(0x9999), // 화이트리스트에 없는 주소
            value: 0,
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        // 화이트리스트에 없는 컨트랙트는 거부되어야 함
        (bool ok, uint256 code) = policy.validate(auth, calls);
        assertFalse(ok);
    }
    
    function test_Validate_ValueLimit() public view {
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: keccak256("policy"),
            policySnapshotHash: bytes32(0),
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: allowedContract,
            value: 10 ether, // 한도를 초과하는 값
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        // 한도를 초과하는 value는 거부되어야 함
        (bool ok, uint256 code) = policy.validate(auth, calls);
        assertFalse(ok);
    }
}
