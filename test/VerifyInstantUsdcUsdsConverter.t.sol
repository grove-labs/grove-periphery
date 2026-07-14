// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { InstantUsdcUsdsConverter }       from "../src/InstantUsdcUsdsConverter.sol";
import { InstantUsdcUsdsConverterDeploy } from "../deploy/InstantUsdcUsdsConverterDeploy.sol";

import {
    VerifyInstantUsdcUsdsConverterMainnet,
    VerifyInstantUsdcUsdsConverterCustom
} from "../script/VerifyInstantUsdcUsdsConverter.s.sol";

import { MockLitePsm } from "./mocks/MockLitePsm.sol";
import { MockDaiUsds } from "./mocks/MockDaiUsds.sol";

// These tests run the real verify scripts against a real, deploy-library-built converter, inducing
// failures via the AccessControl API (roles), constructor args (wiring), or a `vm.mockCall` (the
// immutable usdc/dai/usds/conversionFactor values a real converter can never diverge on).
//
// Mismatch cases call the scripts' parameterized `verify(...)` directly, so they never touch
// process-global env. Only the happy-path tests exercise `run()` (which reads env) to cover the
// env-driven entrypoint.
abstract contract VerifyInstantUsdcUsdsConverterScriptTestBase is Test {

    uint256 constant CONVERSION_FACTOR = 1e12;

    MockLitePsm mockLitePsm;
    MockDaiUsds mockDaiUsds;

    function setUp() public {
        vm.createSelectFork("mainnet");
        mockLitePsm = new MockLitePsm(Ethereum.USDC, Ethereum.DAI, CONVERSION_FACTOR);
        mockDaiUsds = new MockDaiUsds(Ethereum.DAI, Ethereum.USDS);
    }

    function _deployMainnetConverter() internal returns (InstantUsdcUsdsConverter) {
        return InstantUsdcUsdsConverterDeploy.deployMainnet();
    }

    function _deployConverter(address holder, address litePsm, address daiUsds)
        internal
        returns (InstantUsdcUsdsConverter)
    {
        return InstantUsdcUsdsConverterDeploy.deploy(
            Ethereum.GROVE_PROXY, Ethereum.ALM_RELAYER, Ethereum.ALM_FREEZER, holder, litePsm, daiUsds
        );
    }

}

contract VerifyInstantUsdcUsdsConverterMainnetScriptTest is VerifyInstantUsdcUsdsConverterScriptTestBase {

    function test_verifyMainnet_passesForCorrectDeployment() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        _setEnv(address(converter));

        new VerifyInstantUsdcUsdsConverterMainnet().run();
    }

    function test_verifyMainnet_revertsOffMainnet() public {
        VerifyInstantUsdcUsdsConverterMainnet verifyScript = new VerifyInstantUsdcUsdsConverterMainnet();

        vm.chainId(10);

        vm.expectRevert("VerifyInstantUsdcUsdsConverterMainnet/not-mainnet");
        verifyScript.run();
    }

    function test_verifyMainnet_revertsOnLitePsmMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, address(mockLitePsm), Ethereum.DAI_USDS);
        _expectRevert(converter, "verify/lite-psm");
    }

    function test_verifyMainnet_revertsOnDaiUsdsMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, address(mockDaiUsds));
        _expectRevert(converter, "verify/dai-usds");
    }

    function test_verifyMainnet_revertsOnUsdcMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        vm.mockCall(address(converter), abi.encodeWithSignature("usdc()"), abi.encode(makeAddr("wrongUsdc")));
        _expectRevert(converter, "verify/usdc");
    }

    function test_verifyMainnet_revertsOnDaiMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        vm.mockCall(address(converter), abi.encodeWithSignature("dai()"), abi.encode(makeAddr("wrongDai")));
        _expectRevert(converter, "verify/dai");
    }

    function test_verifyMainnet_revertsOnUsdsMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        vm.mockCall(address(converter), abi.encodeWithSignature("usds()"), abi.encode(makeAddr("wrongUsds")));
        _expectRevert(converter, "verify/usds");
    }

    function test_verifyMainnet_revertsOnHolderMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(makeAddr("wrongHolder"), Ethereum.PSM, Ethereum.DAI_USDS);
        _expectRevert(converter, "verify/holder");
    }

    function test_verifyMainnet_revertsOnConversionFactorMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        vm.mockCall(address(converter), abi.encodeWithSignature("conversionFactor()"), abi.encode(uint256(1)));
        _expectRevert(converter, "verify/conversion-factor");
    }

    function test_verifyMainnet_revertsOnAdminRoleMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        bytes32 role = converter.DEFAULT_ADMIN_ROLE();
        vm.prank(Ethereum.GROVE_PROXY);
        converter.revokeRole(role, Ethereum.GROVE_PROXY);
        _expectRevert(converter, "verify/admin-role");
    }

    function test_verifyMainnet_revertsOnSwapperRoleMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        bytes32 role = converter.SWAPPER_ROLE();
        vm.prank(Ethereum.GROVE_PROXY);
        converter.revokeRole(role, Ethereum.ALM_RELAYER);
        _expectRevert(converter, "verify/swapper-role");
    }

    function test_verifyMainnet_revertsOnPauserRoleMismatch() public {
        InstantUsdcUsdsConverter converter = _deployMainnetConverter();
        bytes32 role = converter.PAUSER_ROLE();
        vm.prank(Ethereum.GROVE_PROXY);
        converter.revokeRole(role, Ethereum.ALM_FREEZER);
        _expectRevert(converter, "verify/pauser-role");
    }

    function _setEnv(address converter) internal {
        vm.setEnv("CONVERTER_ADDRESS", vm.toString(converter));
    }

    function _expectRevert(InstantUsdcUsdsConverter converter, bytes memory reason) internal {
        VerifyInstantUsdcUsdsConverterMainnet verifyScript = new VerifyInstantUsdcUsdsConverterMainnet();
        vm.expectRevert(reason);
        verifyScript.verify(address(converter));
    }

}

contract VerifyInstantUsdcUsdsConverterCustomScriptTest is VerifyInstantUsdcUsdsConverterScriptTestBase {

    function test_verifyCustom_passesForCorrectDeployment() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        _setEnv(address(converter));

        new VerifyInstantUsdcUsdsConverterCustom().run();
    }

    function test_verifyCustom_revertsOnLitePsmMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, address(mockLitePsm), Ethereum.DAI_USDS);
        _expectRevert(converter, "verify/lite-psm");
    }

    function test_verifyCustom_revertsOnDaiUsdsMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, address(mockDaiUsds));
        _expectRevert(converter, "verify/dai-usds");
    }

    function test_verifyCustom_revertsOnHolderMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(makeAddr("wrongHolder"), Ethereum.PSM, Ethereum.DAI_USDS);
        _expectRevert(converter, "verify/holder");
    }

    function test_verifyCustom_revertsOnUsdcMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        vm.mockCall(Ethereum.PSM, abi.encodeWithSignature("gem()"), abi.encode(makeAddr("wrongGem")));
        _expectRevert(converter, "verify/usdc");
    }

    function test_verifyCustom_revertsOnDaiMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        vm.mockCall(Ethereum.PSM, abi.encodeWithSignature("dai()"), abi.encode(makeAddr("wrongDai")));
        _expectRevert(converter, "verify/dai");
    }

    function test_verifyCustom_revertsOnUsdsMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        vm.mockCall(Ethereum.DAI_USDS, abi.encodeWithSignature("usds()"), abi.encode(makeAddr("wrongUsds")));
        _expectRevert(converter, "verify/usds");
    }

    function test_verifyCustom_revertsOnConversionFactorMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        vm.mockCall(Ethereum.PSM, abi.encodeWithSignature("to18ConversionFactor()"), abi.encode(uint256(1)));
        _expectRevert(converter, "verify/conversion-factor");
    }

    function test_verifyCustom_revertsOnAdminRoleMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        bytes32 role = converter.DEFAULT_ADMIN_ROLE();
        vm.prank(Ethereum.GROVE_PROXY);
        converter.revokeRole(role, Ethereum.GROVE_PROXY);
        _expectRevert(converter, "verify/admin-role");
    }

    function test_verifyCustom_revertsOnSwapperRoleMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        bytes32 role = converter.SWAPPER_ROLE();
        vm.prank(Ethereum.GROVE_PROXY);
        converter.revokeRole(role, Ethereum.ALM_RELAYER);
        _expectRevert(converter, "verify/swapper-role");
    }

    function test_verifyCustom_revertsOnPauserRoleMismatch() public {
        InstantUsdcUsdsConverter converter = _deployConverter(Ethereum.GROVE_PROXY, Ethereum.PSM, Ethereum.DAI_USDS);
        bytes32 role = converter.PAUSER_ROLE();
        vm.prank(Ethereum.GROVE_PROXY);
        converter.revokeRole(role, Ethereum.ALM_FREEZER);
        _expectRevert(converter, "verify/pauser-role");
    }

    function _setEnv(address converter) internal {
        vm.setEnv("CONVERTER_ADDRESS",  vm.toString(converter));
        vm.setEnv("CONVERTER_ADMIN",    vm.toString(Ethereum.GROVE_PROXY));
        vm.setEnv("CONVERTER_SWAPPER",  vm.toString(Ethereum.ALM_RELAYER));
        vm.setEnv("CONVERTER_PAUSER",   vm.toString(Ethereum.ALM_FREEZER));
        vm.setEnv("CONVERTER_HOLDER",   vm.toString(Ethereum.GROVE_PROXY));
        vm.setEnv("CONVERTER_LITE_PSM", vm.toString(Ethereum.PSM));
        vm.setEnv("CONVERTER_DAI_USDS", vm.toString(Ethereum.DAI_USDS));
    }

    function _expectRevert(InstantUsdcUsdsConverter converter, bytes memory reason) internal {
        VerifyInstantUsdcUsdsConverterCustom verifyScript = new VerifyInstantUsdcUsdsConverterCustom();
        vm.expectRevert(reason);
        verifyScript.verify(
            address(converter),
            Ethereum.GROVE_PROXY,
            Ethereum.ALM_RELAYER,
            Ethereum.ALM_FREEZER,
            Ethereum.GROVE_PROXY,
            Ethereum.PSM,
            Ethereum.DAI_USDS
        );
    }

}
