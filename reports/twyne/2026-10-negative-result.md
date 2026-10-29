# Twyne — Negative Audit Result

**Target:** Twyne contracts v1
**Immunefi program:** live since 2026-01-16, last updated 2026-10-12
**Repo:** `C:\dev\security-audits\targets\003-twyne\twyne-contracts-v1`
**Commit:** `beb4bf15a70b1a8abcf7e17e8a08f556ee5f84ab`
**Fork:** Ethereum mainnet, block `25,308,678`
**RPC:** Chainnodes archive endpoint (key stored in `$CHAINNODES_ETH_RPC`, not committed)
**Date:** `2026-10-29`

## Scope

Reviewed in full:

- `src/twyne/CollateralVaultBase.sol`
- `src/twyne/EulerCollateralVault.sol`
- `src/twyne/MorphoCollateralVault.sol`
- `src/twyne/AaveV3CollateralVault.sol`
- `src/twyne/VaultManager.sol`
- `src/TwyneFactory/CollateralVaultFactory.sol`
- `src/Periphery/AssetZap.sol`
- `src/twyne/IRMTwyneCurve.sol`
- `src/twyne/IRMTwyneCurveGamma32.sol`
- `lib/euler-vault-kit/lib/ethereum-vault-connector/src/utils/EVCUtil.sol` (targeted read of lines 100–175)

Reviewed via targeted grep across all 8 operator files under `src/operators/`, including `LeverageOperator.sol`, `DeleverageOperator.sol`, `MorphoTeleportOperator.sol`, `MorphoDeleverageOperator.sol`, `AaveV3LeverageOperator.sol`, `AaveV3DeleverageOperator.sol`, `AaveV3TeleportOperator.sol`, and `handlers/WstethHandler.sol`.

Fork-based test baseline reproduced in full:

- `Euler*`: **287/287 passing** across 8 suites (`EulerTestNormalActions`, `EulerTestTwyneGovernance`, `EulerTestPostFallbackAccounting`, `EulerTestInternalLiquidation`, `EulerLiquidationTest`, `EulerTestEdgeCases`, `EulerFrontendTests`, `EulerOperators`).
- `Morpho*`: **281/281 passing** across 8 suites.
- `Aave*`: **261/261 passing** across 8 suites.
- `VaultManagerRampTest`: **11/11 passing** (separate suite, non-fork).

Total: **840 passing tests, 0 failing, 0 skipped** at the fork block.

## Out of scope

- **SWAPPER contract**: external immutable address passed to `AssetZap` at construction; not present in `src/`. Trust assumption is documented in the `AssetZap` contract docstring and verified only to the extent that `test_attack_wstEthWithCalldata_blocked` demonstrates one specific allowlist rejection.
- **External protocol internals** (Euler, Aave, Morpho): the Immunefi excluded-issues list explicitly excludes inherited protocol assumptions.
- **Deployment scripts** under `script/`: not executed; `forge-safe` dependency was not installed and scripts were skipped via `--skip script`.

## Leads raised and closed (7 of 7 negative)

### 1. `non-reentrant-not-first` (all four collateral vaults)

**Source:** Foundry linter across `CollateralVaultBase.sol:243,258,355,369,391,421,455,621,704` and derived vaults.

**Closure:** Traced every modifier preceding `nonReentrant` in the chain. `callThroughEVC` resolves to `_callThroughEVC()` in `EVCUtil.sol`, which is an `msg.sender` check, not an outbound call. `whenNotPaused(PauseState)` is a STATICCALL read of `collateralVaultFactory.pauseState()`. `onlyBorrowerAndNotExtLiquidated` checks `_msgSender() == borrower` and calls `_isNotExternallyLiquidated()`, which is a `balanceOf` static read. No modifier in the chain makes an outbound call that could reenter before the guard is set.

**Verdict:** Cosmetic. Not a finding.

### 2. Unchecked `IEVC(evc).call(...)` return values

**Source:** Foundry linter in `AaveV3DeleverageOperator.sol:160`, `MorphoDeleverageOperator.sol:143`, `DeleverageOperator.sol:131`, `MorphoTeleportOperator.sol:83`.

**Closure:** Each call site wraps an EVC batch item whose underlying targets (`redeemUnderlying`, `withdraw`, `skim`, `borrow`) call `evc.requireVaultStatusCheck()` internally. If any inner call fails, the EVC batch aborts. The discarded return value is not a security signal because the EVC guarantees revert-on-failure semantics at the batch boundary.

**Verdict:** Cosmetic. Not a finding.

### 3. `IEVault(__asset).unitOfAccount()` in `EulerCollateralVault.splitCollateralAfterExtLiq`

**Source:** Source read; line casts `asset` (a plain ERC20 like USDC or WETH) to `IEVault`.

**Closure:** Tested topology uses `intermediateVaultFor[eulerWETH]`, whose `asset()` is an EVK vault token (`IEVault`), so the cast resolves. `test_e_vectorAttack_handleExternalLiquidation_SendAssetAmountAfterExternalLiq` and all 50 `EulerTestPostFallbackAccounting` tests pass. `MorphoTestEdgeCases` includes an explicit `test_morpho_createVault_revert_unitOfAccountMismatch` guard at the analogous path. Residual risk: `VaultManager.setIntermediateVault` does not enforce the `IEVault(asset)` invariant, so an admin misconfiguration could make `handleExternalLiquidation()` revert for a given pair. That is admin-only, revert-recoverable, and would fall under Informational.

**Verdict:** Safe in the deployed/tested topology. Not H/M.

### 4. `arbitrary-send-erc20` in the 8 operator files

**Source:** Foundry linter in `LeverageOperator.sol:95,99`.

**Closure:** Read `EVCUtil._msgSender()` at `EVCUtil.sol:109–120`. It returns either `msg.sender` (when caller is not the EVC) or `evc.getCurrentOnBehalfOfAccount(0)` (authenticated EVC context). There is no calldata-controlled or storage-controlled path. Grep of all 8 operators confirms every function does:

```solidity
address msgSender = _msgSender();
require(CollateralVault(collateralVault).borrower() == msgSender, T_CallerNotBorrower());
// ... then uses msgSender in a transfer
