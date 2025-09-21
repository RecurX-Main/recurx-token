// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PublicSale} from "../src/launchpad/PublicSale.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {RCXCategoryVesting} from "../src/vesting/RCXCategoryVesting.sol";
import {RCXVestingBase} from "../src/vesting/RCXVestingBase.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(int256 price) {
        _price = price;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "Mock ETH/USD";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function updatePrice(int256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
        _roundId++;
    }
}

contract PublicSaleTest is Test {
    PublicSale public publicSale;
    RCXVestingFactory public vestingFactory;
    RecurXToken public rcxToken;
    ERC20Mock public usdt;
    ERC20Mock public usdc;
    MockAggregator public ethUsdFeed;

    address public owner;
    address public buyer1;
    address public buyer2;
    address public treasury;

    uint256 public constant INITIAL_BSC_PRICE = 2000e8; // $2000 with 8 decimals
    uint256 public constant TOKEN_PRICE_USD6 = 100_000; // $0.10 with 6 decimals
    uint256 public constant TGE_TIMESTAMP = 1735689600; // Jan 1, 2025
    uint256 public constant MAX_PER_WALLET = 10_000_000e18; // 100k RCX

    event SaleStarted();
    event Purchased(address indexed buyer, uint256 rcxAmount, address paymentToken, uint256 paymentAmount);
    event ClaimedToVesting(address indexed buyer, address vesting, uint256 rcxAmount);

    function setUp() public {
        owner = makeAddr("owner");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        treasury = makeAddr("treasury");

        vm.startPrank(owner);

        RecurXToken rcxImplementation = new RecurXToken();
        bytes memory rcxInitData = abi.encodeWithSignature("initialize(address)", owner);
        ERC1967Proxy rcxProxy = new ERC1967Proxy(address(rcxImplementation), rcxInitData);
        rcxToken = RecurXToken(address(rcxProxy));

        usdt = new ERC20Mock();
        usdc = new ERC20Mock();
        ethUsdFeed = new MockAggregator(int256(INITIAL_BSC_PRICE));

        vestingFactory = new RCXVestingFactory();

        PublicSale implementation = new PublicSale();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,uint256,uint256,uint256)",
            address(rcxToken),
            address(usdt),
            address(usdc),
            address(ethUsdFeed),
            address(vestingFactory),
            owner,
            TOKEN_PRICE_USD6,
            TGE_TIMESTAMP,
            MAX_PER_WALLET
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        publicSale = PublicSale(payable(address(proxy)));

        vestingFactory.transferOwnership(address(publicSale));

        bytes32 VESTING_MANAGER_ROLE = keccak256("VESTING_MANAGER_ROLE");
        rcxToken.grantRole(VESTING_MANAGER_ROLE, address(publicSale));

        rcxToken.setBurnFeeExempt(address(publicSale), true);

        uint256[] memory prices = new uint256[](3);
        uint256[] memory allocations = new uint256[](3);

        prices[0] = 80_000; // $0.08
        prices[1] = 90_000; // $0.09
        prices[2] = 100_000; // $0.10

        allocations[0] = 5_000_000e18; // 5M tokens
        allocations[1] = 8_000_000e18; // 8M tokens
        allocations[2] = 7_000_000e18; // 7M tokens

        publicSale.initializeStages(prices, allocations);

        rcxToken.approve(address(publicSale), 50_000_000e18); // 50M for sale
        publicSale.fundRCX(50_000_000e18);

        usdt.mint(buyer1, 1_000_000e6); // $1,000,000 USDT
        usdt.mint(buyer2, 5_000e6); // $5,000 USDT
        usdc.mint(buyer1, 1_000_000e6); // $1,000,000 USDC
        usdc.mint(buyer2, 5_000e6); // $5,000 USDC

        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 5 ether);

        vm.stopPrank();
    }

    // checked
    function testInitialization() public {
        assertEq(address(publicSale.rcx()), address(rcxToken));
        assertEq(address(publicSale.usdt()), address(usdt));
        assertEq(address(publicSale.usdc()), address(usdc));
        assertEq(address(publicSale.nativeUsdFeed()), address(ethUsdFeed));
        assertEq(publicSale.vestingFactory(), address(vestingFactory));
        assertEq(publicSale.tokenPriceUsd6(), TOKEN_PRICE_USD6);
        assertEq(publicSale.tgeTimestamp(), TGE_TIMESTAMP);
        assertEq(publicSale.maxPerWallet(), MAX_PER_WALLET);
        assertFalse(publicSale.saleActive());
        assertEq(publicSale.totalSold(), 0);
    }

    // checked
    function testStartStopSale() public {
        // Only owner can start sale
        vm.prank(buyer1);
        vm.expectRevert();
        publicSale.startSale();

        // Start sale
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit SaleStarted();
        publicSale.startSale();
        assertTrue(publicSale.saleActive());

        // Stop sale
        vm.prank(owner);
        publicSale.stopSale();
        assertFalse(publicSale.saleActive());
    }

    // checked
    function testStageProgression() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        // Config
        uint256 tokensPerBuyer = 100_000e18; // MAX_PER_WALLET
        uint256 totalToBuy = 5_000_000e18; // Stage 0 allocation
        uint256 tokensBought = 0;
        uint256 buyerIndex = 1;

        while (tokensBought < totalToBuy) {
            // Generate a new buyer address
            address buyer = address(uint160(uint256(keccak256(abi.encodePacked("buyer", buyerIndex)))));
            buyerIndex++;

            // Give buyer enough USDT
            deal(address(usdt), buyer, 1_000_000e6); // Give 1M USDT

            // Buyer approves and buys
            vm.startPrank(buyer);
            usdt.approve(address(publicSale), type(uint256).max);
            publicSale.buyWithUSDT(tokensPerBuyer);
            vm.stopPrank();

            tokensBought += tokensPerBuyer;
        }

        // Check that we progressed to the next stage
        (uint256 stageIndex, uint256 priceUsd6,,, uint256 tokensRemaining) = publicSale.getCurrentStage();

        assertEq(stageIndex, 1, "Should be in stage 1");
        assertEq(priceUsd6, 90_000, "Stage 1 price should be $0.09");
        assertEq(tokensRemaining, 8_000_000e18, "Stage 1 should have 8M tokens remaining");
    }

    // checked
    function testBuyWithUSDT() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 10_000e18; // 10,000 RCX
        uint256 expectedCost = (purchaseAmount * 80_000) / 1e18; // $0.08 per token

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), expectedCost);

        vm.expectEmit(true, true, true, true);
        emit Purchased(buyer1, purchaseAmount, address(usdt), expectedCost);

        publicSale.buyWithUSDT(purchaseAmount);

        assertEq(publicSale.purchased(buyer1), purchaseAmount);
        assertEq(publicSale.totalSold(), purchaseAmount);
        assertEq(usdt.balanceOf(address(publicSale)), expectedCost);
        vm.stopPrank();
    }

    // checked
    function testBuyWithUSDC() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 15_000e18; // 15,000 RCX
        uint256 expectedCost = (purchaseAmount * 80_000) / 1e18;

        vm.startPrank(buyer1);
        usdc.approve(address(publicSale), expectedCost);
        publicSale.buyWithUSDC(purchaseAmount);

        assertEq(publicSale.purchased(buyer1), purchaseAmount);
        assertEq(publicSale.totalSold(), purchaseAmount);
        assertEq(usdc.balanceOf(address(publicSale)), expectedCost);
        vm.stopPrank();
    }

    function testBuyWithNative() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 5_000e18; // 5,000 RCX
        // uint256 costUsd6 = (purchaseAmount * 80_000) / 1e18; // Cost in USD (6 decimals)
        uint256 costEth = publicSale.nativeCost(purchaseAmount);

        vm.startPrank(buyer1);
        uint256 initialBalance = buyer1.balance;

        vm.expectEmit(true, true, true, true);
        emit Purchased(buyer1, purchaseAmount, address(0), costEth);

        publicSale.buyWithNative{value: costEth + 0.1 ether}(purchaseAmount);

        assertEq(publicSale.purchased(buyer1), purchaseAmount);
        assertEq(publicSale.totalSold(), purchaseAmount);
        // Check refund was sent
        assertEq(buyer1.balance, initialBalance - costEth);
        vm.stopPrank();
    }

    function testBuyAcrossMultipleStages() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 6_000_000e18; // 6M tokens (spans stage 0 and 1)

        // Calculate expected cost:
        // Stage 0: 5M tokens at $0.08 = $400,000
        // Stage 1: 1M tokens at $0.09 = $90,000
        // Total: $490,000 (in 6 decimals = 490,000,000,000)
        uint256 expectedCost = (5_000_000e18 * 80_000) / 1e18 + (1_000_000e18 * 90_000) / 1e18;

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), expectedCost);
        publicSale.buyWithUSDT(purchaseAmount);

        assertEq(publicSale.purchased(buyer1), purchaseAmount);
        assertEq(publicSale.totalSold(), purchaseAmount);

        // Check we're now in stage 1 with 7M tokens remaining
        (uint256 stageIndex,,,, uint256 tokensRemaining) = publicSale.getCurrentStage();
        assertEq(stageIndex, 1);
        assertEq(tokensRemaining, 7_000_000e18);
        vm.stopPrank();
    }

    // checked
    function testBuyWhenSaleInactiveRevert() public {
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), 1000e6);
        vm.expectRevert();
        publicSale.buyWithUSDT(1000e18);
        vm.stopPrank();
    }

    // checked
    function testBuyExceedsWalletCapRevert() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 exceedsAmount = MAX_PER_WALLET + 1;

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        vm.expectRevert();
        publicSale.buyWithUSDT(exceedsAmount);
        vm.stopPrank();
    }

    function testBuyExceedsPresaleCapRevert() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        // Try to buy more than total allocation across all stages (20M)
        uint256 exceedsAmount = 20_000_001e18;

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        vm.expectRevert();
        publicSale.buyWithUSDT(exceedsAmount);
        vm.stopPrank();
    }

    // checked
    function testClaimToVestingBeforeTGE() public {
        // Setup: Buy tokens first
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 50_000e18;
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(purchaseAmount);
        vm.stopPrank();

        // Try to claim before TGE
        vm.startPrank(buyer1);
        vm.expectRevert(PublicSale.PublicSale__Unauthorized.selector);
        publicSale.claimToVesting();
        vm.stopPrank();
    }
    // checked

    function testClaimToVestingAfterTGE() public {
        // Setup: Buy tokens first
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 50_000e18;
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(purchaseAmount);
        vm.stopPrank();

        // Fast forward to after TGE
        vm.warp(TGE_TIMESTAMP + 1);

        // Claim to vesting
        vm.startPrank(buyer1);
        vm.expectEmit(true, false, false, false);
        emit ClaimedToVesting(buyer1, address(0), purchaseAmount); // address will be determined at runtime

        publicSale.claimToVesting();

        assertTrue(publicSale.claimed(buyer1));
        assertEq(publicSale.totalClaimed(), purchaseAmount);
        vm.stopPrank();

        // Check that vesting contract was created
        assertEq(vestingFactory.total(), 1);
        RCXVestingFactory.Record memory record = vestingFactory.get(0);
        assertEq(record.beneficiary, buyer1);
        assertEq(record.allocation, purchaseAmount);
        assertEq(record.category, "Presale");
    }
    // checked

    function testFullVestingFlow() public {
        // 1. Buy tokens
        console2.log("PUBLIC SALE STARTED");
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        console2.log("BUY with USDT");
        uint256 purchaseAmount = 100_000e18; // 100k RCX
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(purchaseAmount);
        vm.stopPrank();

        // 2. Fast forward to TGE and claim to vesting
        vm.warp(TGE_TIMESTAMP);

        console2.log("CLAIM TO VESTING");
        vm.startPrank(buyer1);
        publicSale.claimToVesting();
        vm.stopPrank();

        // 3. Get the vesting contract
        RCXVestingFactory.Record memory record = vestingFactory.get(0);
        RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);

        // 4. Check vesting parameters (Presale: 15% TGE, 1 month cliff, 9 months vesting, TGE+1month offset)
        assertEq(vesting.tgeBps(), 1500); // 15%
        assertEq(vesting.cliffMonths(), 1);
        assertEq(vesting.vestingMonths(), 9);
        assertEq(vesting.totalAllocation(), purchaseAmount);
        assertEq(vesting.beneficiary(), buyer1);

        // 5. Test TGE claim - should be able to claim 15% at TGE + 1 month
        uint256 expectedTGE = (purchaseAmount * 1500) / 10000; // 15%

        // Fast forward to TGE + 1 month (when TGE becomes claimable for presale)
        vm.warp(TGE_TIMESTAMP + 30 days);

        uint256 claimableTGE = vesting.claimable();
        assertEq(claimableTGE, expectedTGE);

        // Claim TGE portion
        vm.startPrank(buyer1);
        uint256 balanceBefore = rcxToken.balanceOf(buyer1);
        vesting.claim();
        uint256 balanceAfter = rcxToken.balanceOf(buyer1);
        assertEq(balanceAfter - balanceBefore, expectedTGE);
        vm.stopPrank();

        // 6. Check that no linear tokens are claimable immediately at TGE release time
        // (only TGE portion would be available, which we've already claimed)
        uint256 linearStart = vesting.linearStart();
        assertEq(linearStart, TGE_TIMESTAMP + 30 days); // Linear starts 1 month after TGE

        // At TGE release time, after TGE claim, remaining claimable should be 0
        vm.warp(TGE_TIMESTAMP + 30 days);
        uint256 claimableAtLinearStart = vesting.claimable();
        assertEq(claimableAtLinearStart, 0);

        // 7. Test linear vesting progression (after linear start)
        vm.warp(TGE_TIMESTAMP + 45 days); // 15 days into linear vesting period

        uint256 linearTotal = purchaseAmount - expectedTGE; // 85% linear portion
        uint256 vestingDuration = 9 * 30 days; // 9 months in seconds
        uint256 expectedLinear = (linearTotal * 15 days) / vestingDuration;

        uint256 totalClaimable = vesting.claimable();
        // After claiming TGE, only linear portion accrues
        uint256 expectedTotal = expectedLinear;
        assertApproxEqAbs(totalClaimable, expectedTotal, 1e15); // Allow small rounding errors

        uint256 claimableLinear = vesting.claimable();
        assertGt(claimableLinear, 0); // Should have some linear tokens

        // 8. Test full vesting completion
        vm.warp(TGE_TIMESTAMP + 30 days + vestingDuration); // End of vesting
        uint256 finalClaimable = vesting.claimable();
        assertEq(finalClaimable, linearTotal); // Remaining linear portion after TGE claim

        // Claim remaining tokens
        vm.startPrank(buyer1);
        uint256 finalBalanceBefore = rcxToken.balanceOf(buyer1);
        vesting.claim();
        uint256 finalBalanceAfter = rcxToken.balanceOf(buyer1);
        assertEq(finalBalanceAfter - finalBalanceBefore, linearTotal);

        // Total claimed should equal total allocation
        assertEq(vesting.s_claimed(), purchaseAmount);
        assertEq(vesting.claimable(), 0);
        vm.stopPrank();
    }
    // checked

    function testMultipleBuyersVesting() public {
        // Setup sale
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        // Two buyers purchase different amounts
        uint256 amount1 = 75_000e18;
        uint256 amount2 = 25_000e18;

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(amount1);
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(amount2);
        vm.stopPrank();

        // Fast forward to TGE
        vm.warp(TGE_TIMESTAMP);

        // Both claim to vesting
        vm.prank(buyer1);
        publicSale.claimToVesting();

        vm.prank(buyer2);
        publicSale.claimToVesting();

        // Verify two vesting contracts created
        assertEq(vestingFactory.total(), 2);

        RCXVestingFactory.Record memory record1 = vestingFactory.get(0);
        RCXVestingFactory.Record memory record2 = vestingFactory.get(1);

        assertEq(record1.beneficiary, buyer1);
        assertEq(record1.allocation, amount1);
        assertEq(record2.beneficiary, buyer2);
        assertEq(record2.allocation, amount2);

        // Test both can claim independently
        vm.warp(TGE_TIMESTAMP + 35 days); // TGE + 1 month + 5 days

        RCXCategoryVesting vesting1 = RCXCategoryVesting(record1.vesting);
        RCXCategoryVesting vesting2 = RCXCategoryVesting(record2.vesting);

        vm.startPrank(buyer1);
        uint256 claimable1 = vesting1.claimable();
        vesting1.claim();
        assertEq(rcxToken.balanceOf(buyer1), claimable1);
        vm.stopPrank();

        vm.startPrank(buyer2);
        uint256 claimable2 = vesting2.claimable();
        vesting2.claim();
        assertEq(rcxToken.balanceOf(buyer2), claimable2);
        vm.stopPrank();
    }
    // checked

    function testDoubleClaimToVesting() public {
        // Setup and buy
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(10_000e18);
        vm.stopPrank();

        // Fast forward and claim
        vm.warp(TGE_TIMESTAMP);
        vm.startPrank(buyer1);
        publicSale.claimToVesting();

        // Try to claim again
        vm.expectRevert(PublicSale.PublicSale__AlreadyClaimed.selector);
        publicSale.claimToVesting();
        vm.stopPrank();
    }

    function testWithdrawProceeds() public {
        // Setup and buy with different payment methods
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        usdc.approve(address(publicSale), type(uint256).max);

        publicSale.buyWithUSDT(10_000e18);
        publicSale.buyWithUSDC(5_000e18);
        publicSale.buyWithNative{value: 1 ether}(2_500e18);
        vm.stopPrank();

        // Owner withdraws proceeds
        uint256 initialUsdtBalance = usdt.balanceOf(treasury);
        uint256 initialUsdcBalance = usdc.balanceOf(treasury);
        uint256 initialEthBalance = treasury.balance;

        vm.prank(owner);
        publicSale.withdrawProceeds(payable(treasury));

        // Check that funds were transferred
        assertTrue(usdt.balanceOf(treasury) > initialUsdtBalance);
        assertTrue(usdc.balanceOf(treasury) > initialUsdcBalance);
        assertTrue(treasury.balance > initialEthBalance);

        // Check contract balances are zero
        assertEq(usdt.balanceOf(address(publicSale)), 0);
        assertEq(usdc.balanceOf(address(publicSale)), 0);
        assertEq(address(publicSale).balance, 0);
    }
    // checked

    function testRecoverExcessTokens() public {
        // Fund extra RCX beyond what's needed for sales
        vm.startPrank(owner);
        rcxToken.approve(address(publicSale), 10_000_000e18);
        publicSale.fundRCX(10_000_000e18); // Extra funding beyond the initial 50M

        // Buy some tokens but not all
        publicSale.startSale();
        vm.stopPrank();

        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(10_000e18);
        vm.stopPrank();

        // Recover excess RCX
        uint256 liability = publicSale.unclaimedLiability();
        uint256 contractBalance = rcxToken.balanceOf(address(publicSale));
        uint256 excess = contractBalance - liability;

        vm.prank(owner);
        publicSale.recoverTokens(address(rcxToken), treasury, excess);

        assertEq(rcxToken.balanceOf(treasury), excess);
        assertEq(rcxToken.balanceOf(address(publicSale)), liability);
    }
    // checked

    function testPriceStalenessTolerance() public {
        vm.startPrank(owner);
        publicSale.startSale();

        // Set short staleness tolerance
        publicSale.setPriceStalenessTolerance(300); // 5 minutes
        vm.stopPrank();

        // Fast forward to make price stale
        vm.warp(block.timestamp + 301);

        vm.startPrank(buyer1);
        vm.expectRevert(PublicSale.PublicSale__PriceStale.selector);
        publicSale.buyWithNative{value: 1 ether}(1000e18);
        vm.stopPrank();
    }
    // checked

    function testPauseUnpause() public {
        vm.startPrank(owner);
        publicSale.startSale();

        // Pause contract
        publicSale.pause();
        vm.stopPrank();

        // Try to buy while paused
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        vm.expectRevert(); // Should revert due to whenNotPaused modifier
        publicSale.buyWithUSDT(1000e18);
        vm.stopPrank();

        // Unpause and try again
        vm.prank(owner);
        publicSale.unpause();

        vm.startPrank(buyer1);
        publicSale.buyWithUSDT(1000e18); // Should work now
        assertEq(publicSale.purchased(buyer1), 1000e18);
        vm.stopPrank();
    }
    // checked

    function testVestingTimingEdgeCases() public {
        // Setup: Buy tokens and claim to vesting
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        uint256 purchaseAmount = 50_000e18;
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(purchaseAmount);
        vm.stopPrank();

        vm.warp(TGE_TIMESTAMP);
        vm.prank(buyer1);
        publicSale.claimToVesting();

        RCXVestingFactory.Record memory record = vestingFactory.get(0);
        RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);

        // Test edge case: exactly at TGE timestamp
        vm.warp(TGE_TIMESTAMP);
        assertEq(vesting.claimable(), 0); // TGE release delayed by 1 month

        // Test edge case: exactly at TGE release timestamp
        vm.warp(TGE_TIMESTAMP + 30 days);
        uint256 expectedTGE = (purchaseAmount * 1500) / 10000; // 15%
        assertEq(vesting.claimable(), expectedTGE);

        // Test edge case: exactly at linear start (should be same as TGE release for presale)
        uint256 linearStart = vesting.linearStart();
        vm.warp(linearStart);
        assertEq(vesting.claimable(), expectedTGE);

        // Test edge case: exactly at linear end
        uint256 linearEnd = vesting.linearEnd();
        vm.warp(linearEnd);
        assertEq(vesting.claimable(), purchaseAmount); // All tokens
    }

    function testMultipleVestingCategories() public {
        // This test reveals potential issues with different vesting schedules
        vm.startPrank(owner);
        publicSale.startSale();

        // Since the vesting factory ownership was transferred to publicSale,
        // we need to call the vesting factory methods through the publicSale contract
        // However, the publicSale contract doesn't expose these methods directly.
        // For this test, we'll create vesting contracts by calling the factory directly
        // through the publicSale contract's internal mechanism.

        // We'll simulate the vesting creation by calling the factory directly
        // but we need to do it as the publicSale contract (which is the owner)
        vm.stopPrank();

        // Call vesting factory methods as the publicSale contract (which owns the factory)
        vm.prank(address(publicSale));
        address presaleVestingAddr = vestingFactory.createPresale(address(rcxToken), buyer1, 100_000e18, TGE_TIMESTAMP);

        vm.prank(address(publicSale));
        address idoVestingAddr = vestingFactory.createIDO(address(rcxToken), buyer2, 100_000e18, TGE_TIMESTAMP);

        RCXCategoryVesting presaleVesting = RCXCategoryVesting(presaleVestingAddr);
        RCXCategoryVesting idoVesting = RCXCategoryVesting(idoVestingAddr);

        // Fund the vesting contracts
        vm.startPrank(owner);
        rcxToken.transfer(address(presaleVesting), 100_000e18);
        rcxToken.transfer(address(idoVesting), 100_000e18);
        vm.stopPrank();

        // Test at TGE timestamp
        vm.warp(TGE_TIMESTAMP);
        assertEq(presaleVesting.claimable(), 0); // Presale: 1 month delay
        assertEq(idoVesting.claimable(), 15_000e18); // IDO: immediate TGE

        // Test 1 month after TGE
        vm.warp(TGE_TIMESTAMP + 30 days);
        assertEq(presaleVesting.claimable(), 15_000e18); // Now presale TGE available
        assertEq(idoVesting.claimable(), 15_000e18); // IDO still same (in cliff)
    }
    // checked

    function testBurnFeeScenarios() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        // Test 1: Normal purchase (should not have burn fee)
        vm.startPrank(buyer1);
        usdt.approve(address(publicSale), type(uint256).max);
        publicSale.buyWithUSDT(10_000e18);
        vm.stopPrank();

        // Test 2: Claim to vesting (should not have burn fee)
        vm.warp(TGE_TIMESTAMP);
        vm.prank(buyer1);
        publicSale.claimToVesting();

        // Test 3: Vesting contract transfer to user (should not have burn fee)
        RCXVestingFactory.Record memory record = vestingFactory.get(0);
        RCXCategoryVesting vesting = RCXCategoryVesting(record.vesting);

        vm.warp(TGE_TIMESTAMP + 30 days);
        uint256 balanceBefore = rcxToken.balanceOf(buyer1);

        vm.prank(buyer1);
        vesting.claim();

        uint256 balanceAfter = rcxToken.balanceOf(buyer1);
        uint256 expectedTGE = (10_000e18 * 1500) / 10000;
        assertEq(balanceAfter - balanceBefore, expectedTGE); // No burn fee applied

        // Test 4: Regular user transfer (should have burn fee if enabled)
        vm.prank(buyer1);
        rcxToken.transfer(buyer2, 1000e18);

        // Check if burn fee was applied (buyer1 is not exempt)
        uint256 buyer2Balance = rcxToken.balanceOf(buyer2);
        assertTrue(buyer2Balance < 1000e18); // Should be less due to burn fee
    }
    // checked

    function testAccessControlVulnerabilities() public {
        // Test unauthorized access to critical functions
        vm.startPrank(buyer1); // Non-owner

        // Should fail: only owner can start sale
        vm.expectRevert();
        publicSale.startSale();

        // Should fail: only owner can set vesting exempt
        vm.expectRevert();
        rcxToken.setBurnFeeExempt(buyer1, true);

        // Should fail: only owner can create vesting
        vm.expectRevert();
        vestingFactory.createPresale(address(rcxToken), buyer1, 1000e18, TGE_TIMESTAMP);

        vm.stopPrank();
    }
    // checked

    function testPriceManipulationResistance() public {
        vm.startPrank(owner);
        publicSale.startSale();
        vm.stopPrank();

        // Test with stale price feed
        vm.warp(block.timestamp + 2 hours); // Make price stale

        vm.startPrank(buyer1);
        vm.expectRevert(PublicSale.PublicSale__PriceStale.selector);
        publicSale.buyWithNative{value: 1 ether}(1000e18);
        vm.stopPrank();

        // Test with zero/negative price
        ethUsdFeed.updatePrice(0);

        vm.startPrank(buyer1);
        vm.expectRevert(PublicSale.PublicSale__PriceInvalid.selector);
        publicSale.buyWithNative{value: 1 ether}(1000e18);
        vm.stopPrank();

        ethUsdFeed.updatePrice(-1000e8);

        vm.startPrank(buyer1);
        vm.expectRevert(PublicSale.PublicSale__PriceInvalid.selector);
        publicSale.buyWithNative{value: 1 ether}(1000e18);
        vm.stopPrank();
    }

    receive() external payable {}
}
