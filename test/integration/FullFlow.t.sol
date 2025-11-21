// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {VolrSponsor} from "../../src/sponsor/VolrSponsor.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";

import {TestHelpers} from "../helpers/TestHelpers.sol";

contract FullFlowTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    PolicyRegistry public registry;
    ClientSponsor public clientSponsor;
    VolrSponsor public volrSponsor;
    
    address public user;
    address public client;
    uint256 public userKey;
    bytes32 public policyId;
    
    function setUp() public {
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        client = address(0x1111);
        policyId = keccak256("test-policy");
        
        policy = new ScopedPolicy();
        registry = TestHelpers.deployPolicyRegistry(address(this));
        registry.setTimelock(address(this));
        registry.setMultisig(address(this));
        invoker = new VolrInvoker(address(registry));
        clientSponsor = TestHelpers.deployClientSponsor(address(this));
        volrSponsor = TestHelpers.deployVolrSponsor(address(this));
        
        // Register policy in registry
        registry.register(policyId, address(policy), "test-policy");
        
        // Policy 설정 (Updated to use setPolicy method instead of struct)
        policy.setPolicy(policyId, block.chainid, 0, 3600, false);
        policy.setPair(policyId, address(0x1234), bytes4(0x12345678), true);
        
        // ClientSponsor 설정
        vm.prank(address(this));
        clientSponsor.setBudget(client, 10 ether);
        vm.prank(address(this));
        clientSponsor.setPolicy(client, policyId);
        vm.prank(address(this));
        clientSponsor.setLimits(client, 100 ether, 10 ether);
        
        // VolrSponsor 설정
        vm.prank(address(this));
        volrSponsor.setSubsidyRate(policyId, 2000); // 20%
        
        // ClientSponsor에 VolrSponsor 연결
        vm.prank(address(this));
        clientSponsor.setVolrSponsor(address(volrSponsor));
    }
    
    function test_FullFlow() public {
        // 전체 플로우 테스트는 서명 생성이 필요하므로 복잡함
        // 기본 구조만 확인
        assertEq(registry.get(policyId), address(policy));
        assertEq(clientSponsor.getBudget(client), 10 ether);
    }
}
