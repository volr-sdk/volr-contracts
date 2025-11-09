// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Types} from "../libraries/Types.sol";

/**
 * @title IPolicy
 * @notice Interface for policy validation and execution hooks
 */
interface IPolicy {
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
    ) external view returns (bool ok, uint256 code);
    
    /**
     * @notice Hook called after successful execution
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
    ) external;
    
    /**
     * @notice Hook called after failed execution
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
    ) external;
}

