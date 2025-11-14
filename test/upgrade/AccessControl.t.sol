// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";

contract AccessControlTest is Test {
    ERC1967Proxy public clientSponsorProxy;
    ERC1967Proxy public registryProxy;
    ClientSponsor public clientSponsorImpl;
    PolicyRegistry public registryImpl;
    address public owner;
    address public timelock;
    address public multisig;
    address public attacker;
    
    function setUp() public {
        owner = address(this);
        timelock = address(0x1111);
        multisig = address(0x2222);
        attacker = address(0x9999);
        
        // Deploy implementations
        clientSponsorImpl = new ClientSponsor();
        registryImpl = new PolicyRegistry();
        
        // Deploy proxies
        bytes memory clientInitData = abi.encodeWithSelector(
            ClientSponsor.initialize.selector,
            owner
        );
        clientSponsorProxy = new ERC1967Proxy(address(clientSponsorImpl), clientInitData);
        
        bytes memory registryInitData = abi.encodeWithSelector(
            PolicyRegistry.initialize.selector,
            owner
        );
        registryProxy = new ERC1967Proxy(address(registryImpl), registryInitData);
        
        // Setup governance
        ClientSponsor(address(clientSponsorProxy)).setTimelock(timelock);
        ClientSponsor(address(clientSponsorProxy)).setMultisig(multisig);
        
        PolicyRegistry(address(registryProxy)).setTimelock(timelock);
        PolicyRegistry(address(registryProxy)).setMultisig(multisig);
    }
    
    function test_Upgrade_OnlyTimelockOrMultisig() public {
        ClientSponsor proxy = ClientSponsor(address(clientSponsorProxy));
        ClientSponsor newImpl = new ClientSponsor();
        
        // Attacker cannot upgrade
        vm.prank(attacker);
        vm.expectRevert(ClientSponsor.Unauthorized.selector);
        proxy.upgradeToAndCall(address(newImpl), "");
        
        // Owner cannot upgrade directly
        vm.expectRevert(ClientSponsor.Unauthorized.selector);
        proxy.upgradeToAndCall(address(newImpl), "");
        
        // Timelock can upgrade
        vm.prank(timelock);
        proxy.upgradeToAndCall(address(newImpl), "");
        
        // Multisig can upgrade
        ClientSponsor newImpl2 = new ClientSponsor();
        vm.prank(multisig);
        proxy.upgradeToAndCall(address(newImpl2), "");
    }
    
    function test_PolicyRegistry_Register_OnlyTimelockOrMultisig() public {
        PolicyRegistry registry = PolicyRegistry(address(registryProxy));
        bytes32 policyId = keccak256("test-policy");
        address policyImpl = address(0x1234);
        
        // Attacker cannot register
        vm.prank(attacker);
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.register(policyId, policyImpl, "test");
        
        // Owner cannot register directly
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.register(policyId, policyImpl, "test");
        
        // Timelock can register
        vm.prank(timelock);
        registry.register(policyId, policyImpl, "test");
        assertEq(registry.get(policyId), policyImpl);
        
        // Multisig can register
        bytes32 policyId2 = keccak256("test-policy-2");
        address policyImpl2 = address(0x5678);
        vm.prank(multisig);
        registry.register(policyId2, policyImpl2, "test2");
        assertEq(registry.get(policyId2), policyImpl2);
    }
    
    function test_PolicyRegistry_Unregister_OnlyTimelockOrMultisig() public {
        PolicyRegistry registry = PolicyRegistry(address(registryProxy));
        bytes32 policyId = keccak256("test-policy");
        address policyImpl = address(0x1234);
        
        // Register first
        vm.prank(timelock);
        registry.register(policyId, policyImpl, "test");
        
        // Attacker cannot unregister
        vm.prank(attacker);
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.unregister(policyId);
        
        // Owner cannot unregister directly
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        registry.unregister(policyId);
        
        // Timelock can unregister
        vm.prank(timelock);
        registry.unregister(policyId);
        
        // Verify unregistered
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        registry.get(policyId);
    }
    
    function test_ClientSponsor_AdminFunctions_OnlyOwner() public {
        ClientSponsor sponsor = ClientSponsor(address(clientSponsorProxy));
        address client = address(0x1111);
        
        // Attacker cannot set budget
        vm.prank(attacker);
        vm.expectRevert("Not owner");
        sponsor.setBudget(client, 100 ether);
        
        // Owner can set budget
        sponsor.setBudget(client, 100 ether);
        assertEq(sponsor.getBudget(client), 100 ether);
        
        // Attacker cannot set timelock
        vm.prank(attacker);
        vm.expectRevert("Not owner");
        sponsor.setTimelock(address(0x9999));
        
        // Owner can set timelock
        address newTimelock = address(0x8888);
        sponsor.setTimelock(newTimelock);
        assertEq(sponsor.timelock(), newTimelock);
    }
    
    function test_PolicyRegistry_AdminFunctions_OnlyOwner() public {
        PolicyRegistry registry = PolicyRegistry(address(registryProxy));
        
        // Attacker cannot set timelock
        vm.prank(attacker);
        vm.expectRevert("Not owner");
        registry.setTimelock(address(0x9999));
        
        // Owner can set timelock
        address newTimelock = address(0x8888);
        registry.setTimelock(newTimelock);
        assertEq(registry.timelock(), newTimelock);
    }
}




