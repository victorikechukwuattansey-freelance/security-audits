# Seven-Lead First-Pass Checklist

Before writing any PoC on a new target, work through these seven leads.
Extracted from the Twyne engagement (840/840 test baseline, closed 2026-10-29).

## 1. `non-reentrant-not-first`

Enumerate every modifier preceding `nonReentrant` on every state-changing
function. For each modifier:

- Does it make an outbound call? (`.call`, `.transfer`, `.delegatecall`, external
  contract invocation)
- Does it read state the guarded function later mutates?

Modifiers that are only STATICCALL reads (pause check, balance check, oracle
read) and caller-identity checks (`msg.sender == X`) are safe. Modifiers that
make outbound calls before the guard is set are candidates.

## 2. Unchecked low-level call returns

For every `x.call(...)` or `x.delegatecall(...)` with a discarded return value:

- Does the callee revert on failure? If yes, the discard is cosmetic.
- Does the callee return a bool? If yes, check whether a silent failure can
  leave state inconsistent.

Common safe patterns: callers that wrap EVC batch targets which themselves
call `requireVaultStatusCheck()`. The EVC aborts the batch on inner failure,
so the discarded return is not a security signal.

## 3. Interface cast mismatches

For every `IFoo(addr)` where `addr` comes from runtime input, admin config,
or a factory registration:

- Does the address actually implement `IFoo` at the deployment block?
- Is there an enforced invariant that `IFoo(addr)` type-checks at runtime?
- Can an admin misconfigure the address to a contract that lacks the interface,
  causing a function path to revert permanently?

Admin-only misconfiguration is usually Informational, not High. But if the
invariant is enforced at one path and not another, the unguarded path may
be material.

## 4. `arbitrary-send-erc20`

For every `token.transferFrom(from, to, amount)` or equivalent:

- Trace `from` to its source. Is it `_msgSender()`, a storage field, a calldata
  parameter, or a signed context value?
- If `_msgSender()`: read the implementation. Confirm it returns either
  `msg.sender` or an authenticated EVC/operator value. Confirm no calldata
  path can spoof it.
- Is there a `borrower() == msgSender` or equivalent ownership check
  immediately before the transfer? If yes, the transfer is bounded to the
  caller's own resources.

## 5. `divide-before-multiply`

For every `a * b / c` or `(a / b) * c` pattern in financial math:

- Is `(a/b)` a compile-time constant? Many linter hits are exact folds like
  `1e9 / 1e4 == 1e5` — no precision loss.
- For repeated squarings or accumulators: compute the WORST-CASE truncation
  at the extreme of the input domain. Sum over the operation chain.
- Compare to economically meaningful threshold. < 1 wei total is cosmetic.
  > 1e6 wei may be material depending on how often the function is called.
- Check overflow bounds: `uint256` max is 1.15e77. Every intermediate in a
  chain of `x² / 1e18` where `x ≤ 1e18` is bounded by `1e18`, so the product
  is bounded by `1e36` — no overflow.

## 6. Calldata injection into multicall / swap / executor

For every function that accepts `bytes[] calldata` or `bytes calldata` and
forwards it to an external contract:

- Does the calldata execute in the caller's context (the target contract) or
  a separate sandbox contract's context?
- If sandbox: third-party approvals to the caller are not reachable by the
  injected calldata.
- If caller: the injected calldata is attacker-controlled and can invoke any
  selector the caller is authorized to call — including `transferFrom` on
  tokens for which the caller has approvals.

Check: is the target contract an ERC20 with `transferFrom`? Is it a router
with approvals to user tokens? Is there a verifier that validates selectors
before dispatch?

## 7. Composite state transitions

Before writing a bespoke composite test, check whether the existing test suite
already exercises multi-item batch composition. Search for:

- `*batchSim*`
- `*leverageAndDeleverage*`
- `*teleportSingleBatch*`
- `*batchOpen*`, `*batchClose*`, `*batchPartial*`
- Any test with an `IEVC.BatchItem[]` longer than length 1

If the baseline includes several multi-item batch tests, composite coverage
already exists. Do not duplicate. Reference the existing suite in your report.

If the baseline is single-action only, write ONE composite test per suspected
invariant. Not more.

## Meta

Finding density on mature, heavily-tested codebases is low, and that is
a feature of the codebase, not a failure of the audit. The seven leads above
are cheap to run (10-15 hours) and close out the shallow surface. When all
seven come up negative AND the target has >500 tests, pivot. Do not mine
further on diminishing returns.
