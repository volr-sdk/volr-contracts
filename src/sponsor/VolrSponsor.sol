// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ISponsor} from "../interfaces/ISponsor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/**
 * @title VolrSponsor
 * @notice Upgradeable sponsor contract for Volr gas subsidy
 * @dev Uses UUPS proxy pattern with timelock governance
 */
contract VolrSponsor is ISponsor, ReentrancyGuard, Initializable, UUPSUpgradeable {
    mapping(bytes32 => uint256) public subsidyRates; // basis points (10000 = 100%)
    address public timelock;
    address public multisig;
    address private _owner;
    
    /// @notice Storage gap for future upgrades
    uint256[50] private __gap;
    
    error Unauthorized();
    error ZeroAddress();
    
    event SubsidyPaid(
        address indexed client,
        uint256 gasUsed,
        bytes32 indexed policyId,
        uint256 rate,
        uint256 timestamp
    );
    
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
     * @notice Set subsidy rate for a policy
     * @param policyId Policy ID
     * @param rate Rate in basis points (10000 = 100%)
     */
    function setSubsidyRate(bytes32 policyId, uint256 rate) external onlyOwner {
        require(rate <= 10000, "Rate exceeds 100%");
        subsidyRates[policyId] = rate;
    }
    
    /**
     * @notice Compensate client with subsidy
     * @param client Client address
     * @param gasUsed Gas used
     * @param policyId Policy ID
     */
    function compensateClient(
        address client,
        uint256 gasUsed,
        bytes32 policyId
    ) external override nonReentrant {
        uint256 rate = subsidyRates[policyId];
        
        if (rate == 0) {
            // 보조금 없음
            return;
        }
        
        // 보조금 계산
        uint256 subsidy = (gasUsed * rate) / 10000;
        
        // 보조금 지급 (on-chain)
        if (subsidy > 0 && address(this).balance >= subsidy) {
            payable(client).transfer(subsidy);
        }
        
        // 이벤트 발생 (오프체인 정산용)
        emit SubsidyPaid(client, gasUsed, policyId, rate, block.timestamp);
    }
    
    /**
     * @notice Handle sponsorship (not used in VolrSponsor)
     */
    function handleSponsorship(
        address,
        uint256,
        bytes32
    ) external pure override {
        revert("Not implemented");
    }
    
    /**
     * @notice Receive ETH
     */
    receive() external payable {
        // ETH 수신 허용
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
