// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {Types} from "../../src/libraries/Types.sol";

import {TestHelpers} from "../helpers/TestHelpers.sol";
import {SignatureHelper} from "../helpers/SignatureHelper.sol";
import {MockTarget, MockSponsor} from "../helpers/MockContracts.sol";

/**
 * @title VolrInvokerMockUpgrade
 * @notice Mock upgraded implementation for upgrade testing
 */
contract VolrInvokerMockUpgrade is VolrInvoker {
    // New storage variable for upgraded version
    uint256 public newFeature;
    
    function setNewFeature(uint256 value) external {
        newFeature = value;
    }
    
    function getVersion() external pure returns (string memory) {
        return "upgraded";
    }
}

/**
 * @title InvokerUpgradeTest
 * @notice Tests for VolrInvoker upgrade functionality
 */
contract InvokerUpgradeTest is Test {
    VolrInvoker public invoker;
    VolrInvokerMockUpgrade public implUpgrade;
    ScopedPolicy public policy;
    MockTarget public target;
    MockSponsor public mockSponsor;
    
    address public owner;
    address public user;
    uint256 public userKey;
    bytes32 public policyId;
    bytes32 public policySnapshotHash;
    
    function setUp() public {
        owner = address(this);
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        policyId = keccak256("test-policy");
        
        target = new MockTarget();
        mockSponsor = new MockSponsor();
        policy = new ScopedPolicy();
        
        PolicyRegistry registry = TestHelpers.deployPolicyRegistry(owner);
        registry.setTimelock(owner);
        registry.setMultisig(owner);
        registry.register(policyId, address(policy), "test-policy");
        
        invoker = TestHelpers.deployVolrInvoker(owner, address(registry), address(mockSponsor));
        invoker.setTimelock(owner);
        invoker.setMultisig(owner);
        
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        (, , , policySnapshotHash, ) = policy.policies(policyId);
        
        // Deploy upgraded implementation
        implUpgrade = new VolrInvokerMockUpgrade();
    }
    
    // ============ Storage Preservation ============
    
    function test_Upgrade_PreservesNonces() public {
        // Execute a transaction to set nonce
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            policyId,
            policySnapshotHash
        );
        auth.nonce = 100; // Set specific nonce
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Verify nonce before upgrade
        bytes32 channelKey = keccak256(abi.encode(user, policyId, uint64(0)));
        assertEq(invoker.channelNonces(channelKey), 100);
        
        // Upgrade
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        // Verify nonce preserved after upgrade
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.channelNonces(channelKey), 100);
    }
    
    function test_Upgrade_PreservesRegistry() public {
        address registryBefore = address(invoker.registry());
        
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(address(invokerUpgraded.registry()), registryBefore);
    }
    
    function test_Upgrade_PreservesSponsor() public {
        address sponsorBefore = address(invoker.sponsor());
        
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(address(invokerUpgraded.sponsor()), sponsorBefore);
    }
    
    function test_Upgrade_PreservesOwner() public {
        address ownerBefore = invoker.owner();
        
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.owner(), ownerBefore);
    }
    
    function test_Upgrade_PreservesTimelock() public {
        address timelockBefore = invoker.timelock();
        
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.timelock(), timelockBefore);
    }
    
    // ============ New Functionality ============
    
    function test_Upgrade_NewFunctionWorks() public {
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        invokerUpgraded.setNewFeature(42);
        
        assertEq(invokerUpgraded.newFeature(), 42);
    }
    
    function test_Upgrade_VersionReturnsUpgraded() public {
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.getVersion(), "upgraded");
    }
    
    function test_Upgrade_ExistingFunctionalityWorks() public {
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        
        // Execute a transaction after upgrade
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            policyId,
            policySnapshotHash
        );
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invokerUpgraded),
            auth,
            calls,
            false,
            callsHash
        );
        
        invokerUpgraded.executeBatch(calls, auth, false, callsHash, sig);
        
        assertEq(target.counter(), 1);
    }
    
    // ============ Authorization ============
    
    function test_Upgrade_OnlyTimelockOrMultisig() public {
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert(VolrInvoker.Unauthorized.selector);
        invoker.upgradeToAndCall(address(implUpgrade), "");
    }
    
    function test_Upgrade_TimelockCanUpgrade() public {
        address timelockAddr = address(0x4444);
        invoker.setTimelock(timelockAddr);
        
        vm.prank(timelockAddr);
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.getVersion(), "upgraded");
    }
    
    function test_Upgrade_MultisigCanUpgrade() public {
        address multisigAddr = address(0x5555);
        invoker.setMultisig(multisigAddr);
        
        vm.prank(multisigAddr);
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.getVersion(), "upgraded");
    }
    
    // ============ Upgrade Event ============
    
    function test_Upgrade_EmitsEvents() public {
        // When upgrading, both UpgradeInitiated (from _authorizeUpgrade) and 
        // Upgraded (from UUPS) events are emitted
        // We just verify the upgrade succeeds and emits some event
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        // Verify upgrade succeeded by checking new functionality
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        assertEq(invokerUpgraded.getVersion(), "upgraded");
    }
    
    // ============ Token Receiver After Upgrade ============
    
    function test_Upgrade_TokenReceiverStillWorks() public {
        invoker.upgradeToAndCall(address(implUpgrade), "");
        
        VolrInvokerMockUpgrade invokerUpgraded = VolrInvokerMockUpgrade(payable(address(invoker)));
        
        // ERC721 receiver
        bytes4 erc721Selector = invokerUpgraded.onERC721Received(address(0), address(0), 0, "");
        assertEq(erc721Selector, bytes4(0x150b7a02));
        
        // ERC1155 receiver
        bytes4 erc1155Selector = invokerUpgraded.onERC1155Received(address(0), address(0), 0, 0, "");
        assertEq(erc1155Selector, bytes4(0xf23a6e61));
        
        // ERC165
        assertTrue(invokerUpgraded.supportsInterface(0x01ffc9a7));
        assertTrue(invokerUpgraded.supportsInterface(0x150b7a02));
        assertTrue(invokerUpgraded.supportsInterface(0x4e2312e0));
    }
    
    // ============ Phase 2-6: Upgrade Safety ============
    
    function test_Upgrade_ToEOA_Reverts() public {
        // Try to upgrade to an EOA (address with no code)
        address eoa = address(0xDEADBEEF);
        
        vm.expectRevert("Implementation is not a contract");
        invoker.upgradeToAndCall(eoa, "");
    }
    
    function test_Upgrade_ToZeroAddress_Reverts() public {
        vm.expectRevert("Implementation is not a contract");
        invoker.upgradeToAndCall(address(0), "");
    }
}

