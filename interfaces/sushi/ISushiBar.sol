// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ISushiBar {
    function balanceOf(address owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function enter(uint256 amount) external;
    function leave(uint256 share) external;
}
