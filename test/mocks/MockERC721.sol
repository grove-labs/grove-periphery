// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @dev Mintable ERC721 for tests. When `blockTransfers` is set, transfers silently no-op (via the
///      `_update` hook) to prove `rescueERC721` reverts unless the token actually reached `holder`.
contract MockERC721 is ERC721 {

    bool public blockTransfers;

    constructor() ERC721("Mock", "MOCK") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setBlockTransfers(bool value) external {
        blockTransfers = value;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (blockTransfers) return _ownerOf(tokenId);
        return super._update(to, tokenId, auth);
    }

}
