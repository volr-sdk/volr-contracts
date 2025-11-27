// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {VolrSponsor} from "../../src/sponsor/VolrSponsor.sol";
import {Types} from "../../src/libraries/Types.sol";

import {TestHelpers} from "../helpers/TestHelpers.sol";
import {SignatureHelper} from "../helpers/SignatureHelper.sol";
import {MockTarget} from "../helpers/MockContracts.sol";

/**
 * @title FullFlowTest
 * @notice Integration tests for the complete Volr flow
 */
contract FullFlowTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    PolicyRegistry public registry;
    ClientSponsor public clientSponsor;
    VolrSponsor public volrSponsor;
    MockTarget public target;
    
    address public owner;
    address public client;
    address public user;
    uint256 public userKey;
    bytes32 public policyId;
    bytes32 public policySnapshotHash;
    
    // Allow this contract to receive ETH (for gas refunds)
    receive() external payable {}
    
    function setUp() public {
        owner = address(this);
        client = address(0x1111);
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        policyId = keccak256("test-policy");
        
        // Deploy all contracts
        target = new MockTarget();
        policy = new ScopedPolicy();
        registry = TestHelpers.deployPolicyRegistry(owner);
        clientSponsor = TestHelpers.deployClientSponsor(owner);
        volrSponsor = TestHelpers.deployVolrSponsor(owner);
        
        // Configure registry
        registry.setTimelock(owner);
        registry.setMultisig(owner);
        registry.register(policyId, address(policy), "test-policy");
        
        // Deploy invoker with client sponsor
        invoker = TestHelpers.deployVolrInvoker(owner, address(registry), address(clientSponsor));
        invoker.setTimelock(owner);
        invoker.setMultisig(owner);
        
        // Configure policy
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        (, , , policySnapshotHash, ) = policy.policies(policyId);
        
        // Configure sponsors
        clientSponsor.setTimelock(owner);
        clientSponsor.setMultisig(owner);
        clientSponsor.setVolrSponsor(address(volrSponsor));
        clientSponsor.setInvoker(address(invoker)); // Set invoker for access control
        
        volrSponsor.setTimelock(owner);
        volrSponsor.setMultisig(owner);
        volrSponsor.setSubsidyRate(policyId, 2000); // 20% subsidy
        volrSponsor.setAuthorizedCaller(address(invoker), true); // Authorize invoker
        volrSponsor.setAuthorizedCaller(address(clientSponsor), true); // Authorize clientSponsor for compensateClient
        
        // Fund sponsors
        vm.deal(address(clientSponsor), 100 ether);
        vm.deal(address(volrSponsor), 100 ether);
        
        // Initialize client
        clientSponsor.depositAndInitialize{value: 10 ether}(client, policyId);
    }
    
    // ============ Full Flow Tests ============
    
    function test_FullFlow_SingleCall() public {
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
        
        uint256 clientBudgetBefore = clientSponsor.getBudget(client);
        
        // Act - Set tx.gasprice to simulate real transaction (Phase 2-1 fix uses tx.gasprice)
        vm.txGasPrice(1 gwei);
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(target.counter(), 1);
        // Budget should be reduced (gas was used, converted to wei via tx.gasprice)
        assertLt(clientSponsor.getBudget(client), clientBudgetBefore);
    }
    
    function test_FullFlow_MultipleCalls() public {
        // Arrange
        Types.Call[] memory calls = new Types.Call[](3);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        calls[1] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.incrementBy, (10))
        );
        calls[2] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.setCounter, (100))
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
        
        // Assert - last call sets counter to 100
        assertEq(target.counter(), 100);
    }
    
    function test_FullFlow_WithValue() public {
        // Arrange
        uint256 value = 0.5 ether;
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
        assertEq(address(target).balance, value);
    }
    
    function test_FullFlow_SequentialTransactions() public {
        // Execute multiple transactions sequentially with increasing nonces
        for (uint64 i = 1; i <= 5; i++) {
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
            auth.nonce = i;
            
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
        
        // Assert
        assertEq(target.counter(), 5);
    }
    
    // ============ Policy Validation Tests ============
    
    function test_FullFlow_PolicyWhitelist_AllowedPair() public {
        // Create a new policy with specific pair whitelist
        bytes32 restrictedPolicyId = keccak256("restricted-policy");
        policy.setPolicy(restrictedPolicyId, block.chainid, type(uint256).max, type(uint64).max, false);
        policy.setPair(restrictedPolicyId, address(target), MockTarget.increment.selector, true);
        bytes32 restrictedSnapshotHash;
        (, , , restrictedSnapshotHash, ) = policy.policies(restrictedPolicyId);
        
        registry.register(restrictedPolicyId, address(policy), "restricted");
        clientSponsor.addPolicy(client, restrictedPolicyId);
        
        // Map policy to client
        vm.deal(address(this), 1 ether);
        clientSponsor.depositAndInitialize{value: 1 ether}(client, restrictedPolicyId);
        
        // Arrange
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.increment, ())
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            restrictedPolicyId,
            restrictedSnapshotHash
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
    
    function test_FullFlow_PolicyWhitelist_DisallowedPair_Reverts() public {
        // Create a new policy with specific pair whitelist
        bytes32 restrictedPolicyId = keccak256("restricted-policy-2");
        policy.setPolicy(restrictedPolicyId, block.chainid, type(uint256).max, type(uint64).max, false);
        // Only allow increment, not incrementBy
        policy.setPair(restrictedPolicyId, address(target), MockTarget.increment.selector, true);
        bytes32 restrictedSnapshotHash;
        (, , , restrictedSnapshotHash, ) = policy.policies(restrictedPolicyId);
        
        registry.register(restrictedPolicyId, address(policy), "restricted-2");
        
        // Arrange - try to call incrementBy (not whitelisted)
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(target),
            abi.encodeCall(MockTarget.incrementBy, (5))
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            restrictedPolicyId,
            restrictedSnapshotHash
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
        
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(VolrInvoker.PolicyViolation.selector, 8));
        invoker.executeBatch(calls, auth, false, callsHash, sig);
    }
}

