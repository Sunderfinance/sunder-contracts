// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/yearn/IController.sol";
import "../../interfaces/voter/IVote.sol";

contract VoteController {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public controller;
    address public operator;

    mapping (address => address) public againsts;
    mapping (address => address) public fors;
    mapping (address => address) public abstains;
    mapping (address => address) public governors;
    mapping (address => uint256) public proposalIds;
    mapping (address => uint8) public types;

    constructor (address _controller, address _operator) public {
        governance = msg.sender;
        controller = _controller;
        operator =  _operator;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setController(address _controller) public {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setOperator(address _operator) public {
        require(msg.sender == governance, "!governance");
        operator = _operator;
    }

    function setGovernor(address _comp, address _governor) public {
        require(msg.sender == governance, "!governance");
        governors[_comp] = _governor;
    }
    function setAgainst(address _comp, address _against) public {
        require(msg.sender == governance, "!governance");
        againsts[_comp] = _against;
    }
    function setFor(address _comp, address _for) public {
        require(msg.sender == governance, "!governance");
        fors[_comp] = _for;
    }
    function setAbstain(address _comp, address _abstain) public {
        require(msg.sender == governance, "!governance");
        abstains[_comp] = _abstain;
    }

    function prepareVote(address _comp, uint256 _proposalId, uint256 _against, uint256 _for, uint256 _abstain) public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        require(proposalIds[_comp] == 0, "!proposalId");
        require(types[_comp] == 0, "!types");
        proposalIds[_comp] = _proposalId;
        uint256 _amount = _for.add(_against).add(_abstain);
        IController(controller).withdrawVote(_comp, _amount);

        uint8 _type = 0;
        if (_against > 0 ) {
            address _vote = againsts[_comp];
            _tranferVote(_comp, _vote, _against);
            _type += 4;
        }
        if (_for > 0 ) {
            address _vote = fors[_comp];
            _tranferVote(_comp, _vote, _for);
            _type += 2;
        }
        if (_abstain > 0) {
            address _vote = abstains[_comp];
            _tranferVote(_comp, _vote, _abstain);
            _type += 1;
        }
        types[_comp] = _type;
    }

    function _tranferVote(address _comp, address _vote, uint256 _amount) internal {
        require(_vote != address(0), "address(0)");
        uint256 _balance = IERC20(_comp).balanceOf(address(this));
        if (_amount > _balance) {
            _amount = _balance;
        }
        IERC20(_comp).safeTransfer(_vote, _amount);
    }

    function returnToken(address _comp, uint256 _proposalId) public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        require(proposalIds[_comp] == _proposalId, "!proposalId");
        uint8 _type = types[_comp];
        require(_type > 0, "!type");

        if (_type >= 4 ) {
            address _vote = againsts[_comp];
            IVote(_vote).returnToken(_comp);
            _type -= 4;
        }
        if (_type >= 2 ) {
            address _vote = fors[_comp];
            IVote(_vote).returnToken(_comp);
            _type -= 2;
        }
        if (_type >= 1 ) {
            address _vote = abstains[_comp];
            IVote(_vote).returnToken(_comp);
        }

        uint256 _balance = IERC20(_comp).balanceOf(address(this));
        IERC20(_comp).safeTransfer(controller, _balance);
        IController(controller).depositVote(_comp, _balance);
    }

    function vote(address _comp, uint256 _proposalId) public {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        require(proposalIds[_comp] == _proposalId, "!proposalId");
        uint8 _type = types[_comp];
        require(_type > 0, "!type");

        proposalIds[_comp] = 0;
        types[_comp] = 0;

        if (_type >= 4 ) {
            address _vote = againsts[_comp];
            IVote(_vote).vote(_comp, _proposalId);
            _type -= 4;
        }
        if (_type >= 2 ) {
            address _vote = fors[_comp];
            IVote(_vote).vote(_comp, _proposalId);
            _type -= 2;
        }
        if (_type >= 1 ) {
            address _vote = abstains[_comp];
            IVote(_vote).vote(_comp, _proposalId);
        }
    }

    function assets(address _token) public view returns (uint256) {
        return IController(controller).assets(_token);
    }

    function sweep(address _token) public {
        require(msg.sender == governance, "!governance");
        require(fors[_token] == address(0), "!address(0)");

        uint256 _bal = IERC20(_token).balanceOf(address(this));
        address _rewards = IController(controller).rewards();
        IERC20(_token).safeTransfer(_rewards, _bal);
    }

    function setProposalId(address _comp, uint256 _proposalId) public {
        require(msg.sender == governance, "!governance");
        proposalIds[_comp] == _proposalId;
    }

    function setType(address _comp, uint8 _type) public {
        require(msg.sender == governance, "!governance");
        types[_comp] = _type;
    }

    function prepareVoteByAdmin(address _comp, uint256 _proposalId, uint256 _against, uint256 _for, uint256 _abstain) public {
        require(msg.sender == governance, "!governance");

        uint256 _amount = _for.add(_against).add(_abstain);
        IController(controller).withdrawVote(_comp, _amount);

        if (_against > 0 ) {
            address _vote = againsts[_comp];
            _tranferVote(_comp, _vote, _against);
        }
        if (_for > 0 ) {
            address _vote = fors[_comp];
            _tranferVote(_comp, _vote, _for);
        }
        if (_abstain > 0) {
            address _vote = abstains[_comp];
            _tranferVote(_comp, _vote, _abstain);
        }
    }

    function returnTokenByAdmin(address _comp) public {
        require(msg.sender == governance, "!governance");

        address _vote = againsts[_comp];
        IVote(_vote).returnToken(_comp);

        _vote = fors[_comp];
        IVote(_vote).returnToken(_comp);

        _vote = abstains[_comp];
        IVote(_vote).returnToken(_comp);

        uint256 _balance = IERC20(_comp).balanceOf(address(this));
        IERC20(_comp).safeTransfer(controller, _balance);
        IController(controller).depositVote(_comp, _balance);
    }

    function voteByAdmin(address _comp, uint256 _proposalId) public {
        require(msg.sender == governance, "!governance");

        address _vote = againsts[_comp];
        IVote(_vote).vote(_comp, _proposalId);

        _vote = fors[_comp];
        IVote(_vote).vote(_comp, _proposalId);

        _vote = abstains[_comp];
        IVote(_vote).vote(_comp, _proposalId);
    }
}
