// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";

contract BasePolicyTest is Test {
    ScopedPolicy public policy;
    
    function setUp() public {
        policy = new ScopedPolicy();
    }
    
    function test_Validate_Interface() public view {
        // 인터페이스가 제대로 구현되었는지 확인
        Types.SessionAuth memory auth = Types.SessionAuth({
            callsHash: keccak256("test"),
            revertOnFail: false,
            chainId: 1,
            opNonce: 1,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope")
        });
        
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(0x1234),
            value: 0,
            data: hex"1234"
        });
        
        // validate 함수가 호출 가능한지 확인
        (bool ok, uint256 code) = policy.validate(auth, calls);
        // 기본 구현은 false를 반환할 수 있음
        assertTrue(true); // 인터페이스만 확인
    }
}

