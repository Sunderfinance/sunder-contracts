// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/sushi/IBentoBox.sol";
import "../../interfaces/yearn/IController.sol";

contract StrategyXSushi {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public controller;
    address public strategist;

    uint256 public debt;
    uint256 public performanceFee = 500;
    uint256 constant public performanceMax = 10000;

    address constant public want        = address(0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272); // xSushi
    address constant public bentoBox    = address(0xF5BCE5077908a1b7370B9ae04AdC565EBd643966); // BentoBoxV1

    address constant public eToken = address(0x96741Bb1ca26A7112D40d716013016833E88a3cC);
    address constant public dToken = address(0xD4e422388254a5b9a825146A38F79B6dF1c4712d);

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategyXSushi";
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
            IBentoBox(bentoBox).withdraw(want, address(this), address(this), _amount.sub(_balance), 0);
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
        uint256 _amount = balanceBentoWant();
        if (_amount > 0) {
            IBentoBox(bentoBox).withdraw(want, address(this), address(this), _amount, 0);
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
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        uint256 _balance = balanceWant();
        if (_balance > 0) {
            IERC20(want).approve(bentoBox, _balance);
            IBentoBox(bentoBox).deposit(want, address(this), address(this), _balance, 0);
        }
    }

    function harvest() external {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");

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
    function balanceBentoWant() public view returns (uint256 _amount) {
        uint256 _share = IBentoBox(bentoBox).balanceOf(want, address(this));
        _amount = IBentoBox(bentoBox).toAmount(want, _share, false);
    }
    function totalAssets() public view returns (uint256) {
        return balanceWant().add(balanceBentoWant());
    }
}
