// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ClientSponsor} from "../src/sponsor/ClientSponsor.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeClientSponsor
 * @notice Upgrades ClientSponsor proxy to new implementation
 * @dev Run with: CLIENT_SPONSOR_PROXY=0x... forge script script/UpgradeClientSponsor.s.sol --rpc-url $RPC_URL --broadcast
 */
contract UpgradeClientSponsor is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Read proxy address from environment variable
        address clientSponsorProxy = vm.envAddress("CLIENT_SPONSOR_PROXY");
        require(clientSponsorProxy != address(0), "CLIENT_SPONSOR_PROXY env var not set");
        
        console.log("Deployer:", deployer);
        console.log("ClientSponsor Proxy:", clientSponsorProxy);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Check current state
        ClientSponsor proxy = ClientSponsor(payable(clientSponsorProxy));
        address currentOwner = proxy.owner();
        address currentTimelock = proxy.timelock();
        address currentMultisig = proxy.multisig();
        
        console.log("Current owner:", currentOwner);
        console.log("Current timelock:", currentTimelock);
        console.log("Current multisig:", currentMultisig);

        // 2. Set deployer as multisig if not set (required for upgrade authorization)
        if (currentMultisig == address(0)) {
            console.log("Setting deployer as multisig...");
            proxy.setMultisig(deployer);
            console.log("Multisig set to:", deployer);
        }

        // 3. Deploy new implementation
        console.log("Deploying new ClientSponsor implementation...");
        ClientSponsor newImpl = new ClientSponsor();
        console.log("New implementation deployed at:", address(newImpl));

        // 4. Upgrade proxy to new implementation
        console.log("Upgrading proxy to new implementation...");
        UUPSUpgradeable(clientSponsorProxy).upgradeToAndCall(
            address(newImpl),
            "" // No initialization call needed
        );
        console.log("Upgrade complete!");

        vm.stopBroadcast();
    }
}

