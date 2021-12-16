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

  mapping(address => uint256) public rewards;
  mapping(address => uint256) public gains;
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

      token = token_;
      startTime = startTime_;
      period = period_;
      endTime = startTime_.add(period_);
      effectTime = effectTime.add(endTime);
      start = true;
  }

  function add(address[] memory users_, uint256[] memory rewards_) external returns (bool) {
      require(start == false, 'already started');
      require(users_.length == rewards_.length, "length error");

      uint256 _totalReward = 0;
      for(uint i; i < users_.length; i++){
          rewards[users_[i]] = rewards_[i];
          _totalReward += rewards_[i];
      }
      totalReward = totalReward.add(_totalReward);
      totalUser = totalUser.add(users_.length);
      return true;
  }

  function claim() external returns (uint256) {
      address _user = msg.sender;
      uint256 _amount = getClaim(_user);
      if (_amount > 0) {
          lastUpdates[_user] = block.timestamp;
          gains[_user] = gains[_user].add(_amount);
          require(gains[_user] <= rewards[_user], 'already claim');
          _amount = tokenTransfer(_user, _amount);
      }

      return _amount;
  }

  function getClaim(address user_) public view returns (uint256) {
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

      uint256 _reward = rewards[user_];
      return _to.sub(_from).mul(_reward).div(period);
  }

  function getInfos(address user_) public view returns (uint256 claim_, uint256 reward_, uint256 gain_, uint256 endTime_) {
      claim_ = getClaim(user_);
      reward_ = rewards[user_];
      gain_ = gains[user_];
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
