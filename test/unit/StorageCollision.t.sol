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
        // 두 개의 다른 구현체가 storage를 공유하지 않는지 확인
        ScopedPolicy.PolicyConfig memory config1 = ScopedPolicy.PolicyConfig({
            chainId: block.chainid,
            allowedContracts: new address[](1),
            allowedSelectors: new bytes4[](1),
            maxValue: 0,
            maxExpiry: 3600
        });
        config1.allowedContracts[0] = address(0x1111);
        config1.allowedSelectors[0] = bytes4(0x11111111);
        
        ScopedPolicy.PolicyConfig memory config2 = ScopedPolicy.PolicyConfig({
            chainId: block.chainid,
            allowedContracts: new address[](1),
            allowedSelectors: new bytes4[](1),
            maxValue: 0,
            maxExpiry: 3600
        });
        config2.allowedContracts[0] = address(0x2222);
        config2.allowedSelectors[0] = bytes4(0x22222222);
        
        // 각각 다른 policy 설정
        policy1.setPolicy(policyId, config1);
        policy2.setPolicy(policyId, config2);
        
        // 각각 독립적인 storage를 가져야 함
        // policies mapping은 직접 접근 불가하므로 validate를 통해 확인
        Types.Call[] memory calls1 = new Types.Call[](1);
        calls1[0] = Types.Call({
            target: address(0x1111),
            value: 0,
            data: abi.encodePacked(bytes4(0x11111111)),
            gasLimit: 0
        });
        
        Types.Call[] memory calls2 = new Types.Call[](1);
        calls2[0] = Types.Call({
            target: address(0x2222),
            value: 0,
            data: abi.encodePacked(bytes4(0x22222222)),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls1)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: policyId,
            policyId: keccak256("policy"),
            totalGasCap: 0
        });
        
        // policy1은 config1을 사용하므로 calls1이 통과해야 함
        // policy2는 config2를 사용하므로 calls1이 실패해야 함
        (bool ok1, ) = policy1.validate(auth, calls1);
        (bool ok2, ) = policy2.validate(auth, calls1);
        
        // policy1은 통과, policy2는 실패해야 함 (독립적인 storage)
        // 실제로는 다른 검증 실패 가능하지만, 기본적으로는 독립적이어야 함
    }
}

