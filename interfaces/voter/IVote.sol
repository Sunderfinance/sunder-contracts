// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IVote {
    function castVote(address _comp, uint256 _proposalId) external;
    function propose(address _comp, address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) external returns (uint256);
    function returnToken(address _comp, address _receiver) external returns (uint256 _amount);
    function proposalThreshold(address _comp) external view returns (uint256);
}
