// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/ERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "./DToken.sol";
import "./EToken.sol";
import "../../interfaces/yearn/IController.sol";

contract ConvController {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public guardian;
    uint256 public effectTime;
    address public controller;
    address public reward;
    bool public unlocked;

    uint256 public withdrawalFee = 10;
    uint256 constant public withdrawalMax = 10000;

    address public operator;
    address[] public tokens;
    mapping(address => bool) public locks;
    mapping(address => address) public dTokens;
    mapping(address => address) public eTokens;
    mapping(address => mapping(address => uint256)) public convertAt;

    event PairCreated(address indexed token, address indexed dToken, address indexed eToken);
    event Convert(address indexed account, address indexed token, uint256 amount);
    event Redeem(address indexed account, address indexed token, uint256 amount, uint256 fee);

    constructor(address _controller, address _reward, address _operator) public {
        governance = msg.sender;
        guardian = msg.sender;
        controller = _controller;
        reward = _reward;
        operator = _operator;
        unlocked = true;
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
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
    function setReward(address _reward) external {
        require(msg.sender == governance, "!governance");
        reward = _reward;
    }

    function setOperator(address _operator) external {
        require(msg.sender == governance, "!governance");
        operator = _operator;
    }
    function setWithdrawalFee(uint256 _withdrawalFee) external {
        require(msg.sender == governance, "!governance");
        require(_withdrawalFee <= withdrawalMax, "!_withdrawalFee");
        withdrawalFee = _withdrawalFee;
    }

    function locking(address _token) external {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        locks[_token] = true;
    }
    function unlocking(address _token) external {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        locks[_token] = false;
    }

    function convertAll(address _token) external {
        convert(_token, IERC20(_token).balanceOf(msg.sender));
    }

    function convert(address _token, uint256 _amount) public {
        require(unlocked, "!unlock");
        unlocked = false;
        require(dTokens[_token] != address(0), "address(0)");

        convertAt[_token][msg.sender] = block.number;

        if (IController(controller).strategies(_token) != address(0)) {
            IERC20(_token).safeTransferFrom(msg.sender, controller, _amount);
            IController(controller).deposit(_token, _amount);
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
        _mint(_token, msg.sender, _amount);

        emit Convert(msg.sender, _token, _amount);
        unlocked = true;
    }

    function mint(address _token, address _minter, uint256 _amount) external {
        require(msg.sender == controller, "!controller");
        require(dTokens[_token] != address(0), "address(0)");

        _mint(_token, _minter, _amount);
        emit Convert(_minter, _token, _amount);
    }

    function _mint(address _token, address _minter, uint256 _amount) internal {
        DToken(dTokens[_token]).mint(_minter, _amount);
        EToken(eTokens[_token]).mint(_minter, _amount);
    }

    function redeemAll(address _token) external {
        uint256 _amount = maxRedeemAmount(_token, msg.sender);
        redeem(_token, _amount);
    }

    function redeem(address _token, uint256 _amount) public {
        require(unlocked, "!unlock");
        unlocked = false;
        require(!locks[_token], "locking");
        require(dTokens[_token] != address(0), "address(0)");
        require(convertAt[_token][msg.sender] < block.number, "!convertAt");

        DToken(dTokens[_token]).burn(msg.sender, _amount);
        EToken(eTokens[_token]).burn(msg.sender, _amount);

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        if (_balance < _amount) {
            if (IController(controller).strategies(_token) != address(0)) {
                uint256 _withdraw = _amount.sub(_balance);
                IController(controller).withdraw(_token, _withdraw);
                _balance = IERC20(_token).balanceOf(address(this));
            }
            if (_balance < _amount) {
                _amount = _balance;
            }
        }

        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        IERC20(_token).safeTransfer(reward, _fee);
        IERC20(_token).safeTransfer(msg.sender, _amount.sub(_fee));
        emit Redeem(msg.sender, _token, _amount, _fee);
        unlocked = true;
    }

    function createPair(address _token) external returns (address _dToken, address _eToken) {
        require(unlocked, "!unlock");
        unlocked = false;
        require(dTokens[_token] == address(0), "!address(0)");

        bytes memory _nameD = abi.encodePacked(ERC20(_token).symbol(), " dToken");
        bytes memory _symbolD = abi.encodePacked("d", ERC20(_token).symbol());
        bytes memory _nameE = abi.encodePacked(ERC20(_token).symbol(), " eToken");
        bytes memory _symbolE = abi.encodePacked("e", ERC20(_token).symbol());
        uint8 _decimals = ERC20(_token).decimals();

        bytes memory _bytecodeD = type(DToken).creationCode;
        bytes32 _saltD = keccak256(abi.encodePacked(_token, _nameD, _symbolD));
        assembly {
            _dToken := create2(0, add(_bytecodeD, 32), mload(_bytecodeD), _saltD)
        }
        DToken(_dToken).initialize(governance, _decimals, _nameD, _symbolD);

        bytes memory _bytecodeE = type(EToken).creationCode;
        bytes32 _saltE = keccak256(abi.encodePacked(_token, _nameE, _symbolE));
        assembly {
            _eToken := create2(0, add(_bytecodeE, 32), mload(_bytecodeE), _saltE)
        }
        EToken(_eToken).initialize(governance, _decimals, _nameE, _symbolE);

        dTokens[_token] = _dToken;
        eTokens[_token] = _eToken;
        tokens.push(_token);

        emit PairCreated(_token, _dToken, _eToken);
        unlocked = true;
    }

    function maxRedeemAmount(address _token, address _account) public view returns (uint256) {
        uint256 _dBalance = IERC20(dTokens[_token]).balanceOf(_account);
        uint256 _eBalance = IERC20(eTokens[_token]).balanceOf(_account);
        if (_dBalance > _eBalance) {
            return _eBalance;
        } else {
            return _dBalance;
        }
    }

    function tokenBalance(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function dTokenEToken(address _token) public view returns (address _dToken, address _eToken) {
        _dToken = dTokens[_token];
        _eToken = eTokens[_token];
        return (_dToken, _eToken);
    }

    function tokensInfo() public view returns (address[] memory _tokens){
        uint256 length = tokens.length;
        _tokens = new address[](tokens.length);
        for (uint256 i = 0; i < length; ++i) {
            _tokens[i] = tokens[i];
        }
    }

    function tokenLength() public view returns (uint256) {
        return tokens.length;
    }

    function deposit(address _token) external {
        uint256 _balance = tokenBalance(_token);
        IERC20(_token).safeTransfer(controller, _balance);
        IController(controller).deposit(_token, _balance);
    }

    function sweep(address _token) external {
        require(msg.sender == governance, "!governance");
        require(dTokens[_token] == address(0), "!address(0)");

        uint256 _balance = tokenBalance(_token);
        IERC20(_token).safeTransfer(reward, _balance);
    }

    function sweepGuardian(address _token) external {
        require(msg.sender == guardian, "!guardian");
        require(block.timestamp > effectTime, "!effectTime");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(governance, _balance);
    }

}
