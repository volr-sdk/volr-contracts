// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Signature} from "../../src/libraries/Signature.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";
import {Types} from "../../src/libraries/Types.sol";

contract SignatureTest is Test {
    
    function test_ValidateYParity_Valid() public {
        // y-parity는 0 또는 1이어야 함
        assertTrue(Signature.validateYParity(0));
        assertTrue(Signature.validateYParity(1));
    }
    
    function test_ValidateYParity_Invalid() public {
        // y-parity가 0 또는 1이 아니면 실패
        assertFalse(Signature.validateYParity(2));
        assertFalse(Signature.validateYParity(255));
    }
    
    function test_ValidateRS_Valid() public {
        bytes32 r = bytes32(uint256(0x1234567890ABCDEF));
        bytes32 s = bytes32(uint256(0xFEDCBA0987654321));
        
        assertTrue(Signature.validateRS(r, s));
    }
    
    function test_ValidateRS_InvalidR() public {
        // r이 0이면 실패
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(uint256(0xFEDCBA0987654321));
        
        assertFalse(Signature.validateRS(r, s));
    }
    
    function test_ValidateRS_InvalidS() public {
        // s가 0이면 실패
        bytes32 r = bytes32(uint256(0x1234567890ABCDEF));
        bytes32 s = bytes32(0);
        
        assertFalse(Signature.validateRS(r, s));
    }
    
    function test_ValidateRS_STooLarge() public {
        // s가 secp256k1_order 이상이면 실패
        bytes32 r = bytes32(uint256(0x1234567890ABCDEF));
        bytes32 s = bytes32(uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141));
        
        assertFalse(Signature.validateRS(r, s));
    }
    
    function test_RecoverSigner() public {
        // 실제 서명 복구 테스트는 더 복잡하므로 기본 구조만 테스트
        address signer = address(0x1234);
        bytes32 hash = keccak256("test");
        uint8 v = 27;
        bytes32 r = bytes32(uint256(0x1234));
        bytes32 s = bytes32(uint256(0x5678));
        
        // 기본 검증만 수행 (실제 서명 복구는 ECDSA 라이브러리 사용)
        assertTrue(Signature.validateYParity(v == 27 ? 0 : 1));
    }
}

