// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKAP721Metadata {
    event Uri(uint256 indexed id);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function kapURI(uint256 tokenId) external view returns (string memory);
}
