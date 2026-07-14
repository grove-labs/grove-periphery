// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Script, console } from "forge-std/Script.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import {
    InstantUsdcUsdsConverter,
    ILitePsmLike,
    IDaiUsdsLike
} from "../src/InstantUsdcUsdsConverter.sol";

/// @notice Shared verification logic for InstantUsdcUsdsConverter deployments. Each concrete
///         script supplies the expected wiring/role addresses; `_verify` asserts the live
///         converter matches, reverting on the first mismatch.
abstract contract VerifyInstantUsdcUsdsConverterBase is Script {

    function _verify(
        address converter_,
        address admin,
        address swapper,
        address pauser,
        address holder,
        address litePsm,
        address daiUsds,
        address usdc,
        address dai,
        address usds,
        uint256 conversionFactor
    ) internal view {
        InstantUsdcUsdsConverter converter = InstantUsdcUsdsConverter(converter_);

        require(address(converter.litePsm()) == litePsm,          "verify/lite-psm");
        require(address(converter.daiUsds()) == daiUsds,          "verify/dai-usds");
        require(address(converter.usdc())    == usdc,             "verify/usdc");
        require(address(converter.dai())     == dai,              "verify/dai");
        require(address(converter.usds())    == usds,             "verify/usds");
        require(converter.holder()           == holder,           "verify/holder");
        require(converter.conversionFactor() == conversionFactor, "verify/conversion-factor");

        require(converter.hasRole(converter.DEFAULT_ADMIN_ROLE(), admin),   "verify/admin-role");
        require(converter.hasRole(converter.SWAPPER_ROLE(),       swapper), "verify/swapper-role");
        require(converter.hasRole(converter.PAUSER_ROLE(),        pauser),  "verify/pauser-role");

        console.log("InstantUsdcUsdsConverter verified:", converter_);
    }

}

/// @notice Post-deployment verification for the mainnet deployment. Checks a live
///         InstantUsdcUsdsConverter (address in `CONVERTER_ADDRESS`) against the hardcoded
///         Grove Ethereum mainnet addresses. Reverts on the first mismatch.
contract VerifyInstantUsdcUsdsConverterMainnet is VerifyInstantUsdcUsdsConverterBase {

    uint256 constant ETHEREUM_MAINNET = 1;

    function run() external view {
        require(block.chainid == ETHEREUM_MAINNET, "VerifyInstantUsdcUsdsConverterMainnet/not-mainnet");

        verify(vm.envAddress("CONVERTER_ADDRESS"));
    }

    function verify(address converter_) public view {
        _verify({
            converter_       : converter_,
            admin            : Ethereum.GROVE_PROXY,
            swapper          : Ethereum.ALM_RELAYER,
            pauser           : Ethereum.ALM_FREEZER,
            holder           : Ethereum.GROVE_PROXY,
            litePsm          : Ethereum.PSM,
            daiUsds          : Ethereum.DAI_USDS,
            usdc             : Ethereum.USDC,
            dai              : Ethereum.DAI,
            usds             : Ethereum.USDS,
            conversionFactor : 1e12
        });
    }

}

/// @notice Post-deployment verification for a custom deployment. Checks a live
///         InstantUsdcUsdsConverter (address in `CONVERTER_ADDRESS`) against the same
///         environment variables used to deploy it. Reverts on the first mismatch.
///
///         Required environment variables:
///           CONVERTER_ADDRESS  - deployed InstantUsdcUsdsConverter to verify
///           CONVERTER_ADMIN    - expected DEFAULT_ADMIN_ROLE holder
///           CONVERTER_SWAPPER  - expected SWAPPER_ROLE holder
///           CONVERTER_PAUSER   - expected PAUSER_ROLE holder
///           CONVERTER_HOLDER   - expected holder
///           CONVERTER_LITE_PSM - expected LitePSM
///           CONVERTER_DAI_USDS - expected DAI<>USDS exchanger
contract VerifyInstantUsdcUsdsConverterCustom is VerifyInstantUsdcUsdsConverterBase {

    function run() external view {
        verify(
            vm.envAddress("CONVERTER_ADDRESS"),
            vm.envAddress("CONVERTER_ADMIN"),
            vm.envAddress("CONVERTER_SWAPPER"),
            vm.envAddress("CONVERTER_PAUSER"),
            vm.envAddress("CONVERTER_HOLDER"),
            vm.envAddress("CONVERTER_LITE_PSM"),
            vm.envAddress("CONVERTER_DAI_USDS")
        );
    }

    function verify(
        address converter_,
        address admin,
        address swapper,
        address pauser,
        address holder,
        address litePsm,
        address daiUsds
    ) public view {
        // usdc, dai, usds and conversionFactor are read from the LitePSM / exchanger at
        // construction, so verify the converter mirrors those rather than checking against
        // separately supplied values.
        _verify({
            converter_       : converter_,
            admin            : admin,
            swapper          : swapper,
            pauser           : pauser,
            holder           : holder,
            litePsm          : litePsm,
            daiUsds          : daiUsds,
            usdc             : ILitePsmLike(litePsm).gem(),
            dai              : ILitePsmLike(litePsm).dai(),
            usds             : IDaiUsdsLike(daiUsds).usds(),
            conversionFactor : ILitePsmLike(litePsm).to18ConversionFactor()
        });
    }

}
