// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ThunderLoan} from "./vendor/protocol/ThunderLoan.sol";
import {ThunderLoanUpgraded} from "./vendor/upgradedProtocol/ThunderLoanUpgraded.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice L-01: `getFeePrecision()` is a public getter on `ThunderLoan`.
///         The upgrade removes it entirely. External integrations break silently.
contract L01GetFeePrecisionRemoved is Test {
    ThunderLoan internal tl;
    ERC1967Proxy internal proxy;

    function setUp() public {
        ThunderLoan impl = new ThunderLoan();
        proxy = new ERC1967Proxy(address(impl), abi.encodeWithSignature("initialize(address)", address(0xBEEF)));
        tl = ThunderLoan(address(proxy));
    }

    function test_GetFeePrecisionRemovedAfterUpgrade() public {
        // Pre-upgrade: getter exists
        assertEq(tl.getFeePrecision(), 1e18, "pre-upgrade: getFeePrecision() returns 1e18");

        // Upgrade
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        tl.upgradeTo(address(upgraded));

        // Post-upgrade: selector no longer exists
        (bool ok,) = address(proxy).call(abi.encodeWithSignature("getFeePrecision()"));
        assertFalse(ok, "BUG (L-01): getFeePrecision() was removed in the upgrade - breaks external integrators");
    }
}
