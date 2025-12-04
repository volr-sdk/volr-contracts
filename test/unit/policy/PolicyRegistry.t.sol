// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../../../src/registry/PolicyRegistry.sol";

import {TestHelpers} from "../../helpers/TestHelpers.sol";

/**
 * @title PolicyRegistryTest
 * @notice Unit tests for PolicyRegistry
 */
contract PolicyRegistryTest is Test {
    PolicyRegistry public registry;
    address public owner;
    address public relayer;
    bytes32 public policyId;
    address public policyImpl;
    
    function setUp() public {
        owner = address(this);
        relayer = address(0x1111);
        policyId = keccak256("test-policy");
        policyImpl = address(0x2222);
        
        registry = TestHelpers.deployPolicyRegistry(owner);
        registry.setTimelock(owner);
        registry.setMultisig(owner);
    }
    
    // ============ Registration ============
    
    function test_Register_Success() public {
        registry.register(policyId, policyImpl, "Test Policy");
        
        assertEq(registry.get(policyId), policyImpl);
    }
    
    function test_Register_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit PolicyRegistry.PolicyRegistered(policyId, policyImpl, "Test Policy");
        
        registry.register(policyId, policyImpl, "Test Policy");
    }
    
    function test_Register_ZeroAddress_Reverts() public {
        vm.expectRevert(PolicyRegistry.ZeroAddress.selector);
        registry.register(policyId, address(0), "Test Policy");
    }
    
    function test_Register_AlreadyExists_Reverts() public {
        registry.register(policyId, policyImpl, "Test Policy");
        
        vm.expectRevert(PolicyRegistry.PolicyAlreadyExists.selector);
        registry.register(policyId, address(0x3333), "Another Policy");
    }
    
    function test_Register_Unauthorized_Reverts() public {
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.register(policyId, policyImpl, "Test Policy");
    }
    
    // ============ Unregistration ============
    
    function test_Unregister_Success() public {
        registry.register(policyId, policyImpl, "Test Policy");
        registry.unregister(policyId);
        
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.get(policyId);
    }
    
    function test_Unregister_EmitsEvent() public {
        registry.register(policyId, policyImpl, "Test Policy");
        
        vm.expectEmit(true, false, false, false);
        emit PolicyRegistry.PolicyUnregistered(policyId);
        
        registry.unregister(policyId);
    }
    
    function test_Unregister_NotFound_Reverts() public {
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.unregister(policyId);
    }
    
    function test_Unregister_Unauthorized_Reverts() public {
        registry.register(policyId, policyImpl, "Test Policy");
        
        address unauthorized = address(0x9999);
        vm.prank(unauthorized);
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.unregister(policyId);
    }
    
    // ============ Get ============
    
    function test_Get_ReturnsCorrectAddress() public {
        registry.register(policyId, policyImpl, "Test Policy");
        
        assertEq(registry.get(policyId), policyImpl);
    }
    
    function test_Get_NotFound_Reverts() public {
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.get(policyId);
    }
    
    // ============ Relayer Management ============
    
    function test_SetRelayer_Success() public {
        registry.setRelayer(relayer, true);
        
        assertTrue(registry.isRelayer(relayer));
    }
    
    function test_SetRelayer_Disable() public {
        registry.setRelayer(relayer, true);
        registry.setRelayer(relayer, false);
        
        assertFalse(registry.isRelayer(relayer));
    }
    
    function test_SetRelayer_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit PolicyRegistry.RelayerSet(relayer, true);
        
        registry.setRelayer(relayer, true);
    }
    
    function test_SetRelayer_ZeroAddress_Reverts() public {
        vm.expectRevert(PolicyRegistry.ZeroAddress.selector);
        registry.setRelayer(address(0), true);
    }
    
    function test_Relayer_CanRegister() public {
        registry.setRelayer(relayer, true);
        
        vm.prank(relayer);
        registry.register(policyId, policyImpl, "Test Policy");
        
        assertEq(registry.get(policyId), policyImpl);
    }
    
    // ============ Timelock/Multisig ============
    
    function test_SetTimelock_Success() public {
        address newTimelock = address(0x4444);
        registry.setTimelock(newTimelock);
        
        assertEq(registry.timelock(), newTimelock);
    }
    
    function test_SetTimelock_EmitsEvent() public {
        address newTimelock = address(0x4444);
        
        vm.expectEmit(true, false, false, false);
        emit PolicyRegistry.TimelockSet(newTimelock);
        
        registry.setTimelock(newTimelock);
    }
    
    function test_SetTimelock_ZeroAddress_Reverts() public {
        vm.expectRevert(PolicyRegistry.ZeroAddress.selector);
        registry.setTimelock(address(0));
    }
    
    function test_SetTimelock_Unauthorized_Reverts() public {
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert("Not owner");
        registry.setTimelock(address(0x4444));
    }
    
    function test_SetMultisig_Success() public {
        address newMultisig = address(0x5555);
        registry.setMultisig(newMultisig);
        
        assertEq(registry.multisig(), newMultisig);
    }
    
    function test_SetMultisig_EmitsEvent() public {
        address newMultisig = address(0x5555);
        
        vm.expectEmit(true, false, false, false);
        emit PolicyRegistry.MultisigSet(newMultisig);
        
        registry.setMultisig(newMultisig);
    }
    
    // ============ Authorization ============
    
    function test_Timelock_CanRegister() public {
        address timelockAddr = address(0x4444);
        registry.setTimelock(timelockAddr);
        
        vm.prank(timelockAddr);
        registry.register(policyId, policyImpl, "Test Policy");
        
        assertEq(registry.get(policyId), policyImpl);
    }
    
    function test_Multisig_CanRegister() public {
        address multisigAddr = address(0x5555);
        registry.setMultisig(multisigAddr);
        
        vm.prank(multisigAddr);
        registry.register(policyId, policyImpl, "Test Policy");
        
        assertEq(registry.get(policyId), policyImpl);
    }
    
    // ============ Owner ============
    
    function test_Owner_ReturnsCorrectAddress() public view {
        assertEq(registry.owner(), owner);
    }
}






