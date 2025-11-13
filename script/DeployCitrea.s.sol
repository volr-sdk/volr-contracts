// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VolrInvoker} from "../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../src/registry/PolicyRegistry.sol";
import {WhitelistPolicy} from "../src/policy/WhitelistPolicy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployVolrContracts
 * @notice Deploy Volr contracts to Citrea testnet
 * @dev Deploys: PolicyRegistry (UUPS Proxy), WhitelistPolicy, VolrInvoker
 * 
 * Usage:
 *   forge script script/DeployCitrea.s.sol:DeployVolrContracts --rpc-url citrea_testnet --broadcast --verify
 */
contract DeployVolrContracts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy PolicyRegistry Implementation
        console.log("\n=== Deploying PolicyRegistry Implementation ===");
        PolicyRegistry registryImpl = new PolicyRegistry();
        console.log("PolicyRegistry Implementation:", address(registryImpl));
        
        // 2. Deploy PolicyRegistry Proxy
        console.log("\n=== Deploying PolicyRegistry Proxy ===");
        bytes memory initData = abi.encodeWithSelector(
            PolicyRegistry.initialize.selector,
            deployer // initial owner
        );
        ERC1967Proxy registryProxy = new ERC1967Proxy(
            address(registryImpl),
            initData
        );
        PolicyRegistry registry = PolicyRegistry(address(registryProxy));
        console.log("PolicyRegistry Proxy:", address(registry));
        
        // 2.5. Set timelock and multisig to deployer (for testing)
        // In production, these should be separate governance addresses
        console.log("\n=== Setting timelock and multisig ===");
        registry.setTimelock(deployer);
        registry.setMultisig(deployer);
        console.log("Timelock and multisig set to deployer:", deployer);
        
        // 3. Deploy WhitelistPolicy (simpler than ScopedPolicy for testing)
        console.log("\n=== Deploying WhitelistPolicy ===");
        WhitelistPolicy whitelistPolicy = new WhitelistPolicy();
        console.log("WhitelistPolicy:", address(whitelistPolicy));
        
        // 4. Register default policy (all zeros = default)
        console.log("\n=== Registering default policy ===");
        bytes32 defaultPolicyId = bytes32(0);
        // Note: register() requires timelock or multisig, which we set above
        registry.register(defaultPolicyId, address(whitelistPolicy), "Default whitelist policy");
        console.log("Default policy registered:", vm.toString(defaultPolicyId));
        
        // 5. Note: WhitelistPolicy requires targets to be added after deployment
        // You can add targets using: whitelistPolicy.addTarget(address)
        console.log("\n=== Note: Whitelist Configuration Required ===");
        console.log("WhitelistPolicy requires targets to be added after deployment.");
        console.log("Call whitelistPolicy.addTarget(address) to allow contract addresses.");
        
        // 6. Deploy VolrInvoker
        console.log("\n=== Deploying VolrInvoker ===");
        VolrInvoker invoker = new VolrInvoker(address(registry));
        console.log("VolrInvoker:", address(invoker));
        
        vm.stopBroadcast();
        
        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("PolicyRegistry Proxy:", address(registry));
        console.log("PolicyRegistry Implementation:", address(registryImpl));
        console.log("WhitelistPolicy:", address(whitelistPolicy));
        console.log("VolrInvoker:", address(invoker));
        console.log("\n=== Configuration ===");
        console.log("1. Backend .env:");
        console.log("   INVOKER_ADDRESS_MAP={\"%s\":\"%s\"}", block.chainid, address(invoker));
        console.log("\n2. Frontend VolrProvider config:");
        console.log("   invokerAddressMap: { %s: \"%s\" }", block.chainid, address(invoker));
        console.log("\n3. RPC URL:");
        console.log("   https://rpc.testnet.citrea.xyz");
    }
}

