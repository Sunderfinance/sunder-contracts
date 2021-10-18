// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ISunderBar {
    function balanceOf(address owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 share) external;
}
