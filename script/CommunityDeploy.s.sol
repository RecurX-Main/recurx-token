// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";

contract CommunityDeploy is Script {

    address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828;

    address constant BEN_COMMUNITY = 0x67E199710d81c46910F5e120B3D17933CE0D0314;

    address constant RCX_TOKEN = 0x44221ba12dDf2D2C165F090aaeD4fb064744CC20;

    uint256 COMMUNITY_ALLOCATION = 50_000_000e18;


    function run() external {
        vm.startBroadcast();

        RecurXToken rcx = RecurXToken(RCX_TOKEN);

        RCXVestingFactory factoryCats = new RCXVestingFactory();

        uint256 currentTimestamp = 1757336607;

        console.log("TGE Deployed at: ", currentTimestamp);

        address vCOMMUNITY = factoryCats.createCommunity(address(rcx), BEN_COMMUNITY, COMMUNITY_ALLOCATION, currentTimestamp);

        rcx.setBurnFeeExempt(vCOMMUNITY, true);

        rcx.transfer(vCOMMUNITY, COMMUNITY_ALLOCATION);

        console.log("RCX Token deployed at:", address(rcx));
        console.log("Vesting Factory deployed at:", address(factoryCats));
        console.log("Community Vesting contract deployed at:", vCOMMUNITY);

        vm.stopBroadcast();

    }
}
