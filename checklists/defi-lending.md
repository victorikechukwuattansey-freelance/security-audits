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
