// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {EIP712} from "src/libraries/EIP712.sol";
import {Types} from "src/libraries/Types.sol";

contract EIP712SessionTest is Test {
    using stdJson for string;

    string private constant FIXTURE_RELATIVE = "test/fixtures/eip712-session.json";

    function testFixtureCallsHashMatchesAbiEncode() public view {
        string memory json = _readFixture();
        Types.Call[] memory calls = _loadCalls(json);
        bytes32 expectedHash = json.readBytes32(".callsHash");
        bytes32 computedHash = keccak256(abi.encode(calls));

        assertEq(computedHash, expectedHash, "callsHash mismatch vs fixture");
    }

    function testFixtureDigestMatchesLibrary() public view {
        string memory json = _readFixture();

        Types.SessionAuth memory auth = Types.SessionAuth({
            chainId: json.readUint(".auth.chainId"),
            sessionKey: json.readAddress(".auth.sessionKey"),
            sessionId: uint64(json.readUint(".auth.sessionId")),
            nonce: uint64(json.readUint(".auth.nonce")),
            expiresAt: uint64(json.readUint(".auth.expiresAt")),
            policyId: json.readBytes32(".auth.policyId"),
            policySnapshotHash: json.readBytes32(".auth.policySnapshotHash"),
            gasLimitMax: json.readUint(".auth.gasLimitMax"),
            maxFeePerGas: json.readUint(".auth.maxFeePerGas"),
            maxPriorityFeePerGas: json.readUint(".auth.maxPriorityFeePerGas"),
            totalGasCap: json.readUint(".auth.totalGasCap")
        });

        Types.Call[] memory calls = _loadCalls(json);

        bytes32 callsHash = json.readBytes32(".callsHash");
        bool revertOnFail = json.readBool(".revertOnFail");

        bytes32 digest = EIP712.hashSignedBatch(
            json.readUint(".domain.chainId"),
            json.readAddress(".domain.verifyingContract"),
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

        bytes32 expectedDigest = json.readBytes32(".digest");
        assertEq(digest, expectedDigest, "EIP-712 digest mismatch vs fixture");
    }

    function _readFixture() private view returns (string memory) {
        string memory path = string.concat(vm.projectRoot(), "/", FIXTURE_RELATIVE);
        return vm.readFile(path);
    }

    function _loadCalls(string memory json) private view returns (Types.Call[] memory) {
        uint256 count = json.readUint(".callCount");
        Types.Call[] memory calls = new Types.Call[](count);
        for (uint256 i = 0; i < count; i++) {
            string memory index = vm.toString(i);
            string memory base = string.concat(".calls[", index, "]");
            calls[i] = Types.Call({
                target: json.readAddress(string.concat(base, ".target")),
                value: json.readUint(string.concat(base, ".value")),
                data: json.readBytes(string.concat(base, ".data")),
                gasLimit: json.readUint(string.concat(base, ".gasLimit"))
            });
        }
        return calls;
    }
}


