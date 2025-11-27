// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {IPolicy} from "../interfaces/IPolicy.sol";
import {IPolicyRegistry} from "../registry/PolicyRegistry.sol";
import {Types} from "../libraries/Types.sol";
import {EIP712} from "../libraries/EIP712.sol";
import {Signature} from "../libraries/Signature.sol";
import {CallValidator} from "../libraries/CallValidator.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title VolrInvoker
 * @notice ERC-7702 compatible invoker with UUPS upgradeability and token receiver support
 * @dev Uses PolicyRegistry for strategy-based policy lookup
 *      Implements IERC721Receiver and IERC1155Receiver for safe token transfers
 */
contract VolrInvoker is 
    Initializable, 
    UUPSUpgradeable, 
    ReentrancyGuard,
    IERC721Receiver,
    IERC1155Receiver
{
    // ============ ERC-7201 Storage ============
    
    /// @custom:storage-location erc7201:volr.VolrInvoker.v1
    struct InvokerStorage {
        IPolicyRegistry registry;
        ISponsor sponsor;
        address timelock;
        address multisig;
        address owner;
    // Single keyed nonce channel: keccak256(user, policyId, sessionId) -> last seq
        mapping(bytes32 => uint64) channelNonces;
    }
    
    // keccak256(abi.encode(uint256(keccak256("volr.VolrInvoker.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x8a0c9d8ec1d9f8b4a1c2e3f4d5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f300;
    
    /// @notice Storage gap for future upgrades
    uint256[50] private __gap;
    
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
    error Unauthorized();
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

    event TimelockSet(address indexed timelock);
    event MultisigSet(address indexed multisig);
    event UpgradeInitiated(address indexed oldImpl, address indexed newImpl, uint256 eta);
    
    // ============ Constructor ============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    // ============ Initializer ============
    
    /**
     * @notice Initialize the contract
     * @param _registry PolicyRegistry address
     * @param _sponsor Sponsor address
     * @param _owner Owner address for upgrade authorization
     */
    function initialize(
        address _registry,
        address _sponsor,
        address _owner
    ) external initializer {
        if (_registry == address(0) || _sponsor == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }
        
        InvokerStorage storage $ = _getStorage();
        $.registry = IPolicyRegistry(_registry);
        $.sponsor = ISponsor(_sponsor);
        $.owner = _owner;
    }
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        InvokerStorage storage $ = _getStorage();
        require(msg.sender == $.owner, "Not owner");
        _;
    }
    
    modifier onlyTimelockOrMultisig() {
        InvokerStorage storage $ = _getStorage();
        if (msg.sender != $.timelock && msg.sender != $.multisig) revert Unauthorized();
        _;
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Set timelock address
     * @param _timelock Timelock address
     */
    function setTimelock(address _timelock) external onlyOwner {
        if (_timelock == address(0)) revert ZeroAddress();
        InvokerStorage storage $ = _getStorage();
        $.timelock = _timelock;
        emit TimelockSet(_timelock);
    }
    
    /**
     * @notice Set multisig address
     * @param _multisig Multisig address
     */
    function setMultisig(address _multisig) external onlyOwner {
        if (_multisig == address(0)) revert ZeroAddress();
        InvokerStorage storage $ = _getStorage();
        $.multisig = _multisig;
        emit MultisigSet(_multisig);
    }
    
    // ============ Public Entrypoints ============

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

        bool success = _execute(calls, revertOnFail);
        emit SponsoredExecuted(signer, voucher.sponsor, auth.policyId, callsHash, auth.policySnapshotHash, success);

        uint256 gasUsed = startGas - gasleft() + 21000; // Approximate overhead
        InvokerStorage storage $ = _getStorage();
        $.sponsor.handleSponsorship(signer, gasUsed, auth.policyId);
    }

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

        bool success = _execute(calls, revertOnFail);
        emit BatchExecuted(signer, auth.policyId, callsHash, auth.policySnapshotHash, success);

        uint256 gasUsed = startGas - gasleft() + 21000; // Approximate overhead
        InvokerStorage storage $ = _getStorage();
        $.sponsor.handleSponsorship(signer, gasUsed, auth.policyId);
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
     * @notice Get the nonce for a channel
     * @param channel Channel key
     * @return Current nonce
     */
    function channelNonces(bytes32 channel) external view returns (uint64) {
        InvokerStorage storage $ = _getStorage();
        return $.channelNonces[channel];
    }
    
    /**
     * @notice Get the registry address
     * @return Registry address
     */
    function registry() external view returns (IPolicyRegistry) {
        InvokerStorage storage $ = _getStorage();
        return $.registry;
    }
    
    /**
     * @notice Get the sponsor address
     * @return Sponsor address
     */
    function sponsor() external view returns (ISponsor) {
        InvokerStorage storage $ = _getStorage();
        return $.sponsor;
    }
    
    /**
     * @notice Get the owner address
     * @return Owner address
     */
    function owner() external view returns (address) {
        InvokerStorage storage $ = _getStorage();
        return $.owner;
    }
    
    /**
     * @notice Get the timelock address
     * @return Timelock address
     */
    function timelock() external view returns (address) {
        InvokerStorage storage $ = _getStorage();
        return $.timelock;
    }
    
    /**
     * @notice Get the multisig address
     * @return Multisig address
     */
    function multisig() external view returns (address) {
        InvokerStorage storage $ = _getStorage();
        return $.multisig;
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

    function _validateSponsorVoucher(
        Types.SessionAuth calldata auth,
        SponsorVoucher calldata voucher,
        bytes calldata sponsorSig
    ) internal pure {
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
        // Verify sponsorSig over voucher digest
        bytes32 digest = EIP712.hashSponsorVoucher(
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
        InvokerStorage storage $ = _getStorage();
        address policyAddr = $.registry.get(auth.policyId);
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
        InvokerStorage storage $ = _getStorage();
        if (nonce <= $.channelNonces[channel]) revert InvalidNonce();
        $.channelNonces[channel] = nonce;
    }

    function _execute(Types.Call[] calldata calls, bool revertOnFail) internal returns (bool) {
        bool allSuccess = true;
        for (uint256 i = 0; i < calls.length; i++) {
            Types.Call memory call = calls[i];
            require(call.target.code.length > 0, "Target is not a contract");
            (bool success, bytes memory ret) = call.target.call{
                value: call.value,
                gas: call.gasLimit > 0 ? call.gasLimit : gasleft()
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
    
    // ============ Storage Access ============
    
    function _getStorage() private pure returns (InvokerStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }
    
    // ============ UUPS ============
    
    /**
     * @notice Authorize upgrade (UUPS)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyTimelockOrMultisig {
        address oldImpl = ERC1967Utils.getImplementation();
        emit UpgradeInitiated(oldImpl, newImplementation, block.timestamp);
    }
    
    // ============ Receive ETH ============
    
    receive() external payable {}
}

