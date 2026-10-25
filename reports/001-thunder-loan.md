# Thunder Loan — Security Review

**Target:** Thunder Loan (CodeHawks AI First Flight #7)
**Scope:** `src/interfaces/*`, `src/protocol/*`, `src/upgradedProtocol/*`
**Methodology:** invariant checklist + Foundry PoCs (see `test/poc/`)
**Result:** 2 Critical, 1 High, 1 Low
**PoCs:** 4 passing tests against byte-identical copies of the target source

## Summary

Thunder Loan is a flash-loan protocol built on UUPS-upgradeable contracts. It
allows depositors to mint `AssetToken` shares against deposited tokens, and
allows borrowers to take flash loans in exchange for a fee.

Two critical issues were identified:

1. **C-01** — The upgrade from `ThunderLoan` to `ThunderLoanUpgraded` collides
   the storage layout, corrupting the flash loan fee from `0.3%` to `100%` on
   upgrade. The protocol is unusable after upgrade until the owner manually
   corrects the fee, and no event signals the corruption.

2. **C-02** — `ThunderLoan.deposit` calls `AssetToken.updateExchangeRate` with
   a fee that is never paid by anyone. The exchange rate inflates above `1.0`
   without underlying token backing, causing every subsequent `redeem` to
   revert at `safeTransfer`. All deposited funds are permanently locked.

**H-01** documents the latent insolvency behind C-02 — even if the revert is
bypassed, the accounting is short by the accumulated phantom fee. Fixing C-02
fixes both.

**L-01** documents a breaking change in the upgrade's ABI surface
(`getFeePrecision()` removed).

## Findings

| ID | Severity | Title | File |
| :--- | :--- | :--- | :--- |
| C-01 | Critical | Storage layout collision corrupts flash loan fee to 100% on upgrade | [link](../findings/C-01-storage-collision.md) |
| C-02 | Critical | Deposit inflates rate without backing, permanently blocking redemptions | [link](../findings/C-02-deposit-breaks-redeem.md) |
| H-01 | High | Deposit inflates aggregate claims beyond underlying balance | [link](../findings/H-01-deposit-insolvency.md) |
| L-01 | Low | Upgrade removes getFeePrecision(), breaking external integrators | [link](../findings/L-01-getFeePrecision-removed.md) |

## Scope notes

**In scope and confirmed:**

- `protocol/ThunderLoan.sol` — C-02, H-01
- `upgradedProtocol/ThunderLoanUpgraded.sol` — C-01, L-01

**In scope, reviewed but no findings:**

- `protocol/AssetToken.sol` — the `mint`/`burn`/`updateExchangeRate` primitives
  are correct in isolation; the bug is in the calling contract.
- `protocol/OracleUpgradeable.sol` — price lookups delegate to the external
  pool factory; no manipulation vector is open to a non-admin attacker.
- `interfaces/*` — no code under test.

## Methodology

1. **Baseline build and tests** — the target's own tests pass, but coverage is
   uneven (`ThunderLoanUpgraded.sol` has 0% coverage; `ThunderLoan.redeem`,
   `updateFlashLoanFee`, `getCalculatedFee` are untested).

2. **Source diff** — reading the diff between `ThunderLoan` and
   `ThunderLoanUpgraded` revealed what the fix was intended to change. C-01
   emerged from analyzing that diff for storage-layout side effects.

3. **Invariant checklist** — for each asset (shares, underlying tokens, fee
   accounting), write down the invariant and check whether it holds before and
   after each external call. H-01 is the invariant
   "sum of shares × rate <= token balance" failing after one deposit.

4. **PoC per finding** — every finding has a Foundry test that fails against
   the unmodified target and passes after the fix. PoCs live in `test/poc/`;
   vendored target code is byte-identical to the original (never reformatted).

### Compiler settings

The PoCs compile with `optimizer = true, optimizer_runs = 200` to match the
target's deployment configuration. At default settings (no optimizer) the target's
two main contracts exceed the EIP-170 runtime size limit and could not be
deployed on Ethereum mainnet:

| Contract | Runtime (optimizer off) | Runtime (optimizer on, 200 runs) |
| :--- | :--- | :--- |
| `ThunderLoan` | 27,726 bytes | ~22,000 bytes |
| `ThunderLoanUpgraded` | 27,610 bytes | ~22,000 bytes |

Auditing against the deployed bytecode means matching the settings that produced
it. A PoC compiled without the optimizer runs against a contract that cannot
exist in production.

## What I looked for and did not find

- **Reentrancy in flashloan** — the callback runs inside
  `s_currentlyFlashLoaning[token] = true` window; reentering `flashloan` for
  the same token reverts at `ThunderLoan__AlreadyFlashLoaning`. No issue.

- **Price oracle manipulation** — `getPriceInWeth` delegates to
  `IPoolFactory.getPool(token).getPriceOfOnePoolTokenInWeth()`. This is
  spot-price and would be manipulable in a real deployment, but no in-scope
  code provides a manipulation vector; flagging as informational only.

- **Access control** — `setAllowedToken`, `updateFlashLoanFee`, and
  `_authorizeUpgrade` are all `onlyOwner`. No privilege escalation found.

- **Arithmetic** — `getCalculatedFee` has `divide-before-multiply` suppressed
  via Slither comment. Reviewed and confirmed intentional: the alternative
  (`amount × price × fee`) overflows for large `amount`. No issue.

## What I missed (first submission)

The initial four-finding submission was returned as "Failed to assess issue
due to technical error" on every entry — a judge infrastructure failure, not
a substantive rejection. Two of the four matched the published H-01 and H-02.

## Gap analysis against published findings

| Published | Sev | First submission | After reset |
| :--- | :--- | :--- | :--- |
| H-01 Storage collision | H | ✅ C-01 | ✅ |
| H-02 Exchange rate inflation | H | ✅ C-02 + H-01 | ✅ |
| H-03 Fee-on-transfer tokens | H | ❌ missed | ✅ (new PoC) |
| H-04 Flashloan repaid via deposit | H | ❌ missed | ✅ (new PoC) |
| M-01 setAllowedToken locks LPs | M | ❌ missed | ✅ (new PoC) |
| M-02 Spot-price oracle | M | ⚠ noted "informational", not submitted | ✅ (new PoC) |
| M-03 Fee token drain | M | ❌ missed (same root as H-03) | ✅ (new PoC) |

**Closed 5 of 5 gaps.** All seven H/M-severity findings now have working
Foundry PoCs.

## Root causes of the gaps

**H-03 / M-03 (fee tokens):** no checklist item asked "does the protocol
credit the *received* amount or the *requested* amount?" Fee-on-transfer
tokens break `amount sent == amount received`. One checklist item; two
findings.

**H-04 (flashloan via deposit):** repayment was inferred from a balance
delta; `deposit()` moves the same balance. This is the exact cross-function
reentrancy shape from `reentrancy-lab/VaultCrossFunction` — the pattern was
already studied, not applied.

**M-01 (setAllowedToken):** no checklist item asked "can an admin action
permanently prevent users from exiting?" `delete` on a mapping that
`redeem()` depends on.

**M-02 (oracle):** identified during the first pass, written down as
"informational," not submitted. When a real risk is spotted and self-
downgraded, the impact class should be documented and the finding submitted
as Low at minimum.

**L-01 / L-03 (precision):** `forge build` warning `divide-before-multiply`
was suppressed by a Slither comment in the source, and treated as
intentional. It is — but the *consequence* (zero fee for small loans) was
never submitted.

**L-02 (missing event):** `forge build` warning `missing-events-arithmetic`
was printed on every run and not acted on.

## Checklist updates

`checklists/defi-lending.md` gained:

- Protocol-accounting reentrancy: post-callback balance check vs intent check
- ERC-20 transfer semantics: `amount sent == amount received` invariant
- Admin state transitions: can `onlyOwner` trap users' funds?
- Oracle dependency: is any price a same-transaction-manipulable spot price?
- Build-warning triage: every warning is either fixed or *explicitly
  dismissed in the report* — a real warning left unreported is a missed
  finding.

## Recommendations (cross-cutting)

Beyond the individual findings:

1. **Add storage layout assertions to CI.** `forge inspect <Contract> storageLayout`
   for both implementations should be committed and diffed in CI. A layout
   drift check would have caught C-01 before deployment.

2. **Add an invariant test for `AssetToken`.** A fuzz test asserting
   `totalSupply * exchangeRate / PRECISION <= underlyingBalance` after any
   sequence of deposits/redemptions would have caught H-01 immediately.

3. **Preserve public getters across upgrades.** L-01 is a symptom of a broader
   pattern — the upgrade should be ABI-compatible with the original.
