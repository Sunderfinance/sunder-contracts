// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/IERC20.sol";
import "@openzeppelinV3/contracts/cryptography/MerkleProof.sol";
import "@openzeppelinV3/contracts/math/SafeMath.sol";

contract MerkleDistributor {
    using SafeMath for uint256;

    address public governance;
    address public pendingGovernance;
    address public guardian;
    uint256 public effectTime;

    address public token;
    bytes32 public merkleRoot;
    uint256 public nonce;
    bool public lock;

    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;

    event Claimed(uint256 index, address account, uint256 amount);

    constructor(address token_) public {
        governance = msg.sender;
        guardian = msg.sender;
        token = token_;
        effectTime = block.timestamp + 60 days;
    }

    function setGuardian(address guardian_) external {
        require(msg.sender == guardian, "!guardian");
        guardian = guardian_;
    }
    function addGuardianTime(uint256 addTime_) external {
        require(msg.sender == guardian || msg.sender == governance, "!guardian");
        effectTime = effectTime.add(addTime_);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = msg.sender;
        pendingGovernance = address(0);
    }
    function setPendingGovernance(address pendingGovernance_) external {
        require(msg.sender == governance, "!governance");
        pendingGovernance = pendingGovernance_;
    }

    function setToken(address token_) external {
        require(msg.sender == governance, "!governance");
        token = token_;
    }

    function setMerkleRoot(bytes32 merkleRoot_) external {
        require(msg.sender == governance, "!governance");
        merkleRoot = merkleRoot_;
        nonce++;
    }

    function setNonce(uint256 nonce_) external {
        require(msg.sender == governance, "!governance");
        nonce = nonce_;
    }

    function locking() external {
        require(msg.sender == governance, "!governance");
        lock = true;
    }
    function unlocking() external {
        require(msg.sender == governance, "!governance");
        lock = false;
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[nonce][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[nonce][claimedWordIndex] = claimedBitMap[nonce][claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external {
        require(!lock, "locking");
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        require(IERC20(token).transfer(account, amount), 'MerkleDistributor: Transfer failed.');

        emit Claimed(index, account, amount);
    }

    function sweepGuardian(address token_) external {
        require(msg.sender == guardian, "!guardian");
        require(block.timestamp > effectTime, "!effectTime");

        uint256 _balance = IERC20(token_).balanceOf(address(this));
        IERC20(token_).transfer(governance, _balance);
    }
}
