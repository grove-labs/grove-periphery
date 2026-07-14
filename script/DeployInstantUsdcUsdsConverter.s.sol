// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Script, console } from "forge-std/Script.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { InstantUsdcUsdsConverter }       from "../src/InstantUsdcUsdsConverter.sol";
import { InstantUsdcUsdsConverterDeploy } from "../deploy/InstantUsdcUsdsConverterDeploy.sol";

/// @notice Shared deployment logic for InstantUsdcUsdsConverter. Each concrete script supplies the
///         constructor arguments; `_deploy` broadcasts the deployment and logs the resulting wiring.
abstract contract DeployInstantUsdcUsdsConverterBase is Script {

    function _deploy(
        address admin,
        address swapper,
        address pauser,
        address holder,
        address litePsm,
        address daiUsds
    ) internal returns (InstantUsdcUsdsConverter converter) {
        vm.startBroadcast();
        converter = InstantUsdcUsdsConverterDeploy.deploy({
            admin   : admin,
            swapper : swapper,
            pauser  : pauser,
            holder  : holder,
            litePsm : litePsm,
            daiUsds : daiUsds
        });
        vm.stopBroadcast();

        console.log("InstantUsdcUsdsConverter deployed:", address(converter));
        console.log("  admin    : ", admin);
        console.log("  swapper  : ", swapper);
        console.log("  pauser   : ", pauser);
        console.log("  holder   : ", holder);
        console.log("  litePsm  : ", litePsm);
        console.log("  daiUsds  : ", daiUsds);
    }

}

/// @notice Deploys InstantUsdcUsdsConverter with the hardcoded Grove Ethereum mainnet
///         addresses from `grove-address-registry`. Intended for Ethereum mainnet (or a
///         mainnet fork); the wired addresses will not resolve on other chains.
contract DeployInstantUsdcUsdsConverterMainnet is DeployInstantUsdcUsdsConverterBase {

    uint256 constant ETHEREUM_MAINNET = 1;

    function run() external returns (InstantUsdcUsdsConverter converter) {
        require(block.chainid == ETHEREUM_MAINNET, "DeployInstantUsdcUsdsConverterMainnet/not-mainnet");

        converter = _deploy({
            admin   : Ethereum.GROVE_PROXY,
            swapper : Ethereum.ALM_RELAYER,
            pauser  : Ethereum.ALM_FREEZER,
            holder  : Ethereum.GROVE_PROXY,
            litePsm : Ethereum.PSM,
            daiUsds : Ethereum.DAI_USDS
        });
    }

}

/// @notice Deploys InstantUsdcUsdsConverter with fully custom constructor arguments read from
///         environment variables. Chain agnostic: run it against any chain by pointing
///         `--rpc-url` at that chain and setting the addresses below to that chain's values.
///
///         Required environment variables:
///           CONVERTER_ADMIN    - address granted DEFAULT_ADMIN_ROLE
///           CONVERTER_SWAPPER  - address granted SWAPPER_ROLE
///           CONVERTER_PAUSER   - address granted PAUSER_ROLE
///           CONVERTER_HOLDER   - address funds are pulled from and delivered to
///           CONVERTER_LITE_PSM - DAI LitePSM exposing gem/dai/to18ConversionFactor/sellGem
///           CONVERTER_DAI_USDS - DAI<>USDS exchanger exposing dai/usds/daiToUsds
contract DeployInstantUsdcUsdsConverterCustom is DeployInstantUsdcUsdsConverterBase {

    function run() external returns (InstantUsdcUsdsConverter converter) {
        converter = _deploy({
            admin   : vm.envAddress("CONVERTER_ADMIN"),
            swapper : vm.envAddress("CONVERTER_SWAPPER"),
            pauser  : vm.envAddress("CONVERTER_PAUSER"),
            holder  : vm.envAddress("CONVERTER_HOLDER"),
            litePsm : vm.envAddress("CONVERTER_LITE_PSM"),
            daiUsds : vm.envAddress("CONVERTER_DAI_USDS")
        });
    }

}
