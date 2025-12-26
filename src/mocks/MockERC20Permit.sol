// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MockERC20Permit
 * @notice Mock ERC20 token with EIP-2612 Permit support for testing
 * @dev USDC-like token with 6 decimals
 */
contract MockERC20Permit is ERC20, ERC20Permit {
    uint8 public constant DECIMALS = 6;
    uint256 public constant MINT_AMOUNT = 100 * 10**DECIMALS; // 100 tokens with 6 decimals

    constructor(string memory name, string memory symbol) 
        ERC20(name, symbol) 
        ERC20Permit(name) 
    {}

    /**
     * @notice USDC는 6 decimals
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice 누구나 특정 주소에 100개 민팅 가능 (여러 번 실행 가능)
     */
    function mintTo(address to) external {
        _mint(to, MINT_AMOUNT);
    }
}

