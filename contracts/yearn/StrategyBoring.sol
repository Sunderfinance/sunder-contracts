// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/boring/IBoringChef.sol";
import "../../interfaces/yearn/IController.sol";

contract StrategyBoring {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public controller;
    address public strategist;

    uint256 public debt;
    bool public claim;
    uint256 public performanceFee = 500;
    uint256 constant public performanceMax = 10000;

    address constant public want        = address(0xBC19712FEB3a26080eBf6f2F7849b417FdD792CA); // BORING TOKEN
    address constant public boringChef  = address(0x204c87CDA5DAAC87b2Fc562bFb5371a0B066229C); // BORING Chef
    uint256 constant public pid = 12;
    address constant public dToken = address(0xAe61EBE4b70f0740C53482413C56B8C924e1A9c3);
    address constant public eToken = address(0x066CdF088C17fF05432A48b08f701f5EB8c3CDF3);

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategyBoring";
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
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        strategist = _strategist;
    }
    function setClaim(bool _claim) external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        claim = _claim;
    }

    function setPerformanceFee(uint256 _performanceFee) external {
        require(msg.sender == governance, "!governance");
        require(_performanceFee <= performanceMax, "!_performanceFee");
        performanceFee = _performanceFee;
    }

    function addDebt(uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        require(_balance >= _amount, "_balance < _amount");
        debt = debt.add(_amount);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(address _receiver, uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        debt = debt.sub(_amount);
        _withdraw(_receiver, _amount);
    }

    function _withdraw(address _receiver, uint256 _amount) internal {
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            IBoringChef(boringChef).withdraw(pid, _amount.sub(_balance));
            _balance = IERC20(want).balanceOf(address(this));
            if (_balance < _amount) {
                _amount = _balance;
            }
        }
        IERC20(want).safeTransfer(_receiver, _amount);
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll(address _receiver) external returns (uint256 _balance) {
        require(msg.sender == controller, "!controller");
        uint256 _amount = balanceChefWant();
        if (_amount > 0) {
            IBoringChef(boringChef).emergencyWithdraw(pid);
        }
        debt = 0;
        _balance = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(_receiver, _balance);
    }

    function withdraw(address _asset) external returns (uint256 _balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        _balance = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).safeTransfer(controller, _balance);
    }

    function earn() external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        uint256 _balance = balanceWant();
        if (_balance > 0) {
            IERC20(want).approve(boringChef, _balance);
            IBoringChef(boringChef).deposit(pid, _balance);
        }
    }

    function harvest() external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");

        if (claim) {
            uint256 _balance = balanceWant();
            if (_balance > 0) {
                IERC20(want).approve(boringChef, _balance);
            }
            IBoringChef(boringChef).deposit(pid, _balance);
        }

        uint256 _assets = totalAssets();
        if (_assets > debt) {
            uint256 _amount = _assets - debt;
            IController(controller).mint(want, _amount);
            debt = _assets;

            address _vault = IController(controller).vaults(want);
            require(_vault != address(0), "address(0)");
            uint256 _fee = _amount.mul(performanceFee).div(performanceMax);
            uint256 _reward = _amount - _fee;
            IERC20(eToken).safeTransfer(_vault, _reward);
            IController(controller).setHarvestInfo(want, _reward);
            IERC20(eToken).safeTransfer(IController(controller).rewards(), _fee);
            IERC20(dToken).safeTransfer(IController(controller).rewards(), _amount);
        }
    }

    function balanceWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }
    function balanceChefWant() public view returns (uint256 _amount) {
        (_amount,) = IBoringChef(boringChef).userInfo(pid, address(this));
    }
    function pendingBoring() public view returns (uint256) {
        return IBoringChef(boringChef).pendingBoring(pid, address(this));
    }
    function totalAssets() public view returns (uint256) {
        return balanceWant().add(balanceChefWant()).add(pendingBoring());
    }
}
