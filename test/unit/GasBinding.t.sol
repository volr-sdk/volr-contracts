// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Types} from "../../src/libraries/Types.sol";

contract GasBindingTest is Test {
    function test_Call_WithGasLimit() public {
        Types.Call memory call = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234",
            gasLimit: 100000
        });
        
        assertEq(call.target, address(0x1234));
        assertEq(call.value, 0);
        assertEq(call.data, hex"1234");
        assertEq(call.gasLimit, 100000);
    }
    
    function test_Call_WithoutGasLimit() public {
        Types.Call memory call = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234",
            gasLimit: 0  // 0이면 제한 없음
        });
        
        assertEq(call.gasLimit, 0);
    }
    
    function test_SessionAuth_WithTotalGasCap() public {
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256("test"),
            revertOnFail: false,
            chainId: 1,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope"),
            policyId: keccak256("policy"),
            totalGasCap: 500000
        });
        
        assertEq(auth.totalGasCap, 500000);
    }
    
    function test_SessionAuth_WithoutTotalGasCap() public {
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256("test"),
            revertOnFail: false,
            chainId: 1,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope"),
            policyId: keccak256("policy"),
            totalGasCap: 0  // 0이면 제한 없음
        });
        
        assertEq(auth.totalGasCap, 0);
    }
}

