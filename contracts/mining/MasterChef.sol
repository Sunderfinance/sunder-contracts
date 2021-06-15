// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";
import "@openzeppelinV3/contracts/utils/EnumerableSet.sol";

import "../../interfaces/sunder/IMigratorChef.sol";


contract MasterChef {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 reward;
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSunderPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSunderPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardTime; // Last block number that SUSHIs distribution occurs.
        uint256 accSunderPerShare; // Accumulated SUSHIs per share, times 1e18. See below.
    }

    address public governance;
    IERC20  public sunder;

    uint256 public totalReward;
    uint256 public reward;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public period;

    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    // Info of each pool.
    PoolInfo[] public poolInfos;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 reward);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid,  uint256 amount);

    constructor(address _sunder) public {
        sunder = IERC20(_sunder);
        governance = msg.sender;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setReward(uint256 _startTime, uint256 _endTime, uint256 _reward, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        require(endTime < block.timestamp, "!endTime");
        require(block.timestamp <= _startTime, "!_startTime");
        require(_startTime < _endTime, "!_endTime");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 _balance = sunder.balanceOf(address(this));
        require(_balance >= _reward, "!_reward");
        reward = _reward;

        totalReward = totalReward.add(reward);
        startTime = _startTime;
        endTime = _endTime;
        period = _endTime.sub(_startTime);
    }

    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(IERC20 _lpToken, uint256 _allocPoint, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 _lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfos.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accSunderPerShare: 0
            })
        );
    }

    // Update the given pool's SUSHI allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public {
        require(msg.sender == governance, "!governance");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfos[_pid].allocPoint).add(_allocPoint);
        poolInfos[_pid].allocPoint = _allocPoint;
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public  {
        require(msg.sender == governance, "!governance");
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfos[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 _balance = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), _balance);
        IERC20 newLpToken = IERC20(migrator.migrate(address(lpToken)));
        require(_balance == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    function getReward(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= startTime || _from >= endTime) {
            return 0;
        }
        if (_to < endTime){
            if (_from < startTime) {
                return _to.sub(startTime).mul(reward).div(period);
            } else {
                return _to.sub(_from).mul(reward).div(period);
            }
        } else {
            if (_from <= startTime){
                return reward;
            } else if (_from < endTime) {
                return endTime.sub(_from).mul(reward).div(period);
            }
        }
    }

    // View function to see pending SUSHIs on frontend.
    function pendingSunder(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][_user];
        uint256 accSunderPerShare = pool.accSunderPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > startTime && pool.lastRewardTime < endTime && block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 sunderReward =  getReward(pool.lastRewardTime, block.timestamp).mul(pool.allocPoint).div(totalAllocPoint);
            accSunderPerShare = accSunderPerShare.add(sunderReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accSunderPerShare).div(1e18).sub(user.rewardDebt);
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

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 sunderReward = getReward(pool.lastRewardTime, block.timestamp).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accSunderPerShare = pool.accSunderPerShare.add(sunderReward.mul(1e18).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for SUSHI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _reward = user.amount.mul(pool.accSunderPerShare).div(1e18).sub(user.rewardDebt);
            user.reward = _reward.add(user.reward);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accSunderPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accSunderPerShare).div(1e18).sub(user.rewardDebt);
        user.reward = _reward.add(user.reward);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSunderPerShare).div(1e18);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function harvest(uint256 _pid) public{
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accSunderPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        safeSunderTransfer(msg.sender, _reward);
        user.rewardDebt = user.amount.mul(pool.accSunderPerShare).div(1e18);
        emit Harvest(msg.sender, _pid, _reward);
    }

    function withdrawAndHarvest(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _reward = user.amount.mul(pool.accSunderPerShare).div(1e18).sub(user.rewardDebt);
        _reward = _reward.add(user.reward);
        user.reward = 0;
        safeSunderTransfer(msg.sender, _reward);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accSunderPerShare).div(1e18);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
        emit Harvest(msg.sender, _pid, _reward);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfos[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe sunder transfer function, just in case if rounding error causes pool to not have enough SUSHIs.
    function safeSunderTransfer(address _to, uint256 _amount) internal {
        uint256 _balance = sunder.balanceOf(address(this));
        if (_amount > _balance) {
            sunder.safeTransfer(_to, _balance);
        } else {
            sunder.safeTransfer(_to, _amount);
        }
    }
}
