// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {Types} from "../../src/libraries/Types.sol";
import {EIP712} from "../../src/libraries/EIP712.sol";
import {TestHelpers} from "../helpers/TestHelpers.sol";

contract VoucherTarget {
    function ping() external {}
}

contract SponsorVoucherTest is Test {
    VolrInvoker public invoker;
    PolicyRegistry public registry;
    ScopedPolicy public policy;
    VoucherTarget public target;

    address public user; uint256 public userPk;
    address public sponsor; uint256 public sponsorPk;
    bytes32 public policyId;

    function setUp() public {
        (user, userPk) = makeAddrAndKey("user");
        (sponsor, sponsorPk) = makeAddrAndKey("sponsor");
        registry = TestHelpers.deployPolicyRegistry(address(this));
        invoker = new VolrInvoker(address(registry));
        policy = new ScopedPolicy();
        target = new VoucherTarget();

        policyId = keccak256("policy-voucher");
        registry.setTimelock(address(this));
        registry.setMultisig(address(this));
        registry.register(policyId, address(policy), "1");

        policy.setPolicy(policyId, block.chainid, 0, 1 days, false);
        policy.setPair(policyId, address(target), bytes4(keccak256("ping()")), true);
    }

    function _sessionSig(
        Types.SessionAuth memory auth,
        Types.Call[] memory calls,
        bool revertOnFail,
        bytes32 callsHash
    ) internal view returns (bytes memory) {
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
        return abi.encodePacked(r, s, v);
    }

    function _sponsorSig(VolrInvoker.SponsorVoucher memory v) internal view returns (bytes memory) {
        bytes32 digest = EIP712.hashSponsorVoucher(
            v.sponsor,
            v.policyId,
            v.policySnapshotHash,
            v.sessionId,
            v.nonce,
            v.expiresAt,
            v.gasLimitMax,
            v.maxFeePerGas,
            v.maxPriorityFeePerGas,
            v.totalGasCap
        );
        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(sponsorPk, digest);
        return abi.encodePacked(sr, ss, sv);
    }

    function test_SponsoredExecute_Works() public {
        (,,, bytes32 snapshot,) = policy.policies(policyId);
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({ target: address(target), value: 0, data: abi.encodeWithSignature("ping()"), gasLimit: 200_000 });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 7,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        VolrInvoker.SponsorVoucher memory voucher = VolrInvoker.SponsorVoucher({
            sponsor: sponsor,
            policyId: policyId,
            policySnapshotHash: snapshot,
            sessionId: 7,
            nonce: 1,
            expiresAt: uint64(block.timestamp + 600),
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });

        bytes memory sSig = _sessionSig(auth, calls, true, callsHash);
        bytes memory vSig = _sponsorSig(voucher);

        invoker.sponsoredExecute(calls, auth, voucher, true, callsHash, sSig, vSig);
    }

    function test_SponsoredExecute_Mismatch_Reverts() public {
        (,,, bytes32 snapshot,) = policy.policies(policyId);
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = Types.Call({ target: address(target), value: 0, data: abi.encodeWithSignature("ping()"), gasLimit: 200_000 });
        bytes32 callsHash = keccak256(abi.encode(calls));

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: block.chainid,
            sessionKey: user,
            sessionId: 7,
            nonce: 2,
            expiresAt: uint64(block.timestamp + 600),
            policyId: policyId,
            policySnapshotHash: snapshot,
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        VolrInvoker.SponsorVoucher memory voucher = VolrInvoker.SponsorVoucher({
            sponsor: sponsor,
            policyId: policyId,
            policySnapshotHash: snapshot,
            sessionId: 7,
            nonce: 3, // mismatch
            expiresAt: uint64(block.timestamp + 600),
            gasLimitMax: 500_000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            totalGasCap: 500_000
        });
        bytes memory sSig = _sessionSig(auth, calls, true, callsHash);
        bytes memory vSig = _sponsorSig(voucher);

        vm.expectRevert(); // mismatch path should revert in validation
        invoker.sponsoredExecute(calls, auth, voucher, true, callsHash, sSig, vSig);
    }
}


