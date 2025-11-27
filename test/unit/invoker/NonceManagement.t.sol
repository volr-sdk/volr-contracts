// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry, IPolicyRegistry} from "../../../src/registry/PolicyRegistry.sol";
import {Types} from "../../../src/libraries/Types.sol";

import {TestHelpers} from "../../helpers/TestHelpers.sol";
import {SignatureHelper} from "../../helpers/SignatureHelper.sol";
import {MockTarget, MockSponsor} from "../../helpers/MockContracts.sol";

/**
 * @title NonceManagementTest
 * @notice Unit tests for nonce management in VolrInvoker
 */
contract NonceManagementTest is Test {
    VolrInvoker public invoker;
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
        
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        (, , , policySnapshotHash, ) = policy.policies(policyId);
    }
    
    function _executeWithNonce(uint64 nonce) internal {
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
        auth.nonce = nonce;
        
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
    }
    
    // ============ Nonce Increment ============
    
    function test_Nonce_IncrementsAfterExecution() public {
        // Arrange
        bytes32 channelKey = keccak256(abi.encode(user, policyId, uint64(0)));
        
        // Assert initial nonce
        assertEq(invoker.channelNonces(channelKey), 0);
        
        // Act
        _executeWithNonce(1);
        
        // Assert nonce updated
        assertEq(invoker.channelNonces(channelKey), 1);
    }
    
    function test_Nonce_CanSkipNonces() public {
        // Arrange
        bytes32 channelKey = keccak256(abi.encode(user, policyId, uint64(0)));
        
        // Act - skip from 0 to 100
        _executeWithNonce(100);
        
        // Assert
        assertEq(invoker.channelNonces(channelKey), 100);
        
        // Can use 101
        _executeWithNonce(101);
        assertEq(invoker.channelNonces(channelKey), 101);
    }
    
    function test_Nonce_SequentialExecution() public {
        // Arrange
        bytes32 channelKey = keccak256(abi.encode(user, policyId, uint64(0)));
        
        // Act - execute sequentially
        _executeWithNonce(1);
        _executeWithNonce(2);
        _executeWithNonce(3);
        
        // Assert
        assertEq(invoker.channelNonces(channelKey), 3);
        assertEq(target.counter(), 3);
    }
    
    // ============ Nonce Reuse Prevention ============
    
    function test_Nonce_ReuseReverts() public {
        // Arrange
        _executeWithNonce(1);
        
        // Act & Assert - try to reuse nonce 1
        vm.expectRevert(VolrInvoker.InvalidNonce.selector);
        _executeWithNonce(1);
    }
    
    function test_Nonce_LowerThanCurrentReverts() public {
        // Arrange
        _executeWithNonce(10);
        
        // Act & Assert - try to use lower nonce
        vm.expectRevert(VolrInvoker.InvalidNonce.selector);
        _executeWithNonce(5);
    }
    
    function test_Nonce_ZeroReverts() public {
        // Act & Assert - nonce 0 should fail (must be > 0)
        vm.expectRevert(VolrInvoker.InvalidNonce.selector);
        _executeWithNonce(0);
    }
    
    function test_Nonce_SameAsCurrentReverts() public {
        // Arrange
        _executeWithNonce(5);
        
        // Act & Assert - same nonce should fail
        vm.expectRevert(VolrInvoker.InvalidNonce.selector);
        _executeWithNonce(5);
    }
    
    // ============ Channel Independence ============
    
    function test_Nonce_DifferentPoliciesAreIndependent() public {
        // Arrange
        bytes32 policyId2 = keccak256("test-policy-2");
        policy.setPolicy(policyId2, block.chainid, type(uint256).max, type(uint64).max, true);
        bytes32 snapshotHash2;
        (, , , snapshotHash2, ) = policy.policies(policyId2);
        
        IPolicyRegistry registryInstance = invoker.registry();
        PolicyRegistry(address(registryInstance)).register(policyId2, address(policy), "test-policy-2");
        
        bytes32 channel1 = keccak256(abi.encode(user, policyId, uint64(0)));
        bytes32 channel2 = keccak256(abi.encode(user, policyId2, uint64(0)));
        
        // Act - use nonce 1 on policy 1
        _executeWithNonce(1);
        
        // Assert - policy 1 nonce is 1, policy 2 nonce is still 0
        assertEq(invoker.channelNonces(channel1), 1);
        assertEq(invoker.channelNonces(channel2), 0);
        
        // Act - use nonce 1 on policy 2 (should succeed)
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            policyId2,
            snapshotHash2
        );
        auth.nonce = 1;
        
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
        
        // Assert
        assertEq(invoker.channelNonces(channel2), 1);
    }
    
    function test_Nonce_DifferentSessionIdsAreIndependent() public {
        // Arrange
        bytes32 channel0 = keccak256(abi.encode(user, policyId, uint64(0)));
        bytes32 channel1 = keccak256(abi.encode(user, policyId, uint64(1)));
        
        // Act - use nonce 1 on session 0
        _executeWithNonce(1);
        
        // Assert - session 0 nonce is 1, session 1 nonce is still 0
        assertEq(invoker.channelNonces(channel0), 1);
        assertEq(invoker.channelNonces(channel1), 0);
        
        // Act - use nonce 1 on session 1
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
        auth.sessionId = 1;
        auth.nonce = 1;
        
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
        
        // Assert
        assertEq(invoker.channelNonces(channel1), 1);
    }
    
    function test_Nonce_DifferentUsersAreIndependent() public {
        // Arrange
        uint256 user2Key = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        address user2 = vm.addr(user2Key);
        
        bytes32 channel1 = keccak256(abi.encode(user, policyId, uint64(0)));
        bytes32 channel2 = keccak256(abi.encode(user2, policyId, uint64(0)));
        
        // Act - user 1 uses nonce 1
        _executeWithNonce(1);
        
        // Assert
        assertEq(invoker.channelNonces(channel1), 1);
        assertEq(invoker.channelNonces(channel2), 0);
        
        // Act - user 2 uses nonce 1 (should succeed)
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user2,
            policyId,
            policySnapshotHash
        );
        auth.nonce = 1;
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            user2Key,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(invoker.channelNonces(channel2), 1);
    }
}

