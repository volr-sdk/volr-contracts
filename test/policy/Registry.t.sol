// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {WhitelistPolicy} from "../../src/policy/WhitelistPolicy.sol";
import {PromoPolicy} from "../../src/policy/PromoPolicy.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract RegistryTest is Test {
    PolicyRegistry public registry;
    WhitelistPolicy public whitelistPolicy;
    PromoPolicy public promoPolicy;
    address public owner;
    address public timelock;
    address public multisig;
    address public attacker;
    
    bytes32 public policyId1;
    bytes32 public policyId2;
    
    function setUp() public {
        owner = address(this);
        timelock = address(0x1111);
        multisig = address(0x2222);
        attacker = address(0x9999);
        
        policyId1 = keccak256("whitelist-policy");
        policyId2 = keccak256("promo-policy");
        
        registry = TestHelpers.deployPolicyRegistry(owner);
        registry.setTimelock(timelock);
        registry.setMultisig(multisig);
        
        whitelistPolicy = new WhitelistPolicy();
        promoPolicy = new PromoPolicy();
    }
    
    function test_Register_Policy() public {
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "Whitelist Policy");
        
        assertEq(registry.get(policyId1), address(whitelistPolicy));
    }
    
    function test_Register_OnlyTimelockOrMultisig() public {
        // Attacker cannot register
        vm.prank(attacker);
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        // Owner cannot register directly
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        // Timelock can register
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        // Multisig can register
        vm.prank(multisig);
        registry.register(policyId2, address(promoPolicy), "test");
    }
    
    function test_Register_PolicyAlreadyExists() public {
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        // Cannot register same policy ID again
        vm.prank(timelock);
        vm.expectRevert(PolicyRegistry.PolicyAlreadyExists.selector);
        registry.register(policyId1, address(whitelistPolicy), "test");
    }
    
    function test_Register_ZeroAddress() public {
        vm.prank(timelock);
        vm.expectRevert(PolicyRegistry.ZeroAddress.selector);
        registry.register(policyId1, address(0), "test");
    }
    
    function test_Unregister_Policy() public {
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        vm.prank(timelock);
        registry.unregister(policyId1);
        
        // Policy should not be found after unregister
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.get(policyId1);
    }
    
    function test_Unregister_OnlyTimelockOrMultisig() public {
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        // Attacker cannot unregister
        vm.prank(attacker);
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.unregister(policyId1);
        
        // Owner cannot unregister directly
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.unregister(policyId1);
        
        // Timelock can unregister
        vm.prank(timelock);
        registry.unregister(policyId1);
    }
    
    function test_Unregister_PolicyNotFound() public {
        vm.prank(timelock);
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.unregister(policyId1);
    }
    
    function test_Get_Policy() public {
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        assertEq(registry.get(policyId1), address(whitelistPolicy));
    }
    
    function test_Get_PolicyNotFound() public {
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.get(policyId1);
    }
    
    function test_Events_PolicyRegistered() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit PolicyRegistry.PolicyRegistered(policyId1, address(whitelistPolicy), "test");
        registry.register(policyId1, address(whitelistPolicy), "test");
    }
    
    function test_Events_PolicyUnregistered() public {
        vm.prank(timelock);
        registry.register(policyId1, address(whitelistPolicy), "test");
        
        vm.prank(timelock);
        vm.expectEmit(true, false, false, false);
        emit PolicyRegistry.PolicyUnregistered(policyId1);
        registry.unregister(policyId1);
    }
}
