// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {WhitelistPolicy} from "../src/policy/WhitelistPolicy.sol";

/**
 * @title ConfigureWhitelist
 * @notice Configure WhitelistPolicy after deployment
 * @dev Adds contract addresses to whitelist
 * 
 * Usage:
 *   WHITELIST_POLICY_ADDRESS=0x... forge script script/ConfigureWhitelist.s.sol:ConfigureWhitelist \
 *     --rpc-url citrea_testnet --broadcast -vvvv
 */
contract ConfigureWhitelist is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address whitelistPolicyAddress = vm.envAddress("WHITELIST_POLICY_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        WhitelistPolicy whitelistPolicy = WhitelistPolicy(whitelistPolicyAddress);
        
        // TODO: 여기에 허용할 컨트랙트 주소들을 추가하세요
        // 예시:
        // whitelistPolicy.addTarget(0x1234567890123456789012345678901234567890);
        // whitelistPolicy.addTarget(0xabcdefabcdefabcdefabcdefabcdefabcdefabcd);
        
        console.log("WhitelistPolicy address:", whitelistPolicyAddress);
        console.log("Whitelist configured successfully");
        console.log("\n=== Next Steps ===");
        console.log("Add contract addresses to whitelist by calling:");
        console.log("  whitelistPolicy.addTarget(address)");
        
        vm.stopBroadcast();
    }
}

