// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Test LitePSM. Exposes the getters the converter reads (`gem`, `dai`, `to18ConversionFactor`,
///      `bud`) and a `sellGem` that can skip pulling USDC (via `skipGemPull`) to exercise the
///      allowance reset. `bud` defaults to 0, so the `sellGem` path is used. Must be pre-funded with DAI.
contract MockLitePsm {

    address public gem;
    address public dai;
    uint256 public to18ConversionFactor;

    mapping(address => uint256) public bud;

    bool public skipGemPull;

    constructor(address gem_, address dai_, uint256 to18ConversionFactor_) {
        gem                  = gem_;
        dai                  = dai_;
        to18ConversionFactor = to18ConversionFactor_;
    }

    function setSkipGemPull(bool value) external {
        skipGemPull = value;
    }

    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOut) {
        daiOut = gemAmt * to18ConversionFactor;

        if (!skipGemPull) {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(gem).transferFrom(msg.sender, address(this), gemAmt);
        }

        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(dai).transfer(usr, daiOut);
    }

}
