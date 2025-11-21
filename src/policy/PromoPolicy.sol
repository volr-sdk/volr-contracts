// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IPolicy} from "../interfaces/IPolicy.sol";
import {Types} from "../libraries/Types.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PromoPolicy
 * @notice Stateful policy that tracks promo budgets per client
 * @dev Consumes budget on successful execution
 */
contract PromoPolicy is IPolicy, Ownable, ReentrancyGuard {
    /// @notice Pricing mode: 0 = gas-based, 1 = fixed per call
    uint256 public pricingMode;
    
    /// @notice Price per gas (for gas-based pricing)
    uint256 public pricePerGas;
    
    /// @notice Fixed price per call (for fixed pricing)
    uint256 public fixedPricePerCall;
    
    /// @notice Remaining budget per client
    mapping(address => uint256) public budgets;
    
    error InsufficientBudget();
    error InvalidPricingMode();
    
    event PromoBudgetSet(address indexed client, uint256 amount);
    event PromoConsumed(address indexed client, uint256 amount, bytes32 policyId);
    event PricingModeSet(uint256 mode);
    event PricePerGasSet(uint256 price);
    event FixedPricePerCallSet(uint256 price);
    
    constructor() Ownable(msg.sender) {
        pricingMode = 0; // Default to gas-based
        pricePerGas = 1; // 1 wei per gas
    }
    
    /**
     * @notice Set pricing mode
     * @param mode 0 = gas-based, 1 = fixed per call
     */
    function setPricingMode(uint256 mode) external onlyOwner {
        if (mode > 1) revert InvalidPricingMode();
        pricingMode = mode;
        emit PricingModeSet(mode);
    }
    
    /**
     * @notice Set price per gas (for gas-based pricing)
     * @param price Price per gas in wei
     */
    function setPricePerGas(uint256 price) external onlyOwner {
        pricePerGas = price;
        emit PricePerGasSet(price);
    }
    
    /**
     * @notice Set fixed price per call (for fixed pricing)
     * @param price Fixed price per call in wei
     */
    function setFixedPricePerCall(uint256 price) external onlyOwner {
        fixedPricePerCall = price;
        emit FixedPricePerCallSet(price);
    }
    
    /**
     * @notice Set promo budget for a client
     * @param client Client address
     * @param amount Budget amount
     */
    function setBudget(address client, uint256 amount) external onlyOwner {
        budgets[client] = amount;
        emit PromoBudgetSet(client, amount);
    }
    
    /**
     * @notice Validate session auth and calls
     * @param auth Session authorization data
     * @param calls Array of calls to validate
     * @return ok Whether validation passed
     * @return code Error code if validation failed
     */
    function validate(
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls
    ) external pure override returns (bool ok, uint256 code) {
        // Always pass validation - budget check happens in onExecuted
        // auth and calls are unused but kept for interface compatibility
        auth;
        calls;
        return (true, 0);
    }
    
    /**
     * @notice Hook called after successful execution
     * @param executor Address that executed the calls
     * @param auth Session authorization data
     * @param calls Array of calls that were executed
     * @param gasUsed Gas used for execution
     */
    function onExecuted(
        address executor,
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls,
        uint256 gasUsed
    ) external override nonReentrant {
        // Determine cost based on pricing mode
        uint256 cost;
        if (pricingMode == 0) {
            // Gas-based pricing
            cost = gasUsed * pricePerGas;
        } else {
            // Fixed per call
            cost = calls.length * fixedPricePerCall;
        }
        
        // Get client address (assuming executor is the client)
        address client = executor;
        
        // Check budget
        if (budgets[client] < cost) {
            revert InsufficientBudget();
        }
        
        // Consume budget
        budgets[client] -= cost;
        
        // Emit event
        emit PromoConsumed(client, cost, auth.policyId);
    }
    
    /**
     * @notice Hook called after failed execution (no-op)
     * @param executor Address that executed the calls
     * @param auth Session authorization data
     * @param calls Array of calls that were executed
     * @param reason Revert reason
     */
    function onFailed(
        address executor,
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls,
        bytes calldata reason
    ) external override {
        // No-op on failure - don't consume budget
    }
}






