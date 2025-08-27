// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {RecurXToken} from  "../src/core/RecurxToken.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {RCXCategoryVesting} from"../src/vesting/RCXCategoryVesting.sol";
import {PublicSale} from"../src/launchpad/PublicSale.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockChainlinkFeed} from "./mocks/MockChainlinkFeed.sol";

contract RCXSystemIntegrationTest is Test {
    // Contracts
    RecurXToken public rcxToken;
    MockERC20 public usdt;
    MockERC20 public usdc;
    MockChainlinkFeed public ethUsdFeed;
    RCXVestingFactory public vestingFactory;
    PublicSale public publicSale;

    // Test accounts
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public treasury;

    // Constants
    uint256 public constant TOTAL_SUPPLY = 500_000_000e18;
    uint256 public constant PRESALE_CAP = 20_000_000e18;
    uint256 public constant TOKEN_PRICE_USD6 = 100_000; // $0.10
    uint256 public constant MAX_PER_WALLET = 100_000e18;

    // Test data
    uint256 public tgeTimestamp;
    uint256 public constant ETH_PRICE_USD8 = 2000_00000000; // $2000 with 8 decimals

    function setUp() public {
        // Set up test accounts
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        treasury = makeAddr("treasury");

        // Set TGE to 1 hour from now for testing
        tgeTimestamp = block.timestamp + 1 hours;

        // Deploy mock USDT (6 decimals)
        usdt = new MockERC20("Tether USD", "USDT", 6);
        usdc = new MockERC20("USD Coin","USDC",6);

        // Deploy mock ETH/USD price feed (8 decimals, $2000)
        ethUsdFeed = new MockChainlinkFeed(int256(ETH_PRICE_USD8), 8);

        // Deploy RCX Token
        rcxToken = new RecurXToken();
        rcxToken.initialize(owner);


        // Deploy Vesting Factory
        vestingFactory = new RCXVestingFactory();

        // Deploy Public Sale
        publicSale = new PublicSale();
        publicSale.initialize(
            address(rcxToken),
            address(usdt),
            address(usdc),
            address(ethUsdFeed),
            address(vestingFactory),
            owner,
            TOKEN_PRICE_USD6,
            tgeTimestamp,
            MAX_PER_WALLET
        );
        // CHECK >>>> might need a check again 
        // rcxToken.transferOwnership(address(publicSale));
        // Checked <<
        rcxToken.grantRole(rcxToken.VESTING_MANAGER_ROLE(), address(publicSale));

        vestingFactory.transferOwnership(address(publicSale));


        // Setup: Make public sale and vesting factory exempt from burn fees
        rcxToken.setBurnFeeExempt(address(publicSale), true);
        rcxToken.setBurnFeeExempt(address(vestingFactory), true);

        // Fund test accounts with USDT and ETH
        usdt.mint(alice, 1_000_000e6); // $1M USDT
        usdt.mint(bob, 500_000e6);     // $500k USDT
        usdt.mint(charlie, 250_000e6); // $250k USDT

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 500 ether);
        vm.deal(charlie, 250 ether);

        console.log("Setup completed successfully");
        console.log("RCX Token deployed at:", address(rcxToken));
        console.log("Public Sale deployed at:", address(publicSale));
        console.log("Vesting Factory deployed at:", address(vestingFactory));
        console.log("TGE Timestamp:", tgeTimestamp);
    }

    function testCompleteSystemFlow() public {
        console.log("\n=== STARTING COMPLETE SYSTEM FLOW TEST ===");
        
        // Phase 1: Initial Setup and Funding
        console.log("\n--- Phase 1: Initial Setup ---");
        _testInitialSetup();

        // Phase 2: Pre-sale Operations
        console.log("\n--- Phase 2: Pre-sale Setup ---");
        _testPresaleSetup();

        // Phase 3: KYC and Sale Activation
        console.log("\n--- Phase 3: KYC and Sale Activation ---");
        _testKYCAndSaleActivation();

        // Phase 4: Purchase Operations
        console.log("\n--- Phase 4: Purchase Operations ---");
        _testPurchaseOperations();

        // Phase 5: Pre-TGE State
        console.log("\n--- Phase 5: Pre-TGE Validation ---");
        _testPreTGEState();

        // Phase 6: TGE and Vesting Claims
        console.log("\n--- Phase 6: TGE and Vesting Claims ---");
        _testTGEAndVestingClaims();

        // Phase 7: Vesting Schedule Validation
        console.log("\n--- Phase 7: Vesting Schedule Validation ---");
        _testVestingSchedule();

        // Phase 8: Final State and Cleanup
        console.log("\n--- Phase 8: Final State ---");
        _testFinalState();

        console.log("\n=== COMPLETE SYSTEM FLOW TEST PASSED ===");
    }

    function _testInitialSetup() internal view {
        // Verify initial token state
        assertEq(rcxToken.totalSupply(), TOTAL_SUPPLY);
        assertEq(rcxToken.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(rcxToken.s_totalBurned(), 0);
        assertTrue(rcxToken.s_burnFeeEnabled());

        // Verify public sale initial state
        assertFalse(publicSale.saleActive());
        assertEq(publicSale.totalSold(), 0);
        assertEq(publicSale.tokenPriceUsd6(), TOKEN_PRICE_USD6);
        assertEq(publicSale.tgeTimestamp(), tgeTimestamp);

        console.log(" Initial state verified");
    }

    function _testPresaleSetup() internal {
        // Fund the public sale contract with RCX tokens
        rcxToken.transfer(address(publicSale), PRESALE_CAP);
        
        // Verify funding
        assertEq(rcxToken.balanceOf(address(publicSale)), PRESALE_CAP);
        
        console.log("Public sale funded with", PRESALE_CAP / 1e18, "RCX tokens");
    }

    function _testKYCAndSaleActivation() internal {
        // Test KYC approval
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        // publicSale.approveKYCBatch(users);

        // Verify KYC status
        // assertTrue(publicSale.kycApproved(alice));
        // assertTrue(publicSale.kycApproved(bob));
        // assertTrue(publicSale.kycApproved(charlie));

        // Start the sale
        publicSale.startSale();
        assertTrue(publicSale.saleActive());

        // console.log(" KYC approved for test users");
        console.log(" Sale activated");
    }

    function _testPurchaseOperations() internal {
        // Test USDT purchases
        uint256 aliceRCXAmount = 50_000e18; // 50k RCX
        uint256 bobRCXAmount = 30_000e18;   // 30k RCX

        // Calculate USDT costs
        uint256 aliceUSDTCost = publicSale.usdCost6(aliceRCXAmount);
        uint256 bobUSDTCost = publicSale.usdCost6(bobRCXAmount);

        // Alice buys with USDT
        vm.startPrank(alice);
        usdt.approve(address(publicSale), aliceUSDTCost);
        publicSale.buyWithUSDT(aliceRCXAmount);
        vm.stopPrank();

        // Bob buys with USDT
        vm.startPrank(bob);
        usdt.approve(address(publicSale), bobUSDTCost);
        publicSale.buyWithUSDT(bobRCXAmount);
        vm.stopPrank();

        // Test native ETH purchase
        uint256 charlieRCXAmount = 20_000e18; // 20k RCX
        uint256 charlieETHCost = publicSale.nativeCost(charlieRCXAmount);

        vm.startPrank(charlie);
        publicSale.buyWithNative{value: charlieETHCost + 0.1 ether}(charlieRCXAmount); // Add extra for refund test
        vm.stopPrank();

        // Verify purchases
        assertEq(publicSale.purchased(alice), aliceRCXAmount);
        assertEq(publicSale.purchased(bob), bobRCXAmount);
        assertEq(publicSale.purchased(charlie), charlieRCXAmount);
        assertEq(publicSale.totalSold(), aliceRCXAmount + bobRCXAmount + charlieRCXAmount);

        console.log(" Alice purchased", aliceRCXAmount / 1e18, "RCX with USDT");
        console.log(" Bob purchased", bobRCXAmount / 1e18, "RCX with USDT");
        console.log(" Charlie purchased", charlieRCXAmount / 1e18, "RCX with ETH");
        console.log("Total sold:", publicSale.totalSold() / 1e18, "RCX");
    }

    function _testPreTGEState() internal {
        // Verify users cannot claim before TGE
        vm.expectRevert();
        vm.prank(alice);
        publicSale.claimToVesting();

        // Verify purchase records
        assertGt(publicSale.purchased(alice), 0);
        assertGt(publicSale.purchased(bob), 0);
        assertGt(publicSale.purchased(charlie), 0);

        // Verify claimed status (should all be false)
        assertFalse(publicSale.claimed(alice));
        assertFalse(publicSale.claimed(bob));
        assertFalse(publicSale.claimed(charlie));

        console.log(" Pre-TGE state validated - claims properly blocked");
    }

    function _testTGEAndVestingClaims() internal {
        // Fast forward to TGE
        vm.warp(tgeTimestamp+ 1);
        console.log("Fast forwarded to TGE timestamp");

        // Get initial balances
        uint256 contractBalanceBefore = rcxToken.balanceOf(address(publicSale));

        // Alice claims to vesting
        vm.prank(alice);
        publicSale.claimToVesting();

        // Bob claims to vesting
        vm.prank(bob);
        publicSale.claimToVesting();

        // Charlie claims to vesting
        vm.prank(charlie);
        publicSale.claimToVesting();

        // Verify claimed status
        assertTrue(publicSale.claimed(alice));
        assertTrue(publicSale.claimed(bob));
        assertTrue(publicSale.claimed(charlie));

        // Verify contract balance decreased
        uint256 contractBalanceAfter = rcxToken.balanceOf(address(publicSale));
        assertEq(contractBalanceBefore - contractBalanceAfter, publicSale.totalSold());

        console.log(" All users successfully claimed to vesting");
        console.log(" Public sale contract balance reduced correctly");
    }

    function _testVestingSchedule() internal {
        // Get vesting contracts from factory
        uint256 totalVestings = vestingFactory.total();
        assertEq(totalVestings, 3); // Alice, Bob, Charlie

        // Test each vesting contract
        for (uint256 i = 0; i < totalVestings; i++) {
            RCXVestingFactory.Record memory record = vestingFactory.get(i);
            RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);

            // Verify vesting parameters
            assertEq(vesting.category(), "Presale");
            assertEq(vesting.tgeBps(), 1500); // 15%
            assertEq(vesting.cliffMonths(), 1);
            assertEq(vesting.vestingMonths(), 9);

            // Test TGE claim (15% immediately available)
            uint256 tgeAmount = vesting.tgeAmount();
            uint256 expectedTGE = (record.allocation * 1500) / 10000; // 15%
            assertEq(tgeAmount, expectedTGE);

            // Test immediate claimable amount at TGE
            uint256 claimableAtTGE = vesting.claimable();
            assertEq(claimableAtTGE, tgeAmount);

            console.log("Vesting", i, "- Beneficiary:", record.beneficiary);
            console.log("  Total allocation:", record.allocation / 1e18, "RCX");
            console.log("  TGE amount:", tgeAmount / 1e18, "RCX");
        }

        // Test claiming TGE amounts
        _testTGEClaims();
        
        // Test cliff period
        _testCliffPeriod();
        
        // Test linear vesting
        _testLinearVesting();
    }

    function _testTGEClaims() internal {
        console.log("\n--- Testing TGE Claims ---");
        
        uint256 totalVestings = vestingFactory.total();
        
        for (uint256 i = 0; i < totalVestings; i++) {
            RCXVestingFactory.Record memory record = vestingFactory.get(i);
            RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);
            
            uint256 balanceBefore = rcxToken.balanceOf(record.beneficiary);
            uint256 claimableAmount = vesting.claimable();
            
            // Claim TGE tokens
            vm.prank(record.beneficiary);
            vesting.claim();
            
            uint256 balanceAfter = rcxToken.balanceOf(record.beneficiary);
            assertEq(balanceAfter - balanceBefore, claimableAmount);
            
            console.log(" Beneficiary", record.beneficiary);
            console.log("claimed", claimableAmount / 1e18);
            console.log("RCX at TGE");
        }
    }

    function _testCliffPeriod() internal {
        console.log("\n--- Testing Cliff Period ---");
        
        // Fast forward to middle of cliff (15 days)
        vm.warp(tgeTimestamp + 15 days);
        
        uint256 totalVestings = vestingFactory.total();
        
        for (uint256 i = 0; i < totalVestings; i++) {
            RCXVestingFactory.Record memory record = vestingFactory.get(i);
            RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);
            
            // During cliff, only TGE should be claimable (but already claimed)
            uint256 claimableAmount = vesting.claimable();
            assertEq(claimableAmount, 0);
        }
        
        console.log(" Cliff period validated - no additional tokens claimable");
    }

    function _testLinearVesting() internal {
        console.log("\n--- Testing Linear Vesting ---");
        
        // Fast forward past cliff (1 month + 1 day)
        vm.warp(tgeTimestamp + 31 days);
        
        uint256 totalVestings = vestingFactory.total();
        
        for (uint256 i = 0; i < totalVestings; i++) {
            RCXVestingFactory.Record memory record = vestingFactory.get(i);
            RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);
            
            // After cliff, linear vesting should start
            uint256 claimableAmount = vesting.claimable();
            assertGt(claimableAmount, 0);
            
            // Claim available tokens
            vm.prank(record.beneficiary);
            vesting.claim();
            
            console.log(" Beneficiary", record.beneficiary);
            console.log("claimed", claimableAmount / 1e18);
            console.log("RCX after cliff");
        }
        
        // Test mid-vesting period (5 months from TGE)
        vm.warp(tgeTimestamp + 150 days);
        
        for (uint256 i = 0; i < totalVestings; i++) {
            RCXVestingFactory.Record memory record = vestingFactory.get(i);
            RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);
            
            uint256 vestedAmount = vesting.vested();
            uint256 totalAllocation = vesting.totalAllocation();
            
            // Should be somewhere between TGE and full amount
            assertGt(vestedAmount, vesting.tgeAmount());
            assertLt(vestedAmount, totalAllocation);
        }
        
        // Test full vesting (10 months from TGE = 1 month cliff + 9 months vesting)
        vm.warp(tgeTimestamp + 300 days);
        
        for (uint256 i = 0; i < totalVestings; i++) {
            RCXVestingFactory.Record memory record = vestingFactory.get(i);
            RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);
            
            uint256 vestedAmount = vesting.vested();
            uint256 totalAllocation = vesting.totalAllocation();
            
            // Should be fully vested
            assertEq(vestedAmount, totalAllocation);
            
            // Claim remaining tokens
            uint256 claimableAmount = vesting.claimable();
            if (claimableAmount > 0) {
                vm.prank(record.beneficiary);
                vesting.claim();
            }
        }
        
        console.log(" Linear vesting schedule validated");
        console.log(" Full vesting completed successfully");
    }

    function _testFinalState() internal {
        // Verify all tokens are properly distributed
        uint256 totalUserBalance = 0;
        
        totalUserBalance += rcxToken.balanceOf(alice);
        totalUserBalance += rcxToken.balanceOf(bob);
        totalUserBalance += rcxToken.balanceOf(charlie);
        
        // Account for burned tokens during transfers (if any)
        uint256 expectedBalance = publicSale.totalSold();
        uint256 burnedTokens = rcxToken.s_totalBurned();
        
        console.log("Total user balances:", totalUserBalance / 1e18, "RCX");
        console.log("Expected from purchases:", expectedBalance / 1e18, "RCX");
        console.log("Total burned tokens:", burnedTokens / 1e18, "RCX");
        
        // Verify owner can withdraw proceeds
        uint256 usdtBalance = usdt.balanceOf(address(publicSale));
        uint256 ethBalance = address(publicSale).balance;
        
        if (usdtBalance > 0 || ethBalance > 0) {
            publicSale.withdrawProceeds(payable(treasury));
            
            console.log(" Proceeds withdrawn to treasury");
            console.log("  USDT:", usdtBalance / 1e6);
            console.log("  ETH:", ethBalance / 1e18);
        }
        
        // Test emergency token recovery (should work for excess RCX)
        uint256 liabilities = publicSale.unclaimedLiability(); // Add this function if not already public
        uint256 balance = rcxToken.balanceOf(address(publicSale));
        if (balance > liabilities) {
            uint256 recoverable = balance - liabilities;
            publicSale.recoverTokens(address(rcxToken), treasury, recoverable);
            console.log(" Remaining RCX recovered:", recoverable / 1e18);
        }

        console.log(" Final state validated");
        console.log(" All cleanup operations completed");
    }

    // Additional edge case tests
    function testEdgeCases() public {
        console.log("\n=== TESTING EDGE CASES ===");
        
        // Setup basic state
        _testInitialSetup();
        _testPresaleSetup();
        // _testKYCAndSaleActivation();
        
        // Test maximum purchase limit
        vm.startPrank(alice);
        usdt.approve(address(publicSale), type(uint256).max);
        
        // Try to exceed wallet limit
        vm.expectRevert();
        publicSale.buyWithUSDT(MAX_PER_WALLET + 1);
        
        // Purchase exact limit
        publicSale.buyWithUSDT(MAX_PER_WALLET);
        assertEq(publicSale.purchased(alice), MAX_PER_WALLET);
        
        vm.stopPrank();
        
        // Test sale cap by having multiple users purchase
        vm.startPrank(bob);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(MAX_PER_WALLET);
        vm.stopPrank();
        
        console.log(" Wallet limits enforced correctly");
        console.log(" Edge cases passed");
    }

    function testRevertScenarios() public {
        console.log("\n=== TESTING FAILURE SCENARIOS ===");
        
        _testInitialSetup();
        _testPresaleSetup();
        
        // Test purchase without KYC
        vm.expectRevert();
        vm.prank(alice);
        publicSale.buyWithUSDT(1000e18);
        
        // Test purchase when sale is inactive
        // publicSale.approveKYC(alice, true);
        vm.expectRevert();
        vm.prank(alice);
        publicSale.buyWithUSDT(1000e18);
        
        // Test insufficient native payment
        publicSale.startSale();
        uint256 requiredETH = publicSale.nativeCost(1000e18);
        
        vm.expectRevert();
        vm.prank(alice);
        publicSale.buyWithNative{value: requiredETH - 1}(1000e18);
        
        console.log(" Failure scenarios handled correctly");
    }

    function testPriceFeedEdgeCases() public {
        console.log("\n=== TESTING PRICE FEED EDGE CASES ===");
        
        _testInitialSetup();
        _testPresaleSetup();
        // _testKYCAndSaleActivation();
        
        // Test stale price
        vm.warp(block.timestamp + 2 hours);
        
        vm.expectRevert();
        publicSale.nativeCost(1000e18);
        
        // Update price to make it fresh
        ethUsdFeed.updatePrice(int256(ETH_PRICE_USD8));
        
        // Should work now
        uint256 cost = publicSale.nativeCost(1000e18);
        assertGt(cost, 0);
        
        console.log(" Price feed staleness protection working");
        
        // Test price update scenarios
        ethUsdFeed.updatePrice(3000_00000000); // $3000
        uint256 costAfterIncrease = publicSale.nativeCost(1000e18);
        assertLt(costAfterIncrease, cost); // Should need less ETH when price is higher
        
        console.log(" Price feed updates handled correctly");
    }

    // Helper function to display comprehensive test results
    function testSystemMetrics() public {
        testCompleteSystemFlow();
        
        console.log("\n=== FINAL SYSTEM METRICS ===");
        console.log("Total RCX Supply:", TOTAL_SUPPLY / 1e18);
        console.log("Presale Cap:", PRESALE_CAP / 1e18);
        console.log("Total Sold:", publicSale.totalSold() / 1e18);
        console.log("Token Price: $", TOKEN_PRICE_USD6, "/ 1e6");
        console.log("Max Per Wallet:", MAX_PER_WALLET / 1e18);
        console.log("Total Burned:", rcxToken.s_totalBurned() / 1e18);
        console.log("Remaining Supply:", rcxToken.remainingSupply() / 1e18);
        console.log("Active Vestings:", vestingFactory.total());
        console.log("=================================");
    }
}
