// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ICompController {
    function claimComp(address holder, address[] calldata cTokens) external;
    function claimComp(address[] calldata holders, address[] calldata cTokens, bool borrowers, bool suppliers) external;
}
