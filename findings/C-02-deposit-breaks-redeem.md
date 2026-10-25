# [C-02] Deposit inflates exchange rate without backing, permanently blocking all redemptions

**Severity:** Critical
**Target:** Thunder Loan (CodeHawks AI First Flight #7)
**Location:** `protocol/ThunderLoan.sol` L147-L157 (deposit), L161-L179 (redeem)
**PoC:** `test/poc/001-H-01-deposit-inflates-rate.t.sol::test_DepositBreaksRedeem`

## Root cause

`deposit` calls `assetToken.updateExchangeRate(calculatedFee)` **before** the
depositor's tokens are transferred into `AssetToken`. The `calculatedFee` is
computed from the deposit amount but is never actually paid by anyone — no
underlying token transfer backs the rate increase.

```solidity
// ThunderLoan.sol L147-L157
function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
    AssetToken assetToken = s_tokenToAssetToken[token];
    uint256 exchangeRate = assetToken.getExchangeRate();
    uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
    emit Deposit(msg.sender, token, amount);
    assetToken.mint(msg.sender, mintAmount);
    uint256 calculatedFee = getCalculatedFee(token, amount);
    assetToken.updateExchangeRate(calculatedFee);   // phantom fee, no tokens back it
    token.safeTransferFrom(msg.sender, address(assetToken), amount);
}
```

`AssetToken.s_exchangeRate` therefore increases by `calculatedFee / totalSupply`
on every deposit, without a corresponding increase in underlying token balance.

Consequently, `redeem` (L161-L179) computes:

```solidity
uint256 amountUnderlying = (amountOfAssetToken * exchangeRate) / assetToken.EXCHANGE_RATE_PRECISION();
```

With `exchangeRate > 1e18`, `amountUnderlying > amountOfAssetToken`. The
`AssetToken` contract holds only `sum of deposits` in underlying tokens — never
the phantom fee. When `redeem` attempts to `safeTransfer` the inflated amount,
the transfer reverts with `ERC20: transfer amount exceeds balance`.

## PoC

```solidity
function test_DepositBreaksRedeem() public {
    // Baseline
    assertEq(assetToken.getExchangeRate(), 1e18);

    // Single deposit
    vm.prank(alice);
    tl.deposit(token, 500 ether);

    uint256 inflatedRate = assetToken.getExchangeRate();
    assertGt(inflatedRate, 1e18, "rate inflated above 1.0 by phantom fee");

    // Alice cannot redeem her own shares
    vm.prank(alice);
    vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
    tl.redeem(token, assetToken.balanceOf(alice));
}
```

Output:

```
[PASS] test_DepositBreaksRedeem()
```

The revert is at `safeTransfer`, not at `burn`. Shares are burned correctly;
the shortfall is in the underlying token balance — the contract literally does
not have enough tokens to pay the inflated claim.

## Impact

**Deposits are permanently locked.** After any deposit, no user can redeem
until the contract is upgraded or a rescue mechanism exists. This is not a
theoretical DoS — it is a certainty triggered by the first legitimate
deposit, and it affects every depositor.

Severity is Critical: users cannot withdraw their funds, and there is no
on-chain path to recovery short of a UUPS upgrade (which is itself subject to
C-01).

## Remediation

Remove the two offending lines from `deposit` — exactly what
`ThunderLoanUpgraded` does:

```solidity
- uint256 calculatedFee = getCalculatedFee(token, amount);
- assetToken.updateExchangeRate(calculatedFee);
```

Fee accrual, if desired, must be funded by tokens actually transferred into
`AssetToken`. The deposit path should not call `updateExchangeRate` at all —
the correct model is that `AssetToken` holds the underlying and its rate is
derived from `(totalAssets / totalSupply)`, not pushed by the parent contract.

## Retest

The `test_DepositBreaksRedeem` PoC currently passes against `ThunderLoan.sol`.
Against `ThunderLoanUpgraded.sol`, the same deposit succeeds and redeem
proceeds normally (because the rate stays at `1e18`).

## Residual risk

`AssetToken.updateExchangeRate` is only reachable from `ThunderLoan.deposit`.
If a future upgrade re-adds a phantom-fee call from any other path, the same
DoS returns. A defensive check inside `AssetToken.updateExchangeRate`
(`require(newRate * totalSupply <= token.balanceOf(address(this)) + newFee)`)
would prevent the class of bug entirely, but the simplest fix is not to call
it from `deposit`.
