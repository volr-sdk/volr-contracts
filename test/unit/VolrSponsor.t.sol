// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrSponsor} from "../../src/sponsor/VolrSponsor.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract VolrSponsorTest is Test {
    VolrSponsor public sponsor;
    address public client;
    
    function setUp() public {
        client = address(0x1111);
        sponsor = TestHelpers.deployVolrSponsor(address(this));
    }
    
    function test_CompensateClient() public {
        bytes32 policyId = keccak256("policy1");
        uint256 gasUsed = 100000;
        
        // 보조금 비율 설정
        sponsor.setSubsidyRate(policyId, 20); // 20%
        
        // 보조금 지급
        sponsor.compensateClient(client, gasUsed, policyId);
        
        // 보조금이 지급되었는지 확인
        // 실제 구현에 따라 검증
    }
    
    function test_CompensateClient_DifferentRates() public {
        bytes32 policyId1 = keccak256("policy1");
        bytes32 policyId2 = keccak256("policy2");
        uint256 gasUsed = 100000;
        
        // 다른 보조금 비율 설정
        sponsor.setSubsidyRate(policyId1, 20); // 20%
        sponsor.setSubsidyRate(policyId2, 50); // 50%
        
        // 각 정책에 따라 다른 보조금이 지급되어야 함
        sponsor.compensateClient(client, gasUsed, policyId1);
        sponsor.compensateClient(client, gasUsed, policyId2);
    }
    
    function test_CompensateClient_Event() public {
        bytes32 policyId = keccak256("policy1");
        uint256 gasUsed = 100000;
        
        sponsor.setSubsidyRate(policyId, 20);
        
        // 이벤트 발생 확인
        vm.expectEmit(true, true, false, false);
        emit VolrSponsor.SubsidyPaid(client, gasUsed, policyId, 20, block.timestamp);
        
        sponsor.compensateClient(client, gasUsed, policyId);
    }
}

