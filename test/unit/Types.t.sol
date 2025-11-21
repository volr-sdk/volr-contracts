// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Types} from "../../src/libraries/Types.sol";

contract TypesTest is Test {
    function test_Call_Structure() public pure {
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
    
    function test_SessionAuth_Structure() public view {
        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: 1,
            sessionKey: address(this),
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 3600),
            policyId: keccak256("policy"),
            policySnapshotHash: bytes32(0),
            gasLimitMax: 0,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            totalGasCap: 0
        });
        
        assertEq(auth.chainId, 1);
        assertEq(auth.nonce, 1);
        assertEq(auth.expiresAt, uint64(block.timestamp + 3600));
        assertEq(auth.policyId, keccak256("policy"));
    }
    
    function test_CallArray() public pure {
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
