// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { InstantUsdcUsdsConverter } from "../../src/InstantUsdcUsdsConverter.sol";

/// @dev Malicious ERC721 whose `transferFrom` re-enters the converter, used to prove the
///      `nonReentrant` guard blocks reentrancy through the arbitrary-token rescue path.
contract ReentrantERC721 {

    InstantUsdcUsdsConverter internal immutable converter;

    constructor(InstantUsdcUsdsConverter converter_) {
        converter = converter_;
    }

    function transferFrom(address, address, uint256) external {
        converter.swap(1);
    }

}
