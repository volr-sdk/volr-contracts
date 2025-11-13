// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VolrInvoker} from "../src/invoker/VolrInvoker.sol";

/**
 * @title DeployInvokerV2
 * @notice Deploys the updated VolrInvoker that aligns EIP-712 with the SDK.
 *
 * Env vars:
 * - PRIVATE_KEY        : Deployer private key (hex, no 0x prefix or with 0x)
 * - REGISTRY_ADDRESS   : Existing PolicyRegistry proxy address (required)
 *
 * Usage:
 *   forge script script/DeployInvokerV2.s.sol:DeployInvokerV2 \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract DeployInvokerV2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address registry = vm.envAddress("REGISTRY_ADDRESS");

        require(registry != address(0), "REGISTRY_ADDRESS is required");

        console.log("Deployer:", deployer);
        console.log("Balance :", deployer.balance);
        console.log("ChainId :", block.chainid);
        console.log("Registry:", registry);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy updated Invoker
        console.log("\n=== Deploying VolrInvoker V2 ===");
        VolrInvoker invoker = new VolrInvoker(registry);
        console.log("VolrInvoker V2:", address(invoker));

        vm.stopBroadcast();

        // Output snippets for backend/frontend configs
        console.log("\n=== Update your configs ===");
        console.log("Backend .env (JSON):");
        console.log('INVOKER_ADDRESS_MAP={"%s":"%s"}', block.chainid, address(invoker));
        console.log("\nDB networks.invokerAddress (chainId=%s):", block.chainid);
        console.log("%s", address(invoker));
        console.log("\nFrontend VolrProvider:");
        console.log('invokerAddressMap: { %s: "%s" }', block.chainid, address(invoker));
    }
}


