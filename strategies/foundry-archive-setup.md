# Foundry on Windows — Archive-Fork Setup Playbook

Reusable procedure for setting up a reproducible Foundry environment against an Ethereum mainnet fork, derived from the Twyne engagement (block 25,308,678, Q4 2026). Saves 3–4 hours per new target.

## 1. Windows prerequisites

```bash
# Long path support — required before any submodule work
git config --global core.longpaths true

# Verify
git config --global --get core.longpaths
# Expected: true
