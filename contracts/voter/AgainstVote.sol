// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/voter/IVoteController.sol";
import "../../interfaces/compound/IComp.sol";
import "../../interfaces/compound/IGovernorDelegate.sol";

contract AgainstVote {
    using SafeERC20 for IERC20;

    address public governance;
    address public voteController;

    constructor(address _voteController) public {
        governance = msg.sender;
        voteController = _voteController;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setVoteController(address _voteController) public {
        require(msg.sender == governance, "!governance");
        voteController = _voteController;
    }

    function returnToken(address _comp) public {
        require(msg.sender == voteController || msg.sender == governance, "!voteController");
        uint256 _balance = IERC20(_comp).balanceOf(address(this));
        IERC20(_comp).safeTransfer(voteController, _balance);
    }

    function delegate(address _comp) public {
        IComp(_comp).delegate(address(this));
    }

    function vote(address _comp, uint256 _proposalId) public {
        require(msg.sender == voteController || msg.sender == governance, "!voteController");
        address governor = IVoteController(voteController).governors(_comp);
        require(governor != address(0), "!governor");
        IGovernorDelegate(governor).castVote(_proposalId, 0);
    }

    function proposals(address _comp, uint256 _proposalId) external view returns (uint256 _id, address _proposer,
        uint256 _eta, uint256 _startBlock, uint256 _endBlock, uint256 _forVotes, uint256 _againstVotes,
        uint256 _abstainVotes, bool _canceled, bool _executed){
        address governor = IVoteController(voteController).governors(_comp);
        require(governor != address(0), "!governor");
        return IGovernorDelegate(governor).proposals(_proposalId);
    }

    function state(address _comp, uint256 _proposalId) external view returns (uint8){
        address governor = IVoteController(voteController).governors(_comp);
        require(governor != address(0), "!governor");
        return IGovernorDelegate(governor).state(_proposalId);
    }
}
