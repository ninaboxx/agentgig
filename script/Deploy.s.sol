// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AgentGig.sol";

/// @notice Deploy AgentGig. No private key in this repo — pass it via env.
///  BSC testnet (97):  forge script script/Deploy.s.sol --rpc-url bsc_testnet --broadcast
///  BSC mainnet (56):  forge script script/Deploy.s.sol --rpc-url bsc --broadcast
///  Env: AGENT_ID (contract address) + PRIVATE_KEY (deployer, never commit).
///  Mainnet Agent ID: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
contract Deploy is Script {
    function run() external {
        address agentID = vm.envAddress("AGENT_ID");
        vm.startBroadcast();
        AgentGig gig = new AgentGig(agentID);
        vm.stopBroadcast();
        console.log("AgentGig deployed at:", address(gig));
        console.log("Agent ID contract:", agentID);
    }
}
