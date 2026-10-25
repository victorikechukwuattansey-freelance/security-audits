// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {AssetToken} from "./vendor/protocol/AssetToken.sol";
import {MockPoolFactory} from "./vendor/mocks/MockPoolFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";

/// @notice M-01: setAllowedToken(token, false) deletes s_tokenToAssetToken[token]
///         while LPs still hold AssetToken shares. redeem() is gated by
///         revertIfNotAllowedToken(token), so once the mapping is deleted there
///         is no path to burn shares or withdraw underlying. The owner can
///         permanently lock every depositor's funds with a single call.
contract M01SetAllowedLocksLP is Test {
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

    function test_DisallowingTokenPermanentlyLocksLP() public {
        // ── LP deposits ───────────────────────────────────────────────────
        token.mint(lp, 1_000 ether);
        vm.prank(lp);
        token.approve(address(tl), type(uint256).max);
        vm.prank(lp);
        tl.deposit(token, 1_000 ether);

        uint256 shares = assetToken.balanceOf(lp);
        assertEq(shares, 1_000 ether, "LP holds 1,000 shares");
        assertEq(token.balanceOf(address(assetToken)), 1_000 ether, "pool holds 1,000 tokens");

        // ── Owner disallows the token ─────────────────────────────────────
        tl.setAllowedToken(token, false);
        assertEq(address(tl.getAssetFromToken(token)), address(0), "mapping deleted");

        // ── LP cannot redeem ──────────────────────────────────────────────
        vm.prank(lp);
        vm.expectRevert(); // ThunderLoan__NotAllowedToken
        tl.redeem(token, shares);

        // Verify the underlying tokens are still in the AssetToken contract —
        // the funds exist, they're just permanently inaccessible via redeem().
        assertEq(token.balanceOf(address(assetToken)), 1_000 ether, "funds locked, not stolen");
    }
}
