// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/boring/IBoringChef.sol";
import "../../interfaces/boring/IBoringDAO.sol";
import "../../interfaces/boring/IFeePool.sol";
import "../../interfaces/yearn/IController.sol";

contract StrategyBoringPPBTC2 {
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
    /*
    address constant public want        = address(0x6C189Baa963060DAEEC77B7305b055216090bFC4); // Pledge Provider Token BTC
    address constant public boring      = address(0xBC19712FEB3a26080eBf6f2F7849b417FdD792CA); // BORING TOKEN
    address constant public boringDAOV2 = address(0x77F79FEa3d135847098Adb1fdc6B10A0218823F5); // BORING DAOV2
    address constant public boringChef  = address(0x204c87CDA5DAAC87b2Fc562bFb5371a0B066229C); // BORING Chef
    uint256 constant public pid = 0;
    bytes32 constant public tunnelKey = "BTC";
    address constant public eToken = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);  // online update address
    address constant public dToken = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);  // online update address

    address constant public feePool = address(0x2b781634e4cb0b5236cC957DABA88F911FD66fCD);  // BORING feePool
    address constant public oBtc    = address(0x8064d9Ae6cDf087b1bcd5BDf3531bD5d8C537a68);  // BORING oBTC
    */
    address constant public want        = address(0x9522AFFe079A544938DCF9496f0D008D3D3F9Fa2); // Pledge Provider Token BTC
    address constant public boring      = address(0xc7B671261e2EAd806756D66bFB41980bB627B101); // BORING TOKEN
    address constant public boringDAOV2 = address(0xaa3B8F0EB4d35952232F2Bb167A3910144A98148); // BORING DAOV2
    address constant public boringChef  = address(0x71C2d4Bd90300d9ab20D4131BafBB9De5c025662); // BORING Chef
    uint256 constant public pid = 0;
    bytes32 constant public tunnelKey = "BTC";
    address constant public eToken = address(0x3dcec0AcB78749E6FcFA6916A6BaA81A62fE7DcE);  // online update address
    address constant public dToken = address(0x9435dF1C785F6Bce52952bfdD872f65A19A1729D);  // online update address

    address constant public feePool = address(0xcf761623c643EC79e4889606DB2544e43f511Ee4);  // BORING feePool
    address constant public oBtc    = address(0x8064d9Ae6cDf087b1bcd5BDf3531bD5d8C537a68);  // BORING oBTC

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
    }

    function getName() external pure returns (string memory) {
        return "StrategyBoring PP Token BTC";
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
        require(boring != address(_asset), "boring");
        _balance = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).safeTransfer(controller, _balance);
    }

    function earn() external {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        uint256 _balance = balanceWant();
        if (_balance > 0) {
            IERC20(want).approve(boringChef, _balance);
            IBoringChef(boringChef).deposit(pid, _balance);
        }
    }

    function harvest() external {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        if (claim) {
            IBoringChef(boringChef).deposit(pid, 0);
        }

        uint256 _amount = IERC20(boring).balanceOf(address(this));
        if (_amount > 0) {
            uint256 _fee = _amount.mul(performanceFee).div(performanceMax);
            IERC20(boring).safeTransfer(IController(controller).rewards(), _fee);
            _amount = _amount - _fee;

            uint256 _balance1 = IERC20(want).balanceOf(address(this));
            IERC20(boring).approve(boringDAOV2, _amount);
            IBoringDAO(boringDAOV2).pledge(tunnelKey, _amount);
            uint256 _balance2 = IERC20(want).balanceOf(address(this));

            if (_balance2 <= _balance1) {
                 return;
            }
            _amount = _balance2 - _balance1;
            IController(controller).mint(want, _amount);
            debt = debt.add(_amount);

            address _vault = IController(controller).vaults(want);
            require(_vault != address(0), "address(0)");
            IERC20(eToken).safeTransfer(_vault, _amount);
            IController(controller).setHarvestInfo(want, _amount);
            IERC20(dToken).safeTransfer(IController(controller).rewards(), _amount);
        }
    }

    function claimFee() external {
        IFeePool(feePool).claimFee();
    }

    function boringEarned() external view returns(uint256,uint256) {
        return IFeePool(feePool).earned(address(this));
    }

    function balanceWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }
    function balanceChefWant() public view returns (uint256 _amount) {
        (_amount,) = IBoringChef(boringChef).userInfo(pid, address(this));
    }
    function totalAssets() public view returns (uint256) {
        return balanceWant().add(balanceChefWant());
    }

    function pendingBoring() public view returns (uint256) {
        return IBoringChef(boringChef).pendingBoring(pid, address(this));
    }
    function balanceBoring() public view returns (uint256) {
        return IERC20(boring).balanceOf(address(this));
    }
}
