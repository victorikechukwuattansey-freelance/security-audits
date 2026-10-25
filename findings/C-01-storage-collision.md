# [C-01] Storage layout collision corrupts flash loan fee to 100% on upgrade

**Severity:** Critical
**Target:** Thunder Loan (CodeHawks AI First Flight #7)
**Location:** `upgradedProtocol/ThunderLoanUpgraded.sol` L93-L97
**PoC:** `test/poc/001-C-01-storage-collision.t.sol::test_UpgradeCorruptsFlashLoanFee`

## Root cause

The upgrade removes `s_feePrecision` from storage and replaces it with a
`constant FEE_PRECISION = 1e18`. Constants do not occupy storage slots, so
every variable declared after `s_feePrecision` shifts up by one slot.

**Original `ThunderLoan.sol` storage layout:**

| Slot | Variable | Value after initialize |
| :--- | :--- | :--- |
| X | `s_tokenToAssetToken` | mapping base |
| X+1 | `s_feePrecision` | 1e18 |
| X+2 | `s_flashLoanFee` | 3e15 |
| X+3 | `s_currentlyFlashLoaning` | mapping base |

**Upgraded `ThunderLoanUpgraded.sol` storage layout:**

| Slot | Variable | Type |
| :--- | :--- | :--- |
| X | `s_tokenToAssetToken` | mapping |
| X+1 | `s_flashLoanFee` | uint256 — **reads old `s_feePrecision` value (1e18)** |
| — | `FEE_PRECISION` | constant — no slot |
| X+2 | `s_currentlyFlashLoaning` | mapping — base is now old `s_flashLoanFee` (3e15) |

After the upgrade, `s_flashLoanFee` reads the value that was previously stored
in `s_feePrecision` — which is `1e18` (100%), not `3e15` (0.3%).

## PoC

```solidity
function test_UpgradeCorruptsFlashLoanFee() public {
    assertEq(tl.getFee(), 3e15, "pre-upgrade fee should be 0.3%");

    tl.upgradeTo(address(implUpgraded));

    uint256 postUpgradeFee = ThunderLoanUpgraded(address(proxy)).getFee();
    assertEq(postUpgradeFee, 1e18, "BUG: fee corrupted to 100% by storage collision");
}
```

Output:

```
[PASS] test_UpgradeCorruptsFlashLoanFee()
```

Pre-upgrade `getFee()` returns `3000000000000000` (3e15); post-upgrade returns
`1000000000000000000` (1e18).

## Impact

- Every flash loan after upgrade charges **100% of the token's value** as a fee
  (`valueOfBorrowedToken * 1e18 / 1e18 == valueOfBorrowedToken`), making the
  protocol unusable.
- The protocol is broken from the moment of upgrade, and no event is emitted
  indicating the fee was corrupted. An off-chain monitor watching
  `updateFlashLoanFee` events would not see the change.
- The owner must manually call `updateFlashLoanFee(3e15)` to restore functionality
  — but even that call succeeds silently, and the pre-upgrade fee value
  (`3e15`) is not recoverable from any on-chain state after the collision.

## Remediation

Preserve the storage slot. Two equivalent options:

**Option A — deprecated placeholder (recommended):**

```solidity
mapping(IERC20 => AssetToken) public s_tokenToAssetToken;
uint256 private __deprecated_s_feePrecision;   // slot X+1 preserved
uint256 private s_flashLoanFee;                // stays at slot X+2
uint256 public constant FEE_PRECISION = 1e18;
mapping(IERC20 => bool) private s_currentlyFlashLoaning;
```

**Option B — storage gap:**

```solidity
mapping(IERC20 => AssetToken) public s_tokenToAssetToken;
uint256 private s_flashLoanFee;                // moved to slot X+1 explicitly
uint256 public constant FEE_PRECISION = 1e18;
mapping(IERC20 => bool) private s_currentlyFlashLoaning;
uint256[1] private __gap;                      // eats the freed slot
```

Option A is safer — it keeps the layout byte-identical to the original, so no
other shift occurs.

## Retest

After applying the fix, `forge inspect ThunderLoanUpgraded storageLayout`
should show `s_flashLoanFee` at the same slot as the original `ThunderLoan`.
The PoC's `test_UpgradeCorruptsFlashLoanFee` will fail after the fix (because
`getFee()` correctly returns `3e15`), which is the expected post-fix behavior.

## Residual risk

If the fix instead reorders other storage variables to fill the freed slot,
a new collision may be introduced. The only safe pattern is to preserve the
original layout exactly, adding deprecated placeholders where variables were
removed.

**Recommended check:** `forge inspect ThunderLoan storageLayout` vs
`forge inspect ThunderLoanUpgraded storageLayout` — the layouts must match
through slot X+3.
