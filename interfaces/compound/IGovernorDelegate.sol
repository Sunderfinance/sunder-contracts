// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IGovernorDelegate {
    function castVote(uint256, uint8) external;
}
