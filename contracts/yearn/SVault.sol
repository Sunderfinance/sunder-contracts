// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

contract SVault is ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public token;
    address public governance;
    address public controller;

    /*
    address public operator;
    bool public locking;

    uint256 public min = 10000;
    uint256 public constant max = 10000;
    */

    constructor (address _token, address _controller) public ERC20(
        string(abi.encodePacked("sunder ", ERC20(_token).name())),
        string(abi.encodePacked("s", ERC20(_token).symbol())))
    {
        token = IERC20(_token);
        governance = msg.sender;
        controller = _controller;
        _setupDecimals(ERC20(_token).decimals());
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
    /*
    function setMin(uint256 _min) external {
        require(msg.sender == governance, "!governance");
        min = _min;
    }*/

    /*
    function setOperator(address _operator) public {
        require(msg.sender == governance, "!governance");
        operator = _operator;
    }

    function locking() public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        locking = true;
    }

    function unlocking() public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        locking = false;
    }
    */

    function tokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function depositAll() external {
        deposit(token.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        uint256 _pool = tokenBalance();
        uint256 _before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = token.balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
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
        uint256 r = (tokenBalance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        token.safeTransfer(msg.sender, r);
    }
    /*
    // Used to swap any borrowed reserve over the debt limit to liquidate to 'token'
    function harvest(address reserve, uint256 amount) external {
        require(msg.sender == controller, "!controller");
        require(reserve != address(token), "token");
        IERC20(reserve).safeTransfer(controller, amount);
    }*/

    function getPricePerFullShare() public view returns (uint256) {
        return tokenBalance().mul(1e18).div(totalSupply());
    }
}
