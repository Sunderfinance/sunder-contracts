// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/compound/ICToken.sol";
import "../../interfaces/compound/ICompController.sol";
import "../../interfaces/yearn/IController.sol";

contract StrategyCompound {
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
    address constant public want  = address(0xc00e94Cb662C3520282E6f5717214004A7f26888); // comp
    address constant public cComp = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    address constant public eToken = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    address constant public dToken = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    */
    // test begin
    address public want; // comp
    address public cComp;
    address public eToken;
    address public dToken;
    // test end

    ICompController constant public compController = ICompController(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    // test
    function testAddress(address _want, address _eToken, address _dToken) public {
        want = _want;
        cComp = address(0x1201D1777654C65C052C4c401621625e173a357a);
        eToken = _eToken;
        dToken = _dToken;
    }

    function testHarvest() public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        uint256 _balance = balanceWant();
        if (_balance > debt){
            uint256 _amount = _balance - debt;
            IController(controller).mint(address(want), _amount);
            debt = _balance;
            uint256 _fee = _amount.mul(performanceFee).div(performanceMax);
            address _vault = IController(controller).vaults(want);
            require(_vault != address(0), "address(0)");
            IERC20(eToken).safeTransfer(_vault, _amount.sub(_fee));
            IERC20(eToken).safeTransfer(IController(controller).rewards(), _fee);
            IERC20(dToken).safeTransfer(IController(controller).rewards(), _amount);
        }
    }

    //  test end

    constructor(address _controller) public {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
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

    function getName() external pure returns (string memory) {
        return "StrategyCompound";
    }

    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setPerformanceFee(uint256 _performanceFee) external {
        require(msg.sender == governance, "!governance");
        performanceFee = _performanceFee;
    }

    function addDebt(uint256 _amount) public {
        require(msg.sender == controller, "!controller");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        require(_balance >= _amount, "_balance < _amount");
        debt = debt.add(_amount);
    }

    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(address _receiver, uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        debt.sub(_amount);
        _withdraw(_receiver, _amount);
    }

    function withdrawVote(address _receiver, uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        _withdraw(_receiver, _amount);
    }

    function _withdraw(address _receiver, uint256 _amount) internal {
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            ICToken(cComp).redeemUnderlying(_amount.sub(_balance));
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
        uint256 _amount = balanceCComp();
        if (_amount > 0) {
            ICToken(cComp).redeem(_amount);
        }
        debt = 0;
        _balance = IERC20(want).balanceOf(address(this));
        IERC20(want).safeTransfer(_receiver, _balance);
    }

    function withdraw(address _asset) external returns (uint256 _balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(cComp != address(_asset), "cComp");
        _balance = IERC20(_asset).balanceOf(address(this));
        IERC20(_asset).safeTransfer(controller, _balance);
    }

    function setClaim(bool _claim) public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        claim = _claim;
    }

    function earn() public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        uint256 _balance = IERC20(want).balanceOf(address(this));
        if (_balance > 0) {
            IERC20(want).safeApprove(cComp, _balance);
            ICToken(cComp).mint(_balance);
        }
    }

    function harvest() public {
        require(msg.sender == strategist || msg.sender == governance, "!authorized");
        if (claim) {
            address[] memory holders = new address[](1);
            holders[0] = address(this);
            address[] memory cTokens = new address[](1);
            cTokens[0] = cComp;
            compController.claimComp(holders, cTokens, false, true);
        }
        uint256 _assets = totalAssets();
        if (_assets > debt){
            uint256 _amount = _assets - debt;
            IController(controller).mint(address(want), _amount);
            debt = _assets;
            uint256 _fee = _amount.mul(performanceFee).div(performanceMax);
            address _vault = IController(controller).vaults(want);
            require(_vault != address(0), "address(0)");
            IERC20(eToken).safeTransfer(_vault, _amount.sub(_fee));
            IERC20(eToken).safeTransfer(IController(controller).rewards(), _fee);
            IERC20(dToken).safeTransfer(IController(controller).rewards(), _amount);
        }
    }

    function balanceWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceCCompToWant() public view returns (uint256) {
        // Mantisa 1e18 to decimals
        uint256 _amount = balanceCComp();
        if (_amount > 0) {
            _amount = _amount.mul(ICToken(cComp).exchangeRateStored()).div(1e18);
        }
        return _amount;
    }

    function balanceCComp() public view returns (uint256) {
        return IERC20(cComp).balanceOf(address(this));
    }

    function totalAssets() public view returns (uint256) {
        return balanceWant().add(balanceCCompToWant());
    }

}
