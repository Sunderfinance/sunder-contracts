// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IConvController {
    function mint(address token, address minter, uint256 amount) external;
    function dtokens(address) external view returns (address);
}
