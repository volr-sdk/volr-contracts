// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IPolicy} from "../interfaces/IPolicy.sol";
import {Types} from "../libraries/Types.sol";

/**
 * @title ScopedPolicy
 * @notice Per-policyId scoping with (contract,selector) pairs, optional codehash checks,
 *         and snapshot hashing to bind signed policy state.
 * @dev Nonce/channel checks are enforced in Invoker.
 */
contract ScopedPolicy is IPolicy {
    struct PolicyConfig {
        uint256 chainId;
        uint256 maxValue;
        uint64  maxExpiry;
        bytes32 snapshotHash;
        bool allowAll; // If true, skip pair/codeHash checks (but limits apply)
    }

    mapping(bytes32 => PolicyConfig) public policies;
    mapping(bytes32 => mapping(address => mapping(bytes4 => bool))) public allowedPair;
    mapping(bytes32 => mapping(address => bool)) public allowedContract; // New: Allow all selectors for contract
    mapping(bytes32 => mapping(address => bytes32)) public allowedCodeHash;
    
    // Incremental roots to reflect configuration changes without iterating mappings
    mapping(bytes32 => bytes32) public pairRoot;
    mapping(bytes32 => bytes32) public contractRoot; // New: Root for allowed contracts
    mapping(bytes32 => bytes32) public codeHashRoot;

    event PolicySet(bytes32 indexed policyId, uint256 chainId, uint256 maxValue, uint64 maxExpiry, bool allowAll, bytes32 snapshotHash);
    event PairSet(bytes32 indexed policyId, address indexed target, bytes4 indexed selector, bool allowed, bytes32 newSnapshot);
    event ContractSet(bytes32 indexed policyId, address indexed target, bool allowed, bytes32 newSnapshot); // New event
    event CodeHashSet(bytes32 indexed policyId, address indexed target, bytes32 codeHash, bytes32 newSnapshot);

    function setPolicy(bytes32 policyId, uint256 chainId, uint256 maxValue, uint64 maxExpiry, bool allowAll) external {
        policies[policyId].chainId = chainId;
        policies[policyId].maxValue = maxValue;
        policies[policyId].maxExpiry = maxExpiry;
        policies[policyId].allowAll = allowAll;
        // Reset roots on policy reset to avoid cross-contamination
        pairRoot[policyId] = bytes32(0);
        contractRoot[policyId] = bytes32(0);
        codeHashRoot[policyId] = bytes32(0);
        policies[policyId].snapshotHash = _computeSnapshot(policyId);
        emit PolicySet(policyId, chainId, maxValue, maxExpiry, allowAll, policies[policyId].snapshotHash);
    }

    function setPair(bytes32 policyId, address target, bytes4 selector, bool allowed) external {
        allowedPair[policyId][target][selector] = allowed;
        // Incrementally update pair root (order-dependent but deterministic via event replay)
        pairRoot[policyId] = keccak256(abi.encode(pairRoot[policyId], target, selector, allowed));
        policies[policyId].snapshotHash = _computeSnapshot(policyId);
        emit PairSet(policyId, target, selector, allowed, policies[policyId].snapshotHash);
    }

    function setContract(bytes32 policyId, address target, bool allowed) external {
        allowedContract[policyId][target] = allowed;
        // Incrementally update contract root
        contractRoot[policyId] = keccak256(abi.encode(contractRoot[policyId], target, allowed));
        policies[policyId].snapshotHash = _computeSnapshot(policyId);
        emit ContractSet(policyId, target, allowed, policies[policyId].snapshotHash);
    }

    function setAllowedCodeHash(bytes32 policyId, address target, bytes32 codeHash) external {
        allowedCodeHash[policyId][target] = codeHash;
        // Incrementally update codehash root
        codeHashRoot[policyId] = keccak256(abi.encode(codeHashRoot[policyId], target, codeHash));
        policies[policyId].snapshotHash = _computeSnapshot(policyId);
        emit CodeHashSet(policyId, target, codeHash, policies[policyId].snapshotHash);
    }

    function validate(Types.SessionAuth calldata auth, Types.Call[] calldata calls)
        external view override returns (bool ok, uint256 code)
    {
        bytes32 policyId = auth.policyId;
        PolicyConfig memory cfg = policies[policyId];
        if (cfg.chainId == 0) return (false, 1);
        if (auth.policySnapshotHash != cfg.snapshotHash) return (false, 11);
        if (auth.chainId != cfg.chainId || auth.chainId != block.chainid) return (false, 2);
        if (auth.expiresAt < block.timestamp) return (false, 3);
        // Check expiry if limit set (maxExpiry != type(uint64).max)
        if (cfg.maxExpiry != type(uint64).max && auth.expiresAt > block.timestamp + cfg.maxExpiry) return (false, 4);

        if (auth.totalGasCap > 0) {
            uint256 totalGasLimit = 0;
            for (uint256 i = 0; i < calls.length; i++) {
                if (calls[i].gasLimit > 0) totalGasLimit += calls[i].gasLimit;
            }
            if (totalGasLimit > auth.totalGasCap) return (false, 9);
        }

        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call calldata c = calls[i];
            // Check value limit if set (maxValue != type(uint256).max)
            if (cfg.maxValue != type(uint256).max && c.value > cfg.maxValue) return (false, 6);
            
            if (c.target.code.length == 0) return (false, 12);

            if (!cfg.allowAll) {
                bytes32 required = allowedCodeHash[policyId][c.target];
                address target = c.target;
                bytes32 actual; assembly { actual := extcodehash(target) }
                if (required != bytes32(0) && required != actual) return (false, 13);
                
                // Check if entire contract is allowed
                if (!allowedContract[policyId][c.target]) {
                    // If not, check specific pair
                    bytes4 sel;
                    bytes calldata data = c.data;
                    if (data.length >= 4) {
                        sel = bytes4(data[:4]);
                    } else {
                        sel = 0x00000000; // Fallback for empty data
                    }
                    
                    if (!allowedPair[policyId][c.target][sel]) return (false, 8);
                }
            }
        }
        return (true, 0);
    }

    function onExecuted(
        address, // executor
        Types.SessionAuth calldata, // auth
        Types.Call[] calldata, // calls
        uint256 // gasUsed
    ) external virtual override {
        // No-op for basic scoped policy
    }

    function onFailed(
        address, // executor
        Types.SessionAuth calldata, // auth
        Types.Call[] calldata, // calls
        bytes calldata // reason
    ) external virtual override {
        // No-op for basic scoped policy
    }

    function _computeSnapshot(bytes32 policyId) internal view returns (bytes32) {
        PolicyConfig memory cfg = policies[policyId];
        // Bind snapshot to config + accumulated roots of pairs, contracts, and codehashes
        bytes32 material = keccak256(
            abi.encode(
                cfg.chainId,
                cfg.maxValue,
                cfg.maxExpiry,
                cfg.allowAll,
                pairRoot[policyId],
                contractRoot[policyId],
                codeHashRoot[policyId]
            )
        );
        return keccak256(abi.encode(policyId, material));
    }
}
