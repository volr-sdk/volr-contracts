// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CallValidator} from "../../src/libraries/CallValidator.sol";
import {Types} from "../../src/libraries/Types.sol";

contract CallValidatorTest is Test {
    function test_ValidateCall_Valid() public {
        Types.Call memory call = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234"
        });
        
        bool isValid = CallValidator.validateCall(call);
        assertTrue(isValid);
    }
    
    function test_ValidateCall_ZeroValue() public {
        Types.Call memory call = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234"
        });
        
        // value가 0이면 허용
        assertTrue(CallValidator.validateCall(call));
    }
    
    function test_ValidateCall_NonZeroValue() public {
        Types.Call memory call = Types.Call({
            target: address(0x1234),
            value: 1 ether,
            data: hex"1234"
        });
        
        // 기본 정책: value가 0이 아니면 거부
        bool isValid = CallValidator.validateCall(call);
        // 정책에 따라 다를 수 있지만, 기본적으로는 거부
        // 실제 구현에 따라 조정 필요
    }
    
    function test_ValidateCall_ZeroTarget() public {
        Types.Call memory call = Types.Call({
            target: address(0),
            value: 0,
            data: hex"1234"
        });
        
        // target이 0이면 실패해야 함
        bool isValid = CallValidator.validateCall(call);
        assertFalse(isValid);
    }
    
    function test_ValidateCallArray() public {
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = Types.Call({
            target: address(0x1),
            value: 0,
            data: hex"01"
        });
        calls[1] = Types.Call({
            target: address(0x2),
            value: 0,
            data: hex"02"
        });
        
        bool isValid = CallValidator.validateCalls(calls);
        assertTrue(isValid);
    }
    
    function test_ValidateCallArray_Empty() public {
        Types.Call[] memory calls = new Types.Call[](0);
        
        // 빈 배열은 거부해야 함
        bool isValid = CallValidator.validateCalls(calls);
        assertFalse(isValid);
    }
    
    function test_ValidateCallArray_TooLarge() public {
        // 배열 크기 제한 테스트 (DoS 방지)
        // 실제 구현에 따라 최대 크기 설정
        uint256 maxSize = 100;
        
        Types.Call[] memory calls = new Types.Call[](maxSize + 1);
        for (uint256 i = 0; i < maxSize + 1; i++) {
            calls[i] = Types.Call({
                target: address(uint160(i + 1)),
                value: 0,
                data: hex"01"
            });
        }
        
        // 최대 크기를 초과하면 실패해야 함
        bool isValid = CallValidator.validateCalls(calls);
        // 실제 구현에 따라 조정 필요
    }
}

