// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DelegationGuard} from "../../src/libraries/DelegationGuard.sol";

contract DelegationGuardTest is Test {
    function test_IsDelegated_EOA() public view {
        address eoa = address(0x1234);
        bool isDelegated = DelegationGuard.isDelegated(eoa);
        assertFalse(isDelegated);
    }
    
    function test_IsDelegated_Contract() public {
        // 일반 컨트랙트는 delegation이 아님
        DummyContract dummy = new DummyContract();
        bool isDelegated = DelegationGuard.isDelegated(address(dummy));
        assertFalse(isDelegated);
    }
    
    function test_IsDelegated_DelegatedEOA() public {
        // EIP-7702 delegation 시뮬레이션
        address delegatedEOA = address(0x5678);
        
        // Delegation bytecode 생성: 0xef0100 + 20 bytes address
        bytes memory delegationCode = abi.encodePacked(
            bytes3(0xef0100),
            bytes20(address(0x9999))
        );
        
        vm.etch(delegatedEOA, delegationCode);
        
        bool isDelegated = DelegationGuard.isDelegated(delegatedEOA);
        assertTrue(isDelegated);
    }
    
    function test_IsDelegated_ShortCode() public view {
        // 코드가 3바이트 미만인 경우
        address shortCode = address(0x1111);
        bool isDelegated = DelegationGuard.isDelegated(shortCode);
        assertFalse(isDelegated);
    }
}

contract DummyContract {
    function dummy() public pure returns (uint256) {
        return 1;
    }
}

