// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title ClientSponsor
 * @notice Upgradeable sponsor contract for client gas sponsorship
 * @dev Uses UUPS proxy pattern with timelock governance
 */
contract ClientSponsor is ISponsor, ReentrancyGuard, Initializable, UUPSUpgradeable {
    // ERC-7201 Storage Namespacing
    bytes32 public constant STORAGE_SLOT_CLIENTS = keccak256("volr.ClientSponsor.clients");
    
    // Circuit Breaker Constants
    uint256 public constant MAX_CONSECUTIVE_FAILURES = 5;
    uint256 public constant MAX_WINDOW_FAILURES = 10;
    uint256 public constant FAILURE_WINDOW_SECONDS = 1 hours;
    
    struct FailureCounter {
        uint256 consecutiveFailures;
        uint256 windowFailures;
        uint256 lastFailureTime;
    }
    
    struct ClientConfig {
        uint256 budget;
        bytes32 policyId;
        uint256 dailyLimit;
        uint256 perTxLimit;
        mapping(uint256 => uint256) dailyUsage; // date => amount
    }
    
    mapping(address => ClientConfig) public clients;
    mapping(address => mapping(bytes32 => FailureCounter)) public failureCounters;
    address public volrSponsor;
    address public timelock;
    address public multisig;
    address private _owner;
    
    /// @notice Storage gap for future upgrades
    uint256[50] private __gap;
    
    error Unauthorized();
    error NotThroughProxy();
    error ZeroAddress();
    
    event SponsorshipUsed(
        address indexed client,
        address indexed user,
        uint256 gasUsed,
        bytes32 indexed policyId,
        uint256 timestamp
    );
    
    event BudgetSet(address indexed client, uint256 budget);
    event PolicySet(address indexed client, bytes32 policyId);
    event TimelockSet(address indexed timelock);
    event MultisigSet(address indexed multisig);
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
        _owner = initialOwner;
    }
    
    /**
     * @notice Modifier to restrict access to owner
     */
    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }
    
    /**
     * @notice Modifier to restrict access to timelock or multisig
     */
    modifier onlyTimelockOrMultisig() {
        if (msg.sender != timelock && msg.sender != multisig) revert Unauthorized();
        _;
    }
    
    /**
     * @notice Set timelock address
     * @param _timelock Timelock address
     */
    function setTimelock(address _timelock) external onlyOwner {
        if (_timelock == address(0)) revert ZeroAddress();
        timelock = _timelock;
        emit TimelockSet(_timelock);
    }
    
    /**
     * @notice Set multisig address
     * @param _multisig Multisig address
     */
    function setMultisig(address _multisig) external onlyOwner {
        if (_multisig == address(0)) revert ZeroAddress();
        multisig = _multisig;
        emit MultisigSet(_multisig);
    }
    
    /**
     * @notice Set VolrSponsor address
     * @param _volrSponsor VolrSponsor address
     */
    function setVolrSponsor(address _volrSponsor) external onlyOwner {
        volrSponsor = _volrSponsor;
    }
    
    /**
     * @notice Set client budget
     * @param client Client address
     * @param budget Budget amount
     */
    function setBudget(address client, uint256 budget) external onlyOwner {
        clients[client].budget = budget;
        emit BudgetSet(client, budget);
    }
    
    /**
     * @notice Set client policy
     * @param client Client address
     * @param policyId Policy ID
     */
    function setPolicy(address client, bytes32 policyId) external onlyOwner {
        clients[client].policyId = policyId;
        emit PolicySet(client, policyId);
    }
    
    /**
     * @notice Set client limits
     * @param client Client address
     * @param dailyLimit Daily limit
     * @param perTxLimit Per transaction limit
     */
    function setLimits(
        address client,
        uint256 dailyLimit,
        uint256 perTxLimit
    ) external onlyOwner {
        clients[client].dailyLimit = dailyLimit;
        clients[client].perTxLimit = perTxLimit;
    }
    
    /**
     * @notice Handle sponsorship request
     * @param user User address
     * @param gasUsed Gas used
     * @param policyId Policy ID
     */
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId
    ) external override nonReentrant {
        address client = msg.sender;
        ClientConfig storage config = clients[client];
        FailureCounter storage counter = failureCounters[client][policyId];
        
        // Rolling window 체크
        if (block.timestamp - counter.lastFailureTime > FAILURE_WINDOW_SECONDS) {
            counter.windowFailures = 0;
        }
        if (counter.windowFailures >= MAX_WINDOW_FAILURES) {
            revert("Circuit breaker: too many failures in window");
        }
        
        // Circuit Breaker 체크
        if (counter.consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
            revert("Circuit breaker: too many consecutive failures");
        }
        
        // Policy 검증
        require(config.policyId == policyId, "Invalid policy");
        
        // 예산 검증
        require(config.budget >= gasUsed, "Insufficient budget");
        
        // 한도 검증
        require(gasUsed <= config.perTxLimit, "Per-tx limit exceeded");
        
        // 일일 한도 검증
        uint256 today = block.timestamp / 1 days;
        uint256 dailyUsage = config.dailyUsage[today];
        require(dailyUsage + gasUsed <= config.dailyLimit, "Daily limit exceeded");
        
        // 예산 차감
        config.budget -= gasUsed;
        config.dailyUsage[today] += gasUsed;
        
        // 성공 시 consecutiveFailures 리셋
        counter.consecutiveFailures = 0;
        
        // 이벤트 발생
        emit SponsorshipUsed(client, user, gasUsed, policyId, block.timestamp);
        
        // VolrSponsor에 보조금 요청
        if (volrSponsor != address(0)) {
            ISponsor(volrSponsor).compensateClient(client, gasUsed, policyId);
        }
    }
    
    /**
     * @notice Record failure for circuit breaker
     * @param client Client address
     * @param policyId Policy ID
     */
    function recordFailure(address client, bytes32 policyId) external {
        FailureCounter storage counter = failureCounters[client][policyId];
        counter.consecutiveFailures++;
        counter.windowFailures++;
        counter.lastFailureTime = block.timestamp;
    }
    
    /**
     * @notice Get client budget
     * @param client Client address
     * @return Budget amount
     */
    function getBudget(address client) external view returns (uint256) {
        return clients[client].budget;
    }
    
    /**
     * @notice Compensate client (not used in ClientSponsor)
     */
    function compensateClient(
        address,
        uint256,
        bytes32
    ) external pure override {
        revert("Not implemented");
    }
    
    /**
     * @notice Get daily usage
     * @param client Client address
     * @param date Date timestamp
     * @return Daily usage amount
     */
    function getDailyUsage(address client, uint256 date) external view returns (uint256) {
        return clients[client].dailyUsage[date];
    }
    
    /**
     * @notice Authorize upgrade (UUPS)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyTimelockOrMultisig {
        address oldImpl = ERC1967Utils.getImplementation();
        emit UpgradeInitiated(oldImpl, newImplementation, block.timestamp);
    }
    
    /**
     * @notice Get owner address
     * @return Owner address
     */
    function owner() external view returns (address) {
        return _owner;
    }
}
