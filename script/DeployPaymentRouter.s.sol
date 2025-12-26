// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PaymentRouter} from "../src/payment/PaymentRouter.sol";

/**
 * @title DeployPaymentRouter
 * @notice Deploy PaymentRouter contract for EIP-2612 permit-based payments
 * 
 * Usage:
 *   forge script script/DeployPaymentRouter.s.sol --rpc-url $RPC_URL --broadcast
 * 
 * Environment variables:
 *   PRIVATE_KEY: Deployer private key
 *   PAYMENT_ROUTER_FEE_RECIPIENT: Address to receive fees (optional, defaults to deployer)
 *   PAYMENT_ROUTER_OWNER: Contract owner address (optional, defaults to deployer)
 */
contract DeployPaymentRouter is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        
        // Fee recipient: address that receives fees from payments (should be Volr's operational wallet)
        address feeRecipient = vm.envOr("PAYMENT_ROUTER_FEE_RECIPIENT", address(0));
        // Owner: address that can call setFeeRecipient (should be multisig or separate admin address)
        address owner = vm.envOr("PAYMENT_ROUTER_OWNER", address(0));
        
        // If not set, use deployer as default (for testing convenience)
        if (feeRecipient == address(0)) {
            feeRecipient = deployer;
            console.log("WARNING: Using deployer as feeRecipient (PAYMENT_ROUTER_FEE_RECIPIENT not set)");
        }
        if (owner == address(0)) {
            owner = deployer;
            console.log("WARNING: Using deployer as owner (PAYMENT_ROUTER_OWNER not set)");
        }
        
        console.log("Deployer:", deployer);
        console.log("ChainId :", block.chainid);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Owner:", owner);
        
        vm.startBroadcast(pk);
        
        console.log("\n=== Deploying PaymentRouter ===");
        PaymentRouter router = new PaymentRouter(feeRecipient, owner);
        console.log("PaymentRouter:", address(router));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("Network ID    : %s", block.chainid);
        console.log("PaymentRouter : %s", address(router));
        console.log("Fee Recipient : %s", router.feeRecipient());
        console.log("Owner         : %s", router.owner());
        
        console.log("\n[Action Required] Update backend/DB with PaymentRouter address.");
        console.log("  Network.paymentRouterAddress = %s", address(router));
    }
}

