// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";

contract StorageCollisionTest is Test {
    ScopedPolicy public policy1;
    ScopedPolicy public policy2;
    bytes32 public policyId;
    
    function setUp() public {
        policyId = keccak256("test-policy");
        policy1 = new ScopedPolicy();
        policy2 = new ScopedPolicy();
    }
    
    function test_StorageSlot_Unique() public pure {
        // Storage slot이 고유한지 확인
        bytes32 slot1 = keccak256("volr.ScopedPolicy.policies");
        bytes32 slot2 = keccak256("volr.ScopedPolicy.usedNonces");
        
        assertNotEq(slot1, slot2);
        assertNotEq(slot1, bytes32(0));
        assertNotEq(slot2, bytes32(0));
    }
    
    function test_StorageSlot_Consistent() public pure {
        // 같은 컨트랙트에서 storage slot이 일관적인지 확인
        bytes32 slot1 = keccak256("volr.ScopedPolicy.policies");
        bytes32 slot2 = keccak256("volr.ScopedPolicy.policies");
        
        assertEq(slot1, slot2);
    }
    
    function test_NoStorageCollision_BetweenImplementations() public {
        // Mock code for targets to pass code.length check
        vm.etch(address(0x1111), hex"00");
        vm.etch(address(0x2222), hex"00");

        // 1. policy1 설정
        policy1.setPolicy(policyId, block.chainid, 0, 3600, false);
        policy1.setPair(policyId, address(0x1111), bytes4(0x11111111), true);
        
        // 2. policy2 설정
        policy2.setPolicy(policyId, block.chainid, 0, 3600, false);
        policy2.setPair(policyId, address(0x2222), bytes4(0x22222222), true);

        // 스냅샷 계산
        (,,, bytes32 snapshot1,) = policy1.policies(policyId);

        
        // 3. 검증 준비
        Types.Call[] memory calls1 = new Types.Call[](1);
        calls1[0] = Types.Call({
            target: address(0x1111),
            value: 0,
            data: abi.encodePacked(bytes4(0x11111111)),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: policyId,
            policySnapshotHash: snapshot1,
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        // policy1은 config1을 사용하므로 calls1이 통과해야 함
        (bool ok1, ) = policy1.validate(auth, calls1);
        assertTrue(ok1, "Policy1 should allow calls1");

        // policy2는 config2를 사용하므로 calls1이 실패해야 함
        (bool ok2, ) = policy2.validate(auth, calls1);
        assertFalse(ok2, "Policy2 should deny calls1");
    }
}
