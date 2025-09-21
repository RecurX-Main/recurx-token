
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract InvestorDeploy is Script {
    address constant OWNER = 0xc1DF2461Bae83Cf84431d71996187414A1C85D8e;
    // address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828;

    // Addresses for investors
    address constant BEN_INVESTOR = 0x35fcA3f824DBb631c1E17CdB62be9C650eF02db9;
    // address constant BEN_INVESTOR = 0xf2A3735D9c1714a028A05C5c9b684b00f11D07Ed;

    function run() external {
        vm.startBroadcast();

        // Deploy Token
        RecurXToken impl = new RecurXToken();
        bytes memory initData = abi.encodeWithSelector(RecurXToken.initialize.selector, OWNER);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        RecurXToken rcx = RecurXToken(address(proxy));

        // Deploy Vesting Factory
        RCXVestingFactory factoryCats = new RCXVestingFactory();

        // Current timestamp for TGE
        uint256 currentTimestamp = 1757336607 ;// block.timestamp;
        console.log("TGE Deployed at: ", currentTimestamp);

        // Create Investor Vesting only
        address vINVESTOR = factoryCats.createInvestor(address(rcx), BEN_INVESTOR, 17_697e18, currentTimestamp);

        // Optional burn-fee exemption for smoother vest transfers
        rcx.setBurnFeeExempt(vINVESTOR, true);

        // Fund investor vesting
        rcx.transfer(vINVESTOR, 17_697e18);

        // Log addresses
        console.log("RCX Token deployed at:", address(rcx));
        console.log("Vesting Factory deployed at:", address(factoryCats));
        console.log("Investor Vesting contract deployed at:", vINVESTOR);

        vm.stopBroadcast();
    }
}
