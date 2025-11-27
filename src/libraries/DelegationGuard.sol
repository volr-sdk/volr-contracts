// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library DelegationGuard {
    bytes3 public constant EIP7702_PREFIX = 0xef0100;
    
    error DelegationNotAllowed();
    
    function isDelegated(address account) internal view returns (bool) {
        bytes memory code = account.code;
        if (code.length < 3) {
            return false;
        }
        
        // EIP-7702 delegation prefix 체크: 0xef0100
        return code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }
    
    modifier noEIP7702Delegation() {
        _checkNoEIP7702Delegation();
        _;
    }
    
    function _checkNoEIP7702Delegation() internal view {
        if (isDelegated(msg.sender)) {
            revert DelegationNotAllowed();
        }
    }
}

