// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Script, console } from "forge-std/Script.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import {
    InstantUsdcUsdsConverter,
    ILitePsmLike,
    IDaiUsdsLike
} from "../src/InstantUsdcUsdsConverter.sol";

/// @notice Post-deployment verification for the mainnet deployment. Checks a live
///         InstantUsdcUsdsConverter (address in `CONVERTER_ADDRESS`) against the hardcoded
///         Grove Ethereum mainnet addresses. Reverts on the first mismatch.
contract VerifyInstantUsdcUsdsConverterMainnet is Script {

    uint256 constant ETHEREUM_MAINNET = 1;

    function run() external view {
        require(block.chainid == ETHEREUM_MAINNET, "VerifyInstantUsdcUsdsConverterMainnet/not-mainnet");

        InstantUsdcUsdsConverter converter = InstantUsdcUsdsConverter(vm.envAddress("CONVERTER_ADDRESS"));

        require(address(converter.litePsm()) == Ethereum.PSM,          "verify/lite-psm");
        require(address(converter.daiUsds()) == Ethereum.DAI_USDS,     "verify/dai-usds");
        require(address(converter.usdc())    == Ethereum.USDC,         "verify/usdc");
        require(address(converter.dai())     == Ethereum.DAI,          "verify/dai");
        require(address(converter.usds())    == Ethereum.USDS,         "verify/usds");
        require(converter.holder()           == Ethereum.GROVE_PROXY,  "verify/holder");
        require(converter.conversionFactor() == 1e12,                  "verify/conversion-factor");

        require(converter.hasRole(converter.DEFAULT_ADMIN_ROLE(), Ethereum.GROVE_PROXY), "verify/admin-role");
        require(converter.hasRole(converter.SWAPPER_ROLE(),       Ethereum.ALM_RELAYER), "verify/swapper-role");
        require(converter.hasRole(converter.PAUSER_ROLE(),        Ethereum.ALM_FREEZER), "verify/pauser-role");
        require(!converter.hasRole(converter.SWAPPER_ROLE(),      Ethereum.GROVE_PROXY), "verify/holder-has-swapper");

        console.log("InstantUsdcUsdsConverter verified (mainnet):", address(converter));
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
contract VerifyInstantUsdcUsdsConverterCustom is Script {

    function run() external view {
        InstantUsdcUsdsConverter converter = InstantUsdcUsdsConverter(vm.envAddress("CONVERTER_ADDRESS"));

        address admin   = vm.envAddress("CONVERTER_ADMIN");
        address swapper = vm.envAddress("CONVERTER_SWAPPER");
        address pauser  = vm.envAddress("CONVERTER_PAUSER");
        address holder  = vm.envAddress("CONVERTER_HOLDER");
        address litePsm = vm.envAddress("CONVERTER_LITE_PSM");
        address daiUsds = vm.envAddress("CONVERTER_DAI_USDS");

        require(address(converter.litePsm()) == litePsm, "verify/lite-psm");
        require(address(converter.daiUsds()) == daiUsds, "verify/dai-usds");
        require(converter.holder()           == holder,  "verify/holder");

        // usdc, dai, usds and conversionFactor are read from the LitePSM / exchanger at
        // construction, so verify the converter mirrors those rather than checking against
        // separately supplied values.
        require(address(converter.usdc())    == ILitePsmLike(litePsm).gem(),                  "verify/usdc");
        require(address(converter.dai())     == ILitePsmLike(litePsm).dai(),                  "verify/dai");
        require(address(converter.usds())    == IDaiUsdsLike(daiUsds).usds(),                 "verify/usds");
        require(converter.conversionFactor() == ILitePsmLike(litePsm).to18ConversionFactor(), "verify/conversion-factor");

        require(converter.hasRole(converter.DEFAULT_ADMIN_ROLE(), admin),   "verify/admin-role");
        require(converter.hasRole(converter.SWAPPER_ROLE(),       swapper), "verify/swapper-role");
        require(converter.hasRole(converter.PAUSER_ROLE(),        pauser),  "verify/pauser-role");

        console.log("InstantUsdcUsdsConverter verified (custom):", address(converter));
    }

}
