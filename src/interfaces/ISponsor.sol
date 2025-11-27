// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ISponsor {
    /**
     * @notice Handle gas sponsorship for a user transaction
     * @param user User address who executed the transaction
     * @param gasUsed Gas used by the transaction
     * @param policyId Policy ID associated with the transaction
     * @param relayer Address of the relayer to receive gas refund
     */
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId,
        address relayer
    ) external;
    
    /**
     * @notice Compensate client with subsidy from Volr treasury
     * @param client Client address to receive compensation
     * @param gasUsed Gas used by the transaction
     * @param policyId Policy ID for subsidy rate lookup
     */
    function compensateClient(
        address client,
        uint256 gasUsed,
        bytes32 policyId
    ) external;
}

