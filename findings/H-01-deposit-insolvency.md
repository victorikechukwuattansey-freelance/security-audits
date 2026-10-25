# [H-01] Deposit inflates aggregate claims beyond underlying balance (latent insolvency)

**Severity:** High
**Target:** Thunder Loan (CodeHawks AI First Flight #7)
**Location:** `protocol/ThunderLoan.sol` L147-L157 (deposit), `protocol/AssetToken.sol` L80-L97 (updateExchangeRate)
**PoC:** `test/poc/001-H-01-deposit-inflates-rate.t.sol::test_DepositInflatesAggregateClaimsBeyondBalance`

## Root cause

Same root cause as C-02 (`deposit` calls `updateExchangeRate` with a phantom
fee), but a different consequence: **even if the C-02 DoS were bypassed** —
for example, by wrapping the redemption in a try/catch and paying pro-rata —
the accounting would still be insolvent.

After any deposit:

```
sum(share_balance[user] * exchangeRate / PRECISION) > token.balanceOf(assetToken)
```

The shortfall equals `sum(calculatedFee) / PRECISION * totalSupply`, growing
with every deposit.

## PoC

```solidity
function test_DepositInflatesAggregateClaimsBeyondBalance() public {
    vm.prank(alice);
    tl.deposit(token, 500 ether);

    uint256 shares = assetToken.balanceOf(alice);
    uint256 rate   = assetToken.getExchangeRate();
    uint256 balance = token.balanceOf(address(assetToken));
    uint256 aliceClaim = (shares * rate) / assetToken.EXCHANGE_RATE_PRECISION();

    assertGt(aliceClaim, balance, "aggregate claim exceeds underlying balance");
}
```

Output:

```
[PASS] test_DepositInflatesAggregateClaimsBeyondBalance()
```

## Impact

If a future fix addresses C-02 by deferring the revert (e.g., a queue-based
redemption system, or a pro-rata payout), H-01 remains: the contract cannot
honor all claims. The last redeemer loses the difference between their
inflated claim and the remaining balance.

This finding is distinct from C-02 because it is a **state-consistency**
problem, not a **control-flow** problem. Fixing the revert does not fix the
solvency; fixing the solvency eliminates both.

## Remediation

Same as C-02 — remove the two lines from `deposit`. There is no path to
solvency while `updateExchangeRate` is called with a phantom fee.

## Retest

Against `ThunderLoanUpgraded.sol`, the equivalent
`test_DepositInflatesAggregateClaimsBeyondBalance` passes with the opposite
assertion: `aliceClaim == balance` (exactly, since rate stays at `1e18`).

## Residual risk

Same as C-02: if any future code path calls `AssetToken.updateExchangeRate`
with an unbacked fee, insolvency returns. The fix is structural — the rate
must be derived from `totalAssets / totalSupply`, not pushed externally.
