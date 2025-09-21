// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {PublicSale} from "../src/launchpad/PublicSale.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract PublicSaleDeploy is Script {

    /////////////////////////////////////////
    //////////////// MAINNET ////////////////
    /////////////////////////////////////////

    address constant OWNER = 0xc1DF2461Bae83Cf84431d71996187414A1C85D8e;

    address constant RCX_TOKEN = 0x7c533FF74f965e9E040EDBc6b4322601eB9Fe022;

    address constant RCX_VESTING_FACTORY = 0xeE0ff42ce74C030689B46E1a25fCEd0764b332ED;

    // BSC Mainnet Token Addresses (VERIFIED ON BSCSCAN)
    address constant USDT_BSC = 0x55d398326f99059fF775485246999027B3197955; // BSC USDT (18 decimals)
    address constant USDC_BSC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // BSC USDC (18 decimals)

    // BSC Mainnet Chainlink BNB/USD Price Feed (8 decimals)
    address constant BNB_USD_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;

    // Sale Configuration
    uint256 TGE_TIMESTAMP = block.timestamp; // Sept 21, 2025 (example timestamp)
    uint256 constant TOKEN_PRICE_USD18 = 100000; // $0.10 in 18 decimals (fallback price)
    uint256 constant MAX_PER_WALLET = 100_000e18; // 100k RCX max per wallet

    uint256 constant FALLBACK_TOKEN_PRICE_USD18 = 100000; // $0.10 fallback price

    // Stage prices in USD with 18 decimals (Price_USD * 1e18)
    // Based on CSV data: $0.06 to $0.19
    uint256[] public stagePrices = [
        60000000000000000, // Stage 1: $0.06
        61000000000000000, // Stage 2: $0.061
        63000000000000000, // Stage 3: $0.063
        64000000000000000, // Stage 4: $0.064
        66000000000000000, // Stage 5: $0.066
        67000000000000000, // Stage 6: $0.067
        69000000000000000, // Stage 7: $0.069
        71000000000000000, // Stage 8: $0.071
        72000000000000000, // Stage 9: $0.072
        74000000000000000, // Stage 10: $0.074
        76000000000000000, // Stage 11: $0.076
        78000000000000000, // Stage 12: $0.078
        80000000000000000, // Stage 13: $0.08
        81000000000000000, // Stage 14: $0.081
        83000000000000000, // Stage 15: $0.083
        85000000000000000, // Stage 16: $0.085
        87000000000000000, // Stage 17: $0.087
        90000000000000000, // Stage 18: $0.09
        92000000000000000, // Stage 19: $0.092
        94000000000000000, // Stage 20: $0.094
        96000000000000000, // Stage 21: $0.096
        98000000000000000, // Stage 22: $0.098
        101000000000000000, // Stage 23: $0.101
        103000000000000000, // Stage 24: $0.103
        106000000000000000, // Stage 25: $0.106
        108000000000000000, // Stage 26: $0.108
        111000000000000000, // Stage 27: $0.111
        113000000000000000, // Stage 28: $0.113
        116000000000000000, // Stage 29: $0.116
        119000000000000000, // Stage 30: $0.119
        122000000000000000, // Stage 31: $0.122
        124000000000000000, // Stage 32: $0.124
        127000000000000000, // Stage 33: $0.127
        130000000000000000, // Stage 34: $0.13
        134000000000000000, // Stage 35: $0.134
        137000000000000000, // Stage 36: $0.137
        140000000000000000, // Stage 37: $0.14
        143000000000000000, // Stage 38: $0.143
        147000000000000000, // Stage 39: $0.147
        150000000000000000, // Stage 40: $0.15
        154000000000000000, // Stage 41: $0.154
        157000000000000000, // Stage 42: $0.157
        161000000000000000, // Stage 43: $0.161
        165000000000000000, // Stage 44: $0.165
        169000000000000000, // Stage 45: $0.169
        173000000000000000, // Stage 46: $0.173
        177000000000000000, // Stage 47: $0.177
        181000000000000000, // Stage 48: $0.181
        186000000000000000, // Stage 49: $0.186
        190000000000000000 // Stage 50: $0.19
    ];

    // Stage allocations in RCX tokens based on CSV data
    // Total: 80,000,000 RCX (80M tokens)
    uint256[] public stageAllocations = [
        1096182e18, // Stage 1: 1,096,182 RCX
        1083591e18, // Stage 2: 1,083,591 RCX
        1062119e18, // Stage 3: 1,062,119 RCX
        1064712e18, // Stage 4: 1,064,712 RCX
        1056814e18, // Stage 5: 1,056,814 RCX
        1070395e18, // Stage 6: 1,070,395 RCX
        1072839e18, // Stage 7: 1,072,839 RCX
        1079799e18, // Stage 8: 1,079,799 RCX
        1105915e18, // Stage 9: 1,105,915 RCX
        1120242e18, // Stage 10: 1,120,242 RCX
        1137821e18, // Stage 11: 1,137,821 RCX
        1158322e18, // Stage 12: 1,158,322 RCX
        1181455e18, // Stage 13: 1,181,455 RCX
        1221867e18, // Stage 14: 1,221,867 RCX
        1249505e18, // Stage 15: 1,249,505 RCX
        1279122e18, // Stage 16: 1,279,122 RCX
        1310537e18, // Stage 17: 1,310,537 RCX
        1328661e18, // Stage 18: 1,328,661 RCX
        1363157e18, // Stage 19: 1,363,157 RCX
        1399005e18, // Stage 20: 1,399,005 RCX
        1436091e18, // Stage 21: 1,436,091 RCX
        1474311e18, // Stage 22: 1,474,311 RCX
        1498587e18, // Stage 23: 1,498,587 RCX
        1538706e18, // Stage 24: 1,538,706 RCX
        1564798e18, // Stage 25: 1,564,798 RCX
        1606488e18, // Stage 26: 1,606,488 RCX
        1634063e18, // Stage 27: 1,634,063 RCX
        1677059e18, // Stage 28: 1,677,059 RCX
        1705850e18, // Stage 29: 1,705,850 RCX
        1735230e18, // Stage 30: 1,735,230 RCX
        1765139e18, // Stage 31: 1,765,139 RCX
        1810007e18, // Stage 32: 1,810,007 RCX
        1840729e18, // Stage 33: 1,840,729 RCX
        1871851e18, // Stage 34: 1,871,851 RCX
        1889130e18, // Stage 35: 1,889,130 RCX
        1921019e18, // Stage 36: 1,921,019 RCX
        1953199e18, // Stage 37: 1,953,199 RCX
        1985642e18, // Stage 38: 1,985,642 RCX
        2004594e18, // Stage 39: 2,004,594 RCX
        2037548e18, // Stage 40: 2,037,548 RCX
        2057247e18, // Stage 41: 2,057,247 RCX
        2090610e18, // Stage 42: 2,090,610 RCX
        2110935e18, // Stage 43: 2,110,935 RCX
        2131630e18, // Stage 44: 2,131,630 RCX
        2152663e18, // Stage 45: 2,152,663 RCX
        2174004e18, // Stage 46: 2,174,004 RCX
        2195628e18, // Stage 47: 2,195,628 RCX
        2217510e18, // Stage 48: 2,217,510 RCX
        2227588e18, // Stage 49: 2,227,588 RCX
        2250084e18 // Stage 50: 2,250,084 RCX
    ];

    function run() external {
        vm.startBroadcast();

        // 1. Use real RCX token
        RecurXToken rcx = RecurXToken(RCX_TOKEN);

        // 2. Use real BSC USDT and USDC addresses
        IERC20 usdt = IERC20(USDT_BSC);
        IERC20 usdc = IERC20(USDC_BSC);

        // 3. Use real BSC Chainlink BNB/USD Price Feed
        address bnbUsdFeed = BNB_USD_FEED;

        // 4. Deploy Vesting Factory
        RCXVestingFactory vestingFactory = new RCXVestingFactory(); // RCXVestingFactory(RCX_VESTING_FACTORY);

        // 5. Deploy PublicSale Implementation
        PublicSale saleImpl = new PublicSale();

        // 6. Initialize Proxy
        bytes memory initData = abi.encodeWithSelector(
            PublicSale.initialize.selector,
            address(rcx),
            address(usdt),
            address(usdc),
            address(bnbUsdFeed),
            address(vestingFactory),
            OWNER, // OWNER
            FALLBACK_TOKEN_PRICE_USD18, // fallback price $0.10
            TGE_TIMESTAMP, // TGE timestamp
            MAX_PER_WALLET // max per wallet
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(saleImpl), initData);
        PublicSale sale = PublicSale(payable(address(proxy)));

        // 7. Grant roles and fund contract
        rcx.grantRole(rcx.VESTING_MANAGER_ROLE(), address(sale));
        vestingFactory.transferOwnership(address(sale));
        rcx.setBurnFeeExempt(address(sale), true);
        rcx.setBurnFeeExempt(address(vestingFactory), true);

        // 8. Mint and transfer RCX tokens to sale contract
        // rcx.mint(msg.sender, 80_000_000e18);
        rcx.transfer(address(sale), 80_000_000e18);

        // 9. Setup Stages
        sale.initializeStages(stagePrices, stageAllocations);

        // 10. Configure Stablecoin Decimals for BSC (18 decimals)
       // sale.setStablecoinDecimals(18, 18); // BSC USDT and USDC both use 18 decimals

        // 11. Optional: Start the sale (comment out if you want to start manually later)
        // sale.startSale();

        // ✅ Deployment Summary
        console.log("PublicSale deployed at:", address(sale));
        console.log("RCX Token:", address(rcx));
        console.log("USDT (BSC):", USDT_BSC);
        console.log("USDC (BSC):", USDC_BSC);
        console.log("BNB/USD Feed (BSC):", BNB_USD_FEED);
        console.log("Price feed decimals: 8");
        console.log("Total stages:", stagePrices.length);
        console.log("Price range: $0.06 - $0.19");
        console.log("Total allocation: 80,000,000 RCX");
        console.log("Expected raise: ~$9,800,978");

        vm.stopBroadcast();

        // vm.startBroadcast();

        // console.log("Total stages:", stagePrices.length);
        // console.log("Price range: $0.100 - $0.163");
        // console.log("Total allocation: 20,000,000 RCX");

        // // Get existing RCX token
        // RecurXToken rcx = RecurXToken(RCX_TOKEN);
        // console.log("Using RCX Token at:", address(rcx));

        // // 1. Deploy Presale Vesting Factory
        // console.log("\n1. Deploying Presale Vesting Factory...");

        // // Akready deployed at the time of community version so we can use it instaed
        // RCXVestingFactory factoryPresale = new RCXVestingFactory();

        // // RCXVestingFactory factoryPresale = RCXVestingFactory(RCX_VESTING_FACTORY);

        // console.log("Presale Factory deployed at:", address(factoryPresale));

        // // 2. Deploy PublicSale Implementation
        // console.log("\n2. Deploying PublicSale Implementation...");
        // PublicSale publicSaleImpl = new PublicSale();
        // console.log("PublicSale Implementation at:", address(publicSaleImpl));

        // // 3. Deploy PublicSale Proxy
        // console.log("\n3. Deploying PublicSale Proxy...");
        // bytes memory saleInitData = abi.encodeWithSelector(
        //     PublicSale.initialize.selector,
        //     address(rcx),           // RCX token
        //     USDT_BSC,              // USDT BSC
        //     USDC_BSC,              // USDC BSC
        //     BNB_USD_FEED,          // BNB/USD price feed
        //     address(factoryPresale), // Vesting factory
        //     OWNER,                 // Owner
        //     FALLBACK_TOKEN_PRICE_USD6, // Fallback token price (not used with stages)
        //     TGE_TIMESTAMP,         // TGE timestamp
        //     MAX_PER_WALLET         // Max per wallet
        // );

        // ERC1967Proxy saleProxy = new ERC1967Proxy(address(publicSaleImpl), saleInitData);
        // PublicSale sale = PublicSale(payable(address(saleProxy)));
        // console.log("PublicSale Proxy deployed at:", address(sale));

        // // 4. Setup Roles and Permissions
        // console.log("\n4. Setting up roles and permissions...");

        // // Grant vesting manager role to PublicSale
        // rcx.grantRole(rcx.VESTING_MANAGER_ROLE(), address(sale));
        // console.log("Granted VESTING_MANAGER_ROLE to PublicSale");

        // // Transfer ownership of presale factory to PublicSale
        // factoryPresale.transferOwnership(address(sale));
        // console.log("Transferred presale factory ownership to PublicSale");

        // // Set burn fee exemptions
        // rcx.setBurnFeeExempt(address(sale), true);
        // rcx.setBurnFeeExempt(address(factoryPresale), true);
        // console.log("Set burn fee exemptions");

        // // 5. Initialize Sale Stages
        // console.log("\n5. Initializing", stagePrices.length, "sale stages...");

        // // Validate arrays match
        // require(stagePrices.length == stageAllocations.length, "Array length mismatch");

        // sale.initializeStages(stagePrices, stageAllocations);
        // console.log("Initialized all stages successfully");

        // // Log first few and last few stages for verification
        // console.log("First stage - Price: $0.100, Allocation: 400,000 RCX");
        // console.log("Last stage - Price: $0.163, Allocation: 400,000 RCX");

        // // 6. Fund PublicSale with RCX
        // console.log("\n6. Funding PublicSale with RCX...");
        // uint256 presaleAllocation = 20_000_000e18; // 20M RCX total

        // // Check RCX balance
        // uint256 rcxBalance = rcx.balanceOf(msg.sender);
        // console.log("Your RCX balance:", rcxBalance / 1e18, "RCX");

        // require(rcxBalance >= presaleAllocation, "Insufficient RCX balance");

        // rcx.transfer(address(sale), presaleAllocation);
        // console.log("Transferred 20,000,000 RCX to PublicSale");

        // // 7. Verify Setup
        // console.log("\n7. Verifying setup...");
        // uint256 saleRcxBalance = rcx.balanceOf(address(sale));
        // console.log("PublicSale RCX balance:", saleRcxBalance / 1e18, "RCX");

        // (uint256 currentStage, uint256 currentPrice,,, uint256 remaining) = sale.getCurrentStage();
        // console.log("Current stage:", currentStage);
        // console.log("Current price: $", currentPrice, "(6 decimals)");
        // console.log("Tokens remaining in stage:", remaining / 1e18, "RCX");

        // // Verify total stages
        // uint256 totalStages = sale.getTotalStages();
        // console.log("Total stages configured:", totalStages);

        // // 8. Final deployment summary
        // console.log("\n=== DEPLOYMENT SUMMARY ===");
        // console.log("Network: BSC Mainnet");
        // console.log("RCX Token:", address(rcx));
        // console.log("PublicSale:", address(sale));
        // console.log("Presale Factory:", address(factoryPresale));
        // console.log("USDT:", USDT_BSC);
        // console.log("USDC:", USDC_BSC);
        // console.log("BNB/USD Feed:", BNB_USD_FEED);
        // console.log("TGE Timestamp:", TGE_TIMESTAMP);
        // console.log("Max per wallet: 100,000 RCX");
        // console.log("Total stages:", totalStages);
        // console.log("Price progression: $0.100 - $0.163");
        // console.log("Total raise target: ~$2,630,000");

        // console.log("\n=== NEXT STEPS ===");
        // console.log("1. Verify contracts on BSCScan");
        // console.log("2. Test purchase functions with small amounts");
        // console.log("3. Call sale.startSale() to activate the sale");
        // console.log("4. Monitor stage progression during sales");

        // console.log("\n=== VERIFICATION COMMANDS ===");
        // console.log("Check current stage: sale.getCurrentStage()");
        // console.log("Check if sale active: sale.saleActive()");
        // console.log("Test price calculation: sale.calculateCostAcrossStages(1000e18)");

        // vm.stopBroadcast();
    }

    // Helper function to validate stage data
    function validateStageData() public view returns (bool) {
        // Check if arrays have same length
        if (stagePrices.length != stageAllocations.length) return false;

        // Check total allocation = 80M
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < stageAllocations.length; i++) {
            totalAllocation += stageAllocations[i];
        }

        return totalAllocation == 80_000_000e18;
    }
}
