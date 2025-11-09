// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {WhitelistPolicy} from "../../src/policy/WhitelistPolicy.sol";
import {PromoPolicy} from "../../src/policy/PromoPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract MockTarget {
    bool public called;
    uint256 public callCount;
    
    function callMe() external {
        called = true;
        callCount++;
    }
}

contract HotSwapPolicyTest is Test {
    VolrInvoker public invoker;
    PolicyRegistry public registry;
    WhitelistPolicy public policyA;
    PromoPolicy public policyB;
    MockTarget public target1;
    MockTarget public target2;
    
    address public user;
    uint256 public userKey;
    bytes32 public policyId;
    
    function setUp() public {
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        policyId = keccak256("hot-swap-policy");
        
        registry = TestHelpers.deployPolicyRegistry(address(this));
        registry.setTimelock(address(this));
        registry.setMultisig(address(this));
        
        policyA = new WhitelistPolicy();
        policyB = new PromoPolicy();
        target1 = new MockTarget();
        target2 = new MockTarget();
        
        invoker = new VolrInvoker(address(registry));
    }
    
    function _createAuth(
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
    
    function test_HotSwap_PolicyA_Then_PolicyB() public {
        // Register PolicyA
        registry.register(policyId, address(policyA), "Policy A");
        
        // Setup PolicyA: whitelist target1
        policyA.addTarget(address(target1));
        
        // Execute with PolicyA - should succeed
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target1),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(calls, 1);
        bytes memory sig = _signAuth(auth);
        
        invoker.executeBatch(calls, auth, sig);
        assertTrue(target1.called());
        
        // Unregister PolicyA
        registry.unregister(policyId);
        
        // Register PolicyB
        registry.register(policyId, address(policyB), "Policy B");
        
        // Setup PolicyB: set budget for executor (test contract)
        policyB.setBudget(address(this), 1000 ether);
        
        // Reset target1 state
        target1 = new MockTarget();
        
        // Execute with PolicyB - should succeed (PromoPolicy always validates)
        calls[0] = Types.Call({
            target: address(target1),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        auth = _createAuth(calls, 2);
        sig = _signAuth(auth);
        
        uint256 budgetBefore = policyB.budgets(address(this));
        invoker.executeBatch(calls, auth, sig);
        uint256 budgetAfter = policyB.budgets(address(this));
        
        // Verify PolicyB behavior: budget consumed
        assertTrue(target1.called());
        assertLt(budgetAfter, budgetBefore);
    }
    
    function test_HotSwap_BehaviorChange() public {
        // Register PolicyA (WhitelistPolicy)
        registry.register(policyId, address(policyA), "Policy A");
        
        // PolicyA only allows target1
        policyA.addTarget(address(target1));
        
        // Try to call target2 with PolicyA - should fail
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target2),
            value: 0,
            data: abi.encodeWithSelector(MockTarget.callMe.selector),
            gasLimit: 0
        });
        
        Types.SessionAuth memory auth = _createAuth(calls, 1);
        bytes memory sig = _signAuth(auth);
        
        vm.expectRevert(abi.encodeWithSelector(VolrInvoker.PolicyViolation.selector, 1));
        invoker.executeBatch(calls, auth, sig);
        
        // Unregister PolicyA and register PolicyB
        registry.unregister(policyId);
        registry.register(policyId, address(policyB), "Policy B");
        
        // Setup PolicyB
        policyB.setBudget(address(this), 1000 ether);
        
        // Now target2 should work with PolicyB (PromoPolicy validates all)
        auth = _createAuth(calls, 2);
        sig = _signAuth(auth);
        
        invoker.executeBatch(calls, auth, sig);
        assertTrue(target2.called());
    }
    
    function test_HotSwap_Events() public {
        // Register PolicyA
        vm.expectEmit(true, true, true, true);
        emit PolicyRegistry.PolicyRegistered(policyId, address(policyA), "Policy A");
        registry.register(policyId, address(policyA), "Policy A");
        
        // Unregister PolicyA
        vm.expectEmit(true, false, false, false);
        emit PolicyRegistry.PolicyUnregistered(policyId);
        registry.unregister(policyId);
        
        // Register PolicyB
        vm.expectEmit(true, true, true, true);
        emit PolicyRegistry.PolicyRegistered(policyId, address(policyB), "Policy B");
        registry.register(policyId, address(policyB), "Policy B");
    }
    
    function test_HotSwap_MultipleSwaps() public {
        // First swap: A -> B
        registry.register(policyId, address(policyA), "A");
        registry.unregister(policyId);
        registry.register(policyId, address(policyB), "B");
        
        // Second swap: B -> A
        registry.unregister(policyId);
        registry.register(policyId, address(policyA), "A");
        
        // Verify final state
        assertEq(registry.get(policyId), address(policyA));
    }
}
