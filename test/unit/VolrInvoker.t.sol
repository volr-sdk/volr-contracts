// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";

contract VolrInvokerTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    address public user;
    uint256 public userKey;
    
    function setUp() public {
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        
        policy = new ScopedPolicy();
        invoker = new VolrInvoker(address(policy));
    }
    
    function test_Deploy() public {
        assertEq(address(invoker.policy()), address(policy));
    }
    
    function test_ExecuteBatch_Basic() public {
        // 기본 실행 테스트는 서명이 필요하므로 복잡함
        // 실제 구현 후 더 상세한 테스트 작성
        assertTrue(true);
    }
    
    function test_ExecuteBatch_InvalidSignature() public {
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234"
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope")
        });
        
        bytes memory invalidSig = hex"1234";
        
        // 잘못된 서명으로 실행 시도
        vm.expectRevert();
        invoker.executeBatch(calls, auth, invalidSig);
    }
}

