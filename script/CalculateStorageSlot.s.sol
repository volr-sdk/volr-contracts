// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title CalculateStorageSlot
 * @notice Script to calculate ERC-7201 storage slot
 * @dev Run with: forge script script/CalculateStorageSlot.s.sol -vvv
 */
contract CalculateStorageSlot is Script {
    function run() public pure {
        // ERC-7201 formula: keccak256(abi.encode(uint256(keccak256("namespace")) - 1)) & ~bytes32(uint256(0xff))
        
        string memory namespace = "volr.VolrInvoker.v1";
        
        // Step 1: keccak256 of namespace
        bytes32 step1 = keccak256(bytes(namespace));
        console.log("Step 1 - keccak256(namespace):");
        console.logBytes32(step1);
        
        // Step 2: Convert to uint256 and subtract 1
        uint256 step2 = uint256(step1) - 1;
        console.log("Step 2 - uint256(step1) - 1:");
        console.logBytes32(bytes32(step2));
        
        // Step 3: abi.encode and keccak256
        bytes32 step3 = keccak256(abi.encode(step2));
        console.log("Step 3 - keccak256(abi.encode(step2)):");
        console.logBytes32(step3);
        
        // Step 4: Mask with ~0xff
        bytes32 slot = step3 & ~bytes32(uint256(0xff));
        console.log("Step 4 - Final storage slot:");
        console.logBytes32(slot);
    }
}















