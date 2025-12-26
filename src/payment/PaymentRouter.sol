// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PaymentRouter
 * @notice Executes an ERC-20 payment using EIP-2612 permit so the payer only signs once.
 *
 * Flow:
 * 1) Payer signs permit(owner=payer, spender=router, value=amount+fee, deadline, v/r/s).
 * 2) Relayer calls payWithPermit() with the signature.
 * 3) Router transfers `amount` to receiver and `fee` to feeRecipient.
 *
 * Notes:
 * - This contract does NOT enforce uniqueness of paymentRef.
 *   Idempotency is handled at the application layer (paymentId/idempotencyKey).
 * - The token MUST support EIP-2612; otherwise permit() will revert.
 */
contract PaymentRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event PaymentExecuted(
        bytes32 indexed paymentRef,
        address indexed payer,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 fee,
        address feeRecipient
    );

    error ZeroAddress();
    error ZeroAmount();

    address public feeRecipient;

    constructor(address _feeRecipient, address _owner) Ownable(_owner) {
        if (_feeRecipient == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }
        feeRecipient = _feeRecipient;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert ZeroAddress();
        }
        feeRecipient = _feeRecipient;
    }

    function payWithPermit(
        bytes32 paymentRef,
        address token,
        address payer,
        address receiver,
        uint256 amount,
        uint256 fee,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        if (token == address(0) || payer == address(0) || receiver == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 total = amount + fee;

        // Approve router as spender via EIP-2612 permit
        IERC20Permit(token).permit(payer, address(this), total, deadline, v, r, s);

        // Execute transfers
        IERC20(token).safeTransferFrom(payer, receiver, amount);
        if (fee > 0) {
            IERC20(token).safeTransferFrom(payer, feeRecipient, fee);
        }

        emit PaymentExecuted(paymentRef, payer, receiver, token, amount, fee, feeRecipient);
    }
}


