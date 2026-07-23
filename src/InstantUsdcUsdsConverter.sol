// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 }        from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 }       from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal interface for the DAI LitePSM the converter sells USDC into.
interface ILitePsmLike {
    function gem() external view returns (address);
    function dai() external view returns (address);
    function to18ConversionFactor() external view returns (uint256);
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad);
    function sellGemNoFee(address usr, uint256 gemAmt) external returns (uint256 daiOutWad);
    function bud(address usr) external view returns (uint256);
}

/// @notice Minimal interface for the DAI<>USDS exchanger used to finish the USDC->USDS swap.
interface IDaiUsdsLike {
    function dai() external view returns (address);
    function usds() external view returns (address);
    function daiToUsds(address usr, uint256 wad) external;
}

/// @title  InstantUsdcUsdsConverter
/// @notice Swaps USDC into USDS (one direction only) on behalf of a governance holder.
/// @dev    {swap} pulls USDC from `holder`, sells it for DAI via the LitePSM, and converts the DAI
///         into USDS routed back to `holder`. It uses the fee-free `sellGemNoFee` when this contract
///         is whitelisted on the PSM (via `kiss`), otherwise the permissionless `sellGem`; either
///         way the settlement must be exactly 1:1 or it reverts. The contract never custodies funds;
///         `rescueERC20` / `rescueERC721` recover mistakenly-sent tokens to `holder`.
contract InstantUsdcUsdsConverter is AccessControl {

    using SafeERC20 for IERC20;

    /// @notice Role permitted to call {swap}.
    bytes32 public constant SWAPPER_ROLE = keccak256("SWAPPER_ROLE");

    /// @notice Role permitted to call {removeSwapper} (emergency ejection of a swapper).
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    /// @notice The DAI LitePSM used to sell USDC for DAI.
    ILitePsmLike public immutable litePsm;
    /// @notice The DAI<>USDS exchanger used to convert the DAI into USDS.
    IDaiUsdsLike public immutable daiUsds;
    /// @notice The USDC token pulled from the holder (the PSM's `gem`).
    IERC20 public immutable usdc;
    /// @notice The DAI token the PSM pays out and the exchanger consumes.
    IERC20 public immutable dai;
    /// @notice The USDS token delivered to the holder.
    IERC20 public immutable usds;
    /// @notice The Grove governance proxy; USDC is pulled from it and all outputs/rescues are sent to it.
    address public immutable holder;

    /// @notice Multiplier turning a USDC (gem) amount into its 1:1 USDS (wad) equivalent.
    uint256 public immutable conversionFactor;

    error InvalidAdmin();
    error InvalidSwapper();
    error InvalidFreezer();
    error InvalidHolder();
    error InvalidLitePsm();
    error InvalidDaiUsds();
    error InvalidUsdc();
    error InvalidDai();
    error InvalidUsds();
    error DaiMismatch();
    error InvalidConversionFactor();
    error ZeroAmount();
    error NotOneToOne();
    error UsdsNotReceived();

    /// @notice Emitted when USDC is swapped into USDS for the holder.
    /// @param  caller     Account that invoked the swap.
    /// @param  usdcIn     Amount of USDC (6 decimals) pulled from the holder.
    /// @param  usdsOut    Amount of USDS (18 decimals) delivered to the holder.
    /// @param  noFeeRoute True if the swap used the whitelisted `sellGemNoFee` route, false if it
    ///                    used the permissionless `sellGem` route.
    event Swapped(address indexed caller, uint256 usdcIn, uint256 usdsOut, bool noFeeRoute);

    /// @notice Emitted when a swapper is ejected by a freezer via {removeSwapper}.
    /// @param  swapper Account whose `SWAPPER_ROLE` was revoked.
    event SwapperRemoved(address indexed swapper);

    /// @notice Emitted when an ERC20 balance is rescued to the holder.
    /// @param  token  Rescued ERC20 token.
    /// @param  amount Amount transferred to the holder.
    event ERC20Rescued(address indexed token, uint256 amount);

    /// @notice Emitted when an ERC721 token is rescued to the holder.
    /// @param  token   Rescued ERC721 token.
    /// @param  tokenId Token id transferred to the holder.
    event ERC721Rescued(address indexed token, uint256 tokenId);

    /// @param  admin_    `DEFAULT_ADMIN_ROLE` (role management and rescues); the Grove governance proxy.
    /// @param  swapper_  `SWAPPER_ROLE` (allowed to call the swaps).
    /// @param  freezer_  `FREEZER_ROLE` (allowed to call {removeSwapper}).
    /// @param  holder_   The Grove governance proxy; USDC is pulled from it and all outputs/rescues are sent to it.
    /// @param  litePsm_  DAI LitePSM exposing gem/dai/to18ConversionFactor/sellGem/sellGemNoFee.
    /// @param  daiUsds_  DAI<>USDS exchanger exposing dai/usds/daiToUsds.
    constructor(
        address admin_,
        address swapper_,
        address freezer_,
        address holder_,
        address litePsm_,
        address daiUsds_
    ) {
        if (admin_   == address(0)) revert InvalidAdmin();
        if (swapper_ == address(0)) revert InvalidSwapper();
        if (freezer_ == address(0)) revert InvalidFreezer();
        if (holder_  == address(0)) revert InvalidHolder();
        if (litePsm_ == address(0)) revert InvalidLitePsm();
        if (daiUsds_ == address(0)) revert InvalidDaiUsds();

        address gemToken  = ILitePsmLike(litePsm_).gem();
        address daiToken  = ILitePsmLike(litePsm_).dai();
        address usdsToken = IDaiUsdsLike(daiUsds_).usds();

        if (gemToken  == address(0)) revert InvalidUsdc();
        if (daiToken  == address(0)) revert InvalidDai();
        if (usdsToken == address(0)) revert InvalidUsds();

        if (IDaiUsdsLike(daiUsds_).dai() != daiToken) revert DaiMismatch();

        litePsm = ILitePsmLike(litePsm_);
        daiUsds = IDaiUsdsLike(daiUsds_);
        usdc    = IERC20(gemToken);
        dai     = IERC20(daiToken);
        usds    = IERC20(usdsToken);
        holder  = holder_;

        conversionFactor = ILitePsmLike(litePsm_).to18ConversionFactor();

        if (conversionFactor == 0) revert InvalidConversionFactor();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(SWAPPER_ROLE, swapper_);
        _grantRole(FREEZER_ROLE, freezer_);
    }

    /********************************************************************************************/
    /*** Swapping                                                                             ***/
    /********************************************************************************************/

    /// @notice Pulls `usdcAmount` USDC from the holder, swaps it 1:1 into USDS, and delivers the
    ///         USDS back to the holder.
    /// @dev    Uses `sellGemNoFee` when whitelisted on the PSM (via `kiss`), otherwise `sellGem`.
    /// @param  usdcAmount Amount of USDC (6 decimals) to swap.
    /// @return usdsOut Amount of USDS (18 decimals) delivered to the holder.
    function swap(uint256 usdcAmount) external onlyRole(SWAPPER_ROLE) returns (uint256 usdsOut) {
        if (usdcAmount == 0) revert ZeroAmount();

        uint256 holderUsdsBefore = usds.balanceOf(holder);

        usdc.safeTransferFrom(holder, address(this), usdcAmount);
        usdc.forceApprove(address(litePsm), usdcAmount);

        bool noFeeRoute = litePsm.bud(address(this)) == 1;
        uint256 daiOut = noFeeRoute
            ? litePsm.sellGemNoFee(address(this), usdcAmount)
            : litePsm.sellGem(address(this), usdcAmount);

        // Clear any allowance the PSM left unspent.
        usdc.forceApprove(address(litePsm), 0);

        if (daiOut != usdcAmount * conversionFactor) revert NotOneToOne();

        dai.forceApprove(address(daiUsds), daiOut);
        daiUsds.daiToUsds(holder, daiOut);
        dai.forceApprove(address(daiUsds), 0);

        usdsOut = daiOut;

        // Confirm the holder actually received the USDS.
        if (usds.balanceOf(holder) != holderUsdsBefore + usdsOut) revert UsdsNotReceived();

        emit Swapped(msg.sender, usdcAmount, usdsOut, noFeeRoute);
    }

    /********************************************************************************************/
    /*** Freezing                                                                             ***/
    /********************************************************************************************/

    /// @notice Ejects a swapper as an emergency stop by revoking its `SWAPPER_ROLE`. Callable only
    ///         by `FREEZER_ROLE`; re-granting the role afterwards is `DEFAULT_ADMIN_ROLE`-only.
    /// @param  swapper Account to strip `SWAPPER_ROLE` from.
    function removeSwapper(address swapper) external onlyRole(FREEZER_ROLE) {
        _revokeRole(SWAPPER_ROLE, swapper);
        emit SwapperRemoved(swapper);
    }

    /********************************************************************************************/
    /*** Rescuing                                                                             ***/
    /********************************************************************************************/

    /// @notice Rescues the full balance of an arbitrary ERC20 token held by this contract,
    ///         sending it to `holder`. Only relevant if tokens were sent here by mistake.
    /// @param  token  ERC20 token to rescue.
    /// @return amount Balance transferred to `holder`.
    function rescueERC20(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 amount) {
        amount = token.balanceOf(address(this));

        token.safeTransfer(holder, amount);

        emit ERC20Rescued(address(token), amount);
    }

    /// @notice Rescues a specific ERC721 token held by this contract, sending it to `holder`.
    /// @dev    Uses `transferFrom` rather than `safeTransferFrom`: `holder` is a governance
    ///         contract that may not implement `onERC721Received`, which would otherwise brick
    ///         the rescue.
    /// @param  token   ERC721 token to rescue from.
    /// @param  tokenId Token id to transfer to `holder`.
    function rescueERC721(IERC721 token, uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        token.transferFrom(address(this), holder, tokenId);

        emit ERC721Rescued(address(token), tokenId);
    }

}
