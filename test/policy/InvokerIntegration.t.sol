// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {WhitelistPolicy} from "../../src/policy/WhitelistPolicy.sol";
import {PromoPolicy} from "../../src/policy/PromoPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";
import {Signature} from "../../src/libraries/Signature.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract MockTarget {
    bool public called;
    uint256 public value;
    
    function callMe() external payable {
        called = true;
        value = msg.value;
    }
    
    function revertMe() external pure {
        revert("Revert message");
    }
}

contract InvokerIntegrationTest is Test {
    VolrInvoker public invoker;
    PolicyRegistry public registry;
    WhitelistPolicy public whitelistPolicy;
    PromoPolicy public promoPolicy;
    MockTarget public target;
    
    address public user;
    uint256 public userKey;
    bytes32 public whitelistPolicyId;
    bytes32 public promoPolicyId;
    
    function setUp() public {
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        whitelistPolicyId = keccak256("whitelist");
        promoPolicyId = keccak256("promo");
        
        registry = TestHelpers.deployPolicyRegistry(address(this));
        registry.setTimelock(address(this));
        registry.setMultisig(address(this));
        
        whitelistPolicy = new WhitelistPolicy();
        promoPolicy = new PromoPolicy();
        target = new MockTarget();
        
        // Register policies
        registry.register(whitelistPolicyId, address(whitelistPolicy), "Whitelist");
        registry.register(promoPolicyId, address(promoPolicy), "Promo");
        
        // Setup whitelist
        whitelistPolicy.addTarget(address(target));
        
        // Setup promo policy
        // Note: executor (msg.sender in executeBatch) will be the test contract address
        promoPolicy.setBudget(address(this), 1000 ether);
        
        invoker = new VolrInvoker(address(registry));
    }
    
    function _createAuth(
        bytes32 policyId,
        Types.Call[] memory calls,
        uint256 nonce
    ) internal view returns (Types.SessionAuth memory) {
        bytes32 callsHash = keccak256(abi.encode(calls));
        return Types.SessionAuth({
            callsHash: callsHash,
            revertOnFail: false,
            chainId: block.chainid,
            opNonce: nonce,
            expiry: uint64(block.timestamp + 3600),
            scopeId: keccak256("scope"),
            policyId: policyId,
            totalGasCap: 0
        });
    }
    
    function _signAuth(Types.SessionAuth memory auth) internal view returns (bytes memory) {
        bytes32 hash = EIP712.hashTypedDataV4(address(invoker), auth);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, hash);
        return abi.encodePacked(r, s, v);
    }
    
    function test_WhitelistPolicy_Valid() public {
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(whitelistPolicyId, calls, 1);
        bytes memory sig = _signAuth(auth);
        
        invoker.executeBatch(calls, auth, sig);
        
        assertTrue(target.called());
    }
    
    function test_WhitelistPolicy_Invalid() public {
        address nonWhitelisted = address(0x9999);
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: nonWhitelisted,
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(whitelistPolicyId, calls, 1);
        bytes memory sig = _signAuth(auth);
        
        vm.expectRevert(abi.encodeWithSelector(VolrInvoker.PolicyViolation.selector, 1));
        invoker.executeBatch(calls, auth, sig);
    }
    
    function test_PromoPolicy_OnExecuted() public {
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(promoPolicyId, calls, 1);
        bytes memory sig = _signAuth(auth);
        
        uint256 budgetBefore = promoPolicy.budgets(address(this));
        
        invoker.executeBatch(calls, auth, sig);
        
        // Budget should be consumed (gas-based pricing)
        uint256 budgetAfter = promoPolicy.budgets(address(this));
        assertLt(budgetAfter, budgetBefore);
    }
    
    function test_PromoPolicy_OnFailed() public {
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.revertMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(promoPolicyId, calls, 1);
        auth.revertOnFail = false; // Don't revert on failure
        bytes memory sig = _signAuth(auth);
        
        uint256 budgetBefore = promoPolicy.budgets(address(this));
        
        // Execute should not revert, but call will fail
        invoker.executeBatch(calls, auth, sig);
        
        // Budget should not be consumed on failure
        uint256 budgetAfter = promoPolicy.budgets(address(this));
        assertEq(budgetAfter, budgetBefore);
    }
    
    function test_PolicyViolation_Reverts() public {
        address nonWhitelisted = address(0x9999);
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: nonWhitelisted,
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(whitelistPolicyId, calls, 1);
        bytes memory sig = _signAuth(auth);
        
        vm.expectRevert(abi.encodeWithSelector(VolrInvoker.PolicyViolation.selector, 1));
        invoker.executeBatch(calls, auth, sig);
    }
    
    function test_PolicyNotFound_Reverts() public {
        bytes32 nonExistentPolicyId = keccak256("non-existent");
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(nonExistentPolicyId, calls, 1);
        bytes memory sig = _signAuth(auth);
        
        vm.expectRevert(PolicyRegistry.PolicyNotFound.selector);
        invoker.executeBatch(calls, auth, sig);
    }
}
