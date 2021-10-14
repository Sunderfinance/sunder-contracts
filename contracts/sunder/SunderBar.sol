// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

contract SunderBar is ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public guardian;
    uint256 public effectTime;
    address public operator;
    IERC20  public sunder;
    uint256 public harvestTime;
    uint256 public harvestReward;
    uint256 public harvestBalance;
    uint256 public harvestPeriod;

    mapping(address => uint256) public depositAt;

    event Deposit(address indexed account, uint256 amount, uint256 share);
    event Withdraw(address indexed account, uint256 amount, uint256 share);

    constructor(address _sunder, address _operator) public ERC20(
      string(abi.encodePacked("Bar ", ERC20(_sunder).name())),
      string(abi.encodePacked("x", ERC20(_sunder).symbol()))) {
        sunder = IERC20(_sunder);
        governance = msg.sender;
        guardian = msg.sender;
        operator = _operator;
        _setupDecimals(ERC20(_sunder).decimals());
        harvestTime = block.timestamp;
        effectTime = block.timestamp + 60 days;
    }

    function setGuardian(address _guardian) external {
        require(msg.sender == guardian, "!guardian");
        guardian = _guardian;
    }
    function addGuardianTime(uint256 _addTime) external {
        require(msg.sender == guardian || msg.sender == governance, "!guardian");
        effectTime = effectTime.add(_addTime);
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
    function setController(address _operator) external {
        require(msg.sender == governance, "!governance");
        operator = _operator;
    }

    function depositAll() external {
        deposit(sunder.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        depositAt[msg.sender] = block.number;
        uint256 _pool = sunderBalance();
        sunder.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 _share = 0;
        uint256 _total = totalSupply();
        if (_total == 0 || _pool == 0) {
            _share = _amount;
        } else {
            _share = _amount.mul(_total).div(_pool);
        }
        _mint(msg.sender, _share);
        emit Deposit(msg.sender, _amount, _share);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint256 _share) public {
        require(depositAt[msg.sender] < block.number, "!depositAt");
        uint256 _total = totalSupply();
        uint256 _amount = _share.mul(sunderBalance()).div(_total);
        _burn(msg.sender, _share);
        sunder.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount, _share);
    }

    function sunderBalance() public view returns (uint256) {
        return sunder.balanceOf(address(this));
    }

    function getPricePerFullShare() external view returns (uint256) {
        uint256 _total = totalSupply();
        if (_total == 0) {
            return 1e18;
        }
        return sunderBalance().mul(1e18).div(_total);
    }

    function annualRewardPerShare() public view returns (uint256) {
        if (harvestPeriod == 0 || harvestBalance == 0) {
            return 0;
        }
        // SECS_PER_YEAR  31_556_952  365.2425 days
        return harvestReward.mul(31556952).mul(1e18).div(harvestPeriod).div(harvestBalance);
    }

    function setHarvestInfo(uint256 _harvestReward) external {
        require(msg.sender == operator, "!operator");
        uint256 _harvestTime = block.timestamp;
        require(_harvestTime > harvestTime, "!_harvestTime");
        harvestPeriod = _harvestTime - harvestTime;
        harvestTime = _harvestTime;
        harvestReward = _harvestReward;
        harvestBalance = sunderBalance();
    }

    function sweep(address _token) external {
        require(msg.sender == governance, "!governance");
        require(address(sunder) != _token, "sunder = _token");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

    function sweepGuardian(address _token) external {
        require(msg.sender == guardian, "!guardian");
        require(block.timestamp > effectTime, "!effectTime");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

}
