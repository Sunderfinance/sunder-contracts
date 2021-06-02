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

    IERC20  public eToken;
    address public governance;
    address public controller;

    mapping(address => uint256) depositAt;

    constructor (address _eToken, address _controller) public ERC20(
        string(abi.encodePacked("sunder ", ERC20(_eToken).name())),
        string(abi.encodePacked("s", ERC20(_eToken).symbol())))
    {
        eToken = IERC20(_eToken);
        governance = msg.sender;
        controller = _controller;
        _setupDecimals(ERC20(_eToken).decimals());
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function eTokenBalance() public view returns (uint256) {
        return eToken.balanceOf(address(this));
    }

    function depositAll() external {
        deposit(eToken.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        depositAt[msg.sender] = block.number;
        uint256 _pool = eTokenBalance();
        eToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = eToken.balanceOf(address(this));
        _amount = _after.sub(_pool); // Additional check for deflationary eTokens
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
        require(depositAt[msg.sender] < block.number, "!depositAt");
        uint256 r = (eTokenBalance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        eToken.safeTransfer(msg.sender, r);
    }

    function getPricePerFullShare() public view returns (uint256) {
        return eTokenBalance().mul(1e18).div(totalSupply());
    }

    function sweep(address _token) public {
        require(msg.sender == governance, "!governance");
        require(address(eToken) != _token, "eToken = _token");

        uint256 _bal = IERC20(_token).balanceOf(address(this));
        address _rewards = IController(controller).rewards();
        IERC20(_token).safeTransfer(_rewards, _bal);
    }
}
