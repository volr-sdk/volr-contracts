// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrSponsor} from "../../../src/sponsor/VolrSponsor.sol";

import {TestHelpers} from "../../helpers/TestHelpers.sol";

/**
 * @title VolrSponsorTest
 * @notice Unit tests for VolrSponsor
 */
contract VolrSponsorTest is Test {
    VolrSponsor public sponsor;
    address public owner;
    address public client;
    bytes32 public policyId;
    
    function setUp() public {
        owner = address(this);
        client = address(0x1111);
        policyId = keccak256("test-policy");
        
        sponsor = TestHelpers.deployVolrSponsor(owner);
        sponsor.setTimelock(owner);
        sponsor.setMultisig(owner);
        // Set this test contract as authorized caller for compensateClient
        sponsor.setAuthorizedCaller(address(this), true);
    }
    
    // ============ Subsidy Rate ============
    
    function test_SetSubsidyRate_Success() public {
        sponsor.setSubsidyRate(policyId, 2000); // 20%
        
        assertEq(sponsor.subsidyRates(policyId), 2000);
    }
    
    function test_SetSubsidyRate_UpdatesRate() public {
        sponsor.setSubsidyRate(policyId, 2000);
        assertEq(sponsor.subsidyRates(policyId), 2000);
        
        sponsor.setSubsidyRate(policyId, 5000);
        assertEq(sponsor.subsidyRates(policyId), 5000);
    }
    
    function test_SetSubsidyRate_MaxRate() public {
        sponsor.setSubsidyRate(policyId, 10000); // 100%
        
        assertEq(sponsor.subsidyRates(policyId), 10000);
    }
    
    function test_SetSubsidyRate_ExceedsMax_Reverts() public {
        vm.expectRevert("Rate exceeds 100%");
        sponsor.setSubsidyRate(policyId, 10001);
    }
    
    function test_SetSubsidyRate_Unauthorized_Reverts() public {
        address unauthorized = address(0x9999);
        
        vm.prank(unauthorized);
        vm.expectRevert("Not owner");
        sponsor.setSubsidyRate(policyId, 2000);
    }
    
    // ============ Compensation ============
    
    function test_CompensateClient_Success() public {
        // Fund the sponsor
        vm.deal(address(sponsor), 10 ether);
        
        sponsor.setSubsidyRate(policyId, 2000); // 20%
        
        uint256 gasUsed = 1 ether;
        uint256 expectedSubsidy = (gasUsed * 2000) / 10000; // 0.2 ether
        
        uint256 clientBalanceBefore = client.balance;
        
        sponsor.compensateClient(client, gasUsed, policyId);
        
        assertEq(client.balance, clientBalanceBefore + expectedSubsidy);
    }
    
    function test_CompensateClient_EmitsEvent() public {
        vm.deal(address(sponsor), 10 ether);
        sponsor.setSubsidyRate(policyId, 2000);
        
        uint256 gasUsed = 1 ether;
        // expectedSubsidy = (gasUsed * 2000) / 10000 = 0.2 ether
        
        vm.expectEmit(true, true, false, true);
        emit VolrSponsor.SubsidyPaid(client, gasUsed, policyId, 2000, block.timestamp);
        
        sponsor.compensateClient(client, gasUsed, policyId);
    }
    
    function test_CompensateClient_ZeroRate_NoTransfer() public {
        vm.deal(address(sponsor), 10 ether);
        // Don't set subsidy rate (defaults to 0)
        
        uint256 clientBalanceBefore = client.balance;
        
        sponsor.compensateClient(client, 1 ether, policyId);
        
        assertEq(client.balance, clientBalanceBefore);
    }
    
    function test_CompensateClient_InsufficientBalance_NoTransfer() public {
        // Don't fund the sponsor - should not revert, just skip transfer
        sponsor.setSubsidyRate(policyId, 2000);
        
        uint256 clientBalanceBefore = client.balance;
        
        // Should not revert, but also should not transfer anything
        sponsor.compensateClient(client, 1 ether, policyId);
        
        // Client balance should remain unchanged
        assertEq(client.balance, clientBalanceBefore);
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
        emit VolrSponsor.TimelockSet(newTimelock);
        
        sponsor.setTimelock(newTimelock);
    }
    
    function test_SetTimelock_ZeroAddress_Reverts() public {
        vm.expectRevert(VolrSponsor.ZeroAddress.selector);
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
        emit VolrSponsor.MultisigSet(newMultisig);
        
        sponsor.setMultisig(newMultisig);
    }
    
    // ============ Owner ============
    
    function test_Owner_ReturnsCorrectAddress() public view {
        assertEq(sponsor.owner(), owner);
    }
    
    // ============ Receive ETH ============
    
    function test_Receive_AcceptsETH() public {
        vm.deal(address(this), 1 ether);
        
        (bool success, ) = address(sponsor).call{value: 1 ether}("");
        
        assertTrue(success);
        assertEq(address(sponsor).balance, 1 ether);
    }
}

