// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IMigratorChef {
    function migrate(address token) external returns (address);
}
