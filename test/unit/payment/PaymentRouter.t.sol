// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {PaymentRouter} from "../../../src/payment/PaymentRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Permit is ERC20Permit {
    constructor() ERC20("Mock Permit Token", "MPT") ERC20Permit("Mock Permit Token") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PaymentRouterTest is Test {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    PaymentRouter public router;
    MockERC20Permit public token;

    address public owner;
    address public feeRecipient;
    address public receiver;

    uint256 public payerPk;
    address public payer;

    function setUp() public {
        owner = address(this);
        feeRecipient = address(0xFEE);
        receiver = address(0xBEEF);

        payerPk = 0xA11CE;
        payer = vm.addr(payerPk);

        router = new PaymentRouter(feeRecipient, owner);
        token = new MockERC20Permit();

        token.mint(payer, 1_000 ether);
    }

    function _signPermit(
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = token.nonces(payer);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, payer, address(router), value, nonce, deadline)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(payerPk, digest);
    }

    function test_PayWithPermit_SplitsAmountAndFee_EmitsEvent() public {
        bytes32 paymentRef = keccak256("payment-1");

        uint256 amount = 100 ether;
        uint256 fee = 5 ether;
        uint256 total = amount + fee;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(total, deadline);

        vm.expectEmit(true, true, true, true);
        emit PaymentRouter.PaymentExecuted(
            paymentRef,
            payer,
            receiver,
            address(token),
            amount,
            fee,
            feeRecipient
        );

        router.payWithPermit(
            paymentRef,
            address(token),
            payer,
            receiver,
            amount,
            fee,
            deadline,
            v,
            r,
            s
        );

        assertEq(token.balanceOf(receiver), amount);
        assertEq(token.balanceOf(feeRecipient), fee);
        assertEq(token.balanceOf(payer), 1_000 ether - total);

        // Allowance should be consumed by transferFrom calls
        assertEq(token.allowance(payer, address(router)), 0);
    }

    function test_PayWithPermit_ZeroFee_Works() public {
        bytes32 paymentRef = keccak256("payment-2");

        uint256 amount = 100 ether;
        uint256 fee = 0;
        uint256 total = amount + fee;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(total, deadline);

        router.payWithPermit(
            paymentRef,
            address(token),
            payer,
            receiver,
            amount,
            fee,
            deadline,
            v,
            r,
            s
        );

        assertEq(token.balanceOf(receiver), amount);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function test_PayWithPermit_ZeroAmount_Reverts() public {
        bytes32 paymentRef = keccak256("payment-3");

        uint256 amount = 0;
        uint256 fee = 1 ether;
        uint256 total = amount + fee;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(total, deadline);

        vm.expectRevert(PaymentRouter.ZeroAmount.selector);
        router.payWithPermit(
            paymentRef,
            address(token),
            payer,
            receiver,
            amount,
            fee,
            deadline,
            v,
            r,
            s
        );
    }

    function test_PayWithPermit_ExpiredPermit_Reverts() public {
        bytes32 paymentRef = keccak256("payment-4");

        uint256 amount = 10 ether;
        uint256 fee = 1 ether;
        uint256 total = amount + fee;
        uint256 deadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(total, deadline);

        vm.expectRevert();
        router.payWithPermit(
            paymentRef,
            address(token),
            payer,
            receiver,
            amount,
            fee,
            deadline,
            v,
            r,
            s
        );
    }

    function test_SetFeeRecipient_OnlyOwner() public {
        address newRecipient = address(0xCAFE);

        vm.prank(address(0xBAD));
        vm.expectRevert();
        router.setFeeRecipient(newRecipient);

        router.setFeeRecipient(newRecipient);
        assertEq(router.feeRecipient(), newRecipient);
    }
}


