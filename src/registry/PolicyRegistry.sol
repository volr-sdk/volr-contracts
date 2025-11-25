// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title PolicyRegistry
 * @notice Registry for policy implementations (strategy pattern)
 * @dev Uses UUPS proxy pattern with timelock governance
 */
interface IPolicyRegistry {
    /**
     * @notice Register a policy implementation
     * @param policyId Policy ID
     * @param impl Policy implementation address
     * @param meta Metadata string
     */
    function register(bytes32 policyId, address impl, string calldata meta) external;
    
    /**
     * @notice Unregister a policy
     * @param policyId Policy ID
     */
    function unregister(bytes32 policyId) external;
    
    /**
     * @notice Get policy implementation address
     * @param policyId Policy ID
     * @return Policy implementation address
     */
    function get(bytes32 policyId) external view returns (address);
}

/**
 * @title PolicyRegistry
 * @notice Registry for policy implementations (strategy pattern)
 * @dev Uses UUPS proxy pattern with timelock governance
 */
contract PolicyRegistry is IPolicyRegistry, Initializable, UUPSUpgradeable {
    /// @custom:storage-location erc7201:volr.PolicyRegistry.v1
    struct PolicyRegistryStorage {
        mapping(bytes32 => address) policies;
        mapping(bytes32 => string) metadata;
        address timelock;
        address multisig;
        address owner;
        mapping(address => bool) relayers;
    }
    
    // keccak256(abi.encode(uint256(keccak256("volr.PolicyRegistry.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x25c88f03dcd50eacc408373df47c82f769296e10fa659eec6be11c621d6fde00;
    
    /// @notice Storage gap for future upgrades
    uint256[49] private __gap;
    
    error PolicyNotFound();
    error PolicyAlreadyExists();
    error Unauthorized();
    error ZeroAddress();
    
    event PolicyRegistered(bytes32 indexed policyId, address impl, string meta);
    event PolicyUnregistered(bytes32 indexed policyId);
    event TimelockSet(address indexed timelock);
    event MultisigSet(address indexed multisig);
    event RelayerSet(address indexed relayer, bool active);
    event UpgradeInitiated(address indexed oldImpl, address indexed newImpl, uint256 eta);
    event UpgradeExecuted(address indexed oldImpl, address indexed newImpl, uint256 timestamp);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initialize the contract
     * @param initialOwner Initial owner address
     */
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert ZeroAddress();
        PolicyRegistryStorage storage $ = _getStorage();
        $.owner = initialOwner;
    }
    
    /**
     * @notice Modifier to restrict access to owner
     */
    modifier onlyOwner() {
        PolicyRegistryStorage storage $ = _getStorage();
        require(msg.sender == $.owner, "Not owner");
        _;
    }
    
    /**
     * @notice Modifier to restrict access to timelock, multisig, or authorized relayer
     */
    modifier onlyAuthorized() {
        PolicyRegistryStorage storage $ = _getStorage();
        if (msg.sender != $.timelock && msg.sender != $.multisig && !$.relayers[msg.sender] && msg.sender != $.owner) revert Unauthorized();
        _;
    }
    
    /**
     * @notice Set relayer status
     * @param relayer Relayer address
     * @param active Active status
     */
    function setRelayer(address relayer, bool active) external onlyAuthorized {
        if (relayer == address(0)) revert ZeroAddress();
        PolicyRegistryStorage storage $ = _getStorage();
        $.relayers[relayer] = active;
        emit RelayerSet(relayer, active);
    }

    /**
     * @notice Check whether an address is an authorized relayer
     * @param relayer Relayer address
     * @return True if the address is configured as relayer
     *
     * @dev 별도의 view 함수로 노출해서 온체인에서 relayer 상태를 쉽게 조회할 수 있도록 한다.
     *      Storage 레이아웃은 그대로 두고, 읽기 전용 getter 만 추가한다.
     */
    function isRelayer(address relayer) external view returns (bool) {
        PolicyRegistryStorage storage $ = _getStorage();
        return $.relayers[relayer];
    }

    /**
     * @notice Set timelock address
     * @param _timelock Timelock address
     */
    function setTimelock(address _timelock) external onlyOwner {
        if (_timelock == address(0)) revert ZeroAddress();
        PolicyRegistryStorage storage $ = _getStorage();
        $.timelock = _timelock;
        emit TimelockSet(_timelock);
    }
    
    /**
     * @notice Set multisig address
     * @param _multisig Multisig address
     */
    function setMultisig(address _multisig) external onlyOwner {
        if (_multisig == address(0)) revert ZeroAddress();
        PolicyRegistryStorage storage $ = _getStorage();
        $.multisig = _multisig;
        emit MultisigSet(_multisig);
    }
    
    /**
     * @notice Register a policy implementation
     * @param policyId Policy ID
     * @param impl Policy implementation address
     * @param meta Metadata string
     */
    function register(bytes32 policyId, address impl, string calldata meta) external onlyAuthorized {
        if (impl == address(0)) revert ZeroAddress();
        PolicyRegistryStorage storage $ = _getStorage();
        if ($.policies[policyId] != address(0)) revert PolicyAlreadyExists();
        $.policies[policyId] = impl;
        $.metadata[policyId] = meta;
        emit PolicyRegistered(policyId, impl, meta);
    }
    
    /**
     * @notice Unregister a policy
     * @param policyId Policy ID
     */
    function unregister(bytes32 policyId) external onlyAuthorized {
        PolicyRegistryStorage storage $ = _getStorage();
        if ($.policies[policyId] == address(0)) revert PolicyNotFound();
        delete $.policies[policyId];
        delete $.metadata[policyId];
        emit PolicyUnregistered(policyId);
    }
    
    /**
     * @notice Get policy implementation address
     * @param policyId Policy ID
     * @return Policy implementation address
     */
    function get(bytes32 policyId) external view returns (address) {
        PolicyRegistryStorage storage $ = _getStorage();
        address impl = $.policies[policyId];
        if (impl == address(0)) revert PolicyNotFound();
        return impl;
    }
    
    /**
     * @notice Authorize upgrade (UUPS)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAuthorized {
        address oldImpl = ERC1967Utils.getImplementation();
        emit UpgradeInitiated(oldImpl, newImplementation, block.timestamp);
    }
    
    /**
     * @notice Get storage pointer
     * @return $ Storage struct
     */
    function _getStorage() private pure returns (PolicyRegistryStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }
    
    /**
     * @notice Get timelock address
     * @return Timelock address
     */
    function timelock() external view returns (address) {
        PolicyRegistryStorage storage $ = _getStorage();
        return $.timelock;
    }
    
    /**
     * @notice Get multisig address
     * @return Multisig address
     */
    function multisig() external view returns (address) {
        PolicyRegistryStorage storage $ = _getStorage();
        return $.multisig;
    }
    
    /**
     * @notice Get owner address
     * @return Owner address
     */
    function owner() external view returns (address) {
        PolicyRegistryStorage storage $ = _getStorage();
        return $.owner;
    }
}

