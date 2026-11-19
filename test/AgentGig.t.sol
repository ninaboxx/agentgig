// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentGig.sol";
import "./MockAgentID.sol";

/// @notice Attacker contract that tries to re-enter release().
contract ReentrantWorker {
    AgentGig public gig;
    uint256 public taskId;
    uint256 public reenterCount;

    constructor(AgentGig _gig) {
        gig = _gig;
    }

    function setTask(uint256 _taskId) external {
        taskId = _taskId;
    }

    receive() external payable {
        // Try to call release() again while the first release is in flight.
        // Must fail: status is already Completed (checks-effects-interactions)
        // and/or the nonReentrant guard blocks it.
        if (reenterCount == 0) {
            reenterCount++;
            try gig.release(taskId) {} catch {}
        }
    }
}

contract AgentGigTest is Test {
    MockAgentID agentID;
    AgentGig gig;

    address poster = address(0x1001);
    address worker = address(0x1002);
    address stranger = address(0x1003); // no Agent ID
    address voucher = address(0x1004);

    uint256 constant VALUE = 0.01 ether;

    function setUp() public {
        agentID = new MockAgentID();
        gig = new AgentGig(address(agentID));
        agentID.mint(poster);
        agentID.mint(worker);
        agentID.mint(voucher);
        // stranger deliberately gets NO Agent ID
        vm.deal(poster, 10 ether);
        vm.deal(worker, 10 ether);
        vm.deal(voucher, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    // -- helpers -------------------------------------------------------
    function _postTask() internal returns (uint256) {
        vm.prank(poster);
        return gig.postTask{value: VALUE}("Translate README", "ipfs://details", block.timestamp + 7 days);
    }

    // -- happy paths ---------------------------------------------------
    function testRegisterAndUpdate() public {
        vm.prank(poster);
        gig.register("ipfs://profile-poster");
        AgentGig.Profile memory p = gig.getProfile(poster);
        assertTrue(p.exists);
        assertEq(p.profileURI, "ipfs://profile-poster");
        vm.prank(poster);
        gig.register("ipfs://profile-v2");
        assertEq(gig.getProfile(poster).profileURI, "ipfs://profile-v2");
    }

    function testRegisterRevertsForNonHolder() public {
        vm.prank(stranger);
        vm.expectRevert(AgentGig.NotAgentIDHolder.selector);
        gig.register("ipfs://x");
    }

    function testCheckInStreak() public {
        vm.prank(worker);
        gig.checkIn();
        assertEq(gig.getProfile(worker).streak, 1);
        // Same day: revert
        vm.prank(worker);
        vm.expectRevert(AgentGig.AlreadyCheckedIn.selector);
        gig.checkIn();
        // Next day: streak 2
        vm.warp(block.timestamp + 1 days);
        vm.prank(worker);
        gig.checkIn();
        assertEq(gig.getProfile(worker).streak, 2);
        // Gap > 2 days: streak resets to 1
        vm.warp(block.timestamp + 3 days);
        vm.prank(worker);
        gig.checkIn();
        assertEq(gig.getProfile(worker).streak, 1);
    }

    function testCheckInRevertsForNonHolder() public {
        vm.prank(stranger);
        vm.expectRevert(AgentGig.NotAgentIDHolder.selector);
        gig.checkIn();
    }

    function testFullTaskLifecycle() public {
        uint256 id = _postTask();
        assertEq(gig.taskCount(), 1);
        assertEq(address(gig).balance, VALUE);

        vm.prank(worker);
        gig.claimTask(id);
        assertEq(uint256(gig.getTask(id).status), uint256(AgentGig.TaskStatus.Claimed));

        vm.prank(worker);
        gig.submitWork(id, "ipfs://proof");
        assertEq(uint256(gig.getTask(id).status), uint256(AgentGig.TaskStatus.Submitted));

        uint256 before = worker.balance;
        vm.prank(poster);
        gig.release(id);
        assertEq(uint256(gig.getTask(id).status), uint256(AgentGig.TaskStatus.Completed));
        assertEq(worker.balance, before + VALUE);
        assertEq(address(gig).balance, 0);
    }

    function testCancelRefundsPoster() public {
        uint256 id = _postTask();
        uint256 before = poster.balance;
        vm.prank(poster);
        gig.cancelTask(id);
        assertEq(uint256(gig.getTask(id).status), uint256(AgentGig.TaskStatus.Cancelled));
        assertEq(poster.balance, before + VALUE);
    }

    function testRefundExpiredAfterDeadline() public {
        uint256 id = _postTask();
        vm.warp(block.timestamp + 8 days);
        uint256 before = poster.balance;
        vm.prank(poster);
        gig.refundExpired(id);
        assertEq(uint256(gig.getTask(id).status), uint256(AgentGig.TaskStatus.Refunded));
        assertEq(poster.balance, before + VALUE);
    }

    function testVouch() public {
        vm.prank(voucher);
        gig.vouch(worker);
        assertEq(gig.vouchCount(worker), 1);
        assertTrue(gig.hasVouched(voucher, worker));
    }

    function testGetTasksPagination() public {
        _postTask();
        _postTask();
        AgentGig.Task[] memory tasks = gig.getTasks(0, 10);
        assertEq(tasks.length, 2);
        assertEq(tasks[0].title, "Translate README");
    }

    function testIsAgentIDHolder() public {
        assertTrue(gig.isAgentIDHolder(poster));
        assertFalse(gig.isAgentIDHolder(stranger));
    }

    // -- reverts -------------------------------------------------------
    function testPostRevertsBelowMin() public {
        vm.prank(poster);
        vm.expectRevert(AgentGig.InsufficientValue.selector);
        gig.postTask{value: 0.0005 ether}("T", "ipfs://d", block.timestamp + 1 days);
    }

    function testPostRevertsPastDeadline() public {
        vm.prank(poster);
        vm.expectRevert(AgentGig.InvalidDeadline.selector);
        gig.postTask{value: VALUE}("T", "ipfs://d", block.timestamp);
    }

    function testPostRevertsForNonHolder() public {
        vm.prank(stranger);
        vm.expectRevert(AgentGig.NotAgentIDHolder.selector);
        gig.postTask{value: VALUE}("T", "ipfs://d", block.timestamp + 1 days);
    }

    function testClaimRevertsForPosterSelfClaim() public {
        uint256 id = _postTask();
        vm.prank(poster);
        vm.expectRevert(AgentGig.SelfClaim.selector);
        gig.claimTask(id);
    }

    function testClaimRevertsForNonHolder() public {
        uint256 id = _postTask();
        vm.prank(stranger);
        vm.expectRevert(AgentGig.NotAgentIDHolder.selector);
        gig.claimTask(id);
    }

    function testDoubleClaimReverts() public {
        uint256 id = _postTask();
        vm.prank(worker);
        gig.claimTask(id);
        vm.prank(voucher);
        vm.expectRevert(AgentGig.InvalidStatus.selector);
        gig.claimTask(id);
    }

    function testSubmitRevertsForNonWorker() public {
        uint256 id = _postTask();
        vm.prank(worker);
        gig.claimTask(id);
        vm.prank(voucher);
        vm.expectRevert(AgentGig.NotWorker.selector);
        gig.submitWork(id, "ipfs://proof");
    }

    function testReleaseBeforeSubmitReverts() public {
        uint256 id = _postTask();
        vm.prank(worker);
        gig.claimTask(id);
        vm.prank(poster);
        vm.expectRevert(AgentGig.InvalidStatus.selector);
        gig.release(id);
    }

    function testReleaseRevertsForNonPoster() public {
        uint256 id = _postTask();
        vm.prank(worker);
        gig.claimTask(id);
        vm.prank(worker);
        gig.submitWork(id, "ipfs://proof");
        vm.prank(worker);
        vm.expectRevert(AgentGig.NotPoster.selector);
        gig.release(id);
    }

    function testCancelAfterClaimReverts() public {
        uint256 id = _postTask();
        vm.prank(worker);
        gig.claimTask(id);
        vm.prank(poster);
        vm.expectRevert(AgentGig.InvalidStatus.selector);
        gig.cancelTask(id);
    }

    function testRefundBeforeDeadlineReverts() public {
        uint256 id = _postTask();
        vm.prank(poster);
        vm.expectRevert(AgentGig.DeadlineNotPassed.selector);
        gig.refundExpired(id);
    }

    function testRefundAfterSubmitReverts() public {
        // Anti-cheat: poster cannot refund once work is submitted.
        uint256 id = _postTask();
        vm.prank(worker);
        gig.claimTask(id);
        vm.prank(worker);
        gig.submitWork(id, "ipfs://proof");
        vm.warp(block.timestamp + 8 days);
        vm.prank(poster);
        vm.expectRevert(AgentGig.InvalidStatus.selector);
        gig.refundExpired(id);
    }

    function testVouchSelfReverts() public {
        vm.prank(worker);
        vm.expectRevert(AgentGig.SelfVouch.selector);
        gig.vouch(worker);
    }

    function testVouchTwiceReverts() public {
        vm.prank(voucher);
        gig.vouch(worker);
        vm.prank(voucher);
        vm.expectRevert(AgentGig.AlreadyVouched.selector);
        gig.vouch(worker);
    }

    function testVouchNonHolderTargetReverts() public {
        vm.prank(voucher);
        vm.expectRevert(AgentGig.NotAgentIDHolderTarget.selector);
        gig.vouch(stranger);
    }

    function testDirectBnbTransferReverts() public {
        vm.prank(poster);
        (bool ok,) = address(gig).call{value: 0.01 ether}("");
        assertFalse(ok);
    }

    // -- reentrancy ----------------------------------------------------
    function testReentrancyOnRelease() public {
        // Deploy a malicious worker contract that holds an Agent ID.
        ReentrantWorker evil = new ReentrantWorker(gig);
        agentID.mint(address(evil));
        vm.deal(address(evil), 1 ether);

        vm.prank(poster);
        uint256 id = gig.postTask{value: VALUE}("Evil task", "ipfs://d", block.timestamp + 7 days);
        evil.setTask(id);

        vm.prank(address(evil));
        gig.claimTask(id);
        vm.prank(address(evil));
        gig.submitWork(id, "ipfs://proof");

        vm.prank(poster);
        gig.release(id);

        // Worker got exactly VALUE once — the re-entered release() paid nothing extra.
        assertEq(address(evil).balance, 1 ether + VALUE);
        assertEq(address(gig).balance, 0);
        assertEq(uint256(gig.getTask(id).status), uint256(AgentGig.TaskStatus.Completed));
        assertEq(evil.reenterCount(), 1);
    }
}
