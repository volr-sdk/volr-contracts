// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";

import {TestHelpers} from "../helpers/TestHelpers.sol";

contract VolrInvokerTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    PolicyRegistry public registry;
    address public user;
    uint256 public userKey;
    bytes32 public policyId;
    
    function setUp() public {
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        policyId = keccak256("test-policy");
        
        policy = new ScopedPolicy();
        registry = TestHelpers.deployPolicyRegistry(address(this));
        registry.setTimelock(address(this));
        registry.setMultisig(address(this));
        registry.register(policyId, address(policy), "test-policy");
        invoker = new VolrInvoker(address(registry));
    }
    
    function test_Deploy() public {
        assertEq(registry.get(policyId), address(policy));
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
            data: hex"1234",
            gasLimit: 0
        });

        bytes32 callsHash = keccak256(abi.encode(calls));

        VolrInvoker.SessionAuth memory auth = VolrInvoker.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            expiresAt: uint64(block.timestamp + 3600),
            nonce: 1,
            policyId: keccak256("policy"),
            totalGasCap: 0
        });

        bytes memory invalidSig = hex"1234";

        // 잘못된 서명으로 실행 시도
        vm.expectRevert();
        invoker.executeBatch(calls, auth, false, callsHash, invalidSig);
    }
}

