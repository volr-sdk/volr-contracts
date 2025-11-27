// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {VolrSponsor} from "../../src/sponsor/VolrSponsor.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";

/**
 * @title TestHelpers
 * @notice Helper functions for testing upgradeable contracts
 */
library TestHelpers {
    /**
     * @notice Deploy and initialize PolicyRegistry via proxy
     */
    function deployPolicyRegistry(address owner) internal returns (PolicyRegistry) {
        PolicyRegistry impl = new PolicyRegistry();
        bytes memory initData = abi.encodeWithSelector(
            PolicyRegistry.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return PolicyRegistry(address(proxy));
    }
    
    /**
     * @notice Deploy and initialize ClientSponsor via proxy
     */
    function deployClientSponsor(address owner) internal returns (ClientSponsor) {
        ClientSponsor impl = new ClientSponsor();
        bytes memory initData = abi.encodeWithSelector(
            ClientSponsor.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return ClientSponsor(address(proxy));
    }
    
    /**
     * @notice Deploy and initialize VolrSponsor via proxy
     */
    function deployVolrSponsor(address owner) internal returns (VolrSponsor) {
        VolrSponsor impl = new VolrSponsor();
        bytes memory initData = abi.encodeWithSelector(
            VolrSponsor.initialize.selector,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return VolrSponsor(payable(address(proxy)));
    }
    
    /**
     * @notice Deploy and initialize VolrInvokerUpgradeable via proxy
     * @param owner Owner address for upgrade authorization
     * @param registry PolicyRegistry address
     * @param sponsor Sponsor address
     */
    function deployVolrInvoker(
        address owner,
        address registry,
        address sponsor
    ) internal returns (VolrInvoker) {
        VolrInvoker impl = new VolrInvoker();
        bytes memory initData = abi.encodeWithSelector(
            VolrInvoker.initialize.selector,
            registry,
            sponsor,
            owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return VolrInvoker(payable(address(proxy)));
    }
}

