// script/RestDeploy.s.sol
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {PublicSale} from "../src/launchpad/PublicSale.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OthDeploy is Script {
    // ======== Fill these with deployed contract addresses ========
    address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828;

    // Replace with addresses returned/printed from InvestorDeploy script
    address constant RCX_TOKEN = 0x44221ba12dDf2D2C165F090aaeD4fb064744CC20;
    address constant FACTORY_CATS = 0x6a6811C9aD3882349E8036c30b088486d62f3d81 ;/* fill deployed vesting factory address */

    // Other constants (same as before)
    address constant USDT = 0xb575400Da99E13e2d1a2B21115290Ae669e361f0;
    address constant USDC = 0xb575400Da99E13e2d1a2B21115290Ae669e361f0;
    address constant NATIVE_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    // uint256 constant TGE_TIMESTAMP = block.timestamp - 200 days;  // current time when deploying rest
    uint256 constant TGE_TIMESTAMP = 1757473176 ;
    uint256 constant TOKEN_PRICE_USD6 = 100_000;
    uint256 constant MAX_PER_WALLET = 100_000e18;

    // Beneficiary addresses
    address constant BEN_IDO = 0x332c6A8bcd0C407CF01570aBFeAd840948e01893;
    address constant BEN_IEO = 0x927694F6ef3eb8ea0AC97924F34F344719bCc212;
    address constant BEN_LIQ = 0x981B69B8FB475Ba05A28462832D1f23924f31D04;
    address constant BEN_TEAM = 0x11628b9F11b7001A609697C81C97c26dd360a82A;
    address constant BEN_MARKETING = 0x5970Ff711352cC56e29c4C3f8F6fdbd537A88066;
    address constant BEN_COMMUNITY = 0x67E199710d81c46910F5e120B3D17933CE0D0314;
    address constant BEN_DEV = 0x213f059683d2e431d8487F7E05F38aeB0847558b;
    address constant BEN_RESERVE = 0xc97d8efF1E2D51A59d945B8F9395f01feb2343c2;

    function run() external {
        vm.startBroadcast();

        RecurXToken rcx = RecurXToken(RCX_TOKEN);
        RCXVestingFactory factoryCats = RCXVestingFactory(FACTORY_CATS);

        // Deploy second Vesting Factory for presale
        RCXVestingFactory factoryPresale = new RCXVestingFactory();

        // Deploy PublicSale proxy
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

        // Fund presale
        rcx.transfer(address(sale), 20_000_000e18);

        // Deploy other vesting contracts
        // address vIDO = factoryCats.createIDO(address(rcx), BEN_IDO, 25_000_000e18, TGE_TIMESTAMP);
        // address vIEO = factoryCats.createIEO(address(rcx), BEN_IEO, 80_000_000e18, TGE_TIMESTAMP);
        // address vLIQ = factoryCats.createLiquidity(address(rcx), BEN_LIQ, 75_000_000e18, TGE_TIMESTAMP);
        // address vTEAM = factoryCats.createTeam(address(rcx), BEN_TEAM, 50_000_000e18, TGE_TIMESTAMP);
        // address vMKT = factoryCats.createMarketing(address(rcx), BEN_MARKETING, 50_000_000e18, TGE_TIMESTAMP);
        address vCOMM = factoryCats.createCommunity(address(rcx), BEN_COMMUNITY, 50_000_000e18, TGE_TIMESTAMP);
        // address vDEV = factoryCats.createDevelopment(address(rcx), BEN_DEV, 40_000_000e18, TGE_TIMESTAMP);
        // address vRES = factoryCats.createReserve(address(rcx), BEN_RESERVE, 35_000_000e18, TGE_TIMESTAMP);

        // Burn-fee exemptions
        // rcx.setBurnFeeExempt(vIDO, true);
        // rcx.setBurnFeeExempt(vIEO, true);
        // rcx.setBurnFeeExempt(vLIQ, true);
        // rcx.setBurnFeeExempt(vTEAM, true);
        // rcx.setBurnFeeExempt(vMKT, true);
        rcx.setBurnFeeExempt(vCOMM, true);
        // rcx.setBurnFeeExempt(vDEV, true);
        // rcx.setBurnFeeExempt(vRES, true);

        // Fund vestings
        // rcx.transfer(vIDO, 25_000_000e18);
        // rcx.transfer(vIEO, 80_000_000e18);
        // rcx.transfer(vLIQ, 75_000_000e18);
        // rcx.transfer(vTEAM, 50_000_000e18);
        // rcx.transfer(vMKT, 50_000_000e18);
        rcx.transfer(vCOMM, 50_000_000e18);
        // rcx.transfer(vDEV, 40_000_000e18);
        // rcx.transfer(vRES, 35_000_000e18);

        // Log addresses
        console.log("PublicSale deployed at:", address(sale));
        console.log("factoryPresale:", address(factoryPresale));
        // console.log("vIDO:", vIDO);
        // console.log("vIEO:", vIEO);
        // console.log("vLIQ:", vLIQ);
        // console.log("vTEAM:", vTEAM);
        // console.log("vMKT:", vMKT);
        console.log("vCOMM:", vCOMM);
        // console.log("vDEV:", vDEV);
        // console.log("vRES:", vRES);

        vm.stopBroadcast();
    }
}
