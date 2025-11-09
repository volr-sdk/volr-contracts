// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ISponsor {
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId
    ) external;
    
    function compensateClient(
        address client,
        uint256 gasUsed,
        bytes32 policyId
    ) external;
}

