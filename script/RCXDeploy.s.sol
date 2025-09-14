// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// forge script script/RCXDeploy.s.sol:RCXDeploy --rpc-url $RPC --private-key $PK --broadcast

import "forge-std/Script.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {PublicSale} from "../src/launchpad/PublicSale.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


contract RCXDeploy is Script {
    // ======== TODO: fill these ========
    address constant OWNER           = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828;
    address constant USDT            = 0xb575400Da99E13e2d1a2B21115290Ae669e361f0;
    address constant USDC            = 0xb575400Da99E13e2d1a2B21115290Ae669e361f0;
    address constant NATIVE_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    uint256 constant TGE_TIMESTAMP   = 1735689600;            // e.g., 1735689600
    uint256 constant TOKEN_PRICE_USD6= 100_000;       // $0.05 = 50,000 (6d)
    uint256 constant MAX_PER_WALLET  = 100_000e18;   // or 0 for default

    address constant BEN_IDO        = 0x332c6A8bcd0C407CF01570aBFeAd840948e01893;
    address constant BEN_IEO        = 0x927694F6ef3eb8ea0AC97924F34F344719bCc212;
    address constant BEN_INVESTOR   = 0xf2A3735D9c1714a028A05C5c9b684b00f11D07Ed;
    address constant BEN_LIQ        = 0x981B69B8FB475Ba05A28462832D1f23924f31D04;
    address constant BEN_TEAM       = 0x11628b9F11b7001A609697C81C97c26dd360a82A;
    address constant BEN_MARKETING  = 0x5970Ff711352cC56e29c4C3f8F6fdbd537A88066;
    address constant BEN_COMMUNITY  = 0x67E199710d81c46910F5e120B3D17933CE0D0314;
    address constant BEN_DEV        = 0x213f059683d2e431d8487F7E05F38aeB0847558b;
    address constant BEN_RESERVE    = 0xc97d8efF1E2D51A59d945B8F9395f01feb2343c2;
    address constant TREASURY       = 0x4b03fbC98D13e3a4537Ef151e45A6293E90e8579;


    // ======== End config ========

    function run() external {
        vm.startBroadcast();

        // 1) Token
        // RecurXToken rcx = new RecurXToken();
        // rcx.initialize(OWNER);

        RecurXToken impl = new RecurXToken(); // implementation contract (initializers disabled)
        bytes memory initData = abi.encodeWithSelector(RecurXToken.initialize.selector, OWNER);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        RecurXToken rcx = RecurXToken(address(proxy)); // use rcx to interact with proxy


        // 2) Factories
        RCXVestingFactory factoryCats    = new RCXVestingFactory();
        RCXVestingFactory factoryPresale = new RCXVestingFactory();

        // 3) PublicSale
        // PublicSale sale = new PublicSale();
        // sale.initialize(address(rcx), USDT, USDC, NATIVE_USD_FEED, address(factoryPresale), OWNER, TOKEN_PRICE_USD6, TGE_TIMESTAMP, MAX_PER_WALLET);
        PublicSale publicSaleImpl = new PublicSale();
        bytes memory saleInitData = abi.encodeWithSelector(
            PublicSale.initialize.selector,
            address(rcx),
            USDT,
            USDC,
            NATIVE_USD_FEED,
            address(factoryPresale),
            OWNER,
            TOKEN_PRICE_USD6,
            TGE_TIMESTAMP,
            MAX_PER_WALLET
        );
        ERC1967Proxy saleProxy = new ERC1967Proxy(address(publicSaleImpl), saleInitData);
        PublicSale sale = PublicSale(payable(address(saleProxy)));

        // Roles & exemptions
        rcx.grantRole(rcx.VESTING_MANAGER_ROLE(), address(sale));
        factoryPresale.transferOwnership(address(sale));
        rcx.setBurnFeeExempt(address(sale), true);
        rcx.setBurnFeeExempt(address(factoryPresale), true);

        // 4) Fund presale
        rcx.transfer(address(sale), 20_000_000e18);

        console.log("RCX Token: ",address(rcx));
        console.log("PublicSale deployed at:", address(sale));
        console.log("factoryCats:", address(factoryCats));
        console.log("factoryPresale", address(factoryPresale));


        // 5) Category vestings (using factoryCats)
        address vIDO        = factoryCats.createIDO(       address(rcx), BEN_IDO,      25_000_000e18, TGE_TIMESTAMP);
        address vIEO        = factoryCats.createIEO(       address(rcx), BEN_IEO,      80_000_000e18, TGE_TIMESTAMP);
        // address vINVESTOR   = factoryCats.createInvestor(  address(rcx), BEN_INVESTOR, 75_000_000e18, TGE_TIMESTAMP);
        address vINVESTOR   = factoryCats.createInvestor(  address(rcx), BEN_INVESTOR, 20_000e18, TGE_TIMESTAMP);
        address vLIQ        = factoryCats.createLiquidity( address(rcx), BEN_LIQ,      75_000_000e18, TGE_TIMESTAMP);
        address vTEAM       = factoryCats.createTeam(      address(rcx), BEN_TEAM,     50_000_000e18, TGE_TIMESTAMP);
        address vMKT        = factoryCats.createMarketing( address(rcx), BEN_MARKETING,50_000_000e18, TGE_TIMESTAMP);
        address vCOMM       = factoryCats.createCommunity( address(rcx), BEN_COMMUNITY,50_000_000e18, TGE_TIMESTAMP);
        address vDEV        = factoryCats.createDevelopment(address(rcx), BEN_DEV,     40_000_000e18, TGE_TIMESTAMP);
        address vRES        = factoryCats.createReserve(   address(rcx), BEN_RESERVE,  35_000_000e18, TGE_TIMESTAMP);


        console.log("vIDO:       ", vIDO);
        console.log("vIEO:       ", vIEO);
        console.log("vINVESTOR:  ", vINVESTOR);
        console.log("vLIQ:       ", vLIQ);
        console.log("vTEAM:      ", vTEAM);
        console.log("vMKT:       ", vMKT);
        console.log("vCOMM:      ", vCOMM);
        console.log("vDEV:       ", vDEV);
        console.log("vRES:       ", vRES);


        // Optional burn-fee exemptions (smoother vest transfers)
        rcx.setBurnFeeExempt(vIDO,  true);
        rcx.setBurnFeeExempt(vIEO,  true);
        rcx.setBurnFeeExempt(vINVESTOR, true);
        rcx.setBurnFeeExempt(vLIQ,  true);
        rcx.setBurnFeeExempt(vTEAM, true);
        rcx.setBurnFeeExempt(vMKT,  true);
        rcx.setBurnFeeExempt(vCOMM, true);
        rcx.setBurnFeeExempt(vDEV,  true);
        rcx.setBurnFeeExempt(vRES,  true);

        // Fund vestings
        rcx.transfer(vIDO,   25_000_000e18);
        rcx.transfer(vIEO,   80_000_000e18);
        rcx.transfer(vINVESTOR, 20_000e18);
        rcx.transfer(vLIQ,   75_000_000e18);
        rcx.transfer(vTEAM,  50_000_000e18);
        rcx.transfer(vMKT,   50_000_000e18);
        rcx.transfer(vCOMM,  50_000_000e18);
        rcx.transfer(vDEV,   40_000_000e18);
        rcx.transfer(vRES,   35_000_000e18);

        vm.stopBroadcast();
    }
}
