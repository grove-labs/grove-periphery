// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 }         from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 }        from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Errors }  from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { Ethereum } from "grove-address-registry/Ethereum.sol";

import { InstantUsdcUsdsConverter }       from "../src/InstantUsdcUsdsConverter.sol";
import { InstantUsdcUsdsConverterDeploy } from "../deploy/InstantUsdcUsdsConverterDeploy.sol";

import { MockERC721 }  from "./mocks/MockERC721.sol";
import { MockLitePsm } from "./mocks/MockLitePsm.sol";
import { MockDaiUsds } from "./mocks/MockDaiUsds.sol";

interface ILitePsmAdminLike {
    function file(bytes32 what, uint256 data) external;
    function kiss(address usr) external;
    function tin() external view returns (uint256);
}

contract InstantUsdcUsdsConverterTestBase is Test {

    address constant GROVE_PROXY = Ethereum.GROVE_PROXY;
    address constant ALM_RELAYER = Ethereum.ALM_RELAYER;
    address constant ALM_FREEZER = Ethereum.ALM_FREEZER;
    address constant USDC        = Ethereum.USDC;
    address constant DAI         = Ethereum.DAI;
    address constant USDS        = Ethereum.USDS;
    address constant LITE_PSM    = Ethereum.PSM;
    address constant DAI_USDS    = Ethereum.DAI_USDS;
    address constant PAUSE_PROXY = Ethereum.PAUSE_PROXY;

    uint256 constant CONVERSION_FACTOR = 1e12; // USDC (6 dec) -> USDS (18 dec)

    InstantUsdcUsdsConverter converter;

    bytes32 SWAPPER_ROLE;
    bytes32 FREEZER_ROLE;
    bytes32 ADMIN_ROLE;

    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.createSelectFork("mainnet");

        converter = InstantUsdcUsdsConverterDeploy.deployMainnet();

        SWAPPER_ROLE = converter.SWAPPER_ROLE();
        FREEZER_ROLE = converter.FREEZER_ROLE();
        ADMIN_ROLE   = converter.DEFAULT_ADMIN_ROLE();
    }

    function _fundHolderAndApproveConverter(uint256 usdcAmount) internal {
        deal(USDC, GROVE_PROXY, usdcAmount);
        vm.prank(GROVE_PROXY);
        IERC20(USDC).approve(address(converter), usdcAmount);
    }

}

contract InstantUsdcUsdsConverterAdminTest is InstantUsdcUsdsConverterTestBase {

    /*** Constructor ***/

    function test_constructor_wiring() public view {
        assertEq(address(converter.litePsm()), LITE_PSM);
        assertEq(address(converter.daiUsds()), DAI_USDS);
        assertEq(address(converter.usdc()),    USDC);
        assertEq(address(converter.dai()),     DAI);
        assertEq(address(converter.usds()),    USDS);
        assertEq(converter.holder(),           GROVE_PROXY);
        assertEq(converter.conversionFactor(), CONVERSION_FACTOR);

        assertTrue(converter.hasRole(ADMIN_ROLE,    GROVE_PROXY));
        assertTrue(converter.hasRole(SWAPPER_ROLE,  ALM_RELAYER));
        assertTrue(converter.hasRole(FREEZER_ROLE,  ALM_FREEZER));
        assertFalse(converter.hasRole(SWAPPER_ROLE, GROVE_PROXY));
        assertFalse(converter.hasRole(FREEZER_ROLE, ALM_RELAYER));
        assertFalse(converter.hasRole(SWAPPER_ROLE, ALM_FREEZER));
    }

    function test_constructor_revertsOnZeroAddress() public {
        vm.expectRevert(InstantUsdcUsdsConverter.InvalidAdmin.selector);
        new InstantUsdcUsdsConverter(address(0), ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, LITE_PSM, DAI_USDS);

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidSwapper.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, address(0), ALM_FREEZER, GROVE_PROXY, LITE_PSM, DAI_USDS);

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidFreezer.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, address(0), GROVE_PROXY, LITE_PSM, DAI_USDS);

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidHolder.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, address(0), LITE_PSM, DAI_USDS);

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidLitePsm.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, address(0), DAI_USDS);

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidDaiUsds.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, LITE_PSM, address(0));
    }

    function test_constructor_revertsOnZeroGem() public {
        address litePsm = address(new MockLitePsm(address(0), DAI, CONVERSION_FACTOR));
        address daiUsds = address(new MockDaiUsds(DAI, USDS));

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidUsdc.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, litePsm, daiUsds);
    }

    function test_constructor_revertsOnZeroDai() public {
        address litePsm = address(new MockLitePsm(USDC, address(0), CONVERSION_FACTOR));
        address daiUsds = address(new MockDaiUsds(DAI, USDS));

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidDai.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, litePsm, daiUsds);
    }

    function test_constructor_revertsOnZeroUsds() public {
        address litePsm = address(new MockLitePsm(USDC, DAI, CONVERSION_FACTOR));
        address daiUsds = address(new MockDaiUsds(DAI, address(0)));

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidUsds.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, litePsm, daiUsds);
    }

    function test_constructor_revertsOnDaiMismatch() public {
        address litePsm = address(new MockLitePsm(USDC, DAI, CONVERSION_FACTOR));
        address daiUsds = address(new MockDaiUsds(USDC, USDS)); // exchanger's dai != litePsm's dai

        vm.expectRevert(InstantUsdcUsdsConverter.DaiMismatch.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, litePsm, daiUsds);
    }

    function test_constructor_revertsOnZeroConversionFactor() public {
        address litePsm = address(new MockLitePsm(USDC, DAI, 0));
        address daiUsds = address(new MockDaiUsds(DAI, USDS));

        vm.expectRevert(InstantUsdcUsdsConverter.InvalidConversionFactor.selector);
        new InstantUsdcUsdsConverter(GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, litePsm, daiUsds);
    }

    /*** Role administration ***/

    function test_admin_canRotateSwapper() public {
        address newSwapper = makeAddr("newSwapper");

        vm.startPrank(GROVE_PROXY);
        converter.grantRole(SWAPPER_ROLE, newSwapper);
        converter.revokeRole(SWAPPER_ROLE, ALM_RELAYER);
        vm.stopPrank();

        assertTrue(converter.hasRole(SWAPPER_ROLE, newSwapper));
        assertFalse(converter.hasRole(SWAPPER_ROLE, ALM_RELAYER));

        uint256 amount = 10_000e6;
        _fundHolderAndApproveConverter(amount);

        vm.prank(newSwapper);
        converter.swap(amount);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_RELAYER, SWAPPER_ROLE)
        );
        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function test_admin_canRotateFreezer() public {
        address newFreezer = makeAddr("newFreezer");

        vm.startPrank(GROVE_PROXY);
        converter.grantRole(FREEZER_ROLE, newFreezer);
        converter.revokeRole(FREEZER_ROLE, ALM_FREEZER);
        vm.stopPrank();

        assertTrue(converter.hasRole(FREEZER_ROLE, newFreezer));
        assertFalse(converter.hasRole(FREEZER_ROLE, ALM_FREEZER));

        // The old freezer can no longer eject swappers.
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_FREEZER, FREEZER_ROLE)
        );
        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        // The new freezer can.
        vm.prank(newFreezer);
        converter.removeSwapper(ALM_RELAYER);

        assertFalse(converter.hasRole(SWAPPER_ROLE, ALM_RELAYER));
    }

    function test_admin_canTransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(GROVE_PROXY);
        converter.grantRole(ADMIN_ROLE, newAdmin);

        vm.prank(newAdmin);
        converter.revokeRole(ADMIN_ROLE, GROVE_PROXY);

        assertTrue(converter.hasRole(ADMIN_ROLE, newAdmin));
        assertFalse(converter.hasRole(ADMIN_ROLE, GROVE_PROXY));

        // The old admin can no longer manage roles.
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, GROVE_PROXY, ADMIN_ROLE)
        );
        vm.prank(GROVE_PROXY);
        converter.grantRole(SWAPPER_ROLE, stranger);

        // The new admin can manage every role.
        vm.startPrank(newAdmin);
        converter.grantRole(SWAPPER_ROLE, stranger);
        converter.grantRole(FREEZER_ROLE, stranger);
        vm.stopPrank();

        assertTrue(converter.hasRole(SWAPPER_ROLE, stranger));
        assertTrue(converter.hasRole(FREEZER_ROLE, stranger));
    }

    function test_roleAdmin_isDefaultAdminForAllRoles() public view {
        assertEq(converter.getRoleAdmin(ADMIN_ROLE),   ADMIN_ROLE);
        assertEq(converter.getRoleAdmin(SWAPPER_ROLE), ADMIN_ROLE);
        assertEq(converter.getRoleAdmin(FREEZER_ROLE), ADMIN_ROLE);
    }

    function test_swapper_canRenounceOwnRole() public {
        vm.prank(ALM_RELAYER);
        converter.renounceRole(SWAPPER_ROLE, ALM_RELAYER);

        assertFalse(converter.hasRole(SWAPPER_ROLE, ALM_RELAYER));
    }

    function test_freezer_canRenounceOwnRole() public {
        vm.prank(ALM_FREEZER);
        converter.renounceRole(FREEZER_ROLE, ALM_FREEZER);

        assertFalse(converter.hasRole(FREEZER_ROLE, ALM_FREEZER));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_FREEZER, FREEZER_ROLE)
        );
        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);
    }

    function test_swapper_cannotManageRoles() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_RELAYER, ADMIN_ROLE)
        );
        vm.prank(ALM_RELAYER);
        converter.grantRole(SWAPPER_ROLE, stranger);
    }

    function test_freezer_cannotManageRoles() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_FREEZER, ADMIN_ROLE)
        );
        vm.prank(ALM_FREEZER);
        converter.grantRole(FREEZER_ROLE, stranger);
    }

}

contract InstantUsdcUsdsConverterSwapTest is InstantUsdcUsdsConverterTestBase {

    MockLitePsm              mockLitePsm;
    MockDaiUsds              mockDaiUsds;
    InstantUsdcUsdsConverter mockConverter;

    function _deployOverMocks() internal {
        mockLitePsm   = new MockLitePsm(USDC, DAI, CONVERSION_FACTOR);
        mockDaiUsds   = new MockDaiUsds(DAI, USDS);
        mockConverter = new InstantUsdcUsdsConverter(
            GROVE_PROXY, ALM_RELAYER, ALM_FREEZER, GROVE_PROXY, address(mockLitePsm), address(mockDaiUsds)
        );

        // Pre-fund the mocks so they can deliver DAI and USDS on a well-behaved swap.
        deal(DAI,  address(mockLitePsm), 1_000_000e18);
        deal(USDS, address(mockDaiUsds), 1_000_000e18);
    }

    function _fundMockConverter(uint256 amount) internal {
        deal(USDC, GROVE_PROXY, amount);
        vm.prank(GROVE_PROXY);
        IERC20(USDC).approve(address(mockConverter), amount);
    }

    function test_swap_success() public {
        uint256 amount       = 10_000e6;
        uint256 expectedUsds = amount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(amount);

        uint256 holderUsdsBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

        vm.prank(ALM_RELAYER);
        uint256 usdsOut = converter.swap(amount);

        assertEq(usdsOut, expectedUsds);
        assertEq(IERC20(USDS).balanceOf(GROVE_PROXY), holderUsdsBefore + expectedUsds);
        assertEq(IERC20(USDC).balanceOf(GROVE_PROXY), 0);

        // Nothing left stranded in the converter.
        assertEq(IERC20(USDC).balanceOf(address(converter)), 0);
        assertEq(IERC20(DAI).balanceOf(address(converter)),  0);
        assertEq(IERC20(USDS).balanceOf(address(converter)), 0);
        assertEq(IERC20(USDC).allowance(address(converter), LITE_PSM), 0);
        assertEq(IERC20(DAI).allowance(address(converter),  DAI_USDS), 0);
    }

    function test_swap_emitsSwappedForFeeRoute() public {
        uint256 amount       = 10_000e6;
        uint256 expectedUsds = amount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(amount);

        // Not whitelisted, so the permissionless `sellGem` route is used (noFeeRoute = false).
        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.Swapped(ALM_RELAYER, amount, expectedUsds, false);

        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function test_swap_revertsForNonSwapper() public {
        _fundHolderAndApproveConverter(1_000e6);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, SWAPPER_ROLE)
        );
        vm.prank(stranger);
        converter.swap(1_000e6);
    }

    function test_swap_revertsForAdminWithoutSwapperRole() public {
        _fundHolderAndApproveConverter(1_000e6);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, GROVE_PROXY, SWAPPER_ROLE)
        );
        vm.prank(GROVE_PROXY);
        converter.swap(1_000e6);
    }

    function test_swap_revertsOnZeroAmount() public {
        vm.expectRevert(InstantUsdcUsdsConverter.ZeroAmount.selector);
        vm.prank(ALM_RELAYER);
        converter.swap(0);
    }

    function test_swap_revertsWhenNotOneToOne() public {
        // Introduce a sell fee on the LitePSM so the permissionless path no longer returns 1:1.
        vm.prank(PAUSE_PROXY);
        ILitePsmAdminLike(LITE_PSM).file("tin", 0.01e18);

        uint256 amount = 10_000e6;
        _fundHolderAndApproveConverter(amount);

        vm.expectRevert(InstantUsdcUsdsConverter.NotOneToOne.selector);
        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function test_swap_revertsOnInsufficientAllowance() public {
        uint256 amount = 10_000e6;

        // Holder holds enough USDC but approves less than `amount`.
        deal(USDC, GROVE_PROXY, amount);
        vm.prank(GROVE_PROXY);
        IERC20(USDC).approve(address(converter), amount - 1);

        vm.expectRevert();
        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function test_swap_revertsOnInsufficientBalance() public {
        uint256 amount = 10_000e6;

        // Holder approves enough but does not hold enough USDC.
        deal(USDC, GROVE_PROXY, amount - 1);
        vm.prank(GROVE_PROXY);
        IERC20(USDC).approve(address(converter), amount);

        vm.expectRevert();
        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function testFuzz_swap(uint256 usdcAmount) public {
        usdcAmount = bound(usdcAmount, 1, 1_000_000e6);

        uint256 expectedUsds = usdcAmount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(usdcAmount);

        uint256 holderUsdsBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

        vm.prank(ALM_RELAYER);
        uint256 usdsOut = converter.swap(usdcAmount);

        assertEq(usdsOut, expectedUsds);
        assertEq(IERC20(USDS).balanceOf(GROVE_PROXY), holderUsdsBefore + expectedUsds);
        assertEq(IERC20(USDC).balanceOf(GROVE_PROXY), 0);
        assertEq(IERC20(USDC).balanceOf(address(converter)), 0);
        assertEq(IERC20(DAI).balanceOf(address(converter)),  0);
        assertEq(IERC20(USDS).balanceOf(address(converter)), 0);
        assertEq(IERC20(USDC).allowance(address(converter), LITE_PSM), 0);
        assertEq(IERC20(DAI).allowance(address(converter),  DAI_USDS), 0);
    }

    function test_swap_revertsAfterSwapperRemoved() public {
        uint256 amount = 10_000e6;
        _fundHolderAndApproveConverter(amount);

        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_RELAYER, SWAPPER_ROLE)
        );
        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function test_swap_succeedsAfterSwapperRegranted() public {
        uint256 amount = 10_000e6;
        _fundHolderAndApproveConverter(amount);

        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        vm.prank(GROVE_PROXY);
        converter.grantRole(SWAPPER_ROLE, ALM_RELAYER);

        vm.prank(ALM_RELAYER);
        uint256 usdsOut = converter.swap(amount);

        assertEq(usdsOut, amount * CONVERSION_FACTOR);
    }

    function test_swap_revertsWhenUsdsNotDelivered() public {
        _deployOverMocks();
        mockDaiUsds.setSkipUsdsDelivery(true);

        uint256 amount = 10_000e6;
        _fundMockConverter(amount);

        vm.expectRevert(InstantUsdcUsdsConverter.UsdsNotReceived.selector);
        vm.prank(ALM_RELAYER);
        mockConverter.swap(amount);
    }

    function test_swap_resetsAllowanceEvenWhenPsmLeavesIt() public {
        _deployOverMocks();
        mockLitePsm.setSkipGemPull(true); // PSM delivers DAI but never pulls the approved USDC.

        uint256 amount = 10_000e6;
        _fundMockConverter(amount);

        vm.prank(ALM_RELAYER);
        mockConverter.swap(amount);

        // The dangling allowance the PSM left behind must be cleared.
        assertEq(IERC20(USDC).allowance(address(mockConverter), address(mockLitePsm)), 0);
    }

    function test_swap_resetsDaiAllowanceEvenWhenExchangerLeavesIt() public {
        _deployOverMocks();
        mockDaiUsds.setSkipDaiPull(true); // Exchanger delivers USDS but never pulls the approved DAI.

        uint256 amount = 10_000e6;
        _fundMockConverter(amount);

        vm.prank(ALM_RELAYER);
        mockConverter.swap(amount);

        // The dangling allowance the exchanger left behind must be cleared.
        assertEq(IERC20(DAI).allowance(address(mockConverter), address(mockDaiUsds)), 0);
    }

    function test_swap_sequentialSwapsLeaveNoResidual() public {
        uint256 amount        = 10_000e6;
        uint256 expectedUsds  = amount * CONVERSION_FACTOR;

        for (uint256 i = 0; i < 2; i++) {
            _fundHolderAndApproveConverter(amount);

            uint256 holderUsdsBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

            vm.prank(ALM_RELAYER);
            uint256 usdsOut = converter.swap(amount);

            assertEq(usdsOut, expectedUsds);
            assertEq(IERC20(USDS).balanceOf(GROVE_PROXY), holderUsdsBefore + expectedUsds);

            // No residual balances or allowances carry over between swaps.
            assertEq(IERC20(USDC).balanceOf(address(converter)), 0);
            assertEq(IERC20(DAI).balanceOf(address(converter)),  0);
            assertEq(IERC20(USDS).balanceOf(address(converter)), 0);
            assertEq(IERC20(USDC).allowance(address(converter), LITE_PSM), 0);
            assertEq(IERC20(DAI).allowance(address(converter),  DAI_USDS), 0);
        }
    }

}

contract InstantUsdcUsdsConverterSwapWhitelistedTest is InstantUsdcUsdsConverterTestBase {

    // When the converter is whitelisted (`kiss`ed) on the LitePSM, `swap` auto-selects the
    // fee-free `sellGemNoFee` route. These tests exercise that branch.

    function _kissConverter() internal {
        vm.prank(PAUSE_PROXY);
        ILitePsmAdminLike(LITE_PSM).kiss(address(converter));
    }

    function test_swap_whitelisted_usesNoFeeRoute() public {
        _kissConverter();

        uint256 amount       = 10_000e6;
        uint256 expectedUsds = amount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(amount);

        uint256 holderUsdsBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

        vm.prank(ALM_RELAYER);
        uint256 usdsOut = converter.swap(amount);

        assertEq(usdsOut, expectedUsds);
        assertEq(IERC20(USDS).balanceOf(GROVE_PROXY), holderUsdsBefore + expectedUsds);
        assertEq(IERC20(USDC).balanceOf(GROVE_PROXY), 0);

        assertEq(IERC20(USDC).balanceOf(address(converter)), 0);
        assertEq(IERC20(DAI).balanceOf(address(converter)),  0);
        assertEq(IERC20(USDS).balanceOf(address(converter)), 0);
        assertEq(IERC20(USDC).allowance(address(converter), LITE_PSM), 0);
        assertEq(IERC20(DAI).allowance(address(converter),  DAI_USDS), 0);
    }

    function test_swap_emitsSwappedForNoFeeRoute() public {
        _kissConverter();

        uint256 amount       = 10_000e6;
        uint256 expectedUsds = amount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(amount);

        // Whitelisted, so the fee-free `sellGemNoFee` route is used (noFeeRoute = true).
        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.Swapped(ALM_RELAYER, amount, expectedUsds, true);

        vm.prank(ALM_RELAYER);
        converter.swap(amount);
    }

    function test_swap_feeRevertsUntilKissThenSucceedsAtOneToOne() public {
        // Set a non-zero (but non-halting) sell fee on the PSM and confirm it took effect.
        vm.prank(PAUSE_PROXY);
        ILitePsmAdminLike(LITE_PSM).file("tin", 0.01e18);
        assertGt(ILitePsmAdminLike(LITE_PSM).tin(), 0);

        uint256 amount       = 10_000e6;
        uint256 expectedUsds = amount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(amount);

        uint256 holderUsdsBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

        // Not whitelisted yet: `swap` takes the permissionless `sellGem` route, which settles short
        // under the fee and reverts instead of losing value.
        vm.expectRevert(InstantUsdcUsdsConverter.NotOneToOne.selector);
        vm.prank(ALM_RELAYER);
        converter.swap(amount);

        // Kiss the converter; the fee is still non-zero, but `swap` now uses `sellGemNoFee`.
        _kissConverter();
        assertGt(ILitePsmAdminLike(LITE_PSM).tin(), 0);

        vm.prank(ALM_RELAYER);
        uint256 usdsOut = converter.swap(amount);

        assertEq(usdsOut, expectedUsds);
        assertEq(IERC20(USDS).balanceOf(GROVE_PROXY), holderUsdsBefore + expectedUsds);
    }

    function testFuzz_swap_whitelisted(uint256 usdcAmount) public {
        _kissConverter();

        usdcAmount = bound(usdcAmount, 1, 1_000_000e6);

        uint256 expectedUsds = usdcAmount * CONVERSION_FACTOR;

        _fundHolderAndApproveConverter(usdcAmount);

        uint256 holderUsdsBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

        vm.prank(ALM_RELAYER);
        uint256 usdsOut = converter.swap(usdcAmount);

        assertEq(usdsOut, expectedUsds);
        assertEq(IERC20(USDS).balanceOf(GROVE_PROXY), holderUsdsBefore + expectedUsds);
    }

}

contract InstantUsdcUsdsConverterRescueERC20Test is InstantUsdcUsdsConverterTestBase {

    function test_rescueERC20_success() public {
        uint256 amount = 12_345e6;
        deal(USDC, address(converter), amount);

        uint256 holderBefore = IERC20(USDC).balanceOf(GROVE_PROXY);

        vm.prank(GROVE_PROXY);
        uint256 rescued = converter.rescueERC20(IERC20(USDC));

        assertEq(rescued,                                    amount);
        assertEq(IERC20(USDC).balanceOf(GROVE_PROXY),        holderBefore + amount);
        assertEq(IERC20(USDC).balanceOf(address(converter)), 0);
    }

    function test_rescueERC20_success_arbitraryToken() public {
        uint256 amount = 5_000e18;
        deal(USDS, address(converter), amount);

        uint256 holderBefore = IERC20(USDS).balanceOf(GROVE_PROXY);

        vm.prank(GROVE_PROXY);
        uint256 rescued = converter.rescueERC20(IERC20(USDS));

        assertEq(rescued,                                    amount);
        assertEq(IERC20(USDS).balanceOf(GROVE_PROXY),        holderBefore + amount);
        assertEq(IERC20(USDS).balanceOf(address(converter)), 0);
    }

    function test_rescueERC20_emitsERC20Rescued() public {
        uint256 amount = 12_345e6;
        deal(USDC, address(converter), amount);

        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.ERC20Rescued(USDC, amount);

        vm.prank(GROVE_PROXY);
        converter.rescueERC20(IERC20(USDC));
    }

    function test_rescueERC20_succeedsOnZeroBalance() public {
        assertEq(IERC20(USDC).balanceOf(address(converter)), 0);

        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.ERC20Rescued(USDC, 0);

        vm.prank(GROVE_PROXY);
        uint256 amount = converter.rescueERC20(IERC20(USDC));

        assertEq(amount, 0);
    }

    function test_rescueERC20_revertsForNonAdmin() public {
        deal(USDC, address(converter), 1_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ADMIN_ROLE)
        );
        vm.prank(stranger);
        converter.rescueERC20(IERC20(USDC));
    }

    function test_rescueERC20_revertsForSwapper() public {
        deal(USDC, address(converter), 1_000e6);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_RELAYER, ADMIN_ROLE)
        );
        vm.prank(ALM_RELAYER);
        converter.rescueERC20(IERC20(USDC));
    }

    function testFuzz_rescueERC20(uint256 amount) public {
        amount = bound(amount, 1, 1e33);
        deal(USDC, address(converter), amount);

        uint256 holderBefore = IERC20(USDC).balanceOf(GROVE_PROXY);

        vm.prank(GROVE_PROXY);
        uint256 rescued = converter.rescueERC20(IERC20(USDC));

        assertEq(rescued,                                    amount);
        assertEq(IERC20(USDC).balanceOf(GROVE_PROXY),        holderBefore + amount);
        assertEq(IERC20(USDC).balanceOf(address(converter)), 0);
    }

    function test_rescueERC20_worksAfterSwapperRemoved() public {
        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        uint256 amount = 1_000e6;
        deal(USDC, address(converter), amount);

        vm.prank(GROVE_PROXY);
        uint256 rescued = converter.rescueERC20(IERC20(USDC));

        assertEq(rescued, amount);
    }

}

contract InstantUsdcUsdsConverterRescueERC721Test is InstantUsdcUsdsConverterTestBase {

    function test_rescueERC721_success() public {
        MockERC721 nft = new MockERC721();
        uint256 tokenId = 42;
        nft.mint(address(converter), tokenId);

        assertEq(nft.ownerOf(tokenId), address(converter));

        vm.prank(GROVE_PROXY);
        converter.rescueERC721(nft, tokenId);

        // Reaches the holder even though GROVE_PROXY does not implement onERC721Received.
        assertEq(nft.ownerOf(tokenId), GROVE_PROXY);
    }

    function test_rescueERC721_emitsERC721Rescued() public {
        MockERC721 nft = new MockERC721();
        uint256 tokenId = 42;
        nft.mint(address(converter), tokenId);

        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.ERC721Rescued(address(nft), tokenId);

        vm.prank(GROVE_PROXY);
        converter.rescueERC721(nft, tokenId);
    }

    function test_rescueERC721_revertsForNonAdmin() public {
        MockERC721 nft = new MockERC721();
        nft.mint(address(converter), 1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ADMIN_ROLE)
        );
        vm.prank(stranger);
        converter.rescueERC721(nft, 1);
    }

    function test_rescueERC721_revertsForSwapper() public {
        MockERC721 nft = new MockERC721();
        nft.mint(address(converter), 1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_RELAYER, ADMIN_ROLE)
        );
        vm.prank(ALM_RELAYER);
        converter.rescueERC721(nft, 1);
    }

    function test_rescueERC721_revertsWhenNotOwned() public {
        MockERC721 nft = new MockERC721();
        uint256 tokenId = 7; // never minted, so the converter does not own it

        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId)
        );
        vm.prank(GROVE_PROXY);
        converter.rescueERC721(nft, tokenId);
    }

    function testFuzz_rescueERC721(uint256 tokenId) public {
        MockERC721 nft = new MockERC721();
        nft.mint(address(converter), tokenId);

        vm.prank(GROVE_PROXY);
        converter.rescueERC721(nft, tokenId);

        assertEq(nft.ownerOf(tokenId), GROVE_PROXY);
    }

    function test_rescueERC721_worksAfterSwapperRemoved() public {
        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        MockERC721 nft = new MockERC721();
        nft.mint(address(converter), 1);

        vm.prank(GROVE_PROXY);
        converter.rescueERC721(nft, 1);

        assertEq(nft.ownerOf(1), GROVE_PROXY);
    }

}

contract InstantUsdcUsdsConverterFreezeTest is InstantUsdcUsdsConverterTestBase {

    function test_removeSwapper_byFreezer() public {
        assertTrue(converter.hasRole(SWAPPER_ROLE, ALM_RELAYER));

        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.SwapperRemoved(ALM_RELAYER);
        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        assertFalse(converter.hasRole(SWAPPER_ROLE, ALM_RELAYER));
    }

    function test_removeSwapper_revertsForAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, GROVE_PROXY, FREEZER_ROLE)
        );
        vm.prank(GROVE_PROXY);
        converter.removeSwapper(ALM_RELAYER);
    }

    function test_removeSwapper_revertsForSwapper() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ALM_RELAYER, FREEZER_ROLE)
        );
        vm.prank(ALM_RELAYER);
        converter.removeSwapper(ALM_RELAYER);
    }

    function test_removeSwapper_revertsForStranger() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, FREEZER_ROLE)
        );
        vm.prank(stranger);
        converter.removeSwapper(ALM_RELAYER);
    }

    function test_removeSwapper_onNonSwapperEmitsAndNoops() public {
        assertFalse(converter.hasRole(SWAPPER_ROLE, stranger));

        vm.expectEmit(true, true, true, true, address(converter));
        emit InstantUsdcUsdsConverter.SwapperRemoved(stranger);
        vm.prank(ALM_FREEZER);
        converter.removeSwapper(stranger);

        assertFalse(converter.hasRole(SWAPPER_ROLE, stranger));
    }

    function test_removeSwapper_onlyEjectsTargetedSwapper() public {
        address otherSwapper = makeAddr("otherSwapper");

        vm.prank(GROVE_PROXY);
        converter.grantRole(SWAPPER_ROLE, otherSwapper);

        vm.prank(ALM_FREEZER);
        converter.removeSwapper(ALM_RELAYER);

        assertFalse(converter.hasRole(SWAPPER_ROLE, ALM_RELAYER));
        assertTrue(converter.hasRole(SWAPPER_ROLE, otherSwapper));
    }

    function test_removeSwapper_cannotEjectFreezerOrAdmin() public {
        // The freezer path only revokes SWAPPER_ROLE, never touches other roles.
        vm.startPrank(ALM_FREEZER);
        converter.removeSwapper(ALM_FREEZER);
        converter.removeSwapper(GROVE_PROXY);
        vm.stopPrank();

        assertTrue(converter.hasRole(FREEZER_ROLE, ALM_FREEZER));
        assertTrue(converter.hasRole(ADMIN_ROLE,   GROVE_PROXY));
    }

}

