// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ClientSponsor} from "../../../src/sponsor/ClientSponsor.sol";

import {TestHelpers} from "../../helpers/TestHelpers.sol";

/**
 * @title ClientSponsorTest
 * @notice Unit tests for ClientSponsor
 */
contract ClientSponsorTest is Test {
    ClientSponsor public sponsor;
    address public owner;
    address public client;
    bytes32 public policyId;
    
    function setUp() public {
        owner = address(this);
        client = address(0x1111);
        policyId = keccak256("test-policy");
        
        sponsor = TestHelpers.deployClientSponsor(owner);
        sponsor.setTimelock(owner);
        sponsor.setMultisig(owner);
    }
    
    // ============ Budget Management ============
    
    function test_SetBudget_Success() public {
        sponsor.setBudget(client, 10 ether);
        
        assertEq(sponsor.getBudget(client), 10 ether);
    }
    
    function test_SetBudget_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ClientSponsor.BudgetSet(client, 10 ether);
        
        sponsor.setBudget(client, 10 ether);
    }
    
    function test_SetBudget_Unauthorized_Reverts() public {
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert("Not owner");
        sponsor.setBudget(client, 10 ether);
    }
    
    // ============ Policy Management ============
    
    function test_AddPolicy_Success() public {
        sponsor.addPolicy(client, policyId);
        
        // Policy should be allowed
        // Note: We can't directly check allowedPolicies mapping, 
        // but we can verify through depositAndInitialize behavior
    }
    
    function test_AddPolicy_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ClientSponsor.PolicyAdded(client, policyId);
        
        sponsor.addPolicy(client, policyId);
    }
    
    function test_RemovePolicy_EmitsEvent() public {
        sponsor.addPolicy(client, policyId);
        
        vm.expectEmit(true, false, false, true);
        emit ClientSponsor.PolicyRemoved(client, policyId);
        
        sponsor.removePolicy(client, policyId);
    }
    
    function test_SetPolicy_Legacy_AddsPolicy() public {
        vm.expectEmit(true, false, false, true);
        emit ClientSponsor.PolicySet(client, policyId);
        
        sponsor.setPolicy(client, policyId);
    }
    
    // ============ Limits Management ============
    
    function test_SetLimits_Success() public {
        sponsor.setLimits(client, 100 ether, 10 ether);
        
        // Limits are set (verified through handleSponsorship behavior)
    }
    
    // ============ Deposit and Initialize ============
    
    function test_DepositAndInitialize_Success() public {
        uint256 depositAmount = 5 ether;
        vm.deal(address(this), depositAmount);
        
        sponsor.depositAndInitialize{value: depositAmount}(client, policyId);
        
        assertEq(sponsor.getBudget(client), depositAmount);
    }
    
    function test_DepositAndInitialize_ZeroValue_Success() public {
        sponsor.depositAndInitialize{value: 0}(client, policyId);
        
        assertEq(sponsor.getBudget(client), 0);
    }
    
    function test_DepositAndInitialize_MultipleTimes_Accumulates() public {
        vm.deal(address(this), 10 ether);
        
        sponsor.depositAndInitialize{value: 3 ether}(client, policyId);
        sponsor.depositAndInitialize{value: 2 ether}(client, policyId);
        
        assertEq(sponsor.getBudget(client), 5 ether);
    }
    
    // ============ Anti-Grief Configuration ============
    
    function test_SetAntiGrief_Success() public {
        sponsor.setAntiGrief(21000, 10, 60);
        
        assertEq(sponsor.minGasPerTx(), 21000);
        assertEq(sponsor.userRpsLimit(), 10);
        assertEq(sponsor.userRpsWindowSeconds(), 60);
    }
    
    function test_SetAntiGrief_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ClientSponsor.AntiGriefSet(21000, 10, 60);
        
        sponsor.setAntiGrief(21000, 10, 60);
    }
    
    function test_SetAntiGrief_ZeroWindow_DefaultsToOne() public {
        sponsor.setAntiGrief(21000, 10, 0);
        
        assertEq(sponsor.userRpsWindowSeconds(), 1);
    }
    
    // ============ VolrSponsor Integration ============
    
    function test_SetVolrSponsor_Success() public {
        address volrSponsor = address(0x2222);
        sponsor.setVolrSponsor(volrSponsor);
        
        assertEq(sponsor.volrSponsor(), volrSponsor);
    }
    
    // ============ Timelock/Multisig ============
    
    function test_SetTimelock_Success() public {
        address newTimelock = address(0x4444);
        sponsor.setTimelock(newTimelock);
        
        assertEq(sponsor.timelock(), newTimelock);
    }
    
    function test_SetTimelock_EmitsEvent() public {
        address newTimelock = address(0x4444);
        
        vm.expectEmit(true, false, false, false);
        emit ClientSponsor.TimelockSet(newTimelock);
        
        sponsor.setTimelock(newTimelock);
    }
    
    function test_SetTimelock_ZeroAddress_Reverts() public {
        vm.expectRevert(ClientSponsor.ZeroAddress.selector);
        sponsor.setTimelock(address(0));
    }
    
    function test_SetMultisig_Success() public {
        address newMultisig = address(0x5555);
        sponsor.setMultisig(newMultisig);
        
        assertEq(sponsor.multisig(), newMultisig);
    }
    
    function test_SetMultisig_EmitsEvent() public {
        address newMultisig = address(0x5555);
        
        vm.expectEmit(true, false, false, false);
        emit ClientSponsor.MultisigSet(newMultisig);
        
        sponsor.setMultisig(newMultisig);
    }
    
    // ============ Failure Recording ============
    
    function test_RecordFailure_IncrementsCounters() public {
        // Set invoker for access control
        address invoker = address(0x8888);
        sponsor.setInvoker(invoker);
        
        vm.prank(invoker);
        sponsor.recordFailure(client, policyId);
        
        (uint256 consecutive, uint256 window, ) = sponsor.failureCounters(client, policyId);
        assertEq(consecutive, 1);
        assertEq(window, 1);
    }
    
    function test_RecordFailure_MultipleTimes() public {
        // Set invoker for access control
        address invoker = address(0x8888);
        sponsor.setInvoker(invoker);
        
        vm.startPrank(invoker);
        sponsor.recordFailure(client, policyId);
        sponsor.recordFailure(client, policyId);
        sponsor.recordFailure(client, policyId);
        vm.stopPrank();
        
        (uint256 consecutive, uint256 window, ) = sponsor.failureCounters(client, policyId);
        assertEq(consecutive, 3);
        assertEq(window, 3);
    }
    
    function test_RecordFailureAndCharge_ChargesFee() public {
        // Set invoker for access control
        address invoker = address(0x8888);
        sponsor.setInvoker(invoker);
        
        vm.deal(address(sponsor), 10 ether);
        sponsor.setBudget(client, 10 ether);
        
        address user = address(0x3333);
        uint256 attemptFee = 0.01 ether;
        
        vm.prank(invoker);
        sponsor.recordFailureAndCharge(client, user, policyId, attemptFee);
        
        assertEq(sponsor.getBudget(client), 10 ether - attemptFee);
    }
    
    function test_RecordFailureAndCharge_EmitsEvent() public {
        // Set invoker for access control
        address invoker = address(0x8888);
        sponsor.setInvoker(invoker);
        
        vm.deal(address(sponsor), 10 ether);
        sponsor.setBudget(client, 10 ether);
        
        address user = address(0x3333);
        uint256 attemptFee = 0.01 ether;
        
        vm.expectEmit(true, true, true, true);
        emit ClientSponsor.AttemptFeeCharged(client, user, attemptFee, policyId, block.timestamp);
        
        vm.prank(invoker);
        sponsor.recordFailureAndCharge(client, user, policyId, attemptFee);
    }
    
    // ============ Owner ============
    
    function test_Owner_ReturnsCorrectAddress() public view {
        assertEq(sponsor.owner(), owner);
    }
    
    // ============ Daily Usage ============
    
    function test_GetDailyUsage_ReturnsZeroInitially() public view {
        uint256 today = block.timestamp / 1 days;
        assertEq(sponsor.getDailyUsage(client, today), 0);
    }
    
    // ============ Phase 2-5: Fail-Open Refund ============
    
    function test_HandleSponsorship_RefundFailed_EmitsEvent() public {
        // Setup
        address invokerAddr = address(0x8888);
        sponsor.setInvoker(invokerAddr);
        
        // Use a contract that rejects ETH as the relayer
        RejectingRelayer rejectingRelayer = new RejectingRelayer();
        
        // Fund sponsor and initialize policy (this sets policyToClient mapping)
        vm.deal(address(sponsor), 10 ether);
        sponsor.depositAndInitialize{value: 10 ether}(client, policyId);
        
        address user = address(0x3333);
        uint256 gasUsed = 0.01 ether; // In wei
        
        // Expect RefundFailed event
        vm.expectEmit(true, false, false, true);
        emit ClientSponsor.RefundFailed(address(rejectingRelayer), gasUsed);
        
        // Call handleSponsorship with rejecting relayer
        vm.prank(invokerAddr);
        sponsor.handleSponsorship(user, gasUsed, policyId, address(rejectingRelayer));
        
        // Budget should still be deducted even though refund failed
        assertEq(sponsor.getBudget(client), 10 ether - gasUsed);
    }
    
    function test_HandleSponsorship_RefundSuccess_NoEvent() public {
        // Setup
        address invokerAddr = address(0x8888);
        sponsor.setInvoker(invokerAddr);
        
        // Use a contract that accepts ETH as the relayer
        AcceptingRelayer acceptingRelayer = new AcceptingRelayer();
        
        // Fund sponsor and initialize policy (this sets policyToClient mapping)
        vm.deal(address(sponsor), 10 ether);
        sponsor.depositAndInitialize{value: 10 ether}(client, policyId);
        
        address user = address(0x3333);
        uint256 gasUsed = 0.01 ether; // In wei
        
        // Call handleSponsorship with accepting relayer
        vm.prank(invokerAddr);
        sponsor.handleSponsorship(user, gasUsed, policyId, address(acceptingRelayer));
        
        // Budget should be deducted
        assertEq(sponsor.getBudget(client), 10 ether - gasUsed);
        // Relayer should have received the refund
        assertEq(address(acceptingRelayer).balance, gasUsed);
    }
}

// Helper contract that rejects ETH transfers
contract RejectingRelayer {
    receive() external payable {
        revert("I reject ETH");
    }
}

// Helper contract that accepts ETH transfers
contract AcceptingRelayer {
    receive() external payable {}
}

