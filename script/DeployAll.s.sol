// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VolrInvoker} from "../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../src/registry/PolicyRegistry.sol";
import {ScopedPolicy} from "../src/policy/ScopedPolicy.sol";
import {ClientSponsor} from "../src/sponsor/ClientSponsor.sol";
import {VolrSponsor} from "../src/sponsor/VolrSponsor.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAll
 * @notice Deploy all Volr contracts: Registry, Invoker, Sponsors, Policy Impl.
 */
contract DeployAll is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        console.log("Deployer:", deployer);
        console.log("ChainId :", block.chainid);

        vm.startBroadcast(pk);

        // 1. PolicyRegistry (UUPS Proxy)
        console.log("\n=== 1. PolicyRegistry ===");
        PolicyRegistry registryImpl = new PolicyRegistry();
        bytes memory registryInit = abi.encodeWithSelector(
            PolicyRegistry.initialize.selector,
            deployer
        );
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), registryInit);
        PolicyRegistry registry = PolicyRegistry(address(registryProxy));
        console.log("Registry Proxy:", address(registry));

        // 2. VolrInvoker (Immutable) - Moved after ClientSponsor deployment
        // Invoker now depends on ClientSponsor address
        
        // 3. ScopedPolicy (Implementation only)
        console.log("\n=== 3. ScopedPolicy (Impl) ===");
        ScopedPolicy policyImpl = new ScopedPolicy();
        console.log("ScopedPolicy Impl:", address(policyImpl));

        // 4. ClientSponsor (UUPS Proxy)
        console.log("\n=== 4. ClientSponsor ===");
        ClientSponsor clientSponsorImpl = new ClientSponsor();
        bytes memory clientSponsorInit = abi.encodeWithSelector(
            ClientSponsor.initialize.selector,
            deployer
        );
        ERC1967Proxy clientSponsorProxy = new ERC1967Proxy(address(clientSponsorImpl), clientSponsorInit);
        ClientSponsor clientSponsor = ClientSponsor(payable(address(clientSponsorProxy)));
        console.log("ClientSponsor Proxy:", address(clientSponsor));

        // 2. VolrInvoker (Immutable) - Deployed after ClientSponsor
        console.log("\n=== 2. VolrInvoker ===");
        VolrInvoker invoker = new VolrInvoker(address(registry), address(clientSponsor));
        console.log("VolrInvoker:", address(invoker));

        // 5. VolrSponsor (UUPS Proxy)
        console.log("\n=== 5. VolrSponsor ===");
        VolrSponsor volrSponsorImpl = new VolrSponsor();
        bytes memory volrSponsorInit = abi.encodeWithSelector(
            VolrSponsor.initialize.selector,
            deployer
        );
        ERC1967Proxy volrSponsorProxy = new ERC1967Proxy(address(volrSponsorImpl), volrSponsorInit);
        VolrSponsor volrSponsor = VolrSponsor(payable(address(volrSponsorProxy)));
        console.log("VolrSponsor Proxy:", address(volrSponsor));

        // 6. Register Relayer in PolicyRegistry (if RELAYER_ADDRESS is set)
        console.log("\n=== 6. Register Relayer ===");
        bool hasRelayer = vm.envOr("RELAYER_ADDRESS", bytes32(0)) != bytes32(0);
        if (hasRelayer) {
            address relayerAddr = vm.envAddress("RELAYER_ADDRESS");
            registry.setRelayer(relayerAddr, true);
            console.log("Relayer registered:", relayerAddr);
        } else {
            console.log("RELAYER_ADDRESS not set, skipping relayer registration");
            console.log("Note: You can manually register relayer using PolicyRegistry.setRelayer(address, true)");
        }

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Network ID       : %s", block.chainid);
        console.log("PolicyRegistry   : %s", address(registry));
        console.log("VolrInvoker      : %s", address(invoker));
        console.log("ScopedPolicy Impl: %s", address(policyImpl));
        console.log("ClientSponsor    : %s", address(clientSponsor));
        console.log("VolrSponsor      : %s", address(volrSponsor));
        
        console.log("\n[Action Required] Update backend/DB with these addresses.");
    }
}
