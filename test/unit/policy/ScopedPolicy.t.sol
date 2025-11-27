// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ScopedPolicy} from "../../../src/policy/ScopedPolicy.sol";
import {Types} from "../../../src/libraries/Types.sol";

/**
 * @title ScopedPolicyTest
 * @notice Unit tests for ScopedPolicy
 */
contract ScopedPolicyTest is Test {
    ScopedPolicy public policy;
    bytes32 public policyId;
    address public target;
    bytes4 public selector;
    
    function setUp() public {
        policy = new ScopedPolicy();
        policyId = keccak256("test-policy");
        target = address(0x1234);
        selector = bytes4(0x12345678);
    }
    
    // ============ Policy Configuration ============
    
    function test_SetPolicy_Basic() public {
        policy.setPolicy(policyId, block.chainid, 1 ether, 3600, false);
        
        (uint256 chainId, uint256 maxValue, uint64 maxExpiry, , bool allowAll) = policy.policies(policyId);
        
        assertEq(chainId, block.chainid);
        assertEq(maxValue, 1 ether);
        assertEq(maxExpiry, 3600);
        assertFalse(allowAll);
    }
    
    function test_SetPolicy_AllowAll() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        
        (, , , , bool allowAll) = policy.policies(policyId);
        assertTrue(allowAll);
    }
    
    function test_SetPolicy_EmitsEvent() public {
        // Note: snapshotHash is computed at setPolicy time, so we can't predict it exactly
        // Just verify the event is emitted with correct indexed params
        vm.expectEmit(true, false, false, false);
        emit ScopedPolicy.PolicySet(policyId, block.chainid, 1 ether, 3600, false, bytes32(0));
        
        policy.setPolicy(policyId, block.chainid, 1 ether, 3600, false);
    }
    
    // ============ Pair Configuration ============
    
    function test_SetPair_AllowsTargetSelector() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        policy.setPair(policyId, target, selector, true);
        
        assertTrue(policy.allowedPair(policyId, target, selector));
    }
    
    function test_SetPair_DisallowsTargetSelector() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        policy.setPair(policyId, target, selector, true);
        policy.setPair(policyId, target, selector, false);
        
        assertFalse(policy.allowedPair(policyId, target, selector));
    }
    
    function test_SetPair_UpdatesSnapshotHash() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        (, , , bytes32 hash1, ) = policy.policies(policyId);
        
        policy.setPair(policyId, target, selector, true);
        (, , , bytes32 hash2, ) = policy.policies(policyId);
        
        assertNotEq(hash1, hash2);
    }
    
    // ============ Contract Configuration ============
    
    function test_SetContract_AllowsAllSelectors() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        policy.setContract(policyId, target, true);
        
        assertTrue(policy.allowedContract(policyId, target));
    }
    
    // ============ Validation - AllowAll Mode ============
    
    function test_Validate_AllowAll_Success() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        // Use address(this) which has code, instead of target (0x1234) which is an EOA
        Types.Call[] memory calls = _createCalls(address(this), selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertTrue(ok);
        assertEq(code, 0);
    }
    
    function test_Validate_AllowAll_StillChecksChainId() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        auth.chainId = 9999; // Wrong chain
        Types.Call[] memory calls = _createCalls(target, selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 2); // Chain mismatch
    }
    
    function test_Validate_AllowAll_StillChecksExpiry() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        auth.expiresAt = uint64(block.timestamp - 1); // Expired
        Types.Call[] memory calls = _createCalls(target, selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 3); // Expired
    }
    
    function test_Validate_AllowAll_StillChecksTargetIsContract() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        address eoa = address(0x9999); // EOA, not contract
        Types.Call[] memory calls = _createCalls(eoa, selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 12); // Target not contract
    }
    
    // ============ Validation - Pair Mode ============
    
    function test_Validate_PairMode_AllowedPair_Success() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        policy.setPair(policyId, address(this), selector, true); // Use this contract as target
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        Types.Call[] memory calls = _createCalls(address(this), selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertTrue(ok);
        assertEq(code, 0);
    }
    
    function test_Validate_PairMode_DisallowedPair_Fails() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        // Don't set any pair
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        Types.Call[] memory calls = _createCalls(address(this), selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 8); // Pair not allowed
    }
    
    function test_Validate_ContractMode_AllSelectors_Success() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, false);
        policy.setContract(policyId, address(this), true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        Types.Call[] memory calls = _createCalls(address(this), bytes4(0xdeadbeef), 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertTrue(ok);
        assertEq(code, 0);
    }
    
    // ============ Validation - Value Limits ============
    
    function test_Validate_ValueExceedsMax_Fails() public {
        policy.setPolicy(policyId, block.chainid, 1 ether, type(uint64).max, true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        Types.Call[] memory calls = _createCalls(address(this), selector, 2 ether);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 6); // Value exceeds max
    }
    
    // ============ Validation - Snapshot Hash ============
    
    function test_Validate_WrongSnapshotHash_Fails() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        
        Types.SessionAuth memory auth = _createAuth(policyId, bytes32(0)); // Wrong hash
        Types.Call[] memory calls = _createCalls(address(this), selector, 0);
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 11); // Snapshot mismatch
    }
    
    // ============ Validation - Gas Cap ============
    
    function test_Validate_TotalGasExceedsCap_Fails() public {
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        bytes32 snapshotHash = _getSnapshotHash(policyId);
        
        Types.SessionAuth memory auth = _createAuth(policyId, snapshotHash);
        auth.totalGasCap = 100_000;
        
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = Types.Call({
            target: address(this),
            value: 0,
            data: abi.encodeWithSelector(selector),
            gasLimit: 60_000
        });
        calls[1] = Types.Call({
            target: address(this),
            value: 0,
            data: abi.encodeWithSelector(selector),
            gasLimit: 60_000
        });
        
        (bool ok, uint256 code) = policy.validate(auth, calls);
        
        assertFalse(ok);
        assertEq(code, 9); // Total gas exceeds cap
    }
    
    // ============ Helpers ============
    
    function _getSnapshotHash(bytes32 _policyId) internal view returns (bytes32 snapshotHash) {
        (, , , snapshotHash, ) = policy.policies(_policyId);
    }
    
    function _createAuth(
        bytes32 _policyId,
        bytes32 _snapshotHash
    ) internal view returns (Types.SessionAuth memory) {
        return Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(0x1111),
            sessionId: 0,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: _policyId,
            policySnapshotHash: _snapshotHash,
            gasLimitMax: 1_000_000,
            maxFeePerGas: 100 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 2_000_000
        });
    }
    
    function _createCalls(
        address _target,
        bytes4 _selector,
        uint256 _value
    ) internal pure returns (Types.Call[] memory) {
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: _target,
            value: _value,
            data: abi.encodeWithSelector(_selector),
            gasLimit: 100_000
        });
        return calls;
    }
}

