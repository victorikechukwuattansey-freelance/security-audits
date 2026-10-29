# Foundry on Windows — Archive-Fork Setup Playbook

Reusable procedure for setting up a reproducible Foundry environment against an Ethereum mainnet fork, derived from the Twyne engagement (block 25,308,678, Q4 2026). Saves 3–4 hours per new target.

## 1. Windows prerequisites

```bash
# Long path support — required before any submodule work
git config --global core.longpaths true

# Verify
git config --global --get core.longpaths
# Expected: true
For repos with NTFS-reserved paths or deep nesting, add -c core.protectNTFS=false to individual git clone commands. Do not set this globally — it disables NTFS path validation for all repos, which can hide genuine problems.

2. Dependency resolution
Repos mixing lib/ and node_modules/ are common. The supported path is generally the repo's own tooling:

bash
# If the repo has a forge-install workflow (lib/ with nested submodules)
forge install

# If a specific submodule breaks on Windows (e.g. Aave Certora specs)
# clone the problematic dependency manually and skip the offending submodule
git clone --depth 1 https://github.com/<org>/<repo>.git lib/<name>
rm -rf lib/<name>/<offending-directory>
Do not replace official remappings with node_modules paths. The target project's own remappings.txt is authoritative.

3. OpenZeppelin version pinning
If the repo has a pinned OZ that conflicts with solc 0.8.28 (common when OZ advances to ^0.8.31), pin to the most recent tag that satisfies all constraints:

bash
cd lib/openzeppelin-contracts-upgradeable
git fetch --tags
git checkout v5.3.0
cd lib/openzeppelin-contracts
git fetch --tags
git checkout v5.3.0
cd ../../../..
v5.3.0 is a safe landing point for solc 0.8.28 because it:

Contains ReentrancyGuardTransient.sol (missing before v5.1.0)

Still uses ^0.8.20 / ^0.8.24 pragmas, compatible with 0.8.28

Has the storage-layout and file structure required by openzeppelin-contracts-upgradeable on matching versions

Verify the pragma before running tests:

bash
grep "pragma solidity" lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol
# Should be ^0.8.24, not ^0.8.31
4. Foundry profiles
Always iterate with a lite profile. via_ir = true with optimizer_runs = 20_000 on a multi-dependency DeFi repo takes hours on Windows; the same build under lite takes minutes.

toml
[profile.lite]
via_ir = false
optimizer_runs = 200

[profile.lite.fuzz]
max_test_rejects = 1_000_000
Notes:

max_test_rejects = 1_000_000 is required if the target's [profile.default.fuzz] raises this above Foundry's default 65,536. Without it, fuzz tests that use vm.assume generously will fail with rejected too many inputs.

Do not put eth_rpc_url = "${ENV_VAR}" in foundry.toml. On this Windows / MINGW64 setup the $... substitution failed with Internal transport error: The system cannot find the file specified. (os error 2) with C:\...\${VAR}. Pass --fork-url on the CLI instead, or export the variable in the same shell invocation that runs forge.

Do not use fork_retries / fork_retry_backoff in foundry.toml. Foundry warns unknown fork_retries config for profile lite and ignores the keys. If your Foundry version supports them, verify before adding.

Always pass --skip script unless forge-safe is installed. Scripts under script/ often import forge-safe/src/BatchScript.sol, and their absence blocks the entire compile even when you only want to build src/. --contracts <path> does not skip script compilation; combine with --skip script.

5. Archive RPC endpoints — verified working vs. verified not working
Public keyless endpoints almost never serve deep archive state. Verified behavior on Ethereum mainnet block 25,308,678 (~1M blocks behind head):

Endpoint	Behavior
https://mainnet.chainnodes.org/<personal-key>	Works — archive included on free Core plan. Signup required; URL contains a personal key.
https://ethereum-rpc.publicnode.com	Fails — pruned history unavailable: requested 25308678, earliest available 26286875
https://eth.meowrpc.com	Fails — historical state ... is not available
https://ethereum-json-rpc.stakely.io	Fails — historical state ... is not available
https://eth-pokt.nodies.app	Serves cast block once, then rate-limits with HTTP 429 after repeated test runs
https://eth.llamarpc.com	Fails — Cloudflare 525 SSL handshake
https://rpcfree.com/ethereum-rpc	Not a JSON-RPC endpoint — returns HTML documentation page
https://archive.mainnet.ethpandaops.io	Fails — Cloudflare Access 403 (login required)
https://ethereum.rpc.subquery.network/public	Fails — MPP HTTP error on cast block
https://mainnet.base.org	Wrong chain entirely (Base, not Ethereum)
Recommended workflow:

Sign up for Chainnodes free (12.5M req/month, archival included)

Verify the endpoint before pinning:

bash
export CHAINNODES_ETH_RPC="https://mainnet.chainnodes.org/<your-key>"
cast block <fork-block> --rpc-url "$CHAINNODES_ETH_RPC" --json | head -c 200
Expected: {"schema_version":1,"success":true,"data":{"hash":"0x...","number":"<fork-block>",...

Every forge test command passes --fork-url "$CHAINNODES_ETH_RPC" explicitly.

Keep the endpoint secret. The URL contains a personal API key. Never commit it to foundry.toml, .env.example, reports, or public issues.

6. Stale cache hygiene
When switching endpoints mid-session, clear Foundry's fork state cache:

bash
rm -rf cache out ~/.foundry/cache/rpc
A stale cache can produce confusing partial-state errors on the new endpoint.

7. Diagnostic ladder
When a fork test fails, classify the failure before treating it as a code bug:

Failure	Classification	Fix
EvmError: Revert at gas: 0 in setUp()	No fork active	Pass --fork-url
panic: arithmetic underflow or overflow (0x11) in setUp()	Downstream of no-fork state	Pass --fork-url
pruned history unavailable or historical state ... is not available	Endpoint lacks archive depth	Switch to Chainnodes or another archive provider
HTTP error 429	Rate limit	Switch endpoint, add key, or run single-threaded
call to non-contract address 0x... in setUp()	Wrong chain forked (e.g. Base instead of Ethereum)	Verify chain via cast chain-id --rpc-url "$RPC"
vm.assume rejected too many inputs	max_test_rejects too low	Add [profile.lite.fuzz] max_test_rejects = 1_000_000
FOUNDRY::ASSUME on a test	Test gated on DIFFERENTIAL_FUZZ or another env var	Set env var or accept the skip; do not modify the test
no tests match the provided pattern	Filename vs contract name mismatch	Use --match-path "test/path/*" instead of --match-contract
Identifier not found in a test file	Missing import in child contract (Solidity does not inherit imports)	Add explicit import in the child
8. Baseline verification
Once the environment reproduces the project's own tests, record the exact command and result before writing any PoC:

bash
FOUNDRY_PROFILE=lite forge test \
  --match-path "test/<protocol>/*" \
  --fork-url "$CHAINNODES_ETH_RPC" \
  --skip script
Record:

Total tests passing / failing / skipped

Fork block number

RPC provider

Date

Any test suites that are environment-gated (documented, not skipped by choice)

This becomes the "baseline of record" for the engagement. Every subsequent claim of "the PoC works" or "the exploit is blocked" references this baseline.

9. Time budget
Approximate hours for a first-time setup on a mature DeFi repo on Windows:

Step	Hours
Clone + dependency resolution	1–2
OZ / solc version pinning	1–2
Archive RPC acquisition	0.5
First successful forge test	2–4
Full baseline reproduction	1–2
Total	5.5–10.5
Reduce by 50% if the target repo does not mix lib/ and node_modules/, or if the target's own tests already pin to a known block.
