// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IBoringDAO {
    function pledge(bytes32 _tunnelKey, uint256 _amount) external;
}
