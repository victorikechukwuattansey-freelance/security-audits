# Lending protocol invariant checklist

## Solvency
- [ ] total debt ≤ total collateral × liquidation threshold
- [ ] no borrow without sufficient collateral
- [ ] interest accrual cannot make a healthy position instantly liquidatable
- [ ] liquidation cannot seize more than the debt plus bonus

## Oracle
- [ ] price reads are not manipulable within a single transaction
- [ ] stale prices are rejected (timestamp check)
- [ ] no spot-price reads from a manipulable pool

## Reentrancy
- [ ] every external call happens after state is consistent
- [ ] view functions (`healthFactor`, `getPrice`) are not observable mid-transition
- [ ] cross-function paths to the same state are guarded

## Access
- [ ] admin functions are gated
- [ ] no unguarded initializer
- [ ] no delegatecall to user-controlled address

## Arithmetic
- [ ] rounding direction favors the protocol, not the user
- [ ] no unchecked overflow on share/asset conversion
- [ ] first-depositor inflation is mitigated

## Protocol-accounting reentrancy
- [ ] Does any post-callback check validate *balance* rather than *intent*?
      (e.g. `endingBalance >= startingBalance + fee`)
- [ ] Can the borrower satisfy that check by calling a *different* state-mutating
      function that touches the same balance? (deposit, transfer, mint)
- [ ] Is the guard on the outer function mirrored on **every** function that
      reaches the same state? (This is VaultCrossFunction from reentrancy-lab.)

## ERC-20 transfer semantics
- [ ] Does any path credit `amount` (the parameter) rather than the *received*
      amount? Fee-on-transfer / rebasing tokens break the equality
      `amount sent == amount received`.
- [ ] Does deposit measure `balanceBefore`/`balanceAfter` around
      `safeTransferFrom` and mint against the delta?
- [ ] If fee-on-transfer is "known/out of scope," is the *specific* impact
      (LP dilution, drain) documented? If not, it is still a finding.

## Admin state transitions
- [ ] Can any `onlyOwner` function leave users unable to exit?
      (allowlist removal, pause with no unpause, delete of a required mapping)
- [ ] Before deleting/zeroing state, is there a check that no user funds
      depend on it?

## Oracle dependency
- [ ] Is any price read a **spot** price from an AMM? If so, it is
      same-transaction manipulable.
- [ ] Is the price used for *accounting* (fees, exchange rates) rather than
      just display? Accounting must use TWAP or a feed.

## Read the build output
- [ ] Every `forge build` warning is either fixed or **explicitly dismissed
      in the report** (divide-before-multiply, missing-events, reentrancy-events).
      A warning that is real and unreported is a missed finding.
