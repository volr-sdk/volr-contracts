// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Types} from "../libraries/Types.sol";

interface IInvoker {
    function executeBatch(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        bytes calldata sig
    ) external payable;
    
    function sponsoredExecute(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        bytes calldata sig,
        address sponsor
    ) external;
}

