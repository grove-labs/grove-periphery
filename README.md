# 🔌🌳 Grove Periphery

![Foundry CI](https://github.com/grove-labs/grove-periphery/actions/workflows/test.yml/badge.svg)[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/grove-labs/grove-periphery/blob/main/LICENSE)![Ethereum](https://img.shields.io/badge/Ethereum-3C3C3D?style=flat&logo=ethereum&logoColor=white)

Peripheral contracts supporting Grove protocol operations.

This repository currently contains a single contract, `InstantUsdcUsdsConverter`, which lets an authorized relayer convert USDC held by Grove governance into USDS at a 1:1 rate through the Sky DAI LitePSM and the DAI↔USDS exchanger.

## 💱 InstantUsdcUsdsConverter

`InstantUsdcUsdsConverter` performs a one directional, atomic USDC to USDS swap on behalf of a fixed `holder`:

1. Pulls `usdcAmount` USDC from `holder` (which must have approved the converter).
2. Sells the USDC to the DAI LitePSM for DAI.
3. Converts that DAI 1:1 into USDS through the DAI↔USDS exchanger and delivers it straight back to `holder`.

A single `swap` entrypoint auto-selects the best route:

- When the converter is **whitelisted** on the LitePSM (via Sky governance `kiss`), it uses `sellGemNoFee`, which stays exactly 1:1 even if a sell fee is set.
- Otherwise it uses the permissionless `sellGem`, which needs no whitelisting but reverts (by design) the moment the PSM charges a sell fee.

Key properties:

- **One direction only.** The contract swaps USDC into USDS; there is no reverse path.
- **1:1, no fee.** `swap` requires the swap to yield exactly `usdcAmount * conversionFactor` USDS. On the `sellGem` route, if the output would settle short because the PSM sell fee (`tin`) is non-zero, it reverts with `not-one-to-one` instead of settling at a loss; the whitelisted `sellGemNoFee` route waives the fee entirely (but is still halted if the PSM sets `tin` to its halt sentinel).
- **Verified settlement.** After converting, `swap` clears any allowance the PSM or exchanger did not consume and requires the holder's USDS balance to have risen by exactly `usdsOut`, so a leg that leaves a dangling approval or reports success without delivering causes a revert.
- **Holds no funds.** `swap` pulls and forwards atomically (the intermediate DAI never lingers), leaving no residual balance or allowance. The `rescueERC20` and `rescueERC721` functions exist only to recover tokens sent here by mistake, and always route them to `holder`. `rescueERC721` also confirms the token actually reached `holder`.
- **Reentrancy protected.** `swap`, `rescueERC20` and `rescueERC721` are `nonReentrant` (OpenZeppelin `ReentrancyGuard`), so a callback from a token or PSM cannot re-enter the contract mid-operation.
- **Pausable backstop.** `swap` is gated by a pause switch. Only `PAUSER_ROLE` can `pause` as an emergency stop, and only `DEFAULT_ADMIN_ROLE` can `unpause`. Rescues remain available while paused.
- **No ETH rescue.** The contract is not payable, so it rejects ordinary ETH transfers and cannot accumulate ETH by accident. There is deliberately no `rescueEth` function: the only way to lodge ETH here is to force it (e.g. via `selfdestruct`), which is an intentional act rather than an honest mistake, and `holder` (the Grove governance subproxy) cannot receive ETH anyway, so a rescue routed to it would always revert.

### Roles

Access control uses OpenZeppelin `AccessControl`:

| Role | Capability | Mainnet holder |
| --- | --- | --- |
| `DEFAULT_ADMIN_ROLE` | Manage roles; `unpause`; call `rescueERC20` / `rescueERC721` | Grove governance subproxy |
| `SWAPPER_ROLE` | Call `swap` | ALM relayer |
| `PAUSER_ROLE` | Call `pause` (pausing only; unpausing is admin-only) | ALM freezer multisig |

### Fee-free whitelisting

`swap` automatically uses the LitePSM's `sellGemNoFee` once the converter is whitelisted on the PSM's `kiss` allowlist. To enable the fee-free route, Sky governance must call `litePsm.kiss(<converter>)` after deployment; until then `swap` transparently uses the permissionless `sellGem`, which works while the sell fee (`tin`) is zero and reverts with `not-one-to-one` if a fee is introduced.

### Mainnet wiring

`InstantUsdcUsdsConverterDeploy.deployMainnet()` wires the contract to the Grove Ethereum mainnet addresses from `grove-address-registry`:

| Constructor argument | Address |
| --- | --- |
| `admin_` | `Ethereum.GROVE_PROXY` |
| `swapper_` | `Ethereum.ALM_RELAYER` |
| `pauser_` | `Ethereum.ALM_FREEZER` |
| `holder_` | `Ethereum.GROVE_PROXY` |
| `litePsm_` | `Ethereum.PSM` (DAI LitePSM-USDC) |
| `daiUsds_` | `Ethereum.DAI_USDS` (DAI↔USDS exchanger) |

### Deployment

Two scripts live in `script/DeployInstantUsdcUsdsConverter.s.sol`. Both broadcast with a signer of your choice (`--private-key`, `--account`, `--ledger`, and so on) and deploy to whichever chain `--rpc-url` points at. The mainnet flow also has a Makefile shortcut (see below).

#### Mainnet (hardcoded addresses)

`DeployInstantUsdcUsdsConverterMainnet` uses the Grove Ethereum mainnet addresses from `grove-address-registry`. It is intended for Ethereum mainnet (or a mainnet fork); those addresses will not resolve on other chains.

The simplest path is the Makefile target, which broadcasts and verifies using the `GROVE_MAINNET_DEPLOYER` keystore account:

```shell
make deploy-instant-converter-mainnet
```

That is equivalent to:

```shell
forge script script/DeployInstantUsdcUsdsConverter.s.sol:DeployInstantUsdcUsdsConverterMainnet \
  --rpc-url mainnet \
  --account GROVE_MAINNET_DEPLOYER \
  --broadcast \
  --verify
```

#### Custom (addresses from environment)

`DeployInstantUsdcUsdsConverterCustom` reads every constructor argument from the environment, so it can deploy to any chain. Set `CONVERTER_ADMIN`, `CONVERTER_SWAPPER`, `CONVERTER_PAUSER`, `CONVERTER_HOLDER`, `CONVERTER_LITE_PSM`, and `CONVERTER_DAI_USDS` (see `.env.example`) to values valid on the target chain, then:

```shell
forge script script/DeployInstantUsdcUsdsConverter.s.sol:DeployInstantUsdcUsdsConverterCustom \
  --rpc-url <your_rpc_url> \
  --broadcast \
  --verify
```

Both scripts log the deployed address and the resolved `admin`, `swapper`, `pauser`, `holder`, `litePsm`, and `daiUsds` values.

#### Post-deployment verification

Two read-only scripts in `script/VerifyInstantUsdcUsdsConverter.s.sol` check a live deployment and revert on the first mismatch. Set `CONVERTER_ADDRESS` to the deployed contract (in `.env`, which forge auto-loads, or inline), then run the one matching how you deployed.

Mainnet deployment (verifies against the hardcoded registry addresses). Use the Makefile target:

```shell
CONVERTER_ADDRESS=0x... make verify-instant-converter-mainnet
```

That is equivalent to:

```shell
forge script script/VerifyInstantUsdcUsdsConverter.s.sol:VerifyInstantUsdcUsdsConverterMainnet \
  --rpc-url mainnet
```

Custom deployment (verifies against the same `CONVERTER_*` environment variables used to deploy):

```shell
forge script script/VerifyInstantUsdcUsdsConverter.s.sol:VerifyInstantUsdcUsdsConverterCustom \
  --rpc-url <your_rpc_url>
```

## 🛠️ Development

These steps apply to the whole repository, independent of any single contract.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Setup

```shell
git clone --recurse-submodules <repo-url>
cd grove-periphery
cp .env.example .env
# then set ETH_RPC_URL in .env
```

If you already cloned without submodules, run `git submodule update --init --recursive`.

### Build

```shell
forge build
```

### Test

The test suite forks Ethereum mainnet, so `ETH_RPC_URL` must be set (see `.env.example`).

```shell
forge test
```

### Format

Solidity in this repository is formatted by hand (column-aligned imports and assignments), which `forge fmt` does not preserve. For that reason `forge fmt --check` is intentionally excluded from CI. Run `forge fmt` only if you are prepared to lose the manual alignment.

## ⚖️ License

Licensed under [AGPL-3.0-or-later](./LICENSE).
