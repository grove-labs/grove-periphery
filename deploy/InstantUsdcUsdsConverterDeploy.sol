// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { InstantUsdcUsdsConverter } from "../src/InstantUsdcUsdsConverter.sol";

library InstantUsdcUsdsConverterDeploy {

    /// @notice Deploys InstantUsdcUsdsConverter with explicit constructor arguments.
    ///         Chain agnostic: works on any chain given valid addresses.
    function deploy(
        address admin,
        address swapper,
        address freezer,
        address holder,
        address litePsm,
        address daiUsds
    ) internal returns (InstantUsdcUsdsConverter converter) {
        converter = new InstantUsdcUsdsConverter({
            admin_   : admin,
            swapper_ : swapper,
            freezer_ : freezer,
            holder_  : holder,
            litePsm_ : litePsm,
            daiUsds_ : daiUsds
        });
    }

    /// @notice Deploys InstantUsdcUsdsConverter wired to the Grove Ethereum mainnet addresses:
    ///         admin and holder are the Grove governance subproxy, the swapper is the ALM relayer,
    ///         the freezer is the ALM freezer multisig, the LitePSM is the DAI LitePSM-USDC and the
    ///         DAI<>USDS exchanger is the canonical DaiUsds converter.
    function deployMainnet() internal returns (InstantUsdcUsdsConverter converter) {
        converter = deploy({
            admin   : Ethereum.GROVE_PROXY,
            swapper : Ethereum.ALM_RELAYER,
            freezer : Ethereum.ALM_FREEZER,
            holder  : Ethereum.GROVE_PROXY,
            litePsm : Ethereum.PSM,
            daiUsds : Ethereum.DAI_USDS
        });
    }

}
