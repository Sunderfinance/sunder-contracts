// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;


interface IStrategy {
    function want() external view returns (address);
    function earn() external;
    function harvest() external;
    function addDebt(uint256) external;
    function setClaim(bool) external;

    function withdraw(address) external;

    function withdraw(address,uint256) external;
    function withdrawVote(address,uint256) external;

    function withdrawAll(address) external returns (uint256);

    function balanceOf() external view returns (uint256);
}
