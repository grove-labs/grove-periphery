// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { InstantUsdcUsdsConverter } from "../../src/InstantUsdcUsdsConverter.sol";

/// @dev Malicious ERC20 whose `transfer` re-enters the converter, used to prove the `nonReentrant`
///      guard blocks reentrancy through the ERC20 rescue path.
contract ReentrantERC20 {

    InstantUsdcUsdsConverter internal immutable converter;

    constructor(InstantUsdcUsdsConverter converter_) {
        converter = converter_;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1e18;
    }

    // No return type: `SafeERC20` invokes this via a low-level, selector-based call and the
    // re-entrant `swap` reverts before any return value would be read.
    function transfer(address, uint256) external {
        converter.swap(1);
    }

}
