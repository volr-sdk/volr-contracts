// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library Signature {
    uint256 private constant SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    
    function validateYParity(uint8 v) internal pure returns (bool) {
        // y-parity는 0 또는 1이어야 함 (v는 27 또는 28이지만, 여기서는 변환된 값)
        return v == 0 || v == 1;
    }
    
    function validateRS(bytes32 r, bytes32 s) internal pure returns (bool) {
        uint256 rValue = uint256(r);
        uint256 sValue = uint256(s);
        
        // r과 s는 0이 아니어야 함
        if (rValue == 0 || sValue == 0) {
            return false;
        }
        
        // s는 secp256k1_order 미만이어야 함
        if (sValue >= SECP256K1_ORDER) {
            return false;
        }
        
        return true;
    }
    
    function recoverSigner(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        // EIP-712 hash는 이미 "\x19\x01" + domainSeparator + structHash 형태
        // v가 27 또는 28이어야 함 (vm.sign은 27 또는 28을 반환)
        uint8 vAdjusted = v >= 27 ? v : v + 27;
        
        // EIP-712 해시를 직접 사용 (추가 prefix 없음)
        return ecrecover(hash, vAdjusted, r, s);
    }

    function verifyCalldataSig(
        address expectedSigner,
        bytes32 digest,
        bytes calldata sig
    ) internal pure returns (bool) {
        if (sig.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        uint8 vAdjusted = v >= 27 ? v : v + 27;
        address recovered = ecrecover(digest, vAdjusted, r, s);
        return recovered == expectedSigner;
    }
}

