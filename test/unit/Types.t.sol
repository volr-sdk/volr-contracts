// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Types} from "../../src/libraries/Types.sol";

contract TypesTest is Test {
    function test_Call_Structure() public {
        Types.Call memory call = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234",
            gasLimit: 0
        });
        
        assertEq(call.target, address(0x1234));
        assertEq(call.value, 0);
        assertEq(call.data, hex"1234");
    }
    
    function test_SessionAuth_Structure() public {
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256("test"),
            revertOnFail: false,
            chainId: 1,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope"),
            policyId: keccak256("policy"),
            totalGasCap: 0
        });
        
        assertEq(auth.callsHash, keccak256("test"));
        assertEq(auth.revertOnFail, false);
        assertEq(auth.chainId, 1);
        assertEq(auth.opNonce, 1);
        assertEq(auth.expiry, uint64(block.timestamp + 3600));
        assertEq(auth.scopeId, keccak256("scope"));
    }
    
    function test_CallArray() public {
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = Types.Call({
            target: address(0x1),
            value: 0,
            data: hex"01",
            gasLimit: 0
        });
        calls[1] = Types.Call({
            target: address(0x2),
            value: 1 ether,
            data: hex"02",
            gasLimit: 0
        });
        
        assertEq(calls.length, 2);
        assertEq(calls[0].target, address(0x1));
        assertEq(calls[1].value, 1 ether);
    }
}

