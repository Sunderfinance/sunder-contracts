// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/yearn/IController.sol";

contract VaultChef {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public controller;
    uint256 public intervalTime;

    IERC20  public eToken;
    uint256 public amount;
    IERC20  public rewardToken;
    uint256 public reward;
    uint256 public accTokenPerShare;

    struct UserInfo {
        uint256 depositTime;
        uint256 amount;
        uint256 rewardDebt;
        uint256 reward;
    }
    mapping(address => UserInfo) public userInfos;

    uint256 public harvestTime;
    uint256 public harvestReward;
    uint256 public harvestBalance;
    uint256 public harvestPeriod;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 reward);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor (address _eToken, address _rewardToken, address _controller, uint256 _intervalTime) public {
        eToken = IERC20(_eToken);
        rewardToken = IERC20(_rewardToken);
        controller = _controller;
        intervalTime = _intervalTime;
        governance = msg.sender;
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
    function setIntervalTime(uint256 _intervalTime) external {
        require(msg.sender == governance, "!governance");
        intervalTime = _intervalTime;
    }

    function deposit(uint256 _amount) public {
        UserInfo storage user = userInfos[msg.sender];
        if (user.amount > 0) {
            uint256 _reward = user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
            user.reward = _reward.add(user.reward);
        }

        eToken.safeTransferFrom(msg.sender, address(this), _amount);
        user.depositTime = block.timestamp;
        user.amount = user.amount.add(_amount);
        amount = amount.add(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        UserInfo storage user = userInfos[msg.sender];
        require(user.amount >= _amount, "!_amount");
        require(block.timestamp >= user.depositTime + intervalTime, "!intervalTime");

        uint256 _reward = user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
        user.reward = _reward.add(user.reward);
        user.amount = user.amount.sub(_amount);
        amount = amount.sub(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(1e18);
        eToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    function harvest(uint256 _pid) external {
        UserInfo storage user = userInfos[msg.sender];
        uint256 _reward = user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(1e18);

        safeTokenTransfer(msg.sender, _reward);
        emit Harvest(msg.sender, _reward);
    }

    function withdrawAndHarvest(uint256 _pid, uint256 _amount) external {
        UserInfo storage user = userInfos[msg.sender];
        require(user.amount >= _amount, "!_amount");
        require(block.timestamp >= user.depositTime + intervalTime, "!intervalTime");

        uint256 _reward = user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);

        user.reward = 0;
        user.amount = user.amount.sub(_amount);
        amount = amount.sub(_amount);
        user.rewardDebt = user.amount.mul(accTokenPerShare).div(1e18);

        safeTokenTransfer(msg.sender, _reward);
        eToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
        emit Harvest(msg.sender, _reward);
    }

    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 _balance = rewardToken.balanceOf(address(this));
        if (_amount > _balance) {
            reward = reward.sub(_balance);
            rewardToken.safeTransfer(_to, _balance);
        } else {
            reward = reward.sub(_amount);
            rewardToken.safeTransfer(_to, _amount);
        }
    }

    function updatePool(uint256 _reward) internal {
        if (amount == 0) {
            return;
        }
        reward = reward.add(_reward);
        accTokenPerShare = accTokenPerShare.add(_reward.mul(1e18).div(amount));
    }

    function setHarvestInfo(uint256 _harvestReward) external {
        require(msg.sender == controller, "!controller");
        uint256 _harvestTime = block.timestamp;
        require(_harvestTime > harvestTime, "!_harvestTime");
        harvestPeriod = _harvestTime - harvestTime;
        harvestTime = _harvestTime;
        harvestReward = _harvestReward;
        harvestBalance = amount;
        updatePool(_harvestReward);
    }

    function annualRewardPerShare() public view returns (uint256) {
        if (harvestPeriod == 0 || harvestBalance == 0) {
            return 0;
        }
        // SECS_PER_YEAR  31_556_952  365.2425 days
        return harvestReward.mul(31556952).mul(1e18).div(harvestPeriod).div(harvestBalance);
    }

    function eTokenReward(address _user) external view returns (uint256, uint256) {
        UserInfo storage user = userInfos[_user];
        uint256 _reward = user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
        return (user.amount, _reward.add(user.reward));
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        UserInfo storage user = userInfos[msg.sender];
        require(block.timestamp >= user.depositTime + 1, "!intervalTime"); // prevent flash loan

        user.reward = 0;
        user.rewardDebt = 0;
        uint256 _amount = user.amount;
        user.amount = 0;
        amount = amount.sub(_amount);
        eToken.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    function sweep(address _token) external {
        require(msg.sender == governance, "!governance");
        require(address(eToken) != _token, "eToken == _token");
        require(address(rewardToken) != _token, "rewardToken == _token");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        address _rewards = IController(controller).rewards();
        IERC20(_token).safeTransfer(_rewards, _balance);
    }

}
