// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

contract AirDrop {
  using SafeMath for uint256;

  address public guardian;
  uint256 public effectTime;

  address public token;
  uint256 public startTime;
  uint256 public endTime;
  uint256 public period;

  uint256 public totalUser;
  uint256 public totalReward;
  uint256 public totalGain;
  bool public start;

  mapping(address => uint256) public amounts;
  mapping(address => uint256) public receives;
  mapping(address => uint256) public lastUpdates;

  constructor() public {
      guardian = msg.sender;
      effectTime = 30 days;
  }

  function setGuardian(address _guardian) external {
      require(msg.sender == guardian, "!guardian");
      guardian = _guardian;
  }

  function initialize(address token_, uint256 startTime_, uint256 period_) external {
      require(token == address(0), "already initialized");
      require(block.timestamp <= startTime_, "!startTime_");
      require(period_ > 0, "!period_");

      token = token_;
      startTime = startTime_;
      period = period_;
      endTime = startTime_.add(period_);
      effectTime = effectTime.add(endTime);
      start = true;
  }

  function addUsers(address[] memory users_, uint256[] memory amounts_) external returns (bool) {
      require(start == false, 'already started');
      require(users_.length == amounts_.length, "length error");

      uint256 _totalAmount = 0;
      for(uint i; i < users_.length; i++){
          amounts[users_[i]] = amounts_[i];
          _totalAmount += amounts_[i];
      }
      totalReward = totalReward.add(_totalAmount);
      totalUser = totalUser.add(users_.length);
      return true;
  }

  function claim() external {
      address _user = msg.sender;
      uint256 _amount = getReward(_user);
      if (_amount > 0) {
          lastUpdates[_user] = block.timestamp;
          receives[_user] = receives[_user].add(_amount);
          require(receives[_user] <= amounts[_user], 'already claim');
          tokenTransfer(_user, _amount);
      }
  }

  function getReward(address user_) public view returns (uint256) {
      uint256 _from = lastUpdates[user_];
      uint256 _to = block.timestamp;
      if (_from < startTime) {
          _from = startTime;
      }
      if (_to > endTime) {
          _to = endTime;
      }
      if (_to <= startTime || _from >= endTime) {
          return 0;
      }

      uint256 _reward = amounts[user_];
      return _to.sub(_from).mul(_reward).div(period);
  }

  function getInfos(address user_) public view returns (uint256 reward_, uint256 total_, uint256 claim_, uint256 endTime_) {
      reward_ = getReward(user_);
      total_ = amounts[user_];
      claim_ = receives[user_];
      endTime_ = endTime;
  }

  function tokenTransfer(address user_, uint256 amount_) internal returns (uint256) {
      uint256 _balance = IERC20(token).balanceOf(address(this));
      uint256 _amount = amount_;
      if (_amount > _balance) {
          _amount = _balance;
      }
      totalGain = totalGain.add(_amount);
      IERC20(token).transfer(user_, _amount);
      return _amount;
  }

  function sweepGuardian(address token_) external {
      require(msg.sender == guardian, "!guardian");
      require(block.timestamp > effectTime, "!effectTime");

      uint256 _balance = IERC20(token_).balanceOf(address(this));
      IERC20(token_).transfer(guardian, _balance);
  }
}
