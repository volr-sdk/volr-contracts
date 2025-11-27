// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {IPolicy} from "../interfaces/IPolicy.sol";
import {IPolicyRegistry} from "../registry/PolicyRegistry.sol";
import {Types} from "../libraries/Types.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {Signature} from "../libraries/Signature.sol";
import {CallValidator} from "../libraries/CallValidator.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title VolrInvoker
 * @notice ERC-7702 compatible invoker with token receiver support
 * @dev Uses PolicyRegistry for strategy-based policy lookup
 *      Implements IERC721Receiver and IERC1155Receiver for safe token transfers
 * 
 * IMPORTANT: This contract is NOT upgradeable. For EIP-7702:
 * - EOA delegates to this contract's bytecode directly
 * - No proxy pattern (EOA's storage is empty, proxy slots don't work)
 * - Upgrade = deploy new contract + update backend invokerAddress
 * 
 * All state (registry, sponsor) is immutable (stored in bytecode).
 * When a user's EOA delegatecalls to this contract, immutable values
 * are correctly accessible from the bytecode.
 */
contract VolrInvoker is 
    ReentrancyGuard,
    IERC721Receiver,
    IERC1155Receiver
{
    // ============ Immutable Variables (EIP-7702 Compatible) ============
    
    /// @notice PolicyRegistry address - immutable for EIP-7702 compatibility
    /// @dev Stored in bytecode, not storage, so accessible during delegatecall
    IPolicyRegistry public immutable REGISTRY;
    
    /// @notice Sponsor address - immutable for EIP-7702 compatibility
    /// @dev Stored in bytecode, not storage, so accessible during delegatecall
    ISponsor public immutable SPONSOR;
    
    // ============ Note on Storage ============
    // 
    // EIP-7702 Context: When EOA delegatecalls to this contract:
    // - Bytecode (including immutables) comes from this contract
    // - Storage comes from the EOA (which is empty)
    // 
    // Therefore:
    // - REGISTRY and SPONSOR work (immutable = in bytecode)
    // - channelNonces is stored in EOA's storage (per-user nonce tracking)
    // - No owner/timelock/multisig needed (no upgrades, no admin functions)
    
    /// @notice Nonce tracking per channel (stored in EOA's storage during delegatecall)
    mapping(bytes32 => uint64) public channelNonces;
    
    // ============ Structs ============

    // Sponsor voucher (co-sign gas caps & terms)
    struct SponsorVoucher {
        address sponsor;
        bytes32 policyId;
        bytes32 policySnapshotHash;
        uint64  sessionId;
        uint64  nonce;
        uint64  expiresAt;
        uint256 gasLimitMax;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        uint256 totalGasCap;
    }
    
    // ============ Errors ============

    error PolicyViolation(uint256 code);
    error InvalidNonce();
    error ExpiredSession();
    error ZeroAddress();
    
    // ============ Events ============

    event BatchExecuted(
        address indexed user,
        bytes32 indexed policyId,
        bytes32 indexed callsHash,
        bytes32 policySnapshotHash,
        bool success
    );

    event SponsoredExecuted(
        address indexed user,
        address indexed sponsor,
        bytes32 indexed policyId,
        bytes32 callsHash,
        bytes32 policySnapshotHash,
        bool success
    );
    
    // ============ Constructor ============
    
    /// @param _registry PolicyRegistry address (immutable)
    /// @param _sponsor Sponsor address (immutable)
    constructor(address _registry, address _sponsor) {
        if (_registry == address(0) || _sponsor == address(0)) {
            revert ZeroAddress();
        }
        REGISTRY = IPolicyRegistry(_registry);
        SPONSOR = ISponsor(_sponsor);
    }
    
    // ============ Public Entrypoints ============

    /**
     * @notice Execute sponsored batch with gas limit enforcement (F4 fix)
     * @dev Relayer is msg.sender for gas refund (F1 fix: explicit relayer)
     */
    function sponsoredExecute(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        SponsorVoucher calldata voucher,
        bool revertOnFail,
        bytes32 callsHash,
        bytes calldata sessionSig,
        bytes calldata sponsorSig
    ) external nonReentrant {
        uint256 startGas = gasleft();
        address signer = _validateAndRecoverSigner(calls, auth, revertOnFail, callsHash, sessionSig);
        _validateSponsorVoucher(auth, voucher, sponsorSig);
        _enforceNonce(_channelKey(signer, auth.policyId, auth.sessionId), auth.nonce);

        // F4 fix: Pass gasLimitMax to enforce per-call gas limits
        bool success = _execute(calls, revertOnFail, auth.gasLimitMax);
        emit SponsoredExecuted(signer, voucher.sponsor, auth.policyId, callsHash, auth.policySnapshotHash, success);

        // Phase 2-1 fix: Convert gas units to wei using tx.gasprice
        uint256 gasUnits = startGas - gasleft() + 21000; // Approximate overhead in gas units
        uint256 gasCostWei = gasUnits * tx.gasprice;
        // F1 fix: Pass msg.sender as explicit relayer instead of using tx.origin
        // Use immutable SPONSOR for EIP-7702 compatibility
        SPONSOR.handleSponsorship(signer, gasCostWei, auth.policyId, msg.sender);
    }

    /**
     * @notice Execute batch with gas limit enforcement (F4 fix)
     * @dev Relayer is msg.sender for gas refund (F1 fix: explicit relayer)
     */
    function executeBatch(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        bool revertOnFail,
        bytes32 callsHash,
        bytes calldata sessionSig
    ) external payable nonReentrant {
        uint256 startGas = gasleft();
        address signer = _validateAndRecoverSigner(calls, auth, revertOnFail, callsHash, sessionSig);
        _enforceNonce(_channelKey(signer, auth.policyId, auth.sessionId), auth.nonce);

        // F4 fix: Pass gasLimitMax to enforce per-call gas limits
        bool success = _execute(calls, revertOnFail, auth.gasLimitMax);
        emit BatchExecuted(signer, auth.policyId, callsHash, auth.policySnapshotHash, success);

        // Phase 2-1 fix: Convert gas units to wei using tx.gasprice
        uint256 gasUnits = startGas - gasleft() + 21000; // Approximate overhead in gas units
        uint256 gasCostWei = gasUnits * tx.gasprice;
        // F1 fix: Pass msg.sender as explicit relayer instead of using tx.origin
        // Use immutable SPONSOR for EIP-7702 compatibility
        SPONSOR.handleSponsorship(signer, gasCostWei, auth.policyId, msg.sender);
    }
    
    // ============ ERC721 Receiver ============
    
    /**
     * @notice Handle the receipt of an NFT
     * @dev The ERC721 smart contract calls this function on the recipient
     *      after a `safeTransfer`. This function MAY throw to revert and reject the
     *      transfer. Return of other than the magic value MUST result in the
     *      transaction being reverted.
     * @return bytes4 `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
    
    // ============ ERC1155 Receiver ============
    
    /**
     * @notice Handle the receipt of a single ERC1155 token type
     * @return bytes4 `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }
    
    /**
     * @notice Handle the receipt of multiple ERC1155 token types
     * @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }
    
    // ============ ERC-1363 Receiver (Payable Token) ============
    
    /**
     * @notice Handle the receipt of ERC-1363 tokens
     * @dev Called after `transferAndCall` or `transferFromAndCall`
     * @return bytes4 `bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"))`
     */
    function onTransferReceived(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)"));
    }
    
    /**
     * @notice Handle the approval of ERC-1363 tokens
     * @dev Called after `approveAndCall`
     * @return bytes4 `bytes4(keccak256("onApprovalReceived(address,uint256,bytes)"))`
     */
    function onApprovalReceived(
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onApprovalReceived(address,uint256,bytes)"));
    }
    
    // ============ ERC-777 Receiver ============
    
    /**
     * @notice Handle the receipt of ERC-777 tokens
     * @dev Called by ERC-777 token contracts after tokens are sent
     */
    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external pure {
        // Accept tokens - no action needed
    }
    
    // ============ ERC165 ============
    
    /**
     * @notice Query if a contract implements an interface
     * @param interfaceId The interface identifier
     * @return True if the contract implements `interfaceId`
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||           // 0x01ffc9a7
            interfaceId == type(IERC721Receiver).interfaceId ||   // 0x150b7a02
            interfaceId == type(IERC1155Receiver).interfaceId ||  // 0x4e2312e0
            interfaceId == 0x88a7ca5c ||                          // IERC1363Receiver
            interfaceId == 0x7b04a2d0 ||                          // IERC1363Spender
            interfaceId == 0x0023de29;                            // IERC777Recipient
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get the registry address
     * @return Registry address
     */
    function registry() external view returns (IPolicyRegistry) {
        return REGISTRY;
    }
    
    /**
     * @notice Get the sponsor address
     * @return Sponsor address
     */
    function sponsor() external view returns (ISponsor) {
        return SPONSOR;
    }

    // ============ Internal Helpers ============

    /**
     * @notice Validate session auth and recover signer address
     * @dev Validates calls, hash, expiry, signature, gas caps, and policy
     * @return signer The recovered signer address
     */
    function _validateAndRecoverSigner(
        Types.Call[] calldata calls,
        Types.SessionAuth calldata auth,
        bool revertOnFail,
        bytes32 callsHash,
        bytes calldata sessionSig
    ) internal view returns (address signer) {
        require(CallValidator.validateCalls(calls), "Invalid calls");
        bytes32 expectedCallsHash = keccak256(abi.encode(calls));
        require(callsHash == expectedCallsHash, "Calls hash mismatch");
        if (auth.expiresAt < block.timestamp) revert ExpiredSession();

        // Verify EIP-712 session signature
        signer = _recoverSigner(auth, revertOnFail, calls, callsHash, sessionSig);
        require(signer != address(0), "Invalid signature");

        // Gas caps sanity
        require(auth.gasLimitMax > 0, "gasLimitMax=0");
        require(auth.totalGasCap >= auth.gasLimitMax, "totalGasCap<gasLimitMax");

        // Policy validation
        _validatePolicy(auth, calls);
    }

    function _recoverSigner(
        Types.SessionAuth calldata auth,
        bool revertOnFail,
        Types.Call[] calldata calls,
        bytes32 callsHash,
        bytes calldata sessionSig
    ) internal view returns (address) {
        require(sessionSig.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        // Use calldatacopy to safely read from calldata
        bytes memory sig = sessionSig;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        uint8 vNormalized = v >= 27 ? uint8(v - 27) : v;
        require(Signature.validateYParity(vNormalized), "Invalid y-parity");
        require(EIP712.validateLowS(s), "Invalid s (high-S)");

        Types.Call[] memory mCalls = new Types.Call[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            mCalls[i] = calls[i];
        }
        bytes32 digest = EIP712.hashSignedBatch(
            auth.chainId,
            address(this),
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
            mCalls,
            revertOnFail,
            callsHash
        );
        return Signature.recoverSigner(digest, v, r, s);
    }

    /**
     * @notice Validate sponsor voucher with proper domain binding (F5 fix)
     * @dev Phase 2-4: voucher.sponsor is the backend EOA that signs the voucher.
     *      The actual gas cost is deducted from the client's budget based on policyId,
     *      not from voucher.sponsor. This is by design - the sponsor signature authorizes
     *      the gas terms, while policyId determines the funding source.
     */
    function _validateSponsorVoucher(
        Types.SessionAuth calldata auth,
        SponsorVoucher calldata voucher,
        bytes calldata sponsorSig
    ) internal view {
        require(voucher.sponsor != address(0), "no sponsor");
        require(voucher.policyId == auth.policyId, "policyId mismatch");
        require(voucher.policySnapshotHash == auth.policySnapshotHash, "snapshot mismatch");
        require(voucher.sessionId == auth.sessionId, "sessionId mismatch");
        require(voucher.nonce == auth.nonce, "nonce mismatch");
        require(voucher.expiresAt == auth.expiresAt, "expiry mismatch");
        require(voucher.gasLimitMax == auth.gasLimitMax, "gasLimitMax mismatch");
        require(voucher.maxFeePerGas == auth.maxFeePerGas, "maxFeePerGas mismatch");
        require(voucher.maxPriorityFeePerGas == auth.maxPriorityFeePerGas, "maxPrioFee mismatch");
        require(voucher.totalGasCap == auth.totalGasCap, "totalGasCap mismatch");
        // F5 fix: Verify sponsorSig over voucher digest with proper domain binding
        bytes32 digest = EIP712.hashSponsorVoucher(
            auth.chainId,           // F5 fix: Add chainId for domain binding
            address(this),          // F5 fix: Add verifyingContract for domain binding
            voucher.sponsor,
            voucher.policyId,
            voucher.policySnapshotHash,
            voucher.sessionId,
            voucher.nonce,
            voucher.expiresAt,
            voucher.gasLimitMax,
            voucher.maxFeePerGas,
            voucher.maxPriorityFeePerGas,
            voucher.totalGasCap
        );
        require(Signature.verifyCalldataSig(voucher.sponsor, digest, sponsorSig), "invalid sponsorSig");
    }

    function _validatePolicy(Types.SessionAuth memory auth, Types.Call[] calldata calls) internal view {
        // Use immutable REGISTRY for EIP-7702 compatibility
        address policyAddr = REGISTRY.get(auth.policyId);
        IPolicy policy = IPolicy(policyAddr);
        (bool policyOk, uint256 policyCode) = policy.validate(auth, calls);
        if (!policyOk) {
            revert PolicyViolation(policyCode);
        }
    }

    function _channelKey(address user, bytes32 policyId, uint64 sessionId) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, policyId, sessionId));
    }

    function _enforceNonce(bytes32 channel, uint64 nonce) internal {
        if (nonce <= channelNonces[channel]) revert InvalidNonce();
        channelNonces[channel] = nonce;
    }

    /**
     * @notice Execute calls with gas limit enforcement (F4 fix) and EOA support (F8 fix)
     * @param calls Array of calls to execute
     * @param revertOnFail Whether to revert on any call failure
     * @param gasLimitMax Maximum gas limit per call (from auth.gasLimitMax)
     */
    function _execute(
        Types.Call[] calldata calls, 
        bool revertOnFail,
        uint256 gasLimitMax
    ) internal returns (bool) {
        bool allSuccess = true;
        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call memory call = calls[i];
            
            // F8 fix: Allow EOA calls (pure ETH transfers) when data is empty
            // Only require contract code when there's call data
            if (call.data.length > 0) {
                require(call.target.code.length > 0, "Target is not a contract");
            }
            
            // F4 fix: Enforce gas limit - use call.gasLimit if set, otherwise use gasLimitMax
            // Never default to gasleft() which could exceed signed limits
            uint256 callGas = call.gasLimit > 0 ? call.gasLimit : gasLimitMax;
            require(callGas > 0, "No gas limit specified");
            require(callGas <= gasLimitMax, "Call gas exceeds gasLimitMax");
            
            (bool success, bytes memory ret) = call.target.call{
                value: call.value,
                gas: callGas
            }(call.data);
            if (!success) {
                allSuccess = false;
                if (revertOnFail) {
                    if (ret.length > 0) {
                        assembly {
                            revert(add(ret, 32), mload(ret))
                        }
                    } else {
                        revert("Call execution failed");
                    }
                }
            }
        }
        return allSuccess;
    }
    
    // ============ Receive ETH ============
    
    receive() external payable {}
}

