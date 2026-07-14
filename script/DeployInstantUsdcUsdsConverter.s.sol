// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Script, console } from "forge-std/Script.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { InstantUsdcUsdsConverter }       from "../src/InstantUsdcUsdsConverter.sol";
import { InstantUsdcUsdsConverterDeploy } from "../deploy/InstantUsdcUsdsConverterDeploy.sol";

/// @notice Deploys InstantUsdcUsdsConverter with the hardcoded Grove Ethereum mainnet
///         addresses from `grove-address-registry`. Intended for Ethereum mainnet (or a
///         mainnet fork); the wired addresses will not resolve on other chains.
contract DeployInstantUsdcUsdsConverterMainnet is Script {

    uint256 constant ETHEREUM_MAINNET = 1;

    function run() external returns (InstantUsdcUsdsConverter converter) {
        require(block.chainid == ETHEREUM_MAINNET, "DeployInstantUsdcUsdsConverterMainnet/not-mainnet");

        vm.startBroadcast();
        converter = InstantUsdcUsdsConverterDeploy.deployMainnet();
        vm.stopBroadcast();

        console.log("InstantUsdcUsdsConverter deployed:", address(converter));
        console.log("  admin    : ", Ethereum.GROVE_PROXY);
        console.log("  swapper  : ", Ethereum.ALM_RELAYER);
        console.log("  pauser   : ", Ethereum.ALM_FREEZER);
        console.log("  holder   : ", Ethereum.GROVE_PROXY);
        console.log("  litePsm  : ", Ethereum.PSM);
        console.log("  daiUsds  : ", Ethereum.DAI_USDS);
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
contract DeployInstantUsdcUsdsConverterCustom is Script {

    function run() external returns (InstantUsdcUsdsConverter converter) {
        address admin   = vm.envAddress("CONVERTER_ADMIN");
        address swapper = vm.envAddress("CONVERTER_SWAPPER");
        address pauser  = vm.envAddress("CONVERTER_PAUSER");
        address holder  = vm.envAddress("CONVERTER_HOLDER");
        address litePsm = vm.envAddress("CONVERTER_LITE_PSM");
        address daiUsds = vm.envAddress("CONVERTER_DAI_USDS");

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
