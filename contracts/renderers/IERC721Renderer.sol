// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

interface IERC721Renderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}