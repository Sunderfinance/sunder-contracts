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

    address public governance;
    address public pendingGovernance;
    address public guardian;
    uint256 public guardianTime;
    address public controller;
    IERC20  public eToken;
    uint256 public harvestTime;
    uint256 public harvestReward;
    uint256 public harvestBalance;
    uint256 public harvestPeriod;

    mapping(address => uint256) public depositAt;

    event Deposit(address indexed account, uint256 amount, uint256 share);
    event Withdraw(address indexed account, uint256 amount, uint256 share);

    constructor(address _eToken, address _controller) public ERC20(
      string(abi.encodePacked("sunder ", ERC20(_eToken).name())),
      string(abi.encodePacked("s", ERC20(_eToken).symbol()))) {
        eToken = IERC20(_eToken);
        governance = msg.sender;
        guardian = msg.sender;
        controller = _controller;
        _setupDecimals(ERC20(_eToken).decimals());
        harvestTime = block.timestamp;
        guardianTime = block.timestamp + 30 days;
    }

    function setGuardian(address _guardian) external {
        require(msg.sender == guardian, "!guardian");
        guardian = _guardian;
    }
    function addGuardianTime(uint256 _addTime) external {
        require(msg.sender == guardian || msg.sender == pendingGovernance, "!guardian");
        guardianTime = guardianTime.add(_addTime);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = msg.sender;
        pendingGovernance = address(0);
    }
    function setPendingGovernance(address _pendingGovernance) external {
        require(msg.sender == governance, "!governance");
        pendingGovernance = _pendingGovernance;
    }
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
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
        uint256 _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, _shares);
        emit Deposit(msg.sender, _amount, _shares);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    // No rebalance implementation for lower fees and faster swaps
    function withdraw(uint256 _shares) public {
        require(depositAt[msg.sender] < block.number, "!depositAt");
        uint256 _amount = (eTokenBalance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        eToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount, _shares);
    }

    function eTokenBalance() public view returns (uint256) {
        return eToken.balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18;
        }
        return eTokenBalance().mul(1e18).div(totalSupply());
    }

    function annualRewardPerShare() public view returns (uint256) {
        if (harvestPeriod == 0 || harvestBalance == 0) {
            return 0;
        }
        // SECS_PER_YEAR  31_556_952  365.2425 days
        return harvestReward.mul(31556952).mul(1e18).div(harvestPeriod).div(harvestBalance);
    }

    function setHarvestInfo(uint256 _harvestReward) external {
        require(msg.sender == controller, "!controller");
        uint256 _harvestTime = block.timestamp;
        require(_harvestTime > harvestTime, "!_harvestTime");
        harvestPeriod = _harvestTime - harvestTime;
        harvestTime = _harvestTime;
        harvestReward = _harvestReward;
        harvestBalance = eTokenBalance();
    }

    function sweep(address _token) external {
        require(msg.sender == governance, "!governance");
        require(address(eToken) != _token, "eToken = _token");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        address _rewards = IController(controller).rewards();
        IERC20(_token).safeTransfer(_rewards, _balance);
    }

    function sweepGuardian(address _token) external {
        require(msg.sender == guardian, "!guardian");
        require(block.timestamp > guardianTime, "!guardianTime");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

}
