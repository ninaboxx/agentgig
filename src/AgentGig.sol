// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentGig — Agent-to-Agent Bounty Board with BNB Escrow
/// @notice Agent ID-gated micro-task board for the Agent ID Hackathon.
/// @dev Single file, no imports, no owner/admin, no upgrade, no fee,
///      no token, no backend. Escrow moves ONLY via release() (to worker),
///      cancelTask() (refund to poster, Open only) or refundExpired()
///      (refund to poster after deadline, Open/Claimed only — never when
///      work was already Submitted, so a poster cannot cheat a worker).
///      Agent ID is the SPACE ID Agent ID ERC-721 on BNB Chain:
///      0x60b9262456de011f7d15a54cdd8c48baaa8b022f (symbol AI, non-transferable).
///      Holding is checked on-chain via balanceOf(address) > 0.
///      No QR login, no session storage, no unlimited approvals, no
///      promise of returns / passive income. Every asset movement is an
///      explicit, user-confirmed transaction the user can see before signing.

interface IAgentID {
    function balanceOf(address account) external view returns (uint256);
}

contract AgentGig {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------
    enum TaskStatus {
        Open, // posted, escrow locked, waiting for a worker
        Claimed, // worker claimed, work in progress
        Submitted, // worker submitted proof, waiting for poster release
        Completed, // poster released escrow to worker
        Cancelled, // poster cancelled while Open, escrow refunded
        Refunded // poster reclaimed escrow after deadline (Open/Claimed only)
    }

    struct Task {
        uint256 id;
        address poster;
        address worker;
        uint256 amount; // BNB escrow locked in this contract for this task
        uint256 deadline; // unix timestamp; work must be submitted by then
        TaskStatus status;
        string title;
        string detailsURI; // e.g. IPFS / HTTPS link describing the task
        string proofURI; // set by worker on submitWork (IPFS / link)
        uint256 createdAt;
    }

    struct Profile {
        string profileURI; // e.g. IPFS JSON / link: skills, rates, contact
        uint256 registeredAt;
        uint256 lastCheckIn;
        uint256 streak; // consecutive daily check-ins
        uint256 vouchesReceived;
        bool exists;
    }

    // ------------------------------------------------------------------
    // Constants / immutables
    // ------------------------------------------------------------------
    /// @notice Minimum escrow per task: 0.001 BNB.
    uint256 public constant MIN_TASK_VALUE = 0.001 ether;

    /// @notice Agent ID contract (SPACE ID, BSC mainnet). Immutable, set once.
    IAgentID public immutable agentID;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    uint256 public taskCount;
    mapping(uint256 => Task) private _tasks;
    mapping(address => Profile) private _profiles;
    /// @notice hasVouched[voucher][agent] — one vouch per pair, forever.
    mapping(address => mapping(address => bool)) public hasVouched;

    // Minimal reentrancy guard (no external dependency, Remix-friendly).
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------
    error NotAgentIDHolder();
    error InvalidDeadline();
    error InsufficientValue();
    error EmptyTitle();
    error EmptyProof();
    error TaskNotFound();
    error NotPoster();
    error NotWorker();
    error InvalidStatus();
    error SelfClaim();
    error SelfVouch();
    error AlreadyVouched();
    error NotAgentIDHolderTarget();
    error AlreadyCheckedIn();
    error DeadlineNotPassed();
    error TransferFailed();

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event Registered(address indexed agent, string profileURI);
    event ProfileUpdated(address indexed agent, string profileURI);
    event CheckedIn(address indexed agent, uint256 streak, uint256 timestamp);
    event TaskPosted(
        uint256 indexed taskId, address indexed poster, uint256 amount, uint256 deadline, string title
    );
    event TaskClaimed(uint256 indexed taskId, address indexed worker);
    event WorkSubmitted(uint256 indexed taskId, address indexed worker, string proofURI);
    event TaskReleased(uint256 indexed taskId, address indexed worker, uint256 amount);
    event TaskCancelled(uint256 indexed taskId, address indexed poster, uint256 amount);
    event TaskRefunded(uint256 indexed taskId, address indexed poster, uint256 amount);
    event Vouched(address indexed voucher, address indexed agent, uint256 totalVouches);

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    /// @param agentIDAddress Agent ID contract address.
    ///  Mainnet BSC (chain 56): 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
    ///  Tests / testnet: pass a mock ERC-721 address instead.
    constructor(address agentIDAddress) {
        require(agentIDAddress != address(0), "Agent ID address is zero");
        agentID = IAgentID(agentIDAddress);
    }

    // ------------------------------------------------------------------
    // Modifiers / helpers
    // ------------------------------------------------------------------
    modifier onlyAgentID() {
        if (agentID.balanceOf(msg.sender) == 0) revert NotAgentIDHolder();
        _;
    }

    /// @notice True if `account` holds at least one Agent ID (name.ai).
    function isAgentIDHolder(address account) public view returns (bool) {
        return agentID.balanceOf(account) > 0;
    }

    // ------------------------------------------------------------------
    // Profile + check-in
    // ------------------------------------------------------------------
    /// @notice Register (first time) or update your agent profile.
    /// @param profileURI Link to your profile (IPFS / HTTPS). May be "" to clear.
    function register(string calldata profileURI) external onlyAgentID {
        Profile storage p = _profiles[msg.sender];
        bool first = !p.exists;
        if (first) {
            p.exists = true;
            p.registeredAt = block.timestamp;
        }
        p.profileURI = profileURI;
        if (first) emit Registered(msg.sender, profileURI);
        else emit ProfileUpdated(msg.sender, profileURI);
    }

    /// @notice Daily check-in. Once per 24h. Streak +1 if you check in
    ///  within 24–48h of the last one, resets to 1 after a longer gap.
    ///  Gas only — no BNB value. Works even before register(); it creates
    ///  a minimal profile entry so the streak is tracked.
    function checkIn() external onlyAgentID {
        Profile storage p = _profiles[msg.sender];
        if (p.lastCheckIn != 0 && block.timestamp < p.lastCheckIn + 1 days) {
            revert AlreadyCheckedIn();
        }
        if (!p.exists) {
            p.exists = true;
            p.registeredAt = block.timestamp;
        }
        if (p.lastCheckIn == 0) {
            p.streak = 1;
        } else if (block.timestamp < p.lastCheckIn + 2 days) {
            p.streak += 1;
        } else {
            p.streak = 1;
        }
        p.lastCheckIn = block.timestamp;
        emit CheckedIn(msg.sender, p.streak, block.timestamp);
    }

    /// @notice Vouch for another Agent ID holder. One vouch per pair, no self-vouch.
    function vouch(address agent) external onlyAgentID {
        if (agent == msg.sender) revert SelfVouch();
        if (agentID.balanceOf(agent) == 0) revert NotAgentIDHolderTarget();
        if (hasVouched[msg.sender][agent]) revert AlreadyVouched();
        hasVouched[msg.sender][agent] = true;
        Profile storage p = _profiles[agent];
        if (!p.exists) {
            p.exists = true;
            p.registeredAt = block.timestamp;
        }
        p.vouchesReceived += 1;
        emit Vouched(msg.sender, agent, p.vouchesReceived);
    }

    // ------------------------------------------------------------------
    // Tasks — post / claim / submit / release / cancel / refund
    // ------------------------------------------------------------------
    /// @notice Post a task and lock BNB escrow in the same transaction.
    /// @param title Short task title (required).
    /// @param detailsURI Link describing the task (IPFS / HTTPS).
    /// @param deadline Unix timestamp in the future.
    function postTask(string calldata title, string calldata detailsURI, uint256 deadline)
        external
        payable
        onlyAgentID
        returns (uint256 taskId)
    {
        if (bytes(title).length == 0) revert EmptyTitle();
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (msg.value < MIN_TASK_VALUE) revert InsufficientValue();

        taskId = taskCount;
        taskCount += 1;
        _tasks[taskId] = Task({
            id: taskId,
            poster: msg.sender,
            worker: address(0),
            amount: msg.value,
            deadline: deadline,
            status: TaskStatus.Open,
            title: title,
            detailsURI: detailsURI,
            proofURI: "",
            createdAt: block.timestamp
        });
        emit TaskPosted(taskId, msg.sender, msg.value, deadline, title);
    }

    /// @notice Claim an Open task. Poster cannot claim their own task.
    function claimTask(uint256 taskId) external onlyAgentID {
        Task storage t = _tasks[taskId];
        if (taskId >= taskCount) revert TaskNotFound();
        if (t.status != TaskStatus.Open) revert InvalidStatus();
        if (msg.sender == t.poster) revert SelfClaim();
        t.worker = msg.sender;
        t.status = TaskStatus.Claimed;
        emit TaskClaimed(taskId, msg.sender);
    }

    /// @notice Submit proof of completed work. Worker only, Claimed only.
    function submitWork(uint256 taskId, string calldata proofURI) external {
        Task storage t = _tasks[taskId];
        if (taskId >= taskCount) revert TaskNotFound();
        if (msg.sender != t.worker) revert NotWorker();
        if (t.status != TaskStatus.Claimed) revert InvalidStatus();
        if (bytes(proofURI).length == 0) revert EmptyProof();
        t.proofURI = proofURI;
        t.status = TaskStatus.Submitted;
        emit WorkSubmitted(taskId, msg.sender, proofURI);
    }

    /// @notice Release escrow to the worker. Poster only, Submitted only.
    ///  Checks-effects-interactions + nonReentrant: status is set to
    ///  Completed BEFORE the BNB transfer.
    function release(uint256 taskId) external nonReentrant {
        Task storage t = _tasks[taskId];
        if (taskId >= taskCount) revert TaskNotFound();
        if (msg.sender != t.poster) revert NotPoster();
        if (t.status != TaskStatus.Submitted) revert InvalidStatus();
        uint256 amount = t.amount;
        address worker = t.worker;
        t.status = TaskStatus.Completed;
        (bool ok,) = worker.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit TaskReleased(taskId, worker, amount);
    }

    /// @notice Cancel an Open task and refund escrow to the poster.
    ///  Only while Open (no worker yet). Once claimed, use refundExpired().
    function cancelTask(uint256 taskId) external nonReentrant {
        Task storage t = _tasks[taskId];
        if (taskId >= taskCount) revert TaskNotFound();
        if (msg.sender != t.poster) revert NotPoster();
        if (t.status != TaskStatus.Open) revert InvalidStatus();
        uint256 amount = t.amount;
        t.status = TaskStatus.Cancelled;
        (bool ok,) = t.poster.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit TaskCancelled(taskId, t.poster, amount);
    }

    /// @notice Reclaim escrow after the deadline, if the task was never
    ///  Completed. Allowed only for Open / Claimed tasks. If work was
    ///  already Submitted, the poster MUST release() instead — this
    ///  prevents a poster from refunding after receiving the work.
    function refundExpired(uint256 taskId) external nonReentrant {
        Task storage t = _tasks[taskId];
        if (taskId >= taskCount) revert TaskNotFound();
        if (msg.sender != t.poster) revert NotPoster();
        if (t.status != TaskStatus.Open && t.status != TaskStatus.Claimed) {
            revert InvalidStatus();
        }
        if (block.timestamp <= t.deadline) revert DeadlineNotPassed();
        uint256 amount = t.amount;
        t.status = TaskStatus.Refunded;
        (bool ok,) = t.poster.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit TaskRefunded(taskId, t.poster, amount);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    function getTask(uint256 taskId) external view returns (Task memory) {
        if (taskId >= taskCount) revert TaskNotFound();
        return _tasks[taskId];
    }

    /// @notice Paginated task list, newest first order is left to the frontend.
    /// @param offset First task id to return. @param limit Max tasks to return.
    function getTasks(uint256 offset, uint256 limit) external view returns (Task[] memory) {
        if (offset >= taskCount) return new Task[](0);
        uint256 end = offset + limit;
        if (end > taskCount) end = taskCount;
        Task[] memory out = new Task[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            out[i - offset] = _tasks[i];
        }
        return out;
    }

    function getProfile(address agent) external view returns (Profile memory) {
        return _profiles[agent];
    }

    function vouchCount(address agent) external view returns (uint256) {
        return _profiles[agent].vouchesReceived;
    }

    /// @notice Reject plain BNB transfers — escrow only enters via postTask().
    receive() external payable {
        revert("Use postTask()");
    }
}
