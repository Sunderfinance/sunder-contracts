// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/yearn/IController.sol";

contract SVault is ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public etoken;
    address public governance;
    address public controller;

    constructor (address _etoken, address _controller) public ERC20(
        string(abi.encodePacked("sunder ", ERC20(_etoken).name())),
        string(abi.encodePacked("s", ERC20(_etoken).symbol())))
    {
        etoken = IERC20(_etoken);
        governance = msg.sender;
        controller = _controller;
        _setupDecimals(ERC20(_etoken).decimals());
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function etokenBalance() public view returns (uint256) {
        return etoken.balanceOf(address(this));
    }

    function depositAll() external {
        deposit(etoken.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        uint256 _pool = etokenBalance();
        etoken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = etoken.balanceOf(address(this));
        _amount = _after.sub(_pool); // Additional check for deflationary etokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public {
        uint256 r = (etokenBalance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        etoken.safeTransfer(msg.sender, r);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return etokenBalance().mul(1e18).div(totalSupply());
    }

    function sweep(address _token) public {
        require(msg.sender == governance, "!governance");
        require(address(etoken) != _token, "!address(0)");

        uint256 _bal = IERC20(_token).balanceOf(address(this));
        address _rewards = IController(controller).rewards();
        IERC20(_token).safeTransfer(_rewards, _bal);
    }
}
