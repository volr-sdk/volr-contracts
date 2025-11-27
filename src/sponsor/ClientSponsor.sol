// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
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
        // bytes32 policyId; // DEPRECATED: Replaced by allowedPolicies mapping
        uint256 dailyLimit;
        uint256 perTxLimit;
        mapping(uint256 => uint256) dailyUsage; // date => amount
        mapping(bytes32 => bool) allowedPolicies; // New: Multi-policy support
    }
    
    mapping(address => ClientConfig) public clients;
    mapping(bytes32 => address) public policyToClient; // Policy -> Client mapping
    mapping(address => mapping(bytes32 => FailureCounter)) public failureCounters;
    address public volrSponsor;
    address public timelock;
    address public multisig;
    address private _owner;
    address public invoker; // Authorized invoker address (F1 fix)
    
    // Anti-grief configs
    uint256 public minGasPerTx;           // 최소 가스 사용량(wei 단위 또는 gasUsed 포인트)
    uint256 public userRpsLimit;          // 사용자별 초당 트랜잭션 허용 횟수
    uint256 public userRpsWindowSeconds;  // 윈도 크기(초)
    struct RpsState { uint256 windowStart; uint256 count; }
    mapping(address => RpsState) public userRps;
    
    /// @notice Storage gap for future upgrades
    uint256[50] private __gap;
    
    error Unauthorized();
    error NotThroughProxy();
    error ZeroAddress();
    error NotInvoker();
    
    event SponsorshipUsed(
        address indexed client,
        address indexed user,
        uint256 gasUsed,
        bytes32 indexed policyId,
        uint256 timestamp
    );
    
    event BudgetSet(address indexed client, uint256 budget);
    event PolicySet(address indexed client, bytes32 policyId); // Legacy event, still emitted for compatibility/logging
    event PolicyAdded(address indexed client, bytes32 policyId);
    event PolicyRemoved(address indexed client, bytes32 policyId);
    event TimelockSet(address indexed timelock);
    event MultisigSet(address indexed multisig);
    event UpgradeInitiated(address indexed oldImpl, address indexed newImpl, uint256 eta);
    event UpgradeExecuted(address indexed oldImpl, address indexed newImpl, uint256 timestamp);
    event AntiGriefSet(uint256 minGasPerTx, uint256 userRpsLimit, uint256 userRpsWindowSeconds);
    event AttemptFeeCharged(address indexed client, address indexed user, uint256 amount, bytes32 indexed policyId, uint256 timestamp);
    event InvokerSet(address indexed invoker);
    event RefundFailed(address indexed relayer, uint256 amount); // Phase 2-5: Fail-open refund event
    
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
        _checkOwner();
        _;
    }
    
    function _checkOwner() internal view {
        require(msg.sender == _owner, "Not owner");
    }
    
    /**
     * @notice Modifier to restrict access to timelock or multisig
     */
    modifier onlyTimelockOrMultisig() {
        _checkTimelockOrMultisig();
        _;
    }
    
    function _checkTimelockOrMultisig() internal view {
        if (msg.sender != timelock && msg.sender != multisig) revert Unauthorized();
    }
    
    /**
     * @notice Modifier to restrict access to invoker only
     * @dev EIP-7702 compatible: checks if caller's bytecode matches invoker's bytecode
     *      In EIP-7702 context:
     *      - msg.sender = User EOA (delegating to VolrInvoker bytecode)
     *      - invoker = VolrInvoker contract address
     *      - msg.sender.codehash == invoker.codehash (both have VolrInvoker bytecode)
     */
    modifier onlyInvoker() {
        _checkInvoker();
        _;
    }
    
    function _checkInvoker() internal view {
        // EIP-7702 compatible check:
        // - Direct call: msg.sender == invoker (standard case)
        // - EIP-7702: msg.sender.codehash == invoker.codehash (EOA delegating to invoker bytecode)
        if (msg.sender != invoker && msg.sender.codehash != invoker.codehash) {
            revert NotInvoker();
        }
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
     * @notice Set invoker address (F1 fix)
     * @param _invoker Invoker address
     */
    function setInvoker(address _invoker) external onlyOwner {
        if (_invoker == address(0)) revert ZeroAddress();
        invoker = _invoker;
        emit InvokerSet(_invoker);
    }
    
    /**
     * @notice Set anti-grief parameters
     */
    function setAntiGrief(
        uint256 _minGasPerTx,
        uint256 _userRpsLimit,
        uint256 _userRpsWindowSeconds
    ) external onlyOwner {
        minGasPerTx = _minGasPerTx;
        userRpsLimit = _userRpsLimit;
        userRpsWindowSeconds = _userRpsWindowSeconds == 0 ? 1 : _userRpsWindowSeconds;
        emit AntiGriefSet(minGasPerTx, userRpsLimit, userRpsWindowSeconds);
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
     * @notice Add allowed policy for client
     */
    function addPolicy(address client, bytes32 policyId) external onlyOwner {
        clients[client].allowedPolicies[policyId] = true;
        emit PolicyAdded(client, policyId);
    }

    /**
     * @notice Remove allowed policy for client
     */
    function removePolicy(address client, bytes32 policyId) external onlyOwner {
        clients[client].allowedPolicies[policyId] = false;
        emit PolicyRemoved(client, policyId);
    }

    /**
     * @notice Set client policy (Legacy support: adds policy, does not clear others)
     * @param client Client address
     * @param policyId Policy ID
     */
    function setPolicy(address client, bytes32 policyId) external onlyOwner {
        // Legacy behavior: was setting a single field. Now we just enable it in the set.
        clients[client].allowedPolicies[policyId] = true;
        emit PolicySet(client, policyId);
        emit PolicyAdded(client, policyId);
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
     * @notice Deposit ETH and initialize policy for client (gasless onboarding)
     * @dev Called by backend relayer when client deposits or uses coupon
     * @param client Client address
     * @param policyId Policy ID to enable
     */
    function depositAndInitialize(
        address client,
        bytes32 policyId
    ) external payable {
        // 1. Fund Budget (can be 0 if just initializing policy)
        if (msg.value > 0) {
            clients[client].budget += msg.value;
            emit BudgetSet(client, clients[client].budget);
        }
        
        // 2. Enable Policy (if not already)
        if (!clients[client].allowedPolicies[policyId]) {
            clients[client].allowedPolicies[policyId] = true;
            emit PolicyAdded(client, policyId);
        }
        
        // Map policy to client (overwrites if reassigned, but typically 1-to-1 in our model)
        policyToClient[policyId] = client;
        
        // 3. Set Default Limits (if 0) - Unlimited
        if (clients[client].dailyLimit == 0) {
            clients[client].dailyLimit = type(uint256).max;
        }
        if (clients[client].perTxLimit == 0) {
            clients[client].perTxLimit = type(uint256).max;
        }
    }
    
    /**
     * @notice Handle sponsorship request (F1 fix: onlyInvoker + explicit relayer)
     * @param user User address
     * @param gasUsed Gas used
     * @param policyId Policy ID
     * @param relayer Address to receive gas refund (replaces tx.origin)
     */
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId,
        address relayer
    ) external override nonReentrant {
        // TODO: onlyInvoker 제거됨 - 7702 환경 테스트용. 메인넷 전 재검토 필요
        require(relayer != address(0), "Invalid relayer");
        
        address client = policyToClient[policyId];
        require(client != address(0), "Policy not mapped to client");

        ClientConfig storage config = clients[client];
        FailureCounter storage counter = failureCounters[client][policyId];
        
        // Anti-grief: 최소 가스 임계
        if (minGasPerTx > 0) {
            require(gasUsed >= minGasPerTx, "Below min gas per tx");
        }
        // Anti-grief: 사용자 RPS 제한
        if (userRpsLimit > 0) {
            RpsState storage rs = userRps[user];
            if (block.timestamp - rs.windowStart >= userRpsWindowSeconds) {
                rs.windowStart = block.timestamp;
                rs.count = 0;
            }
            require(rs.count < userRpsLimit, "RPS limit exceeded");
            rs.count += 1;
        }
        
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
        
        // Policy 검증 (Multi-policy check)
        require(config.allowedPolicies[policyId], "Policy not allowed for client");
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

        // Refund Relayer with ETH from client's budget (F1 fix: explicit relayer, not tx.origin)
        // Since budget is already deducted, we just transfer ETH to relayer
        // Note: This assumes ClientSponsor holds enough ETH (budget tracks ETH)
        // Phase 2-5 fix: Fail-open - emit event on failure instead of reverting
        // This prevents malicious relayers from griefing by rejecting refunds
        (bool success, ) = relayer.call{value: gasUsed}("");
        if (!success) {
            emit RefundFailed(relayer, gasUsed);
            // Transaction continues - relayer's responsibility to accept ETH
        }
    }
    
    /**
     * @notice Record failure for circuit breaker (F1 fix: onlyInvoker)
     * @param client Client address
     * @param policyId Policy ID
     */
    function recordFailure(address client, bytes32 policyId) external {
        // TODO: onlyInvoker 제거됨 - 7702 환경 테스트용. 메인넷 전 재검토 필요
        FailureCounter storage counter = failureCounters[client][policyId];
        counter.consecutiveFailures++;
        counter.windowFailures++;
        counter.lastFailureTime = block.timestamp;
    }
    
    /**
     * @notice Record failure and optionally charge attempt fee (F1 fix: onlyInvoker)
     */
    function recordFailureAndCharge(
        address client,
        address user,
        bytes32 policyId,
        uint256 attemptFee
    ) external {
        // TODO: onlyInvoker 제거됨 - 7702 환경 테스트용. 메인넷 전 재검토 필요
        FailureCounter storage counter = failureCounters[client][policyId];
        counter.consecutiveFailures++;
        counter.windowFailures++;
        counter.lastFailureTime = block.timestamp;
        
        if (attemptFee > 0) {
            ClientConfig storage config = clients[client];
            require(config.budget >= attemptFee, "Insufficient budget");
            config.budget -= attemptFee;
            emit AttemptFeeCharged(client, user, attemptFee, policyId, block.timestamp);
        }
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
        // Phase 2-6 fix: Verify newImplementation is a contract (not EOA)
        require(newImplementation.code.length > 0, "Implementation is not a contract");
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
