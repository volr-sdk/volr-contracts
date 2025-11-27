// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";

/**
 * @title StorageSlotTest
 * @notice Test to output the calculated ERC-7201 storage slot
 * @dev Run with: forge test --match-test test_CalculateSlotDirectly -vvv
 */
contract StorageSlotTest is Test {
    function test_CalculateSlotDirectly() public pure {
        // Calculate directly in the test
        bytes32 step1 = keccak256("volr.VolrInvoker.v1");
        console.log("Step 1 - keccak256(namespace):");
        console.logBytes32(step1);
        
        uint256 step2 = uint256(step1) - 1;
        console.log("Step 2 - uint256(step1) - 1:");
        console.logBytes32(bytes32(step2));
        
        bytes32 step3 = keccak256(abi.encode(step2));
        console.log("Step 3 - keccak256(abi.encode(step2)):");
        console.logBytes32(step3);
        
        bytes32 slot = step3 & ~bytes32(uint256(0xff));
        console.log("Step 4 - Final slot (masked):");
        console.logBytes32(slot);
    }
}

