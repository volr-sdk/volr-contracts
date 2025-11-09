// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VolrSponsor is ISponsor, ReentrancyGuard, Ownable {
    mapping(bytes32 => uint256) public subsidyRates; // basis points (10000 = 100%)
    
    event SubsidyPaid(
        address indexed client,
        uint256 gasUsed,
        bytes32 indexed policyId,
        uint256 rate,
        uint256 timestamp
    );
    
    constructor() Ownable(msg.sender) {}
    
    function setSubsidyRate(bytes32 policyId, uint256 rate) external onlyOwner {
        require(rate <= 10000, "Rate exceeds 100%");
        subsidyRates[policyId] = rate;
    }
    
    function compensateClient(
        address client,
        uint256 gasUsed,
        bytes32 policyId
    ) external override nonReentrant {
        uint256 rate = subsidyRates[policyId];
        
        if (rate == 0) {
            // 보조금 없음
            return;
        }
        
        // 보조금 계산
        uint256 subsidy = (gasUsed * rate) / 10000;
        
        // 보조금 지급 (on-chain)
        if (subsidy > 0 && address(this).balance >= subsidy) {
            payable(client).transfer(subsidy);
        }
        
        // 이벤트 발생 (오프체인 정산용)
        emit SubsidyPaid(client, gasUsed, policyId, rate, block.timestamp);
    }
    
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId
    ) external override {
        // VolrSponsor는 이 함수를 사용하지 않음
        revert("Not implemented");
    }
    
    receive() external payable {
        // ETH 수신 허용
    }
}

