// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IController {
    function mint(address, uint256) external;
    function earn(address, uint256) external;
    function withdraw(address, uint256) external;
    function withdrawVote(address, uint256) external;
    function assets(address) external view returns (uint256);
    function deposit(address, uint256) external;
    function depositVote(address, uint256) external;
    function want(address) external view returns (address);
    function rewards() external view returns (address);
    function vaults(address) external view returns (address);
}
