// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WhitelistPolicy} from "../src/policy/WhitelistPolicy.sol";

/**
 * @title AddToWhitelist
 * @notice Add addresses to WhitelistPolicy
 * @dev Usage: WHITELIST_POLICY=<policy_address> TARGETS=<comma_separated_addresses> forge script script/AddToWhitelist.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract AddToWhitelist is Script {
    function run() external {
        address policyAddress = vm.envAddress("WHITELIST_POLICY");
        require(policyAddress != address(0), "WHITELIST_POLICY not set");

        string memory targetsStr = vm.envString("TARGETS");
        require(bytes(targetsStr).length > 0, "TARGETS not set");

        WhitelistPolicy policy = WhitelistPolicy(policyAddress);

        // Parse comma-separated addresses
        string[] memory parts = split(targetsStr, ',');
        address[] memory targets = new address[](parts.length);

        for (uint256 i = 0; i < parts.length; i++) {
            targets[i] = parseAddress(parts[i]);
            console.log("Adding target:", targets[i]);
        }

        vm.startBroadcast();

        for (uint256 i = 0; i < targets.length; i++) {
            policy.addTarget(targets[i]);
            console.log("Added to whitelist:", targets[i]);
        }

        vm.stopBroadcast();
    }

    function parseAddress(string memory s) internal pure returns (address) {
        bytes memory ss = bytes(s);
        require(ss.length == 42, "Invalid address length");
        require(ss[0] == '0' && ss[1] == 'x', "Address must start with 0x");

        uint160 addr;
        for (uint256 i = 2; i < 42; i++) {
            uint8 b = uint8(ss[i]);
            if (b >= 48 && b <= 57) {
                b -= 48;
            } else if (b >= 65 && b <= 70) {
                b -= 55;
            } else if (b >= 97 && b <= 102) {
                b -= 87;
            } else {
                revert("Invalid hex character");
            }
            addr |= uint160(b) << (4 * (41 - i));
        }
        return address(addr);
    }

    function split(string memory s, bytes1 delimiter) internal pure returns (string[] memory) {
        uint256 count = 1;
        for (uint256 i = 0; i < bytes(s).length; i++) {
            if (bytes(s)[i] == delimiter) {
                count++;
            }
        }

        string[] memory parts = new string[](count);
        uint256 partIndex = 0;
        uint256 start = 0;

        for (uint256 i = 0; i <= bytes(s).length; i++) {
            if (i == bytes(s).length || bytes(s)[i] == delimiter) {
                bytes memory part = new bytes(i - start);
                for (uint256 j = start; j < i; j++) {
                    part[j - start] = bytes(s)[j];
                }
                parts[partIndex++] = string(part);
                start = i + 1;
            }
        }

        return parts;
    }
}



