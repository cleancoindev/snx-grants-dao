pragma solidity 0.5.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract GrantsDAO {

  using SafeMath for uint256;

  uint256 public constant SUBMISSION_PHASE = 2 days;
  uint256 public constant VOTING_PHASE = 9 days; // for 7 days after the submission phase
  uint256 public toPass;
  uint256 public counter = 1;
  uint256 public members;
  uint256 public locked;

  IERC20 public SNX;

  struct Proposal {
    bool teamApproval;
    address receiver;
    uint256 amount;
    uint256 createdAt;
    uint256 approvals;
    mapping(address => bool) voted;
  }

  mapping(uint256 => Proposal) public proposals;
  mapping(address => bool) public teamMembers;
  mapping(address => bool) public communityMembers;

  event NewProposal(address receiver, uint256 amount, uint256 proposalNumber);
  event VoteProposal(uint256 proposal, address member, bool vote);
  event ExecuteProposal(address receiver, uint256 amount);
  event DeleteProposal(uint256 proposalNumber);

  constructor(
    address _snx,
    address[] memory _teamMembers,
    address[] memory _communityMembers,
    uint256 _toPass
  ) public {
    require(_teamMembers.length > 0, "Need at least one teamMember");
    require(_toPass > _communityMembers.length, "Need higher value for toPass");
    for (uint i = 0; i < _teamMembers.length; i++) {
      teamMembers[_teamMembers[i]] = true;
      members++;
    }
    for (uint i = 0; i < _communityMembers.length; i++) {
      communityMembers[_communityMembers[i]] = true;
      members++;
    }

    require(_toPass <= members, "Not enough members to pass votes");
    toPass = _toPass;
    SNX = IERC20(_snx);
  }

  function createProposal(
    address _receiver,
    uint256 _amount
  ) external onlyProposer() {
    require(_amount > 0, "Amount must be greater than 0");
    require(_receiver != address(0), "Receiver cannot be zero address");
    uint256 available = SNX.balanceOf(address(this)).sub(locked);
    require(_amount <= available, "Invalid funds on DAO");
    proposals[counter] = Proposal(false, _receiver, _amount, block.timestamp, 1);
    locked = locked.add(_amount);
    proposals[counter].voted[msg.sender] = true;
    emit NewProposal(_receiver, _amount, counter);
    counter++;
  }

  function voteProposal(uint256 _proposal, bool _vote) external onlyProposer() isValidProposal(_proposal) {
    require(!proposals[_proposal].voted[msg.sender], "Already voted");
    proposals[_proposal].voted[msg.sender] = true;
    if (_vote) {
      if (teamMembers[msg.sender]) {
        proposals[_proposal].teamApproval = true;
      }
      proposals[_proposal].approvals++;
      // Only execute if enough approvals AND the proposal has at least one teamApproval
      if (proposals[_proposal].approvals >= toPass && proposals[_proposal].teamApproval) {
        _executeProposal(_proposal);
      }
    } else {
      // Allows a team member to automatically kill a proposal
      if (teamMembers[msg.sender]) {
        _deleteProposal(_proposal);
      }
    }

    emit VoteProposal(_proposal, msg.sender, _vote);
  }

  function deleteProposal(uint256 _proposal) external onlyProposer() isExpiredProposal(_proposal) {
    _deleteProposal(_proposal);
  }

  function voted(address _member, uint256 _proposal) external view returns (bool) {
    return proposals[_proposal].voted[_member];
  }

  function _deleteProposal(uint256 _proposal) private {
    locked = locked.sub(proposals[_proposal].amount);
    delete proposals[_proposal];
    emit DeleteProposal(_proposal);
  }

  function _executeProposal(uint256 _proposal) private {
    Proposal memory proposal = proposals[_proposal];
    delete proposals[_proposal];
    assert(SNX.transfer(proposal.receiver, proposal.amount));
    emit ExecuteProposal(proposal.receiver, proposal.amount);
  }

  modifier isExpiredProposal(uint256 _proposal) {
    require(block.timestamp > proposals[_proposal].createdAt + VOTING_PHASE, "Proposal not expired");
    _;
  }

  modifier isValidProposal(uint256 _proposal) {
    uint256 createdAt = proposals[_proposal].createdAt;
    require(createdAt <= block.timestamp - SUBMISSION_PHASE, "Proposal in submission phase");
    require(block.timestamp <= createdAt + VOTING_PHASE, "Proposal not in voting phase");
    _;
  }

  modifier onlyProposer() {
    require(
      teamMembers[msg.sender] ||
      communityMembers[msg.sender],
      "Not proposer"
    );
    _;
  }
}
