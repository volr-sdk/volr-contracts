// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {Types} from "../../src/libraries/Types.sol";

contract ClientSponsorTest is Test {
    ClientSponsor public sponsor;
    address public client;
    address public user;
    address public owner;
    
    function setUp() public {
        owner = address(this);
        client = address(0x1111);
        user = address(0x2222);
        sponsor = new ClientSponsor();
    }
    
    function test_HandleSponsorship() public {
        bytes32 policyId = keccak256("policy1");
        uint256 gasUsed = 100000;
        
        // 예산 설정 (owner로 프랭크)
        vm.prank(owner);
        sponsor.setBudget(client, 1 ether);
        vm.prank(owner);
        sponsor.setPolicy(client, policyId);
        vm.prank(owner);
        sponsor.setLimits(client, 10 ether, 1 ether);
        
        // client로 프랭크하여 스폰서십 처리
        vm.prank(client);
        sponsor.handleSponsorship(user, gasUsed, policyId);
        
        // 예산이 차감되었는지 확인
        assertEq(sponsor.getBudget(client), 1 ether - gasUsed);
    }
    
    function test_HandleSponsorship_InsufficientBudget() public {
        bytes32 policyId = keccak256("policy1");
        uint256 gasUsed = 1 ether; // 매우 큰 값
        
        // 예산 설정 (작은 값)
        vm.prank(owner);
        sponsor.setBudget(client, 0.1 ether);
        vm.prank(owner);
        sponsor.setPolicy(client, policyId);
        vm.prank(owner);
        sponsor.setLimits(client, 10 ether, 1 ether);
        
        // 예산 부족 시 실패해야 함
        vm.prank(client);
        vm.expectRevert("Insufficient budget");
        sponsor.handleSponsorship(user, gasUsed, policyId);
    }
    
    function test_SponsorshipUsed_Event() public {
        bytes32 policyId = keccak256("policy1");
        uint256 gasUsed = 100000;
        
        vm.prank(owner);
        sponsor.setBudget(client, 1 ether);
        vm.prank(owner);
        sponsor.setPolicy(client, policyId);
        vm.prank(owner);
        sponsor.setLimits(client, 10 ether, 1 ether);
        
        // 이벤트 발생 확인
        vm.expectEmit(true, true, false, true);
        emit ClientSponsor.SponsorshipUsed(client, user, gasUsed, policyId, block.timestamp);
        
        vm.prank(client);
        sponsor.handleSponsorship(user, gasUsed, policyId);
    }
}

