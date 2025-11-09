// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Types} from "./Types.sol";

library CallValidator {
    uint256 public constant MAX_CALLS = 100;
    
    function validateCall(Types.Call memory call) internal pure returns (bool) {
        // target이 0이면 실패
        if (call.target == address(0)) {
            return false;
        }
        
        // 기본 정책: value는 0만 허용 (정책에 따라 변경 가능)
        // 여기서는 기본 검증만 수행하고, 실제 value 검증은 Policy에서 수행
        
        return true;
    }
    
    function validateCalls(Types.Call[] memory calls) internal pure returns (bool) {
        // 빈 배열은 거부
        if (calls.length == 0) {
            return false;
        }
        
        // 배열 크기 제한 (DoS 방지)
        if (calls.length > MAX_CALLS) {
            return false;
        }
        
        // 각 call 검증
        for (uint256 i = 0; i < calls.length; i++) {
            if (!validateCall(calls[i])) {
                return false;
            }
        }
        
        return true;
    }
    
    function containsDangerousOpcode(bytes memory data) internal pure returns (bool) {
        // 위험한 opcode 검증
        // delegatecall: 0xf4
        // callcode: 0xf2
        // selfdestruct: 0xff
        // tx.origin: 0x32
        
        // 간단한 검증: delegatecall, selfdestruct 등이 포함되어 있는지 확인
        // 실제로는 더 정교한 검증이 필요할 수 있음
        
        for (uint256 i = 0; i < data.length; i++) {
            uint8 opcode = uint8(data[i]);
            // delegatecall (0xf4) 또는 selfdestruct (0xff) 검증
            if (opcode == 0xf4 || opcode == 0xff) {
                return true;
            }
        }
        
        return false;
    }
}

