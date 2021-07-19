// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

contract MasterChef {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    // Info of each user.
    struct UserInfo {
        uint256 depositTime;
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 reward;
        uint256 rewardDebtOther; // Reward debt.
        uint256 rewardOther;
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20  lpToken; // Address of LP token contract.
        uint256 amount;  // How many LP tokens.
        uint256 lastRewardTime; // Last block number that Token distribution occurs.
        uint256 allocPoint; // How many allocation points assigned to this pool. Token to distribute per block.
        uint256 allocPointOther; // How many allocation points assigned to this pool. Token to distribute per block.
        uint256 accTokenPerShare; // Accumulated Token per share, times 1e18. See below.
        uint256 accTokenPerShareOther; // Accumulated Token per share, times 1e18. See below.
    }

    address public governance;
    address public pendingGovernance;
    address public guardian;
    uint256 public guardianTime;

    IERC20  public rewardToken;
    uint256 public totalReward;
    uint256 public totalGain;
    uint256 public intervalTime;

    IERC20  public rewardTokenOther;
    uint256 public totalRewardOther;
    uint256 public totalGainOther;

    uint256 public epochId;
    uint256 public reward;
    uint256 public rewardOther;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public period;

    struct EpochReward{
        uint256 epochId;
        uint256 startTime;
        uint256 endTime;
        uint256 reward;
        uint256 rewardOther;
    }
    mapping (uint256 => EpochReward) public epochRewards;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    uint256 public totalAllocPointOther;

    // Info of each pool.
    PoolInfo[] public poolInfos;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 reward, uint256 rewardOther);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid,  uint256 amount);

    constructor(address _rewardToken, uint256 _intervalTime) public {
        rewardToken = IERC20(_rewardToken);
        intervalTime = _intervalTime;
        governance = msg.sender;
        guardian = msg.sender;
        guardianTime = block.timestamp + 30 days;
    }

    function setGuardian(address _guardian) public {
        require(msg.sender == guardian, "!guardian");
        guardian = _guardian;
    }

    function addGuardianTime(uint256 _addTime) public {
        require(msg.sender == guardian || msg.sender == pendingGovernance, "!guardian");
        guardianTime = guardianTime.add(_addTime);
    }

    function acceptGovernance() public {
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = msg.sender;
        pendingGovernance = address(0);
    }

    function setPendingGovernance(address _pendingGovernance) public {
        require(msg.sender == governance, "!governance");
        pendingGovernance = _pendingGovernance;
    }

    function setRewardTokenOther(address _rewardTokenOther) public {
        require(msg.sender == governance, "!governance");
        require(address(rewardTokenOther) == address(0), "!rewardTokenOther");
        rewardTokenOther = IERC20(_rewardTokenOther);
    }

    function setReward(uint256 _startTime, uint256 _period, uint256 _reward, uint256 _rewardOther, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        require(endTime < block.timestamp, "!endTime");
        require(block.timestamp <= _startTime, "!_startTime");
        require(_startTime <= block.timestamp + 30 days, "!_startTime");
        require(_period > 0, "!_period");
        if (_withUpdate) {
            massUpdatePools();
        }

        // transfer _reward token
        if (_reward > 0) {
            uint256 _balance = rewardToken.balanceOf(address(this));
            require(_balance >= _reward, "!_reward");
            totalReward = totalReward.add(reward);
        }
        reward = _reward;

        // transfer _rewardOther token
        if (_rewardOther > 0) {
            uint256 _balanceOther = rewardTokenOther.balanceOf(address(this));
            require(_balanceOther >= _rewardOther, "!_rewardOther");
            totalRewardOther = totalRewardOther.add(rewardOther);
        }
        rewardOther = _rewardOther;

        startTime = _startTime;
        endTime = _startTime.add(_period);
        period = _period;
        epochId++;

        epochRewards[epochId] = EpochReward({
            epochId: epochId,
            startTime: _startTime,
            endTime: endTime,
            reward: _reward,
            rewardOther: _rewardOther
        });
    }

    function setIntervalTime(uint256 _intervalTime) public {
        require(msg.sender == governance, "!governance");
        intervalTime = _intervalTime;
    }

    function setAllocPoint(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        require(_pid < poolInfos.length, "!_pid");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfos[_pid].allocPoint).add(_allocPoint);
        require(totalAllocPoint > 0, "!totalAllocPoint");
        poolInfos[_pid].allocPoint = _allocPoint;
    }

    function setAllocPointOther(uint256 _pid, uint256 _allocPointOther, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        require(_pid < poolInfos.length, "!_pid");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPointOther = totalAllocPointOther.sub(poolInfos[_pid].allocPointOther).add(_allocPointOther);
        require(totalAllocPointOther > 0, "!totalAllocPointOther");
        poolInfos[_pid].allocPointOther = _allocPointOther;
    }

    function addPool(address _lpToken, uint256 _allocPoint, uint256 _allocPointOther, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        uint256 length = poolInfos.length;
        for (uint256 i = 0; i < length; i++) {
            require(_lpToken != address(poolInfos[i].lpToken), "!_lpToken");
        }
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 _lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfos.push(
            PoolInfo({
                lpToken: IERC20(_lpToken),
                amount: 0,
                lastRewardTime: _lastRewardTime,
                allocPoint: _allocPoint,
                allocPointOther: _allocPointOther,
                accTokenPerShare: 0,
                accTokenPerShareOther: 0
            })
        );
    }

    function getReward(uint256 _from, uint256 _to) public view returns (uint256, uint256) {
        if (_to <= startTime || _from >= endTime) {
            return (0, 0);
        }

        if (_from < startTime) {
            _from = startTime; // [startTime, endTime)
        }

        if (_to > endTime){
            _to = endTime;  // (startTime, endTime]
        }
        require(_from < _to, "!_from < _to");

        return (_to.sub(_from).mul(reward).div(period), _to.sub(_from).mul(rewardOther).div(period));
    }

    // View function to see pending Token on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256, uint256) {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][_user];
        uint256 _accTokenPerShare = pool.accTokenPerShare;
        uint256 _accTokenPerShareOther = pool.accTokenPerShareOther;
        uint256 _lpSupply = pool.amount;
        if (block.timestamp > startTime && pool.lastRewardTime < endTime && block.timestamp > pool.lastRewardTime && _lpSupply != 0) {
            (uint256 _rewardAmount, uint256 _rewardAmountOther)=  getReward(pool.lastRewardTime, block.timestamp);
            if (_rewardAmount > 0) {
                _rewardAmount = _rewardAmount.mul(pool.allocPoint).div(totalAllocPoint);
                _accTokenPerShare = _accTokenPerShare.add(_rewardAmount.mul(1e18).div(_lpSupply));
            }
            if (_rewardAmountOther > 0) {
                _rewardAmountOther = _rewardAmount.mul(pool.allocPointOther).div(totalAllocPointOther);
                _accTokenPerShareOther = _accTokenPerShareOther.add(_rewardAmountOther.mul(1e18).div(_lpSupply));
            }
        }
        uint256 _reward = user.amount.mul(_accTokenPerShare).div(1e18).sub(user.rewardDebt);
        uint256 _rewardOther = user.amount.mul(_accTokenPerShareOther).div(1e18).sub(user.rewardDebtOther);
        return (user.reward.add(_reward), user.rewardOther.add(_rewardOther));
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfos.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        require(_pid < poolInfos.length, "!_pid");

        PoolInfo storage pool = poolInfos[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (block.timestamp <= startTime) {
            pool.lastRewardTime = startTime;
            return;
        }

        if (pool.lastRewardTime >= endTime) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 _lpSupply = pool.amount;
        if (_lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        (uint256 _rewardAmount, uint256 _rewardAmountOther) = getReward(pool.lastRewardTime, block.timestamp);
        if (_rewardAmount > 0) {
            _rewardAmount = _rewardAmount.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accTokenPerShare = pool.accTokenPerShare.add(_rewardAmount.mul(1e18).div(_lpSupply));
        }
        if (_rewardAmountOther > 0) {
            _rewardAmountOther = _rewardAmountOther.mul(pool.allocPointOther).div(totalAllocPointOther);
            pool.accTokenPerShareOther = pool.accTokenPerShareOther.add(_rewardAmountOther.mul(1e18).div(_lpSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
            user.reward = _reward.add(user.reward);
            uint256 _rewardOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18).sub(user.rewardDebtOther);
            user.rewardOther = _rewardOther.add(user.rewardOther);
        }
        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        user.depositTime = block.timestamp;
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18);
        pool.amount = pool.amount.add(_amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "!_amount");
        require(block.timestamp >= user.depositTime + intervalTime, "!intervalTime");
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        user.reward = _reward.add(user.reward);
        uint256 _rewardOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18).sub(user.rewardDebtOther);
        user.rewardOther = _rewardOther.add(user.rewardOther);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18);
        pool.amount = pool.amount.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function harvest(uint256 _pid) public{
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        uint256 _rewardOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18).sub(user.rewardDebtOther);
        _rewardOther = _rewardOther.add(user.rewardOther);
        user.rewardOther = 0;
        safeTokenTransfer(msg.sender, _reward, _rewardOther);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18);
        emit Harvest(msg.sender, _pid, _reward, _rewardOther);
    }

    function withdrawAndHarvest(uint256 _pid, uint256 _amount) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "!_amount");
        require(block.timestamp >= user.depositTime + intervalTime, "!intervalTime");
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        uint256 _rewardOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18).sub(user.rewardDebtOther);
        _rewardOther = _rewardOther.add(user.rewardOther);
        user.rewardOther = 0;
        safeTokenTransfer(msg.sender, _reward, _rewardOther);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        user.rewardDebtOther = user.amount.mul(pool.accTokenPerShareOther).div(1e18);
        pool.amount = pool.amount.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _pid, _amount);
        emit Harvest(msg.sender, _pid, _reward, _rewardOther);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(block.timestamp >= user.depositTime + 1, "!intervalTime"); // prevent flash loan
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.reward = 0;
        user.rewardDebtOther = 0;
        user.rewardOther = 0;
        pool.amount = pool.amount.sub(_amount);
        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe rewardToken transfer function, just in case if rounding error causes pool to not have enough Token.
    function safeTokenTransfer(address _to, uint256 _amount, uint256 _amountOther) internal {
        if (_amount > 0) {
            uint256 _balance = rewardToken.balanceOf(address(this));
            if (_amount > _balance) {
                totalGain = totalGain.add(_balance);
                rewardToken.safeTransfer(_to, _balance);
            } else {
                totalGain = totalGain.add(_amount);
                rewardToken.safeTransfer(_to, _amount);
            }
        }
        if (_amountOther > 0) {
            uint256 _balanceOther = rewardTokenOther.balanceOf(address(this));
            if (_amountOther > _balanceOther) {
                totalGainOther = totalGainOther.add(_balanceOther);
                rewardTokenOther.safeTransfer(_to, _balanceOther);
            } else {
                totalGainOther = totalGainOther.add(_amountOther);
                rewardTokenOther.safeTransfer(_to, _amountOther);
            }
        }
    }

    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }

    function annualReward(uint256 _pid) public view returns (uint256 _annual, uint256 _annualOther){
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        // SECS_PER_YEAR  31_556_952  365.2425 days
        _annual = reward.mul(31556952).mul(pool.allocPoint).div(totalAllocPoint).div(period);
        _annualOther = rewardOther.mul(31556952).mul(pool.allocPointOther).div(totalAllocPointOther).div(period);
    }

    function annualRewardPerShare(uint256 _pid) public view returns (uint256, uint256){
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        if (pool.amount == 0) {
            return (0, 0);
        }
        (uint256 _annual, uint256 _annualOther) = annualReward(_pid);
        return (_annual.mul(1e18).div(pool.amount), _annualOther.mul(1e18).div(pool.amount));
    }

    function sweepGuardian(address _token) public {
        require(msg.sender == guardian, "!guardian");
        require(block.timestamp > guardianTime, "!guardianTime");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

    function sweep(address _token) public {
        require(msg.sender == governance, "!governance");
        require(_token != address(rewardToken), "!_token");
        require(_token != address(rewardTokenOther), "!_token");
        uint256 length = poolInfos.length;
        for (uint256 i = 0; i < length; i++) {
            require(_token != address(poolInfos[i].lpToken), "!_token");
        }

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

    function sweepLpToken(uint256 _pid) public {
        require(msg.sender == governance, "!governance");
        require(_pid < poolInfos.length, "!_pid");
        PoolInfo storage pool = poolInfos[_pid];
        IERC20 _token = pool.lpToken;

        uint256 _balance = _token.balanceOf(address(this));
        uint256 _amount = _balance.sub(pool.amount);
        _token.safeTransfer(governance, _amount);
    }
}
