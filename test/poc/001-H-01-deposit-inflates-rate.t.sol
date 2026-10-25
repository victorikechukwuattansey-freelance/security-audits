// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {AssetToken} from "./vendor/protocol/AssetToken.sol";
import {MockPoolFactory} from "./vendor/mocks/MockPoolFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice H-01: `deposit` calls `assetToken.updateExchangeRate(fee)` with a fee
///         computed from the deposit amount but never paid by anyone. The rate
///         inflates above 1.0, which breaks `redeem` — because `redeem` computes
///         `amountUnderlying = shares * rate / PRECISION` and passes it to
///         `AssetToken.burn`, once `rate > PRECISION` every redemption reverts
///         with "burn amount exceeds balance". The protocol becomes a one-way trap.
contract H01DepositBreaksRedeem is Test {
    ThunderLoan internal tl;
    AssetToken internal assetToken;
    MockToken internal token;
    MockPoolFactory internal poolFactory;

    address internal alice = makeAddr("alice");

    function setUp() public {
        poolFactory = new MockPoolFactory();
        token = new MockToken();

        ThunderLoan impl = new ThunderLoan();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeWithSignature("initialize(address)", address(poolFactory)));
        tl = ThunderLoan(address(proxy));

        poolFactory.createPool(address(token));
        assetToken = tl.setAllowedToken(token, true);

        token.mint(alice, 1_000 ether);
        vm.prank(alice);
        token.approve(address(tl), type(uint256).max);
    }

    function test_DepositBreaksRedeem() public {
        /// @notice H-01: `deposit` calls `assetToken.updateExchangeRate(fee)` with a fee
        ///         computed from the deposit amount but never paid by anyone. The rate
        ///         inflates above 1.0 without underlying tokens to back the increase.
        ///
        ///         Consequence 1 (DoS): after any deposit, redeem reverts because the
        ///         inflated `amountUnderlying` exceeds the actual token balance held by
        ///         AssetToken. Every depositor's funds are locked.
        ///
        ///         Consequence 2 (insolvency): even if the revert were resolved, aggregate
        ///         claims (Σ shares × rate) exceed AssetToken's underlying balance by the
        ///         accumulated phantom fee. The contract cannot honor all claims.
        // ─── Baseline: rate starts at 1.0 ──────────────────────────────
        assertEq(assetToken.getExchangeRate(), 1e18, "baseline: rate should be 1.0");

        // ─── Alice deposits 500 tokens ─────────────────────────────────
        vm.prank(alice);
        tl.deposit(token, 500 ether);

        uint256 inflatedRate = assetToken.getExchangeRate();
        uint256 aliceShares = assetToken.balanceOf(alice);

        // Rate has been inflated by the phantom fee (~1.003) — no tokens backed it
        assertGt(inflatedRate, 1e18, "BUG (H-01): rate inflated above 1.0 by phantom fee");
        assertGt(aliceShares, 0, "alice holds shares");

        // ─── Alice cannot redeem her OWN shares ────────────────────────
        // `redeem` computes amountUnderlying = shares * rate / 1e18 > shares,
        // then burns that inflated amount — which exceeds her share balance.
        vm.prank(alice);
        // Revert at safeTransfer, not burn — proves the contract has fewer tokens
        // than the inflated claim it computed. Alice's 500 shares claim 501.5 tokens,
        // but AssetToken holds exactly 500. This is the insolvency in one call.
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        tl.redeem(token, aliceShares);
    }

    function test_DepositInflatesAggregateClaimsBeyondBalance() public {
        vm.prank(alice);
        tl.deposit(token, 500 ether);

        uint256 shares = assetToken.balanceOf(alice);
        uint256 rate = assetToken.getExchangeRate();
        uint256 balance = token.balanceOf(address(assetToken));
        uint256 aliceClaim = (shares * rate) / assetToken.EXCHANGE_RATE_PRECISION();

        // Even ignoring redeem's DoS, the accounting is already insolvent:
        // alice's shares * rate exceeds the actual underlying token balance.
        assertGt(aliceClaim, balance, "BUG (H-01): aggregate claim exceeds contract's actual underlying balance");
    }
}
