// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/converter/IConvController.sol";
import "../../interfaces/yearn/IOneSplitAudit.sol";
import "../../interfaces/yearn/IStrategy.sol";

contract Controller {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public strategist;
    address public onesplit;
    address public rewards;

    address public voteController;
    address public convController;

    mapping(address => address) public vaults;
    mapping(address => address) public strategies;
    mapping(address => mapping(address => bool)) public approvedStrategies;

    uint256 public split = 500;
    uint256 public constant max = 10000;

    constructor(address _rewards) public {
        governance = msg.sender;
        strategist = msg.sender;
        onesplit = address(0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e);
        rewards = _rewards;
    }

    function setRewards(address _rewards) public {
        require(msg.sender == governance, "!governance");
        rewards = _rewards;
    }

    function setConvController(address _convController) public {
        require(msg.sender == governance, "!governance");
        convController = _convController;
    }

    function setVoteController(address _voteController) public {
        require(msg.sender == governance, "!governance");
        voteController = _voteController;
    }

    function setStrategist(address _strategist) public {
        require(msg.sender == governance, "!governance");
        strategist = _strategist;
    }

    function setSplit(uint256 _split) public {
        require(msg.sender == governance, "!governance");
        split = _split;
    }

    function setOneSplit(address _onesplit) public {
        require(msg.sender == governance, "!governance");
        onesplit = _onesplit;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setVault(address _token, address _vault) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(vaults[_token] == address(0), "vault");
        vaults[_token] = _vault;
    }

    function approveStrategy(address _token, address _strategy) public {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_token][_strategy] = true;
    }

    function revokeStrategy(address _token, address _strategy) public {
        require(msg.sender == governance, "!governance");
        approvedStrategies[_token][_strategy] = false;
    }

    function setStrategy(address _token, address _strategy) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        require(approvedStrategies[_token][_strategy] == true, "!approved");

        address _current = strategies[_token];
        if (_current != address(0)) {
           IStrategy(_current).withdrawAll(convController);
        }
        strategies[_token] = _strategy;
    }

    function earn(address _token, uint256 _amount) public {
        require(msg.sender == convController, "!convController");
        _deposit(_token, _amount);
        address _strategy = strategies[_token];
        IStrategy(_strategy).addDebt(_amount);
    }

    function deposit(address _token) public {
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        _deposit(_token, _balance);
    }

    function depositVote(address _token, uint256 _amount) public {
        require(msg.sender == voteController, "!voteController");
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        require(_balance >= _amount, "!_balance >= _amount");
        _deposit(_token, _amount);
    }

    function _deposit(address _token, uint256 _amount) internal {
        address _strategy = strategies[_token];
        address _want = IStrategy(_strategy).want();
        require(_want == _token, "!_want == _token");
        IERC20(_token).safeTransfer(_strategy, _amount);
    }

    function withdraw(address _token, uint256 _amount) public {
        require(msg.sender == convController, "!convController");
        IStrategy(strategies[_token]).withdraw(msg.sender, _amount);
    }

    function withdrawAll(address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!strategist");
        IStrategy(strategies[_token]).withdrawAll(convController);
    }

    function withdrawVote(address _token, uint256 _amount) public {
        require(msg.sender == voteController, "!voteController");
        IStrategy(strategies[_token]).withdrawVote(msg.sender, _amount);
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function inCaseStrategyTokenGetStuck(address _strategy, address _token) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        IStrategy(_strategy).withdraw(_token);
    }

    function getExpectedReturn(address _strategy, address _token, uint256 _parts) public view returns (uint256 expected) {
        uint256 _balance = IERC20(_token).balanceOf(_strategy);
        address _want = IStrategy(_strategy).want();
        (expected,) = IOneSplitAudit(onesplit).getExpectedReturn(_token, _want, _balance, _parts, 0);
    }

    // Only allows to withdraw non-core strategy tokens ~ this is over and above normal yield
    function yearn(address _strategy, address _token, uint256 _parts) public {
        require(msg.sender == strategist || msg.sender == governance, "!governance");
        // This contract should never have value in it, but just incase since this is a public call
        uint256 _before = IERC20(_token).balanceOf(address(this));
        IStrategy(_strategy).withdraw(_token);
        uint256 _after = IERC20(_token).balanceOf(address(this));
        if (_after > _before) {
            uint256 _amount = _after.sub(_before);
            address _want = IStrategy(_strategy).want();
            uint256[] memory _distribution;
            uint256 _expected;
            _before = IERC20(_want).balanceOf(address(this));
            IERC20(_token).safeApprove(onesplit, 0);
            IERC20(_token).safeApprove(onesplit, _amount);
            (_expected, _distribution) = IOneSplitAudit(onesplit).getExpectedReturn(_token, _want, _amount, _parts, 0);
            IOneSplitAudit(onesplit).swap(_token, _want, _amount, _expected, _distribution, 0);
            _after = IERC20(_want).balanceOf(address(this));
            if (_after > _before) {
                _amount = _after.sub(_before);
                uint256 _reward = _amount.mul(split).div(max);
                _deposit(_want, _amount.sub(_reward));
                IERC20(_want).safeTransfer(rewards, _reward);
            }
        }
    }

    function mint(address _token, uint256 _amount) public {
        require(msg.sender == strategies[_token], "!token strategies");
        IConvController(convController).mint(_token, msg.sender, _amount);
    }

    function totalAssets(address _token) external view returns (uint256) {
        return IStrategy(strategies[_token]).totalAssets();
    }
}
