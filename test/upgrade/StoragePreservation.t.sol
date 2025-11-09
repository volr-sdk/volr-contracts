// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";

/**
 * @title ClientSponsorV1
 * @notice Initial version for upgrade testing
 */
contract ClientSponsorV1 is ClientSponsor {
    uint256 public counter;
    
    function increment() external virtual {
        counter++;
    }
    
    function setBudgetAndIncrement(address client, uint256 budget) external {
        this.setBudget(client, budget);
        counter++;
    }
}

/**
 * @title ClientSponsorV2
 * @notice Upgraded version with new storage variables
 */
contract ClientSponsorV2 is ClientSponsorV1 {
    uint256 public newCounter; // New storage variable
    string public newString; // New storage variable
    
    function increment() external override {
        // Directly increment counter (don't call parent to avoid recursion)
        counter++;
        newCounter++;
    }
    
    function setNewString(string memory str) external {
        newString = str;
    }
}

contract StoragePreservationTest is Test {
    ERC1967Proxy public proxy;
    ClientSponsorV1 public implV1;
    ClientSponsorV2 public implV2;
    address public owner;
    address public client;
    
    function setUp() public {
        owner = address(this);
        client = address(0x1111);
        
        // Deploy V1 implementation
        implV1 = new ClientSponsorV1();
        
        // Deploy proxy with V1 implementation
        bytes memory initData = abi.encodeWithSelector(
            ClientSponsor.initialize.selector,
            owner
        );
        proxy = new ERC1967Proxy(address(implV1), initData);
        
        // Cast proxy to ClientSponsorV1
        ClientSponsorV1 proxyV1 = ClientSponsorV1(address(proxy));
        
        // Set timelock and multisig for upgrade authorization
        proxyV1.setTimelock(owner);
        proxyV1.setMultisig(owner);
        
        // Set initial state (owner로 prank)
        vm.prank(owner);
        proxyV1.setBudget(client, 100 ether);
        proxyV1.increment();
        proxyV1.increment();
        
        // Deploy V2 implementation
        implV2 = new ClientSponsorV2();
    }
    
    function test_StoragePreservation_AfterUpgrade() public {
        ClientSponsorV1 proxyV1 = ClientSponsorV1(address(proxy));
        
        // Verify initial state
        assertEq(proxyV1.getBudget(client), 100 ether);
        assertEq(proxyV1.counter(), 2); // 2 from increment
        
        // Upgrade to V2
        ClientSponsorV2 proxyV2 = ClientSponsorV2(address(proxy));
        proxyV2.upgradeToAndCall(address(implV2), "");
        
        // Verify old state is preserved
        assertEq(proxyV2.getBudget(client), 100 ether);
        assertEq(proxyV2.counter(), 2);
        
        // Verify new functionality works
        proxyV2.setNewString("test");
        assertEq(proxyV2.newString(), "test");
        
        // Verify new counter starts at 0
        assertEq(proxyV2.newCounter(), 0);
        
        // Increment both counters
        proxyV2.increment();
        assertEq(proxyV2.counter(), 3);
        assertEq(proxyV2.newCounter(), 1);
    }
    
    function test_StoragePreservation_MultipleUpgrades() public {
        ClientSponsorV1 proxyV1 = ClientSponsorV1(address(proxy));
        
        // Set more state
        vm.prank(owner);
        proxyV1.setBudget(address(0x2222), 50 ether);
        proxyV1.increment();
        
        // Upgrade to V2
        ClientSponsorV2 proxyV2 = ClientSponsorV2(address(proxy));
        proxyV2.upgradeToAndCall(address(implV2), "");
        
        // Verify all state preserved
        assertEq(proxyV2.getBudget(client), 100 ether);
        assertEq(proxyV2.getBudget(address(0x2222)), 50 ether);
        assertEq(proxyV2.counter(), 3);
    }
}

/**
 * @title PolicyRegistryV1
 * @notice Initial version for upgrade testing
 */
contract PolicyRegistryV1 is PolicyRegistry {
    uint256 public counter;
    
    function increment() external virtual {
        counter++;
    }
}

/**
 * @title PolicyRegistryV2
 * @notice Upgraded version with new storage variables
 */
contract PolicyRegistryV2 is PolicyRegistryV1 {
    uint256 public newCounter;
    
    function increment() external override {
        // Directly increment counter (don't call parent to avoid recursion)
        counter++;
        newCounter++;
    }
}

contract PolicyRegistryStoragePreservationTest is Test {
    ERC1967Proxy public proxy;
    PolicyRegistryV1 public implV1;
    PolicyRegistryV2 public implV2;
    address public owner;
    bytes32 public policyId;
    address public policyImpl;
    
    function setUp() public {
        owner = address(this);
        policyId = keccak256("test-policy");
        policyImpl = address(0x1234);
        
        // Deploy V1 implementation
        implV1 = new PolicyRegistryV1();
        
        // Deploy proxy with V1 implementation
        bytes memory initData = abi.encodeWithSelector(
            PolicyRegistry.initialize.selector,
            owner
        );
        proxy = new ERC1967Proxy(address(implV1), initData);
        
        // Cast proxy to PolicyRegistryV1
        PolicyRegistryV1 proxyV1 = PolicyRegistryV1(address(proxy));
        
        // Set timelock and multisig for authorization
        proxyV1.setTimelock(owner);
        proxyV1.setMultisig(owner);
        
        // Set initial state
        proxyV1.register(policyId, policyImpl, "test");
        proxyV1.increment();
        
        // Deploy V2 implementation
        implV2 = new PolicyRegistryV2();
    }
    
    function test_PolicyRegistry_StoragePreservation() public {
        PolicyRegistryV1 proxyV1 = PolicyRegistryV1(address(proxy));
        
        // Verify initial state
        assertEq(proxyV1.get(policyId), policyImpl);
        assertEq(proxyV1.counter(), 1);
        
        // Upgrade to V2
        PolicyRegistryV2 proxyV2 = PolicyRegistryV2(address(proxy));
        proxyV2.upgradeToAndCall(address(implV2), "");
        
        // Verify old state is preserved
        assertEq(proxyV2.get(policyId), policyImpl);
        assertEq(proxyV2.counter(), 1);
        
        // Verify new counter starts at 0
        assertEq(proxyV2.newCounter(), 0);
        
        // Increment both counters
        proxyV2.increment();
        assertEq(proxyV2.counter(), 2);
        assertEq(proxyV2.newCounter(), 1);
    }
}

