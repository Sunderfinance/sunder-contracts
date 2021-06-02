// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IVote {
    function castVote(address _comp, uint256 _proposalId) external;
    function returnToken(address _comp, address _receiver) external returns (uint256 _amount);
}
