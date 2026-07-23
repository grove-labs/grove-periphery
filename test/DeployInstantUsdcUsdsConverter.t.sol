// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { InstantUsdcUsdsConverter } from "../src/InstantUsdcUsdsConverter.sol";

import {
    DeployInstantUsdcUsdsConverterMainnet,
    DeployInstantUsdcUsdsConverterCustom
} from "../script/DeployInstantUsdcUsdsConverter.s.sol";

contract DeployInstantUsdcUsdsConverterScriptTest is Test {

    uint256 constant CONVERSION_FACTOR = 1e12;

    function setUp() public {
        vm.createSelectFork("mainnet");
    }

    function test_mainnetScript_deploysWithRegistryAddresses() public {
        InstantUsdcUsdsConverter converter = new DeployInstantUsdcUsdsConverterMainnet().run();

        assertEq(address(converter.litePsm()), Ethereum.PSM);
        assertEq(address(converter.daiUsds()), Ethereum.DAI_USDS);
        assertEq(address(converter.usdc()),    Ethereum.USDC);
        assertEq(address(converter.dai()),     Ethereum.DAI);
        assertEq(address(converter.usds()),    Ethereum.USDS);
        assertEq(converter.holder(),           Ethereum.GROVE_PROXY);
        assertEq(converter.conversionFactor(), CONVERSION_FACTOR);

        assertTrue(converter.hasRole(converter.DEFAULT_ADMIN_ROLE(), Ethereum.GROVE_PROXY));
        assertTrue(converter.hasRole(converter.SWAPPER_ROLE(),       Ethereum.ALM_RELAYER));
        assertTrue(converter.hasRole(converter.FREEZER_ROLE(),       Ethereum.ALM_FREEZER));
    }

    function test_mainnetScript_revertsOffMainnet() public {
        DeployInstantUsdcUsdsConverterMainnet deployScript = new DeployInstantUsdcUsdsConverterMainnet();

        vm.chainId(10);

        vm.expectRevert("DeployInstantUsdcUsdsConverterMainnet/not-mainnet");
        deployScript.run();
    }

    function test_customScript_deploysFromEnv() public {
        address admin   = Ethereum.GROVE_PROXY;
        address swapper = Ethereum.ALM_RELAYER;
        address freezer = Ethereum.ALM_FREEZER;
        address holder  = Ethereum.GROVE_PROXY;
        address litePsm = Ethereum.PSM;
        address daiUsds = Ethereum.DAI_USDS;

        vm.setEnv("CONVERTER_ADMIN",    vm.toString(admin));
        vm.setEnv("CONVERTER_SWAPPER",  vm.toString(swapper));
        vm.setEnv("CONVERTER_FREEZER",  vm.toString(freezer));
        vm.setEnv("CONVERTER_HOLDER",   vm.toString(holder));
        vm.setEnv("CONVERTER_LITE_PSM", vm.toString(litePsm));
        vm.setEnv("CONVERTER_DAI_USDS", vm.toString(daiUsds));

        InstantUsdcUsdsConverter converter = new DeployInstantUsdcUsdsConverterCustom().run();

        assertEq(address(converter.litePsm()), litePsm);
        assertEq(address(converter.daiUsds()), daiUsds);
        assertEq(address(converter.usdc()),    Ethereum.USDC);
        assertEq(address(converter.dai()),     Ethereum.DAI);
        assertEq(address(converter.usds()),    Ethereum.USDS);
        assertEq(converter.holder(),           holder);
        assertEq(converter.conversionFactor(), CONVERSION_FACTOR);

        assertTrue(converter.hasRole(converter.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(converter.hasRole(converter.SWAPPER_ROLE(),       swapper));
        assertTrue(converter.hasRole(converter.FREEZER_ROLE(),       freezer));
    }

}
