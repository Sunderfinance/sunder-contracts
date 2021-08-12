// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IFeePool {
    function claimFee() external;
    function earned(address account) external view returns (uint256,uint256);
}
