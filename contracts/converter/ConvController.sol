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
    address public reward;
    address public controller;

    address public operator;
    mapping(address => bool) public locks;

    uint256 public withdrawalFee = 200;
    uint256 constant public withdrawalMax = 10000;

    mapping(address => address) public dtokens;
    mapping(address => address) public etokens;
    mapping(address => mapping(address => uint256)) public convertAt;

    event PairCreated(address indexed token, address indexed dtoken, address indexed etoken);
    event Convert(address indexed account, address indexed token, uint256 amount);
    event Redeem(address indexed account, address indexed token, uint256 amount, uint256 fee);

    constructor(address _controller, address _reward, address _operator) public {
        governance = msg.sender;
        controller = _controller;
        reward = _reward;
        operator = _operator;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }
    function setReward(address _reward) public {
        require(msg.sender == governance, "!governance");
        reward = _reward;
    }
    function setOperator(address _operator) public {
        require(msg.sender == governance, "!governance");
        operator = _operator;
    }
    function setWithdrawalFee(uint256 _withdrawalFee) public {
        require(msg.sender == governance, "!governance");
        withdrawalFee = _withdrawalFee;
    }

    function locking(address _token) public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        locks[_token] = true;
    }
    function unlocking(address _token) public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        locks[_token] = false;
    }

    function convertAll(address _token) external {
        convert(_token, IERC20(_token).balanceOf(msg.sender));
    }

    function convert(address _token, uint256 _amount) public {
        require(dtokens[_token] != address(0), "address(0)");

        convertAt[_token][msg.sender] = block.number;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _mint(_token, msg.sender, _amount);
    }

    function mint(address _token, address _minter, uint256 _amount) public {
        require(msg.sender == controller, "!controller");
        require(dtokens[_token] != address(0), "address(0)");
        _mint(_token, _minter, _amount);
    }

    function _mint(address _token, address _minter, uint256 _amount) internal {
        DToken(dtokens[_token]).mint(_minter, _amount);
        EToken(etokens[_token]).mint(_minter, _amount);
        emit Convert(_minter, _token, _amount);
    }

    function redeemAll(address _token) external {
        uint256 _amount = maxRedeemAmount(_token);
        redeem(_token, _amount);
    }

    function redeem(address _token, uint256 _amount) public {
        require(!locks[_token], "locking");
        require(dtokens[_token] != address(0), "address(0)");
        require(convertAt[_token][msg.sender] < block.number, "!convertAt");

        DToken(dtokens[_token]).burn(msg.sender, _amount);
        EToken(etokens[_token]).burn(msg.sender, _amount);

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        if (_balance < _amount) {
            uint256 _withdraw = _amount.sub(_balance);
            IController(controller).withdraw(_token, _withdraw);
            _balance = IERC20(_token).balanceOf(address(this));
            if (_balance < _amount) {
                _amount = _balance;
            }
        }

        uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        IERC20(_token).safeTransfer(reward, _fee);
        IERC20(_token).safeTransfer(msg.sender, _amount.sub(_fee));
        emit Redeem(msg.sender, _token, _amount, _fee);
    }

    function createPair(address _token) external  returns (address _dtoken, address _etoken) {
        require(msg.sender == governance, "!governance");
        require(_token != address(0), " address(0)");
        require(dtokens[_token] == address(0), "!address(0)");

        bytes memory _nameD = abi.encodePacked("dToken ", ERC20(_token).name());
        bytes memory _symbolD = abi.encodePacked("d", ERC20(_token).symbol());
        bytes memory _nameE = abi.encodePacked("eToken ", ERC20(_token).name());
        bytes memory _symbolE = abi.encodePacked("e", ERC20(_token).symbol());
        uint8 _decimals = ERC20(_token).decimals();

        bytes memory _bytecodeD = type(DToken).creationCode;
        bytes32 _saltD = keccak256(abi.encodePacked(_token, _nameD, _symbolD));
        assembly {
            _dtoken := create2(0, add(_bytecodeD, 32), mload(_bytecodeD), _saltD)
        }
        DToken(_dtoken).initialize(governance, _decimals, _nameD, _symbolD);

        bytes memory _bytecodeE = type(EToken).creationCode;
        bytes32 _saltE = keccak256(abi.encodePacked(_token, _nameE, _symbolE));
        assembly {
            _etoken := create2(0, add(_bytecodeE, 32), mload(_bytecodeE), _saltE)
        }
        EToken(_etoken).initialize(governance, _decimals, _nameE, _symbolE);

        dtokens[_token] = _dtoken;
        etokens[_token] = _etoken;

        emit PairCreated(_token, _dtoken, _etoken);
    }

    function maxRedeemAmount(address _token) public view returns (uint256) {
        uint256 _dbalance = IERC20(dtokens[_token]).balanceOf(msg.sender);
        uint256 _ebalance = IERC20(etokens[_token]).balanceOf(msg.sender);
        if (_dbalance > _ebalance) {
            return _ebalance;
        } else {
            return _dbalance;
        }
    }

    function tokenBalance(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function deposit(address _token) public {
        uint256 _bal = tokenBalance(_token);
        IERC20(_token).safeTransfer(controller, _bal);
        IController(controller).deposit(_token, _bal);
    }

    function sweep(address _token) public {
        require(msg.sender == governance, "!governance");
        require(dtokens[_token] == address(0), "!address(0)");

        uint256 _bal = tokenBalance(_token);
        IERC20(_token).safeTransfer(reward, _bal);
    }
}
