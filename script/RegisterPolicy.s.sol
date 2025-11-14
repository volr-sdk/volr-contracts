// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
// Import the registry contract directly
import {PolicyRegistry} from "../src/registry/PolicyRegistry.sol";

/**
 * @title RegisterPolicy
 * @notice Register WhitelistPolicy with PolicyRegistry
 * @dev Usage: POLICY_REGISTRY=<registry_address> WHITELIST_POLICY=<policy_address> forge script script/RegisterPolicy.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract RegisterPolicy is Script {
    function run() external {
        address registryAddress = vm.envAddress("POLICY_REGISTRY");
        address policyAddress = vm.envAddress("WHITELIST_POLICY");

        require(registryAddress != address(0), "POLICY_REGISTRY not set");
        require(policyAddress != address(0), "WHITELIST_POLICY not set");

        PolicyRegistry registry = PolicyRegistry(registryAddress);

        console.log("Registering WhitelistPolicy...");
        console.log("Registry:", registryAddress);
        console.log("Policy:", policyAddress);

        vm.startBroadcast();

        // Register default policy (bytes32(0))
        registry.register(bytes32(0), policyAddress, "Default whitelist policy");

        console.log("Policy registered successfully!");

        vm.stopBroadcast();
    }
}
