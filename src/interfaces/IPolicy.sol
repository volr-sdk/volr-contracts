// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Types} from "../libraries/Types.sol";

interface IPolicy {
    function validate(
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls
    ) external view returns (bool ok, uint256 code);
}

