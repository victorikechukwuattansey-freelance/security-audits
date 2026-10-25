// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {ThunderLoanUpgraded} from "./vendor/upgradedProtocol/ThunderLoanUpgraded.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice C-01: Upgrade from ThunderLoan to ThunderLoanUpgraded collides storage.
///         `s_feePrecision` is removed and `FEE_PRECISION` is a `constant` (no slot),
///         shifting `s_flashLoanFee` from slot X+2 to X+1 - where `s_feePrecision`'s
///         value (1e18) is read as the new fee.
contract C01StorageCollision is Test {
    ThunderLoan internal impl;
    ThunderLoanUpgraded internal implUpgraded;
    ERC1967Proxy internal proxy;
    ThunderLoan internal tl;

    function setUp() public {
        impl = new ThunderLoan();
        proxy = new ERC1967Proxy(address(impl), abi.encodeWithSignature("initialize(address)", address(0xBEEF)));
        tl = ThunderLoan(address(proxy));
        implUpgraded = new ThunderLoanUpgraded();
    }

    function test_UpgradeCorruptsFlashLoanFee() public {
        // Pre-upgrade: 0.3% = 3e15
        assertEq(tl.getFee(), 3e15, "pre-upgrade fee should be 0.3% (3e15)");

        // Upgrade
        tl.upgradeTo(address(implUpgraded));

        // Post-upgrade: reads OLD s_feePrecision (1e18) as the new s_flashLoanFee
        ThunderLoanUpgraded upgraded = ThunderLoanUpgraded(address(proxy));
        uint256 postUpgradeFee = upgraded.getFee();

        assertEq(
            postUpgradeFee, 1e18, "BUG (C-01): fee corrupted to 100% by storage collision (expected 3e15, got 1e18)"
        );
    }
}
