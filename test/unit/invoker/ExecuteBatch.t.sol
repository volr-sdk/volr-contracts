// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry} from "../../../src/registry/PolicyRegistry.sol";
import {Types} from "../../../src/libraries/Types.sol";

import {TestHelpers} from "../../helpers/TestHelpers.sol";
import {SignatureHelper} from "../../helpers/SignatureHelper.sol";
import {MockTarget, MockSponsor} from "../../helpers/MockContracts.sol";

/**
 * @title ExecuteBatchTest
 * @notice Unit tests for VolrInvoker.executeBatch
 */
contract ExecuteBatchTest is Test {
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
        
        // Deploy mock contracts
        target = new MockTarget();
        mockSponsor = new MockSponsor();
        policy = new ScopedPolicy();
        
        // Deploy registry and invoker
        PolicyRegistry registry = TestHelpers.deployPolicyRegistry(owner);
        registry.setTimelock(owner);
        registry.setMultisig(owner);
        registry.register(policyId, address(policy), "test-policy");
        
        invoker = TestHelpers.deployVolrInvoker(owner, address(registry), address(mockSponsor));
        invoker.setTimelock(owner);
        invoker.setMultisig(owner);
        
        // Configure policy with allowAll=true for simplicity
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        (, , , policySnapshotHash, ) = policy.policies(policyId);
    }
    
    // ============ Success Cases ============
    
    function test_ExecuteBatch_SingleCall_Success() public {
        // Arrange
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
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(target.counter(), 1);
    }
    
    function test_ExecuteBatch_MultipleCalls_Success() public {
        // Arrange
        Types.Call[] memory calls = new Types.Call[](3);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        calls[1] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.incrementBy, (5))
        );
        calls[2] = SignatureHelper.createCall(
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
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(target.counter(), 7); // 1 + 5 + 1
    }
    
    function test_ExecuteBatch_WithValue_Success() public {
        // Arrange
        uint256 value = 1 ether;
        vm.deal(address(this), value);
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCallWithValue(
            address(target),
            abi.encodeCall(MockTarget.payableIncrement, ()),
            value,
            200_000
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
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act
        invoker.executeBatch{value: value}(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(target.counter(), 1);
        assertEq(target.lastValue(), value);
    }
    
    function test_ExecuteBatch_EmitsEvent() public {
        // Arrange
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
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Assert - expect event
        vm.expectEmit(true, true, true, true);
        emit VolrInvoker.BatchExecuted(user, policyId, callsHash, policySnapshotHash, true);
        
        // Act
        invoker.executeBatch(calls, auth, false, callsHash, sig);
    }
    
    // ============ Failure Cases ============
    
    function test_ExecuteBatch_InvalidSignatureLength_Reverts() public {
        // Arrange
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
        
        // Use invalid signature length (not 65 bytes)
        bytes memory invalidSig = hex"1234";
        
        // Act & Assert
        vm.expectRevert("Invalid signature length");
        invoker.executeBatch(calls, auth, false, callsHash, invalidSig);
    }
    
    function test_ExecuteBatch_ExpiredSession_Reverts() public {
        // Arrange
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
        auth.expiresAt = uint64(block.timestamp - 1); // Already expired
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act & Assert
        vm.expectRevert(VolrInvoker.ExpiredSession.selector);
        invoker.executeBatch(calls, auth, false, callsHash, sig);
    }
    
    function test_ExecuteBatch_CallsHashMismatch_Reverts() public {
        // Arrange
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
        
        bytes32 wrongCallsHash = keccak256("wrong");
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            wrongCallsHash
        );
        
        // Act & Assert
        vm.expectRevert("Calls hash mismatch");
        invoker.executeBatch(calls, auth, false, wrongCallsHash, sig);
    }
    
    function test_ExecuteBatch_ZeroGasLimitMax_Reverts() public {
        // Arrange
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
        auth.gasLimitMax = 0;
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act & Assert
        vm.expectRevert("gasLimitMax=0");
        invoker.executeBatch(calls, auth, false, callsHash, sig);
    }
    
    function test_ExecuteBatch_TotalGasCapLessThanGasLimitMax_Reverts() public {
        // Arrange
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
        auth.gasLimitMax = 1_000_000;
        auth.totalGasCap = 500_000; // Less than gasLimitMax
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act & Assert
        vm.expectRevert("totalGasCap<gasLimitMax");
        invoker.executeBatch(calls, auth, false, callsHash, sig);
    }
    
    function test_ExecuteBatch_TargetNotContract_Reverts() public {
        // Arrange
        address eoa = address(0x1234);
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            eoa,
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
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Act & Assert - PolicyViolation code 12 means target is not a contract
        vm.expectRevert(abi.encodeWithSelector(VolrInvoker.PolicyViolation.selector, 12));
        invoker.executeBatch(calls, auth, false, callsHash, sig);
    }
    
    function test_ExecuteBatch_RevertOnFail_PropagatesRevert() public {
        // Arrange
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.alwaysRevert, ())
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
            address(invoker),
            auth,
            calls,
            true, // revertOnFail = true
            callsHash
        );
        
        // Act & Assert
        vm.expectRevert();
        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }
    
    function test_ExecuteBatch_NoRevertOnFail_ContinuesExecution() public {
        // Arrange
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.alwaysRevert, ())
        );
        calls[1] = SignatureHelper.createCall(
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
            address(invoker),
            auth,
            calls,
            false, // revertOnFail = false
            callsHash
        );
        
        // Act
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert - second call should have executed
        assertEq(target.counter(), 1);
    }
}

