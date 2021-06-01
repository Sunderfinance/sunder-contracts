// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IGovernorDelegate {
    function castVote(uint256, uint8) external;
    function state(uint proposalId) external view returns (uint8);
    function proposals(uint256) external view returns (uint256, address, uint256, uint256, uint256, uint256, uint256, uint256, bool, bool);
}
