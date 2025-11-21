// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract ClientSponsorAntiGriefTest is Test {
    ClientSponsor public sponsor;
    address public owner = address(this);
    address public client = address(0xC1);
    address public user = address(0x1234567890123456789012345678901234567890); // Valid address
    bytes32 public policyId = keccak256("policy-ag");

    function setUp() public {
        sponsor = TestHelpers.deployClientSponsor(owner);
        sponsor.setBudget(client, 100 ether);
        sponsor.setPolicy(client, policyId);
        sponsor.setLimits(client, 10 ether, 1 ether);
        sponsor.setAntiGrief(100_000, 2, 10); // minGas=100k, rps=2 per 10s window
    }

    function test_MinGasThreshold() public {
        vm.startPrank(client);
        vm.expectRevert(bytes("Below min gas per tx"));
        sponsor.handleSponsorship(user, 50_000, policyId);
        vm.stopPrank();
    }

    function test_RpsLimit() public {
        vm.startPrank(client);
        sponsor.handleSponsorship(user, 200_000, policyId);
        sponsor.handleSponsorship(user, 200_000, policyId);
        vm.expectRevert(bytes("RPS limit exceeded"));
        sponsor.handleSponsorship(user, 200_000, policyId);
        vm.stopPrank();
    }
}
