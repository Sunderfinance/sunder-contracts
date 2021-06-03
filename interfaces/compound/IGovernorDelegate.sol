// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IGovernorDelegate {
    function castVote(uint256, uint8) external;
    function propose(address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) external returns (uint256);
    function proposalThreshold()  external view returns (uint256);
    function state(uint proposalId) external view returns (uint8);
    function proposals(uint256) external view returns (uint256, address, uint256, uint256, uint256, uint256, uint256, uint256, bool, bool);
}
