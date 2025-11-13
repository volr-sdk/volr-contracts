// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {Types} from "../../src/libraries/Types.sol";

contract ERC20False {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

// Harness to expose _executeCalls for unit testing without signature/policy plumbing
contract VolrInvokerHarness is VolrInvoker {
    constructor(address _registry) VolrInvoker(_registry) {}
    function harnessExecute(Types.Call[] calldata calls, bool revertOnFail) external returns (bool) {
        return _executeCalls(calls, revertOnFail);
    }
}

contract VolrInvokerFailureTest is Test {
    VolrInvokerHarness public invoker;
    PolicyRegistry public registry;

    function setUp() public {
        registry = new PolicyRegistry();
        invoker = new VolrInvokerHarness(address(registry));
    }

    function test_EOA_Target_Should_Revert() public {
        // target is EOA (address(this) has code here, so use a random EOA)
        address eoa = address(0x1234);
        assertEq(eoa.code.length, 0);

        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: eoa,
            value: 0,
            data: hex"",
            gasLimit: 0
        });

        vm.expectRevert(bytes("Target is not a contract"));
        invoker.harnessExecute(calls, true);
    }

    function test_ERC20_False_Should_Revert_When_RevertOnFail() public {
        ERC20False token = new ERC20False();
        Types.Call[] memory calls = new Types.Call[](1);
        // transfer(address,uint256) selector 0xa9059cbb
        bytes memory data = abi.encodeWithSelector(0xa9059cbb, address(0xdead), uint256(1));
        calls[0] = Types.Call({
            target: address(token),
            value: 0,
            data: data,
            gasLimit: 0
        });

        vm.expectRevert(bytes("ERC20 returned false"));
        invoker.harnessExecute(calls, true);
    }

    function test_ERC20_False_Sets_AllSuccessFalse_When_NoRevert() public {
        ERC20False token = new ERC20False();
        Types.Call[] memory calls = new Types.Call[](1);
        bytes memory data = abi.encodeWithSelector(0xa9059cbb, address(0xdead), uint256(1));
        calls[0] = Types.Call({
            target: address(token),
            value: 0,
            data: data,
            gasLimit: 0
        });

        bool ok = invoker.harnessExecute(calls, false);
        assertTrue(!ok, "should return false when ERC20 returned false and revertOnFail=false");
    }
}


