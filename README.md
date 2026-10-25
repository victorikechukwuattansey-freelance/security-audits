# Security Audits

Public security review reports on open-source code. Each report follows the
same format: scope, methodology, findings with Foundry PoCs, remediation,
retest, and documented residual risk.

## Reports

| # | Target | Scope | Findings | Report |
| :--- | :--- | :--- | :--- | :--- |
| 001 | [Thunder Loan](https://github.com/Cyfrin/2023-11-Thunder-Loan) | CodeHawks AI First Flight #7 | 2C / 1H / 1L | [report](./reports/001-thunder-loan.md) |

## Method

Every report follows the same workflow:

1. **Clone the target and build it.** Run the project's own tests; note coverage
   gaps.

2. **Read the diff between vulnerable and upgraded contracts** (if any). The
   diff reveals what the patch author thought was wrong — and, sometimes, what
   they introduced.

3. **Run the invariant checklist for the target class** (`checklists/`).

4. **Write one PoC per finding** in `test/poc/`, against byte-identical
   vendored target code. Never reformat vendored files (enforced via
   `[fmt] ignore`).

5. **Submit to the platform, incorporate the judgment, publish the report.**
   The "What I missed" section is the feedback loop made public.

## Findings index

- [C-01](./findings/C-01-storage-collision.md) — Storage collision on upgrade
- [C-02](./findings/C-02-deposit-breaks-redeem.md) — Deposit inflates rate, blocks redeem
- [H-01](./findings/H-01-deposit-insolvency.md) — Latent insolvency behind C-02
- [L-01](./findings/L-01-getFeePrecision-removed.md) — Getter removed in upgrade

## Why this repo exists

The companion repos (`my-erc-20-token`, `my-nft`, `nft-staking`,
`reentrancy-lab`) show I can build and break code I wrote. This repo shows I
can find issues in code I did not write — under a scope constraint, with a
severity judgment a protocol team would accept, backed by reproducible PoCs.

## License

MIT
