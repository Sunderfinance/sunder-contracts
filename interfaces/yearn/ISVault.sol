// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ISVault {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function setHarvestInfo(uint256 _harvestReward) external;
}
