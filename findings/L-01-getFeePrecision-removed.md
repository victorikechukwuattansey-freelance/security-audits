# [L-01] Upgrade removes getFeePrecision() getter, breaking external integrators

**Severity:** Low
**Target:** Thunder Loan (CodeHawks AI First Flight #7)
**Location:** `upgradedProtocol/ThunderLoanUpgraded.sol` (removed function)
**PoC:** `test/poc/001-L-01-getFeePrecision-removed.t.sol::test_GetFeePrecisionRemovedAfterUpgrade`

## Root cause

`ThunderLoan.getFeePrecision()` is a public view function that returns the
current fee precision (1e18). The upgrade removes it entirely.

## PoC

```solidity
function test_GetFeePrecisionRemovedAfterUpgrade() public {
    assertEq(tl.getFeePrecision(), 1e18, "pre-upgrade: getter exists");

    tl.upgradeTo(address(implUpgraded));

    (bool ok,) = address(proxy).call(abi.encodeWithSignature("getFeePrecision()"));
    assertFalse(ok, "getFeePrecision removed in upgrade");
}
```

Output:

```
[PASS] test_GetFeePrecisionRemovedAfterUpgrade()
```

## Impact

Any off-chain monitor, dashboard, or on-chain integrator that calls
`getFeePrecision()` will break silently after the upgrade. Because the value
is now a `constant` (`FEE_PRECISION = 1e18`), the information is still
accessible via reading the contract bytecode or docs, but not via the ABI.

Severity is Low because:

- No funds are at risk.
- The value (`1e18`) is now fixed and documented in code.

But it warrants reporting because the upgrade path should be
interface-preserving where possible, and a one-line fix preserves compatibility.

## Remediation

Keep the getter, return the constant:

```solidity
function getFeePrecision() external pure returns (uint256) {
    return FEE_PRECISION;
}
```

## Retest

After the fix, `test_GetFeePrecisionRemovedAfterUpgrade` fails its second
assertion (because `ok == true`), which is the expected post-fix behavior.

## Residual risk

None identified. The removed getter is easily restored.
