// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20Permit} from "../src/mocks/MockERC20Permit.sol";

/**
 * @title DeployMockERC20Permit
 * @notice Deploy MockERC20Permit contract for testing
 * 
 * Usage:
 *   forge script script/DeployMockERC20Permit.s.sol --rpc-url $RPC_URL --broadcast
 * 
 * Environment variables:
 *   PRIVATE_KEY: Deployer private key
 *   TOKEN_NAME: Token name (optional, defaults to "Mock USDC")
 *   TOKEN_SYMBOL: Token symbol (optional, defaults to "MUSDC")
 */
contract DeployMockERC20Permit is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        
        string memory tokenName = vm.envOr("TOKEN_NAME", string("Mock USDC"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("MUSDC"));
        
        console.log("Deployer:", deployer);
        console.log("ChainId :", block.chainid);
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        
        vm.startBroadcast(pk);
        
        console.log("\n=== Deploying MockERC20Permit ===");
        MockERC20Permit token = new MockERC20Permit(tokenName, tokenSymbol);
        console.log("MockERC20Permit:", address(token));
        console.log("Decimals:", token.DECIMALS());
        console.log("Mint Amount:", token.MINT_AMOUNT());
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("Network ID    : %s", block.chainid);
        console.log("Token Address : %s", address(token));
        console.log("Token Name    : %s", tokenName);
        console.log("Token Symbol  : %s", tokenSymbol);
        console.log("Decimals      : %s", token.DECIMALS());
        console.log("Mint Amount   : %s", token.MINT_AMOUNT());
        
        console.log("\n[Usage] Call token.mintTo(address) to mint 100 tokens to any address.");
    }
}

