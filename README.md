# Security Audits & Research

Public security reviews, audit portfolios, and competitive challenge solutions on open-source code. Each report follows a strict format: scope, methodology, findings with Foundry PoCs, remediation, and documented residual risk.

## Security Reports

| # | Target | Platform / Scope | Findings | Report |
| :--- | :--- | :--- | :--- | :--- |
| 001 | [Thunder Loan](https://github.com/Cyfrin/2023-11-Thunder-Loan) | CodeHawks AI First Flight #7 | 2C / 1H / 1L | [Report](./reports/001-thunder-loan.md) |
| 002 | [Twyne Contracts](https://immunefi.com/bounty/twyne/) | Immunefi (Live Program) | 0 (7 leads closed) | [Report](./reports/twyne/2026-10-negative-result.md) |

## Audit Challenges & Portfolios

| Challenge | Focus Area | Deliverable |
| :--- | :--- | :--- |
| **[Pessimistic Junior](./pessimistic-junior/README.md)** | Reentrancy, Signature Malleability, Access Control, Slither | 11 completed smart contract security tasks |
| **OtterSec Challenge** | EVM Bytecode Decompilation & Storage Analysis | [Foundry PoC](./pocs/ottersec-challenge/test/OtterSec.t.sol) |

## Methodology

Every audit and challenge follows a strict, repeatable workflow:

1. **Environment & Baseline:** Clone the target, configure the toolchain (Foundry, archive forks), and reproduce the existing test suite to establish a baseline.
2. **Source Review & Threat Modeling:** Read the codebase in full. Map out invariants and state transitions before looking for bugs.
3. **First-Pass Checklist:** Run the `[Seven-Lead Checklist](./strategies/seven-lead-checklist.md)` to quickly eliminate linter false positives and common vulnerability patterns.
4. **Write PoCs:** Do not submit a finding without a working Foundry PoC that fails in the exact predicted way.
5. **Honest Reporting:** If a lead is negative, document the evidence and move on. Never submit speculative findings.

## Why this repo exists

The companion repos (`my-erc-20-token`, `my-nft`, `nft-staking`, `reentrancy-lab`) show I can build code. This repo shows I can break it, audit it, and document it under real-world constraints. 

It includes both **positive findings** (Thunder Loan) and a **negative audit result** (Twyne), demonstrating the discipline to know when a codebase is secure and the rigor to prove it.
