// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal ERC-721 balanceOf mock for the real Agent ID contract.
///  Only implements what AgentGig reads: balanceOf + a mint helper for tests.
contract MockAgentID {
    mapping(address => uint256) private _balances;

    function mint(address to) external {
        _balances[to] += 1;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}
