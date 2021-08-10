// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IBoringChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256,uint256);
    function pendingBoring(uint256 _pid, address _user) external view returns (uint256);
}
