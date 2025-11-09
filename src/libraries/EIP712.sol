// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Types} from "./Types.sol";

library EIP712 {
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    
    bytes32 public constant SESSION_AUTH_TYPEHASH =
        keccak256("SessionAuth(bytes32 callsHash,bool revertOnFail,uint256 chainId,uint256 opNonce,uint64 expiry,bytes32 scopeId,bytes32 policyId,uint256 totalGasCap)");
    
    bytes32 public constant DOMAIN_NAME = keccak256("volr");
    bytes32 public constant DOMAIN_VERSION = keccak256("1");
    
    uint256 private constant SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    
    function domainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                DOMAIN_NAME,
                DOMAIN_VERSION,
                block.chainid,
                verifyingContract
            )
        );
    }
    
    function hashTypedDataV4(
        address verifyingContract,
        Types.SessionAuth memory auth
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SESSION_AUTH_TYPEHASH,
                auth.callsHash,
                auth.revertOnFail,
                auth.chainId,
                auth.opNonce,
                auth.expiry,
                auth.scopeId,
                auth.policyId,
                auth.totalGasCap
            )
        );
        
        bytes32 domainSeparator_ = domainSeparator(verifyingContract);
        
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator_, structHash));
    }
    
    function validateLowS(bytes32 s) internal pure returns (bool) {
        uint256 sValue = uint256(s);
        uint256 halfOrder = SECP256K1_ORDER / 2;
        return sValue <= halfOrder;
    }
}

