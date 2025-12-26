// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VolrInvoker} from "../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../src/registry/PolicyRegistry.sol";
import {ScopedPolicy} from "../src/policy/ScopedPolicy.sol";
import {ClientSponsor} from "../src/sponsor/ClientSponsor.sol";
import {VolrSponsor} from "../src/sponsor/VolrSponsor.sol";
import {PaymentRouter} from "../src/payment/PaymentRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAll
 * @notice Deploy all Volr contracts: Registry, Invoker (UUPS), Sponsors, Policy Impl.
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

        // 2. ScopedPolicy (Implementation only)
        console.log("\n=== 2. ScopedPolicy (Impl) ===");
        ScopedPolicy policyImpl = new ScopedPolicy();
        console.log("ScopedPolicy Impl:", address(policyImpl));

        // 3. ClientSponsor (UUPS Proxy)
        console.log("\n=== 3. ClientSponsor ===");
        ClientSponsor clientSponsorImpl = new ClientSponsor();
        bytes memory clientSponsorInit = abi.encodeWithSelector(
            ClientSponsor.initialize.selector,
            deployer
        );
        ERC1967Proxy clientSponsorProxy = new ERC1967Proxy(address(clientSponsorImpl), clientSponsorInit);
        ClientSponsor clientSponsor = ClientSponsor(payable(address(clientSponsorProxy)));
        console.log("ClientSponsor Proxy:", address(clientSponsor));

        // 4. VolrInvoker (Direct deployment - NO PROXY for EIP-7702)
        // EIP-7702: EOA delegates to contract bytecode directly, not through proxy
        // Proxy pattern doesn't work because EOA's storage is empty (no implementation slot)
        console.log("\n=== 4. VolrInvoker ===");
        VolrInvoker invoker = new VolrInvoker(
            address(registry),
            address(clientSponsor)
        );
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

        // 6. VolrInvoker has no admin functions (stateless, immutable references)
        console.log("\n=== 6. VolrInvoker Configuration ===");
        console.log("VolrInvoker is stateless - no admin configuration needed");
        console.log("Registry:", address(invoker.REGISTRY()));
        console.log("Sponsor:", address(invoker.SPONSOR()));

        // 7. Configure ClientSponsor (F1 fix: set invoker for access control)
        console.log("\n=== 7. Configure ClientSponsor ===");
        clientSponsor.setInvoker(address(invoker));
        clientSponsor.setVolrSponsor(address(volrSponsor));
        console.log("ClientSponsor invoker set to:", address(invoker));
        console.log("ClientSponsor volrSponsor set to:", address(volrSponsor));

        // 8. Configure VolrSponsor (F2 fix: authorize ClientSponsor as caller)
        console.log("\n=== 8. Configure VolrSponsor ===");
        volrSponsor.setAuthorizedCaller(address(clientSponsor), true);
        console.log("VolrSponsor authorized caller:", address(clientSponsor));

        // 9. PaymentRouter (for EIP-2612 permit payments)
        console.log("\n=== 9. PaymentRouter ===");
        // Fee recipient: address that receives fees from payments (should be Volr's operational wallet)
        address feeRecipient = vm.envOr("PAYMENT_ROUTER_FEE_RECIPIENT", address(0));
        // Owner: address that can call setFeeRecipient (should be multisig or separate admin address)
        address routerOwner = vm.envOr("PAYMENT_ROUTER_OWNER", address(0));
        
        // If not set, use deployer as default (for testing convenience)
        if (feeRecipient == address(0)) {
            feeRecipient = deployer;
            console.log("WARNING: Using deployer as feeRecipient (PAYMENT_ROUTER_FEE_RECIPIENT not set)");
        }
        if (routerOwner == address(0)) {
            routerOwner = deployer;
            console.log("WARNING: Using deployer as owner (PAYMENT_ROUTER_OWNER not set)");
        }
        
        PaymentRouter paymentRouter = new PaymentRouter(feeRecipient, routerOwner);
        console.log("PaymentRouter:", address(paymentRouter));
        console.log("Fee Recipient:", paymentRouter.feeRecipient());
        console.log("Owner:", paymentRouter.owner());

        // 10. Register Relayer in PolicyRegistry (if RELAYER_ADDRESS is set)
        console.log("\n=== 10. Register Relayer ===");
        address relayerAddr = vm.envOr("RELAYER_ADDRESS", address(0));
        bool hasRelayer = relayerAddr != address(0);
        if (hasRelayer) {
            registry.setRelayer(relayerAddr, true);
            console.log("Relayer registered:", relayerAddr);
        } else {
            console.log("RELAYER_ADDRESS not set, skipping relayer registration");
            console.log("Note: You can manually register relayer using PolicyRegistry.setRelayer(address, true)");
        }

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Network ID            : %s", block.chainid);
        console.log("PolicyRegistry (Proxy): %s", address(registry));
        console.log("VolrInvoker           : %s", address(invoker));
        console.log("ScopedPolicy (Impl)   : %s", address(policyImpl));
        console.log("ClientSponsor (Proxy) : %s", address(clientSponsor));
        console.log("VolrSponsor (Proxy)   : %s", address(volrSponsor));
        console.log("PaymentRouter         : %s", address(paymentRouter));
        
        console.log("\n[Action Required] Update backend/DB with these addresses.");
        console.log("[Note] VolrInvoker is NOT a proxy - direct contract for EIP-7702.");
        console.log("[Note] To upgrade VolrInvoker: deploy new contract, update backend invokerAddress.");
        console.log("[Note] PaymentRouter is optional - only needed for external wallet permit payments.");
    }
}
