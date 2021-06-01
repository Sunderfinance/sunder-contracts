// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IVote {
    function vote(address _comp, uint256 _proposalId) external;
    function returnToken(address _comp) external;
}
