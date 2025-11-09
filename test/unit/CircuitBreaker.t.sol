// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract CircuitBreakerTest is Test {
    ClientSponsor public sponsor;
    address public client;
    address public user;
    address public owner;
    bytes32 public policyId;
    
    function setUp() public {
        owner = address(this);
        client = address(0x1111);
        user = address(0x2222);
        policyId = keccak256("policy1");
        sponsor = TestHelpers.deployClientSponsor(owner);
        
        // 기본 설정
        sponsor.setBudget(client, 10 ether);
        sponsor.setPolicy(client, policyId);
        sponsor.setLimits(client, 100 ether, 10 ether);
    }
    
    function test_CircuitBreaker_ConsecutiveFailures() public {
        // 연속 실패 기록
        uint256 maxFailures = 5; // MAX_CONSECUTIVE_FAILURES
        for (uint256 i = 0; i < maxFailures; i++) {
            sponsor.recordFailure(client, policyId);
        }
        
        // Threshold 도달 시 revert
        vm.prank(client);
        vm.expectRevert("Circuit breaker: too many consecutive failures");
        sponsor.handleSponsorship(user, 100000, policyId);
    }
    
    function test_CircuitBreaker_Success_ResetsConsecutiveFailures() public {
        // 몇 번 실패 기록
        sponsor.recordFailure(client, policyId);
        sponsor.recordFailure(client, policyId);
        
        // 성공 시 consecutiveFailures 리셋
        vm.prank(client);
        sponsor.handleSponsorship(user, 100000, policyId);
        
        // 다시 실패해도 카운터가 리셋되었으므로 통과해야 함
        // (다시 5번 실패해야 threshold 도달)
        uint256 maxFailures = 5; // MAX_CONSECUTIVE_FAILURES
        for (uint256 i = 0; i < maxFailures; i++) {
            sponsor.recordFailure(client, policyId);
        }
        
        // 여전히 threshold 도달
        vm.prank(client);
        vm.expectRevert("Circuit breaker: too many consecutive failures");
        sponsor.handleSponsorship(user, 100000, policyId);
    }
    
    function test_CircuitBreaker_WindowFailures() public {
        // Window 내에서 여러 실패 기록
        uint256 maxWindowFailures = 10; // MAX_WINDOW_FAILURES
        for (uint256 i = 0; i < maxWindowFailures; i++) {
            sponsor.recordFailure(client, policyId);
        }
        
        // Threshold 도달 시 revert
        vm.prank(client);
        vm.expectRevert("Circuit breaker: too many failures in window");
        sponsor.handleSponsorship(user, 100000, policyId);
    }
    
    function test_CircuitBreaker_WindowRollOff() public {
        // Window 내에서 실패 기록 (consecutiveFailures는 5 미만으로 유지)
        // 패턴: 실패 -> 성공 -> 실패 -> 성공 ... (consecutiveFailures는 항상 1 이하)
        for (uint256 i = 0; i < 9; i++) {
            sponsor.recordFailure(client, policyId);
            // 성공하여 consecutiveFailures 리셋
            vm.prank(client);
            sponsor.handleSponsorship(user, 100000, policyId);
        }
        
        // 이제 windowFailures는 9, consecutiveFailures는 0
        // Window가 지나면 windowFailures 리셋
        uint256 windowSeconds = 3600; // FAILURE_WINDOW_SECONDS
        vm.warp(block.timestamp + windowSeconds + 1);
        
        // 이제 통과해야 함 (windowFailures가 리셋됨)
        vm.prank(client);
        sponsor.handleSponsorship(user, 100000, policyId);
    }
    
    function test_CircuitBreaker_EarlyBlock_NoGasWaste() public {
        // 연속 실패 기록
        uint256 maxFailures = 5; // MAX_CONSECUTIVE_FAILURES
        for (uint256 i = 0; i < maxFailures; i++) {
            sponsor.recordFailure(client, policyId);
        }
        
        // Early block으로 gas 낭비 방지
        uint256 gasBefore = gasleft();
        vm.prank(client);
        vm.expectRevert("Circuit breaker: too many consecutive failures");
        sponsor.handleSponsorship(user, 100000, policyId);
        uint256 gasAfter = gasleft();
        
        // Early revert로 인해 gas 사용량이 적어야 함
        // (실제 검증 로직을 실행하지 않음)
        assertLt(gasBefore - gasAfter, 50000); // 임의의 threshold
    }
}

