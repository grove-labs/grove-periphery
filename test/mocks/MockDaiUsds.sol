// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Test DAI<>USDS exchanger. `daiToUsds` pulls DAI (unless `skipDaiPull`, to exercise the DAI
///      allowance reset) and delivers USDS (unless `skipUsdsDelivery`, to exercise the
///      `usds-not-received` check). Must be pre-funded with USDS.
contract MockDaiUsds {

    address public dai;
    address public usds;

    bool public skipDaiPull;
    bool public skipUsdsDelivery;

    constructor(address dai_, address usds_) {
        dai  = dai_;
        usds = usds_;
    }

    function setSkipDaiPull(bool value) external {
        skipDaiPull = value;
    }

    function setSkipUsdsDelivery(bool value) external {
        skipUsdsDelivery = value;
    }

    function daiToUsds(address usr, uint256 wad) external {
        if (!skipDaiPull) {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(dai).transferFrom(msg.sender, address(this), wad);
        }

        if (!skipUsdsDelivery) {
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(usds).transfer(usr, wad);
        }
    }

}
