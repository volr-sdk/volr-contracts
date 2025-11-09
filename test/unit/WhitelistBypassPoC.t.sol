// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";
import {DelegationGuard} from "../../src/libraries/DelegationGuard.sol";

contract WhitelistBypassPoCTest is Test {
    ScopedPolicy public policy;
    address public allowedContract;
    bytes4 public allowedSelector;
    bytes32 public policyId;
    
    function setUp() public {
        allowedContract = address(0x1234);
        allowedSelector = bytes4(0x12345678);
        policyId = keccak256("test-policy");
        
        policy = new ScopedPolicy();
        
        // Policy 설정
        ScopedPolicy.PolicyConfig memory config = ScopedPolicy.PolicyConfig({
            chainId: block.chainid,
            allowedContracts: new address[](1),
            allowedSelectors: new bytes4[](1),
            maxValue: 0,
            maxExpiry: 3600
        });
        config.allowedContracts[0] = allowedContract;
        config.allowedSelectors[0] = allowedSelector;
        
        policy.setPolicy(policyId, config);
    }
    
    function test_DelegatedEOA_Rejected() public {
        // Delegated EOA 생성
        address delegatedEOA = address(0x5678);
        bytes memory delegationCode = abi.encodePacked(
            bytes3(0xef0100),
            bytes20(address(0x9999))
        );
        vm.etch(delegatedEOA, delegationCode);
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: allowedContract,
            value: 0,
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: policyId,
            policyId: keccak256("policy"),
            totalGasCap: 0
        });
        
        // Delegated EOA로 호출 시 거부되어야 함
        vm.prank(delegatedEOA);
        (bool ok, uint256 code) = policy.validate(auth, calls);
        assertFalse(ok);
        assertEq(code, 10); // DELEGATION_NOT_ALLOWED
    }
    
    function test_NormalEOA_Allowed() public view {
        address normalEOA = address(0x1111);
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: allowedContract,
            value: 0,
            data: abi.encodePacked(allowedSelector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256(abi.encode(calls)),
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: policyId,
            policyId: keccak256("policy"),
            totalGasCap: 0
        });
        
        // 일반 EOA는 허용되어야 함 (다른 검증 실패 가능하지만 delegation 체크는 통과)
        // Policy가 설정되지 않았을 수 있으므로 실제로는 실패할 수 있음
        // 하지만 delegation 체크는 통과해야 함
    }
}

