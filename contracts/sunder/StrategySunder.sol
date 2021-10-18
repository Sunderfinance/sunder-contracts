// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/sunder/ISunderBar.sol";
import "../../interfaces/yearn/IController.sol";

contract StrategySunder {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public controller;
    address public strategist;

    uint256 public debt;
    uint256 public performanceFee = 500;
    uint256 constant public performanceMax = 10000;

    address constant public want    = address(0xcC7675C0B1f4DDf3c774e960e4C627F566CB3f0F); // Sunder
    address constant public xSunder = address(0xbD57731106CD80924F13F57F6e6825c8375b07b2); // xSunder

    address constant public dToken = address(0x5f4aB41aF4fCD8F0f5Fc15FD425860672036425f);
    address constant public eToken = address(0xf2573d779fC477aC4d78b5854C7dE75C35bF0752);

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategySunder";
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
            uint256  _share = getShare(_amount - _balance);
            if (_share > 0) {
                ISunderBar(xSunder).withdraw(_share);
            }

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
        uint256 _share = ISunderBar(xSunder).balanceOf(address(this));
        if (_share > 0) {
            ISunderBar(xSunder).withdraw(_share);
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
            IERC20(want).approve(xSunder, _balance);
            ISunderBar(xSunder).deposit(_balance);
        }
    }

    function harvest() external {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");

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
    function balanceXSunderWant() public view returns (uint256 _amount) {
        uint256 _total = ISunderBar(xSunder).totalSupply();
        if (_total == 0) {
            _amount = 0;
        } else {
            uint256 _share = ISunderBar(xSunder).balanceOf(address(this));
            uint256 _balance = IERC20(want).balanceOf(xSunder);
            _amount = _share.mul(_balance).div(_total);
        }
    }
    function totalAssets() public view returns (uint256) {
        return balanceWant().add(balanceXSunderWant());
    }

    function getShare(uint256 _amount) public view returns (uint256) {
        uint256 _balance = IERC20(want).balanceOf(xSunder);
        /*
        if (_balance == 0) {
            return 0;
        }
        if (_amount > _balance) {
            _amount = _balance;
        }
        */

        if (_amount > _balance) {
            return 0;
        }
        uint256 _total = ISunderBar(xSunder).totalSupply();
        return _amount.mul(_total).div(_balance);
    }
}
