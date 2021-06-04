// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ISushi {
    function mint(address _to, uint256 _amount) external;
    function balanceOf(address) external returns (uint256);
    function transfer(address _to, uint256 _amount) external;
}
