// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ClientSponsor is ISponsor, ReentrancyGuard, Ownable {
    struct ClientConfig {
        uint256 budget;
        bytes32 policyId;
        uint256 dailyLimit;
        uint256 perTxLimit;
        mapping(uint256 => uint256) dailyUsage; // date => amount
    }
    
    mapping(address => ClientConfig) public clients;
    address public volrSponsor;
    
    event SponsorshipUsed(
        address indexed client,
        address indexed user,
        uint256 gasUsed,
        bytes32 indexed policyId,
        uint256 timestamp
    );
    
    event BudgetSet(address indexed client, uint256 budget);
    event PolicySet(address indexed client, bytes32 policyId);
    
    constructor() Ownable(msg.sender) {}
    
    function setVolrSponsor(address _volrSponsor) external onlyOwner {
        volrSponsor = _volrSponsor;
    }
    
    function setBudget(address client, uint256 budget) external onlyOwner {
        clients[client].budget = budget;
        emit BudgetSet(client, budget);
    }
    
    function setPolicy(address client, bytes32 policyId) external onlyOwner {
        clients[client].policyId = policyId;
        emit PolicySet(client, policyId);
    }
    
    function setLimits(
        address client,
        uint256 dailyLimit,
        uint256 perTxLimit
    ) external onlyOwner {
        clients[client].dailyLimit = dailyLimit;
        clients[client].perTxLimit = perTxLimit;
    }
    
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId
    ) external override nonReentrant {
        address client = msg.sender;
        ClientConfig storage config = clients[client];
        
        // Policy 검증
        require(config.policyId == policyId, "Invalid policy");
        
        // 예산 검증
        require(config.budget >= gasUsed, "Insufficient budget");
        
        // 한도 검증
        require(gasUsed <= config.perTxLimit, "Per-tx limit exceeded");
        
        // 일일 한도 검증
        uint256 today = block.timestamp / 1 days;
        uint256 dailyUsage = config.dailyUsage[today];
        require(dailyUsage + gasUsed <= config.dailyLimit, "Daily limit exceeded");
        
        // 예산 차감
        config.budget -= gasUsed;
        config.dailyUsage[today] += gasUsed;
        
        // 이벤트 발생
        emit SponsorshipUsed(client, user, gasUsed, policyId, block.timestamp);
        
        // VolrSponsor에 보조금 요청
        if (volrSponsor != address(0)) {
            ISponsor(volrSponsor).compensateClient(client, gasUsed, policyId);
        }
    }
    
    function getBudget(address client) external view returns (uint256) {
        return clients[client].budget;
    }
    
    function compensateClient(
        address client,
        uint256 gasUsed,
        bytes32 policyId
    ) external override {
        // ClientSponsor는 이 함수를 사용하지 않음
        revert("Not implemented");
    }
    
    function getDailyUsage(address client, uint256 date) external view returns (uint256) {
        return clients[client].dailyUsage[date];
    }
}

