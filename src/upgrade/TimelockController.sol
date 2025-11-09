// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TimelockController
 * @notice Mock TimelockController for upgrade governance
 * @dev Enforces minimum delay between scheduling and executing upgrades
 */
contract TimelockController is Ownable {
    /// @notice Minimum delay required between schedule and execute
    uint256 public minDelay;
    
    /// @notice Mapping of scheduled operations: operationId => scheduled timestamp
    mapping(bytes32 => uint256) public scheduled;
    
    /// @notice Mapping of proposers: address => is proposer
    mapping(address => bool) public proposers;
    
    /// @notice Mapping of executors: address => is executor
    mapping(address => bool) public executors;
    
    /// @notice Event emitted when an upgrade is scheduled
    event UpgradeScheduled(
        bytes32 indexed operationId,
        address indexed proxy,
        address indexed newImpl,
        uint256 eta
    );
    
    /// @notice Event emitted when an upgrade is executed
    event UpgradeExecuted(
        bytes32 indexed operationId,
        address indexed proxy,
        address indexed newImpl,
        uint256 timestamp
    );
    
    /// @notice Event emitted when a proposer is added/removed
    event ProposerSet(address indexed proposer, bool enabled);
    
    /// @notice Event emitted when an executor is added/removed
    event ExecutorSet(address indexed executor, bool enabled);
    
    error OperationNotScheduled();
    error OperationTooEarly();
    error Unauthorized();
    
    /**
     * @notice Constructor
     * @param _minDelay Minimum delay in seconds
     * @param _proposers Array of proposer addresses
     * @param _executors Array of executor addresses
     */
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) Ownable(msg.sender) {
        minDelay = _minDelay;
        
        for (uint256 i = 0; i < _proposers.length; i++) {
            proposers[_proposers[i]] = true;
            emit ProposerSet(_proposers[i], true);
        }
        
        for (uint256 i = 0; i < _executors.length; i++) {
            executors[_executors[i]] = true;
            emit ExecutorSet(_executors[i], true);
        }
    }
    
    /**
     * @notice Schedule an upgrade operation
     * @param proxy Address of the proxy to upgrade
     * @param newImpl Address of the new implementation
     * @param salt Salt for operation ID uniqueness
     * @return operationId Unique operation identifier
     */
    function scheduleUpgrade(
        address proxy,
        address newImpl,
        bytes32 salt
    ) external returns (bytes32 operationId) {
        if (!proposers[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
        
        operationId = keccak256(abi.encode(proxy, newImpl, salt));
        uint256 eta = block.timestamp + minDelay;
        scheduled[operationId] = eta;
        
        emit UpgradeScheduled(operationId, proxy, newImpl, eta);
        
        return operationId;
    }
    
    /**
     * @notice Execute a scheduled upgrade
     * @param proxy Address of the proxy to upgrade
     * @param newImpl Address of the new implementation
     * @param salt Salt used in scheduleUpgrade
     */
    function executeUpgrade(
        address proxy,
        address newImpl,
        bytes32 salt
    ) external {
        if (!executors[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
        
        bytes32 operationId = keccak256(abi.encode(proxy, newImpl, salt));
        uint256 eta = scheduled[operationId];
        
        if (eta == 0) {
            revert OperationNotScheduled();
        }
        
        if (block.timestamp < eta) {
            revert OperationTooEarly();
        }
        
        // Clear the scheduled operation
        delete scheduled[operationId];
        
        // Execute upgrade via proxy's upgradeToAndCall function
        // Note: This assumes the proxy implements UUPSUpgradeable
        (bool success, ) = proxy.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, "")
        );
        require(success, "Upgrade execution failed");
        
        emit UpgradeExecuted(operationId, proxy, newImpl, block.timestamp);
    }
    
    /**
     * @notice Set a proposer
     * @param proposer Address to set
     * @param enabled Whether to enable or disable
     */
    function setProposer(address proposer, bool enabled) external onlyOwner {
        proposers[proposer] = enabled;
        emit ProposerSet(proposer, enabled);
    }
    
    /**
     * @notice Set an executor
     * @param executor Address to set
     * @param enabled Whether to enable or disable
     */
    function setExecutor(address executor, bool enabled) external onlyOwner {
        executors[executor] = enabled;
        emit ExecutorSet(executor, enabled);
    }
    
    /**
     * @notice Set minimum delay
     * @param _minDelay New minimum delay in seconds
     */
    function setMinDelay(uint256 _minDelay) external onlyOwner {
        minDelay = _minDelay;
    }
}

