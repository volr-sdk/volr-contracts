// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VolrInvoker} from "../src/invoker/VolrInvoker.sol";
import {PolicyRegistry, IPolicyRegistry} from "../src/registry/PolicyRegistry.sol";
import {WhitelistPolicy} from "../src/policy/WhitelistPolicy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAll
 * @notice One-shot deploy for Registry + WhitelistPolicy + Invoker
 *
 * Env:
 * - PRIVATE_KEY           (required)
 * - REGISTRY_ADDRESS      (optional) if provided, reuse existing registry
 * - WHITELIST_TARGET      (optional) single address to whitelist
 */
contract DeployAll is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        console.log("Deployer:", deployer);
        console.log("Balance :", deployer.balance);
        console.log("ChainId :", block.chainid);

        // Optional envs
        address existingRegistry = _envAddressOrZero("REGISTRY_ADDRESS");
        address whitelistTarget = _envAddressOrZero("WHITELIST_TARGET");

        vm.startBroadcast(pk);

        PolicyRegistry registry;

        if (existingRegistry != address(0)) {
            console.log("\n=== Using existing PolicyRegistry ===");
            registry = PolicyRegistry(existingRegistry);
            console.log("PolicyRegistry Proxy:", existingRegistry);
        } else {
            console.log("\n=== Deploying PolicyRegistry (UUPS) ===");
            PolicyRegistry impl = new PolicyRegistry();
            bytes memory initData = abi.encodeWithSelector(
                PolicyRegistry.initialize.selector,
                deployer
            );
            ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
            registry = PolicyRegistry(address(proxy));
            console.log("PolicyRegistry Impl :", address(impl));
            console.log("PolicyRegistry Proxy:", address(registry));

            // Governance shortcuts for dev/test
            registry.setTimelock(deployer);
            registry.setMultisig(deployer);
        }

        console.log("\n=== Deploying WhitelistPolicy ===");
        WhitelistPolicy policy = new WhitelistPolicy();
        console.log("WhitelistPolicy:", address(policy));

        console.log("\n=== Registering default policy ===");
        bytes32 defaultPolicyId = bytes32(0);
        IPolicyRegistry(address(registry)).register(defaultPolicyId, address(policy), "Default whitelist policy");

        if (whitelistTarget != address(0)) {
            console.log("\n=== Adding whitelist target ===");
            policy.addTarget(whitelistTarget);
            console.log("Added:", whitelistTarget);
        }

        console.log("\n=== Deploying VolrInvoker ===");
        VolrInvoker invoker = new VolrInvoker(address(registry));
        console.log("VolrInvoker:", address(invoker));

        vm.stopBroadcast();

        console.log("\n=== Summary ===");
        console.log("ChainId:", block.chainid);
        console.log("Registry:", address(registry));
        console.log("Policy  :", address(policy));
        console.log("Invoker :", address(invoker));
        console.log("\nBackend .env (JSON):");
        console.log('INVOKER_ADDRESS_MAP={"%s":"%s"}', block.chainid, address(invoker));
        console.log('POLICY_REGISTRY_ADDRESS_MAP={"%s":"%s"}', block.chainid, address(registry));
    }

    function _envAddressOrZero(string memory key) internal view returns (address) {
        try vm.envAddress(key) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }
}


