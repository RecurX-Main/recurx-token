// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {TokenAirdrop} from "../src/airdrop/TokenAirdrop.sol";

contract Deploy is Script {
    // Configuration
    address constant OWNER = 0xc1DF2461Bae83Cf84431d71996187414A1C85D8e;

    address constant COMMUNITY_WALLET = 0xCd9FBDaF769a42C4798553C1029bbBf9c16958C3; 

    address constant RCX_TOKEN = 0x7c533FF74f965e9E040EDBc6b4322601eB9Fe022;

    uint256 constant AIRDROP_ALLOCATION = 100_000e18;

    RecurXToken public rcxToken;
    TokenAirdrop public airdropContract;

    function run() external {
        vm.startBroadcast();

        rcxToken = RecurXToken(RCX_TOKEN);

        // Deploy airdrop contract
        airdropContract = new TokenAirdrop();

        // Exempt from burn fee and fund airdrop
        rcxToken.setBurnFeeExempt(address(airdropContract), true);
        rcxToken.setBurnFeeExempt(COMMUNITY_WALLET, true);
        // rcxToken.transfer(address(airdropContract), AIRDROP_ALLOCATION);

        // Final deployment summary
        console.log("Deployment complete:");
        console.log("RecurXToken address:", address(rcxToken));
        console.log("TokenAirdrop address:", address(airdropContract));
        console.log("Airdrop contract balance:", rcxToken.balanceOf(address(airdropContract)) / 1e18);
        console.log("Airdrop burn fee exempt:", rcxToken.isBurnFeeExempt(address(airdropContract)));
        console.log("Community Wallet burn fee exempt", rcxToken.isBurnFeeExempt(address(COMMUNITY_WALLET)));

        vm.stopBroadcast();
    }
}
