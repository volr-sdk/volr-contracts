// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";
import {Types} from "../../src/libraries/Types.sol";

contract EIP712Test is Test {
    function setUp() public {
        // 테스트용 체인 ID 설정
        vm.chainId(1);
    }
    
    function test_DomainSeparator() public {
        bytes32 domainSeparator = EIP712.domainSeparator(address(0x1234));
        
        // Domain separator는 0이 아니어야 함
        assertNotEq(domainSeparator, bytes32(0));
    }
    
    function test_DomainSeparator_Consistency() public {
        address verifyingContract = address(0x5678);
        bytes32 domain1 = EIP712.domainSeparator(verifyingContract);
        bytes32 domain2 = EIP712.domainSeparator(verifyingContract);
        
        // 같은 파라미터로 생성한 domain separator는 동일해야 함
        assertEq(domain1, domain2);
    }
    
    function test_DomainSeparator_DifferentContracts() public {
        bytes32 domain1 = EIP712.domainSeparator(address(0x1111));
        bytes32 domain2 = EIP712.domainSeparator(address(0x2222));
        
        // 다른 컨트랙트 주소는 다른 domain separator를 생성해야 함
        assertNotEq(domain1, domain2);
    }
    
    function test_HashTypedDataV4() public {
        address verifyingContract = address(0x1234);
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256("test"),
            revertOnFail: false,
            chainId: 1,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope")
        });
        
        bytes32 hash = EIP712.hashTypedDataV4(verifyingContract, auth);
        
        // 해시는 0이 아니어야 함
        assertNotEq(hash, bytes32(0));
    }
    
    function test_HashTypedDataV4_Consistency() public {
        address verifyingContract = address(0x1234);
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256("test"),
            revertOnFail: false,
            chainId: 1,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope")
        });
        
        bytes32 hash1 = EIP712.hashTypedDataV4(verifyingContract, auth);
        bytes32 hash2 = EIP712.hashTypedDataV4(verifyingContract, auth);
        
        // 같은 데이터로 생성한 해시는 동일해야 함
        assertEq(hash1, hash2);
    }
    
    function test_ValidateLowS() public {
        // low-S 값 (secp256k1_order/2 미만)
        bytes32 s = bytes32(uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0));
        
        bool isValid = EIP712.validateLowS(s);
        assertTrue(isValid);
    }
    
    function test_ValidateLowS_Invalid() public {
        // high-S 값 (secp256k1_order/2 이상)
        bytes32 s = bytes32(uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141));
        
        bool isValid = EIP712.validateLowS(s);
        assertFalse(isValid);
    }
}

