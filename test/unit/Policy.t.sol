// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {ClientSponsor} from "../../src/sponsor/ClientSponsor.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract DummyTarget {
    event Ping(address caller, uint256 value, bytes data);
    function ping() external payable {
        emit Ping(msg.sender, msg.value, msg.data);
    }
    function pong() external payable {
        emit Ping(msg.sender, msg.value, msg.data);
    }
}

contract PolicyTest is Test {
    VolrInvoker public invoker;
    PolicyRegistry public registry;
    ScopedPolicy public policy;
    ClientSponsor public clientSponsor;
    DummyTarget public target;

    address public user;
    uint256 public userPk;
    bytes32 public policyId;

    function setUp() public {
        (user, userPk) = makeAddrAndKey("user");
        registry = TestHelpers.deployPolicyRegistry(address(this));
        clientSponsor = TestHelpers.deployClientSponsor(address(this));
        invoker = new VolrInvoker(address(registry), address(clientSponsor));
        policy = new ScopedPolicy();
        target = new DummyTarget();

        // register policy
        policyId = keccak256("policy-test");
        registry.setTimelock(address(this));
        registry.setMultisig(address(this));
        registry.register(policyId, address(policy), "1");

        // configure policy
        policy.setPolicy(policyId, block.chainid, 1 ether, 1 days, false);
        // allow target.ping()
        policy.setPair(policyId, address(target), bytes4(keccak256("ping()")), true);
    }

    function _signAuth(
        Types.SessionAuth memory auth,
        Types.Call[] memory calls,
        bool revertOnFail,
        bytes32 callsHash
    ) internal view returns (bytes memory sig) {
        bytes32 digest = EIP712.hashSignedBatch(
            auth.chainId,
            address(invoker),
            auth.sessionKey,
            auth.sessionId,
            auth.nonce,
            auth.expiresAt,
            auth.policyId,
            auth.policySnapshotHash,
            auth.gasLimitMax,
            auth.maxFeePerGas,
            auth.maxPriorityFeePerGas,
            auth.totalGasCap,
            calls,
            revertOnFail,
            callsHash
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function test_SnapshotMismatch_Reverts() public {
        // prepare call
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSignature("ping()"),
            gasLimit: 200_000
        });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: bytes32(uint256(1234)), // wrong snapshot
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sig = _signAuth(auth, calls, true, callsHash);

        vm.expectRevert(); // PolicyViolation
        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }

    function test_PairAllowed_Succeeds() public {
        // get current snapshot
        (,,, bytes32 snapshot,) = policy.policies(policyId);

        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSignature("ping()"),
            gasLimit: 200_000
        });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sig = _signAuth(auth, calls, true, callsHash);

        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }

    function test_CodeHashMismatch_Reverts() public {
        // set a fake codeHash requirement
        bytes32 fakeHash = keccak256("not-actual-code");
        policy.setAllowedCodeHash(policyId, address(target), fakeHash);

        (,,, bytes32 snapshot,) = policy.policies(policyId);
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSignature("ping()"),
            gasLimit: 200_000
        });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 1,
            nonce: 2,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sig = _signAuth(auth, calls, true, callsHash);
        vm.expectRevert(); // CODE_HASH_MISMATCH
        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }
    
    function test_Snapshot_Changes_OnPairUpdate() public {
        // Initial snapshot with current config
        (,,, bytes32 beforeSnap,) = policy.policies(policyId);
        // Update pair rule (toggle allow for a different selector)
        bytes4 sel = bytes4(keccak256("pong()"));
        policy.setPair(policyId, address(target), sel, true);
        (,,, bytes32 afterSnap,) = policy.policies(policyId);
        assertTrue(beforeSnap != afterSnap, "snapshot should change after pair update");
    }
    function test_KeyedNonce_PreventsReplay() public {
        (,,, bytes32 snapshot,) = policy.policies(policyId);
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSignature("ping()"),
            gasLimit: 200_000
        });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 1,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sig = _signAuth(auth, calls, true, callsHash);
        invoker.executeBatch(calls, auth, true, callsHash, sig);

        // reuse same nonce
        vm.expectRevert(VolrInvoker.InvalidNonce.selector);
        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }

    function test_AllowAll_Mode() public {
        // 1. Enable Allow-All mode
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        (,,, bytes32 snapshot,) = policy.policies(policyId);

        // 2. Call a function NOT explicitly allowed (pong)
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 0,
            data: abi.encodeWithSignature("pong()"), // NOT in allowedPair
            gasLimit: 200_000
        });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 3,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sig = _signAuth(auth, calls, true, callsHash);

        // Should succeed despite not being in allow-list
        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }

    function test_Limits_Enforced_In_AllowAll() public {
        // 1. Enable Allow-All but with strict limits
        policy.setPolicy(policyId, block.chainid, 0.5 ether, 3600, true);
        (,,, bytes32 snapshot,) = policy.policies(policyId);

        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({
            target: address(target),
            value: 1 ether, // Exceeds maxValue
            data: abi.encodeWithSignature("ping()"),
            gasLimit: 200_000
        });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 4,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sig = _signAuth(auth, calls, true, callsHash);

        // Should fail due to limit check (code 6 = ValueLimitExceeded)
        vm.expectRevert(); 
        invoker.executeBatch(calls, auth, true, callsHash, sig);
    }
}
