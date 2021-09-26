// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/voter/IVoteController.sol";
import "../../interfaces/compound/IComp.sol";
import "../../interfaces/compound/IGovernorDelegate.sol";

contract Vote {
    using SafeERC20 for IERC20;

    address public governance;
    address public pendingGovernance;
    address public voteController;
    uint8   public support;

    constructor(address _voteController, uint8 _support) public {
        governance = msg.sender;
        voteController = _voteController;
        support = _support;
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
    function setVoteController(address _voteController) external {
        require(msg.sender == governance, "!governance");
        voteController = _voteController;
    }

    function delegate(address _token) external {
        IComp(_token).delegate(address(this));
    }

    function returnToken(address _token, address _receiver) external returns (uint256 _amount) {
        require(msg.sender == voteController || msg.sender == governance, "!voteController");
        _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function castVote(address _token, uint256 _proposalId) external {
        require(msg.sender == voteController || msg.sender == governance, "!voteController");
        address governor = IVoteController(voteController).governors(_token);
        require(governor != address(0), "!governor");
        IGovernorDelegate(governor).castVote(_proposalId, support);
    }

    function propose(address _token, address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) external returns (uint256){
        require(msg.sender == voteController || msg.sender == governance, "!voteController");
        address governor = IVoteController(voteController).governors(_token);
        require(governor != address(0), "!governor");
        return IGovernorDelegate(governor).propose(targets, values, signatures, calldatas, description);
    }

    function proposalThreshold(address _token) public view returns (uint256){
        address governor = IVoteController(voteController).governors(_token);
        require(governor != address(0), "!governor");
        return IGovernorDelegate(governor).proposalThreshold();
    }

    function state(address _token, uint256 _proposalId) public view returns (uint8){
        address governor = IVoteController(voteController).governors(_token);
        require(governor != address(0), "!governor");
        return IGovernorDelegate(governor).state(_proposalId);
    }

    function proposals(address _token, uint256 _proposalId) public view returns (uint256 _id, address _proposer,
        uint256 _eta, uint256 _startBlock, uint256 _endBlock, uint256 _forVotes, uint256 _againstVotes,
        uint256 _abstainVotes, bool _canceled, bool _executed){
        address governor = IVoteController(voteController).governors(_token);
        require(governor != address(0), "!governor");
        return IGovernorDelegate(governor).proposals(_proposalId);
    }
}
