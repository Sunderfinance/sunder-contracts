// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

import "../../interfaces/yearn/IController.sol";
import "../../interfaces/voter/IVote.sol";

contract VoteController {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public controller;
    address public operator;

    mapping (address => address) public againsts;
    mapping (address => address) public fors;
    mapping (address => address) public abstains;
    mapping (address => address) public proposes;
    mapping (address => address) public governors;
    mapping (address => uint256) public proposalIds;
    mapping (address => uint256) public voteProposalIds;
    mapping (address => uint8) public types;

    constructor (address _controller, address _operator) public {
        governance = msg.sender;
        controller = _controller;
        operator =  _operator;
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
    function setOperator(address _operator) external {
        require(msg.sender == governance, "!governance");
        operator = _operator;
    }
    function setGovernor(address _comp, address _governor) external {
        require(msg.sender == governance, "!governance");
        governors[_comp] = _governor;
    }

    function setAgainst(address _comp, address _against) external {
        require(msg.sender == governance, "!governance");
        againsts[_comp] = _against;
    }
    function setFor(address _comp, address _for) external {
        require(msg.sender == governance, "!governance");
        fors[_comp] = _for;
    }
    function setAbstain(address _comp, address _abstain) external {
        require(msg.sender == governance, "!governance");
        abstains[_comp] = _abstain;
    }
    function setPropose(address _comp, address _propose) external {
        require(msg.sender == governance, "!governance");
        proposes[_comp] = _propose;
    }

    function prepareVote(address _comp, uint256 _proposalId, uint256 _against, uint256 _for, uint256 _abstain) external {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        require(proposalIds[_comp] == 0, "!proposalId");
        // require(types[_comp] == 0, "!types");
        uint256 _amount = _for.add(_against).add(_abstain);
        require(_amount > 0, "!_amount");

        IController(controller).withdrawVote(_comp, _amount);
        proposalIds[_comp] = _proposalId;

        uint8 _type = 0;
        if (_against > 0) {
            address _vote = againsts[_comp];
            _tranferVote(_comp, _vote, _against);
            _type += 4;
        }
        if (_for > 0) {
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

    function returnToken(address _comp, uint256 _proposalId) external {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        require(proposalIds[_comp] == _proposalId, "!proposalId");
        uint8 _type = types[_comp];
        require(_type > 0, "!type");

        proposalIds[_comp] = 0;
        voteProposalIds[_comp] = _proposalId;

        uint256 _totalAmount;
        if (_type >= 4) {
            address _vote = againsts[_comp];
            _totalAmount = IVote(_vote).returnToken(_comp, controller);
            _type -= 4;
        }
        if (_type >= 2) {
            address _vote = fors[_comp];
            uint256 _amount = IVote(_vote).returnToken(_comp, controller);
            _totalAmount = _totalAmount.add(_amount);
            _type -= 2;
        }
        if (_type >= 1) {
            address _vote = abstains[_comp];
            uint256 _amount = IVote(_vote).returnToken(_comp, controller);
            _totalAmount = _totalAmount.add(_amount);
        }

        IController(controller).depositVote(_comp, _totalAmount);
    }

    function castVote(address _comp, uint256 _proposalId) external {
        require(msg.sender == operator || msg.sender == governance, "!operator");
        require(voteProposalIds[_comp] == _proposalId, "!proposalId");
        uint8 _type = types[_comp];
        require(_type > 0, "!type");

        voteProposalIds[_comp] = 0;
        types[_comp] = 0;

        if (_type >= 4) {
            address _vote = againsts[_comp];
            IVote(_vote).castVote(_comp, _proposalId);
            _type -= 4;
        }
        if (_type >= 2) {
            address _vote = fors[_comp];
            IVote(_vote).castVote(_comp, _proposalId);
            _type -= 2;
        }
        if (_type >= 1) {
            address _vote = abstains[_comp];
            IVote(_vote).castVote(_comp, _proposalId);
        }
    }

    function totalAssets(address _token) external view returns (uint256) {
        return IController(controller).totalAssets(_token);
    }

    function state(address _comp, uint256 _proposalId) external view returns (uint8){
        address _vote = fors[_comp];
        return IVote(_vote).state(_comp, _proposalId);
    }

    function proposals(address _comp, uint256 _proposalId) external view returns (uint256 _id, address _proposer,
        uint256 _eta, uint256 _startBlock, uint256 _endBlock, uint256 _forVotes, uint256 _againstVotes, uint256 _abstainVotes, bool _canceled, bool _executed){
        address _vote = fors[_comp];
        return IVote(_vote).proposals(_comp, _proposalId);
    }

    function sweep(address _token) external {
        require(msg.sender == governance, "!governance");

        uint256 _balance = IERC20(_token).balanceOf(address(this));
        address _rewards = IController(controller).rewards();
        IERC20(_token).safeTransfer(_rewards, _balance);
    }

    function setProposalId(address _comp, uint256 _proposalId) external {
        require(msg.sender == governance, "!governance");
        proposalIds[_comp] = _proposalId;
    }

    function setType(address _comp, uint8 _type) external {
        require(msg.sender == governance, "!governance");
        types[_comp] = _type;
    }

    function prepareProposeByAdmin(address _comp) external {
        require(msg.sender == governance, "!governance");

        address _vote = proposes[_comp];
        uint256 _amount = IVote(_vote).proposalThreshold(_comp);
        IController(controller).withdrawVote(_comp, _amount);
        _tranferVote(_comp, _vote, _amount);
    }

    function proposeByAdmin(address _comp, address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) external returns (uint256) {
        require(msg.sender == governance, "!operator");

        address _vote = proposes[_comp];
        return IVote(_vote).propose(_comp, targets, values, signatures, calldatas, description);
    }

    function returnProposeByAdmin(address _comp) external {
        require(msg.sender == governance, "!operator");

        address _vote = proposes[_comp];
        uint256 _amount = IVote(_vote).returnToken(_comp, controller);
        IController(controller).depositVote(_comp, _amount);
    }

    function prepareVoteByAdmin(address _comp, uint256 _against, uint256 _for, uint256 _abstain) external {
        require(msg.sender == governance, "!governance");

        uint256 _amount = _for.add(_against).add(_abstain);
        IController(controller).withdrawVote(_comp, _amount);

        if (_against > 0) {
            address _vote = againsts[_comp];
            _tranferVote(_comp, _vote, _against);
        }
        if (_for > 0) {
            address _vote = fors[_comp];
            _tranferVote(_comp, _vote, _for);
        }
        if (_abstain > 0) {
            address _vote = abstains[_comp];
            _tranferVote(_comp, _vote, _abstain);
        }
    }

    function returnTokenByAdmin(address _comp) external {
        require(msg.sender == governance, "!governance");

        address _vote = againsts[_comp];
        uint256 _totalAmount = IVote(_vote).returnToken(_comp, controller);

        _vote = fors[_comp];
        uint256 _amount = IVote(_vote).returnToken(_comp, controller);
        _totalAmount = _totalAmount.add(_amount);

        _vote = abstains[_comp];
        _amount = IVote(_vote).returnToken(_comp, controller);
        _totalAmount = _totalAmount.add(_amount);

        IController(controller).depositVote(_comp, _totalAmount);
    }

    function voteByAdmin(address _comp, uint256 _proposalId) external {
        require(msg.sender == governance, "!governance");

        address _vote = againsts[_comp];
        IVote(_vote).castVote(_comp, _proposalId);

        _vote = fors[_comp];
        IVote(_vote).castVote(_comp, _proposalId);

        _vote = abstains[_comp];
        IVote(_vote).castVote(_comp, _proposalId);
    }
}
