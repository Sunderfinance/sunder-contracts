// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IBentoBox {
    function balanceOf(address erc20, address owner) external view returns (uint256);
    function deposit(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable  returns (uint256 amountOut, uint256 shareOut);
    function withdraw(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
    function toAmount(
        address token,
        uint256 share,
        bool roundUp
    ) external view returns (uint256 amount);
}
