// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IPolicy} from "../interfaces/IPolicy.sol";
import {Types} from "../libraries/Types.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WhitelistPolicy
 * @notice Stateless policy that validates calls against a whitelist
 * @dev Only allows calls to whitelisted target addresses
 */
contract WhitelistPolicy is IPolicy, Ownable {
    mapping(address => bool) public whitelisted;

    // Error codes for validation failures
    uint256 constant TARGET_NOT_WHITELISTED = 1;

    error TargetNotWhitelisted(address target);
    
    event TargetAdded(address indexed target);
    event TargetRemoved(address indexed target);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Add a target address to whitelist
     * @param target Target address to whitelist
     */
    function addTarget(address target) external onlyOwner {
        whitelisted[target] = true;
        emit TargetAdded(target);
    }
    
    /**
     * @notice Remove a target address from whitelist
     * @param target Target address to remove
     */
    function removeTarget(address target) external onlyOwner {
        whitelisted[target] = false;
        emit TargetRemoved(target);
    }
    
    /**
     * @notice Validate session auth and calls
     * @param auth Session authorization data
     * @param calls Array of calls to validate
     * @return ok Whether validation passed
     * @return code Error code if validation failed
     */
    function validate(
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls
    ) external view override returns (bool ok, uint256 code) {
        // Validate that all call targets are whitelisted
        for (uint256 i = 0; i < calls.length; i++) {
            if (!whitelisted[calls[i].target]) {
                return (false, TARGET_NOT_WHITELISTED);
            }
        }
        return (true, 0);
    }
    
    /**
     * @notice Hook called after successful execution (no-op for stateless policy)
     * @param executor Address that executed the calls
     * @param auth Session authorization data
     * @param calls Array of calls that were executed
     * @param gasUsed Gas used for execution
     */
    function onExecuted(
        address executor,
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls,
        uint256 gasUsed
    ) external override {
        // No-op for stateless policy
    }
    
    /**
     * @notice Hook called after failed execution (no-op for stateless policy)
     * @param executor Address that executed the calls
     * @param auth Session authorization data
     * @param calls Array of calls that were executed
     * @param reason Revert reason
     */
    function onFailed(
        address executor,
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls,
        bytes calldata reason
    ) external override {
        // No-op for stateless policy
    }
}



