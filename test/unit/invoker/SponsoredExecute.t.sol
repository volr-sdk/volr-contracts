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
 * @title SponsoredExecuteTest
 * @notice Unit tests for VolrInvoker.sponsoredExecute
 */
contract SponsoredExecuteTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    MockTarget public target;
    MockSponsor public mockSponsor;
    
    address public owner;
    address public user;
    uint256 public userKey;
    address public sponsorAddr;
    uint256 public sponsorKey;
    bytes32 public policyId;
    bytes32 public policySnapshotHash;
    
    function setUp() public {
        owner = address(this);
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        sponsorKey = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        sponsorAddr = vm.addr(sponsorKey);
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
    }
    
    function _createVoucher(
        Types.SessionAuth memory auth
    ) internal view returns (VolrInvoker.SponsorVoucher memory) {
        return VolrInvoker.SponsorVoucher({
            sponsor: sponsorAddr,
            policyId: auth.policyId,
            policySnapshotHash: auth.policySnapshotHash,
            sessionId: auth.sessionId,
            nonce: auth.nonce,
            expiresAt: auth.expiresAt,
            gasLimitMax: auth.gasLimitMax,
            maxFeePerGas: auth.maxFeePerGas,
            maxPriorityFeePerGas: auth.maxPriorityFeePerGas,
            totalGasCap: auth.totalGasCap
        });
    }
    
    // ============ Success Cases ============
    
    function test_SponsoredExecute_Success() public {
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
        
        VolrInvoker.SponsorVoucher memory voucher = _createVoucher(auth);
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sessionSig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        bytes memory sponsorSig = SignatureHelper.signSponsorVoucher(
            sponsorKey,
            block.chainid,
            address(invoker),
            voucher.sponsor,
            voucher.policyId,
            voucher.policySnapshotHash,
            voucher.sessionId,
            voucher.nonce,
            voucher.expiresAt,
            voucher.gasLimitMax,
            voucher.maxFeePerGas,
            voucher.maxPriorityFeePerGas,
            voucher.totalGasCap
        );
        
        // Act
        invoker.sponsoredExecute(
            calls,
            auth,
            voucher,
            false,
            callsHash,
            sessionSig,
            sponsorSig
        );
        
        // Assert
        assertEq(target.counter(), 1);
    }
    
    function test_SponsoredExecute_EmitsEvent() public {
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
        
        VolrInvoker.SponsorVoucher memory voucher = _createVoucher(auth);
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sessionSig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        bytes memory sponsorSig = SignatureHelper.signSponsorVoucher(
            sponsorKey,
            block.chainid,
            address(invoker),
            voucher.sponsor,
            voucher.policyId,
            voucher.policySnapshotHash,
            voucher.sessionId,
            voucher.nonce,
            voucher.expiresAt,
            voucher.gasLimitMax,
            voucher.maxFeePerGas,
            voucher.maxPriorityFeePerGas,
            voucher.totalGasCap
        );
        
        // Assert - expect event
        vm.expectEmit(true, true, true, true);
        emit VolrInvoker.SponsoredExecuted(
            user,
            sponsorAddr,
            policyId,
            callsHash,
            policySnapshotHash,
            true
        );
        
        // Act
        invoker.sponsoredExecute(
            calls,
            auth,
            voucher,
            false,
            callsHash,
            sessionSig,
            sponsorSig
        );
    }
    
    // ============ Failure Cases ============
    
    function test_SponsoredExecute_ZeroSponsor_Reverts() public {
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
        
        VolrInvoker.SponsorVoucher memory voucher = _createVoucher(auth);
        voucher.sponsor = address(0); // Zero address
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sessionSig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        bytes memory sponsorSig = hex"00"; // Dummy sig
        
        // Act & Assert
        vm.expectRevert("no sponsor");
        invoker.sponsoredExecute(
            calls,
            auth,
            voucher,
            false,
            callsHash,
            sessionSig,
            sponsorSig
        );
    }
    
    function test_SponsoredExecute_PolicyIdMismatch_Reverts() public {
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
        
        VolrInvoker.SponsorVoucher memory voucher = _createVoucher(auth);
        voucher.policyId = keccak256("different-policy"); // Mismatched
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sessionSig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        bytes memory sponsorSig = SignatureHelper.signSponsorVoucher(
            sponsorKey,
            block.chainid,
            address(invoker),
            voucher.sponsor,
            voucher.policyId,
            voucher.policySnapshotHash,
            voucher.sessionId,
            voucher.nonce,
            voucher.expiresAt,
            voucher.gasLimitMax,
            voucher.maxFeePerGas,
            voucher.maxPriorityFeePerGas,
            voucher.totalGasCap
        );
        
        // Act & Assert
        vm.expectRevert("policyId mismatch");
        invoker.sponsoredExecute(
            calls,
            auth,
            voucher,
            false,
            callsHash,
            sessionSig,
            sponsorSig
        );
    }
    
    function test_SponsoredExecute_NonceMismatch_Reverts() public {
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
        
        VolrInvoker.SponsorVoucher memory voucher = _createVoucher(auth);
        voucher.nonce = auth.nonce + 1; // Mismatched nonce
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sessionSig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        bytes memory sponsorSig = SignatureHelper.signSponsorVoucher(
            sponsorKey,
            block.chainid,
            address(invoker),
            voucher.sponsor,
            voucher.policyId,
            voucher.policySnapshotHash,
            voucher.sessionId,
            voucher.nonce,
            voucher.expiresAt,
            voucher.gasLimitMax,
            voucher.maxFeePerGas,
            voucher.maxPriorityFeePerGas,
            voucher.totalGasCap
        );
        
        // Act & Assert
        vm.expectRevert("nonce mismatch");
        invoker.sponsoredExecute(
            calls,
            auth,
            voucher,
            false,
            callsHash,
            sessionSig,
            sponsorSig
        );
    }
    
    function test_SponsoredExecute_InvalidSponsorSig_Reverts() public {
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
        
        VolrInvoker.SponsorVoucher memory voucher = _createVoucher(auth);
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sessionSig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Sign with wrong key
        uint256 wrongKey = 0xdead;
        bytes memory sponsorSig = SignatureHelper.signSponsorVoucher(
            wrongKey,
            block.chainid,
            address(invoker),
            voucher.sponsor,
            voucher.policyId,
            voucher.policySnapshotHash,
            voucher.sessionId,
            voucher.nonce,
            voucher.expiresAt,
            voucher.gasLimitMax,
            voucher.maxFeePerGas,
            voucher.maxPriorityFeePerGas,
            voucher.totalGasCap
        );
        
        // Act & Assert
        vm.expectRevert("invalid sponsorSig");
        invoker.sponsoredExecute(
            calls,
            auth,
            voucher,
            false,
            callsHash,
            sessionSig,
            sponsorSig
        );
    }
}

