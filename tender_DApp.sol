// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DecentralizedTender
 * @notice Procurement tender system with bid placement and community voting.
 *
 * VOTING MODEL (auction-style):
 *  - After bidding closes (deadline passed), a voting window opens.
 *  - Every approved vendor can cast ONE vote per tender for any bidder.
 *  - Vendors CANNOT vote for themselves.
 *  - Voting window = votingDuration minutes set at tender creation.
 *  - Once voting closes, the bid with the most votes wins.
 *    Tie-breaking: highest bid amount among tied candidates.
 *  - Admin can also finalize early via endTender().
 */
contract DecentralizedTender {

    // ─────────────────────────────────────
    // ADMIN + REGISTRATION
    // ─────────────────────────────────────
    address public owner;

    enum RegStatus { None, Pending, Approved, Rejected }

    struct UserProfile {
        string   fullName;
        string   organization;
        string   email;
        string   phone;
        string   role;
        RegStatus status;
        uint     requestedAt;
        uint     reviewedAt;
    }

    mapping(address => UserProfile) public profiles;
    address[] public pendingUsers;

    event RegistrationRequested(address indexed user, string role);
    event RegistrationApproved(address indexed user);
    event RegistrationRejected(address indexed user, string reason);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only admin");
        _;
    }

    modifier onlyApproved() {
        require(profiles[msg.sender].status == RegStatus.Approved, "Not approved");
        _;
    }

    // ─────────────────────────────────────
    // TENDER + BID + VOTE
    // ─────────────────────────────────────
    uint public tenderCount;

    struct Tender {
        uint      id;
        string    title;
        string    description;
        uint      biddingDeadline;   // bidding closes at this timestamp
        uint      votingDeadline;    // voting closes at this timestamp
        address   creator;
        uint      highestBid;
        address   highestBidder;
        bool      ended;
        address[] bidders;
        // voting
        uint      totalVotes;
        address   winner;            // set when finalized
    }

    // tenders[id] → Tender
    mapping(uint => Tender) public tenders;

    // bids[tenderId][bidderAddr] = amount
    mapping(uint => mapping(address => uint)) public bids;

    // votes[tenderId][voterAddr] = candidateAddr  (zero = not voted)
    mapping(uint => mapping(address => address)) public votes;

    // voteCount[tenderId][candidateAddr] = number of votes received
    mapping(uint => mapping(address => uint)) public voteCount;

    // ─── Events ───────────────────────────
    event TenderCreated (uint id, string title, uint biddingDeadline, uint votingDeadline);
    event BidPlaced     (uint tenderId, address bidder, uint amount);
    event VoteCast      (uint tenderId, address voter,  address candidate);
    event TenderFinalized(uint tenderId, address winner, uint winningBid, uint winningVotes);

    // ─────────────────────────────────────
    constructor() {
        owner = msg.sender;
        profiles[msg.sender] = UserProfile({
            fullName:    "System Admin",
            organization:"Central Authority",
            email:       "admin@tender.core",
            phone:       "000",
            role:        "Admin",
            status:      RegStatus.Approved,
            requestedAt: block.timestamp,
            reviewedAt:  block.timestamp
        });
    }

    // ─────────────────────────────────────
    // REGISTRATION
    // ─────────────────────────────────────
    function requestRegistration(
        string memory _fullName,
        string memory _organization,
        string memory _email,
        string memory _phone
    ) public {
        require(
            profiles[msg.sender].status == RegStatus.None ||
            profiles[msg.sender].status == RegStatus.Rejected,
            "Status already active"
        );
        profiles[msg.sender] = UserProfile({
            fullName:    _fullName,
            organization:_organization,
            email:       _email,
            phone:       _phone,
            role:        "Vendor",
            status:      RegStatus.Pending,
            requestedAt: block.timestamp,
            reviewedAt:  0
        });
        pendingUsers.push(msg.sender);
        emit RegistrationRequested(msg.sender, "Vendor");
    }

    function approveUser(address user) public onlyOwner {
        require(profiles[user].status == RegStatus.Pending, "Not pending");
        profiles[user].status    = RegStatus.Approved;
        profiles[user].reviewedAt = block.timestamp;
        emit RegistrationApproved(user);
    }

    function rejectUser(address user, string memory reason) public onlyOwner {
        require(profiles[user].status == RegStatus.Pending, "Not pending");
        profiles[user].status    = RegStatus.Rejected;
        profiles[user].reviewedAt = block.timestamp;
        emit RegistrationRejected(user, reason);
    }

    function getPendingUsers() public view returns (address[] memory) {
        return pendingUsers;
    }

    function getProfile(address user) public view returns (
        string memory, string memory, string memory,
        string memory, string memory, uint8, uint256, uint256
    ) {
        UserProfile storage p = profiles[user];
        return (p.fullName, p.organization, p.email, p.phone, p.role,
                uint8(p.status), p.requestedAt, p.reviewedAt);
    }

    // ─────────────────────────────────────
    // TENDER CREATION
    // ─────────────────────────────────────
    /**
     * @param _title             Tender title
     * @param _description       Scope of work
     * @param _biddingMinutes    How long bidding is open (minutes)
     * @param _votingMinutes     How long voting window lasts after bidding closes (minutes)
     */
    function createTender(
        string memory _title,
        string memory _description,
        uint _biddingMinutes,
        uint _votingMinutes
    ) public onlyOwner {
        require(_biddingMinutes > 0, "Bidding duration must be > 0");
        require(_votingMinutes  > 0, "Voting duration must be > 0");

        tenderCount++;
        Tender storage t = tenders[tenderCount];
        t.id              = tenderCount;
        t.title           = _title;
        t.description     = _description;
        t.biddingDeadline = block.timestamp + (_biddingMinutes * 1 minutes);
        t.votingDeadline  = t.biddingDeadline + (_votingMinutes * 1 minutes);
        t.creator         = msg.sender;
        t.ended           = false;

        emit TenderCreated(tenderCount, _title, t.biddingDeadline, t.votingDeadline);
    }

    // ─────────────────────────────────────
    // BID PLACEMENT
    // ─────────────────────────────────────
    function placeBid(uint _tenderId, uint _amount)
        public
        validTender(_tenderId)
        onlyApproved
    {
        Tender storage t = tenders[_tenderId];
        require(block.timestamp < t.biddingDeadline, "Bidding closed");
        require(!t.ended, "Tender ended");
        require(_amount > 0, "Bid must be > 0");

        if (bids[_tenderId][msg.sender] == 0) {
            t.bidders.push(msg.sender);
        }
        bids[_tenderId][msg.sender] = _amount;

        if (_amount > t.highestBid) {
            t.highestBid    = _amount;
            t.highestBidder = msg.sender;
        }
        emit BidPlaced(_tenderId, msg.sender, _amount);
    }

    // ─────────────────────────────────────
    // VOTING
    // ─────────────────────────────────────
    /**
     * @notice Cast a vote for a bidder on a tender.
     *         Only callable during the voting window (after bidding closes).
     *         Approved vendors can vote; they cannot vote for themselves.
     *         Each voter gets exactly one vote per tender (no re-vote).
     */
    function castVote(uint _tenderId, address _candidate)
        public
        validTender(_tenderId)
        onlyApproved
    {
        Tender storage t = tenders[_tenderId];
        require(block.timestamp >= t.biddingDeadline,  "Bidding still open");
        require(block.timestamp <  t.votingDeadline,   "Voting window closed");
        require(!t.ended,                              "Tender already finalized");
        require(_candidate != msg.sender,              "Cannot vote for yourself");
        require(bids[_tenderId][_candidate] > 0,       "Candidate has no bid");
        require(votes[_tenderId][msg.sender] == address(0), "Already voted");

        votes[_tenderId][msg.sender] = _candidate;
        voteCount[_tenderId][_candidate]++;
        t.totalVotes++;

        emit VoteCast(_tenderId, msg.sender, _candidate);
    }

    /**
     * @notice Finalize a tender once the voting window has closed.
     *         Determines winner by highest vote count; ties broken by highest bid.
     *         Can only be called by admin OR after voting deadline has passed.
     */
    function finalizeTender(uint _tenderId)
        public
        validTender(_tenderId)
    {
        Tender storage t = tenders[_tenderId];
        require(!t.ended, "Already finalized");
        require(block.timestamp >= t.votingDeadline || msg.sender == owner, "Voting still open");
        require(t.bidders.length > 0, "No bids placed");

        // Find winner: most votes, tie-break by highest bid
        address bestAddr  = address(0);
        uint    bestVotes = 0;
        uint    bestBid   = 0;

        for (uint i = 0; i < t.bidders.length; i++) {
            address b = t.bidders[i];
            uint    v = voteCount[_tenderId][b];
            uint    a = bids[_tenderId][b];

            if (v > bestVotes || (v == bestVotes && a > bestBid)) {
                bestVotes = v;
                bestBid   = a;
                bestAddr  = b;
            }
        }

        t.ended    = true;
        t.winner   = bestAddr;
        // Update highestBidder to reflect vote winner
        t.highestBidder = bestAddr;
        t.highestBid    = bids[_tenderId][bestAddr];

        emit TenderFinalized(_tenderId, bestAddr, t.highestBid, bestVotes);
    }

    // ─────────────────────────────────────
    // VIEW HELPERS
    // ─────────────────────────────────────
    function getBidders(uint _tenderId) public view returns (address[] memory) {
        return tenders[_tenderId].bidders;
    }

    /// @notice Returns the vote count for every bidder on a tender.
    function getVoteCounts(uint _tenderId)
        public view
        returns (address[] memory bidderList, uint[] memory voteCounts)
    {
        address[] memory bdrs = tenders[_tenderId].bidders;
        uint[] memory counts  = new uint[](bdrs.length);
        for (uint i = 0; i < bdrs.length; i++) {
            counts[i] = voteCount[_tenderId][bdrs[i]];
        }
        return (bdrs, counts);
    }

    /// @notice Returns the candidate this voter voted for (address(0) if not voted).
    function getMyVote(uint _tenderId, address voter) public view returns (address) {
        return votes[_tenderId][voter];
    }

    // ─────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────
    modifier validTender(uint _id) {
        require(_id > 0 && _id <= tenderCount, "Invalid tender");
        _;
    }
}
