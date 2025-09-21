// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {RecurXToken} from "../core/RecurxToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PublicSale is
    Initializable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;


    error PublicSale__ZeroAddress();
    error PublicSale__SaleInactive();
    error PublicSale__AmountZero();
    error PublicSale__ExceedsWalletCap();
    error PublicSale__ExceedsPresaleCap();
    error PublicSale__InsufficientNative();
    error PublicSale__RefundFailed();
    error PublicSale__AlreadyClaimed();
    error PublicSale__NothingToClaim();
    error PublicSale__InsufficientRCXFunded();
    error PublicSale__VestingFactoryCallFailed();
    error PublicSale__VestingZeroAddress();
    error PublicSale__Unauthorized();
    error PublicSale__PriceInvalid();
    error PublicSale__PriceStale();
    error PublicSale__InvalidTolerance();
    error PublicSale__InvalidDecimals();
    error PublicSale__ZeroToAddress();
    error PublicSale__InvalidImplementation();
    error PublicSale__NoExcessRCX();
    error PublicSale__ExceedsExcess();
    error PublicSale__TransferFailed();

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    IERC20 public rcx;            // RCX token (18d)
    IERC20 public usdt;           // USDT (6d)
    IERC20 public usdc;           // USDC (6d)
    AggregatorV3Interface public nativeUsdFeed; // e.g. ETH/USD, BNB/USD, MATIC/USD
    address public vestingFactory;             // RCXVestingFactory

    uint256 public constant PRESALE_CAP = 20_000_000e18; // 20M RCX (18d)
    uint256 public tokenPriceUsd6;     // price per RCX in USD with 6 decimals (e.g., $0.10 = 100_000)
    uint256 public tgeTimestamp;       // unix TGE timestamp; claim enabled at/after this

    uint256 public maxPerWallet;       // default set in initialize (e.g., 100_000e18)

    bool public saleActive;
    uint256 public totalSold; // RCX (18d)
    uint256 public priceStalenessTolerance = 1 hours;

    // mapping(address => bool) public kycApproved;

    mapping(address => uint256) public purchased; // RCX (18d)
    mapping(address => bool) public claimed;      // whether this buyer claimed vesting

    uint256 public totalClaimed; // keeping track of claimed tokens

    struct Stage {
        uint256 priceUsd6; // Price per token in USD (6 decimals)
        uint256 tokenAllocation; // Total tokens available in this stage
        uint256 tokensSold; // Tokens sold in this stage
    }

    Stage[] public stages; // Array of all stages
    uint256 public currentStageIndex;

    event SaleStarted();
    event SaleStopped();
    // event KYCApproved(address indexed user);
    // event KYCBatchApproved(uint256 count);
    event PriceUpdated(uint256 usd6);
    event MaxPerWalletUpdated(uint256 maxAmount);
    event Purchased(address indexed buyer, uint256 rcxAmount, address paymentToken, uint256 paymentAmount);
    event ClaimedToVesting(address indexed buyer, address vesting, uint256 rcxAmount);
    event ProceedsWithdrawn(address indexed to, uint256 usdtAmount, uint256 nativeAmount);
    event RcxFunded(uint256 amount);
    event TokensRecovered(address indexed token, address indexed to, uint256 amount);
    event TgeTimestampUpdated(uint256 ts);

    event StageInitialized(uint256 indexed stageIndex, uint256 priceUsd6, uint256 tokenAllocation);
    event StageCompleted(uint256 indexed stageIndex);
    event StageAdvanced(uint256 indexed fromStage, uint256 indexed toStage);

    // uint16 internal constant PRESALE_TGE_BPS = 1500; // 15%
    // uint32 internal constant PRESALE_CLIFF_MONTHS = 1;
    // uint32 internal constant PRESALE_VESTING_MONTHS = 9;
    // uint32 internal constant PRESALE_TGE_RELEASE_OFFSET_MONTHS = 0;

    // -------- Initialization --------
    /// @notice Initializes the PublicSale contract with required parameters.
    /// @param _rcx Address of the RCX token (18 decimals).
    /// @param _usdt Address of the USDT token (6 decimals).
    /// @param _usdc Address of the USDC token (6 decimals).
    /// @param _nativeUsdFeed Chainlink price feed address for native/USD.
    /// @param _vestingFactory Address of the RCX vesting factory.
    /// @param _owner Address of the contract owner.
    /// @param _tokenPriceUsd6 Price of one RCX token in USD (6 decimals). Default fallback price from now on
    /// @param _tgeTimestamp Timestamp for the TGE (Token Generation Event).
    /// @param _maxPerWallet Maximum RCX an individual wallet can purchase.

    function initialize(
        address _rcx,
        address _usdt,
        address _usdc,
        address _nativeUsdFeed,
        address _vestingFactory,
        address _owner,
        uint256 _tokenPriceUsd6,
        uint256 _tgeTimestamp,
        uint256 _maxPerWallet
    ) public initializer {
        require(
            _rcx != address(0) && _usdt != address(0) && _usdc != address(0) && _nativeUsdFeed != address(0)
                && _vestingFactory != address(0) && _owner != address(0),
            "Invalid addr"
        );
        __Ownable_init(_owner);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(UPGRADER_ROLE, _owner);

        rcx = IERC20(_rcx);
        usdt = IERC20(_usdt);
        usdc = IERC20(_usdc);
        nativeUsdFeed = AggregatorV3Interface(_nativeUsdFeed);
        vestingFactory = _vestingFactory;

        tokenPriceUsd6 = _tokenPriceUsd6; // 6 decimals
        tgeTimestamp = _tgeTimestamp;
        maxPerWallet = _maxPerWallet == 0 ? 100_000e18 : _maxPerWallet; // default 100k RCX

        saleActive = false;
        priceStalenessTolerance = 1 hours; // Ensure staleness tolerance is set

        currentStageIndex = 0;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Starts the public sale. Only callable by the owner.
    function startSale() external onlyOwner { saleActive = true; emit SaleStarted(); }

    /// @notice Stops the public sale. Only callable by the owner.
    function stopSale() external onlyOwner { saleActive = false; emit SaleStopped(); }

    /// @notice Pauses the contract, disabling sensitive functions. Only callable by the owner.
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpauses the contract. Only callable by the owner.
    function unpause() external onlyOwner { _unpause(); }

    // function approveKYC(address user, bool approved) external onlyOwner {
    //     require(user != address(0), "Zero addr");
    //     kycApproved[user] = approved;
    //     if (approved) emit KYCApproved(user);
    // }

    // function approveKYCBatch(address[] calldata users) external onlyOwner {
    //     uint256 length = users.length;
    //     require(length > 0, "Empty array");

    //     for (uint256 i = 0; i < length; ) {
    //         address u = users[i];
    //         if (u != address(0)) {
    //             kycApproved[u] = true;
    //             emit KYCApproved(u);
    //         }
    //         unchecked { ++i; }
    //     }
    //     emit KYCBatchApproved(length);
    // }

    /// @notice Updates the token price in USD (6 decimals).
    /// @param usd6 The new price per RCX token in USD with 6 decimals.
    function setTokenPriceUsd6(uint256 usd6) external onlyOwner { tokenPriceUsd6 = usd6; emit PriceUpdated(usd6); }

    /// @notice Sets the maximum number of RCX tokens a wallet can buy.
    /// @param maxAmount The new maximum amount per wallet.
    function setMaxPerWallet(uint256 maxAmount) external onlyOwner { maxPerWallet = maxAmount; emit MaxPerWalletUpdated(maxAmount); }

    /// @notice Sets the timestamp for the Token Generation Event (TGE).
    /// @param ts The new TGE timestamp.
    function setTgeTimestamp(uint256 ts) external onlyOwner {
        require(ts > block.timestamp, "Invalid TGE timestamp");
        tgeTimestamp = ts;
        emit TgeTimestampUpdated(ts);
    }

    /// @notice Funds the contract with RCX tokens for vesting.
    /// @param amount Amount of RCX tokens to transfer into the contract.
    function fundRCX(uint256 amount) external onlyOwner {
        rcx.safeTransferFrom(msg.sender, address(this), amount);
        emit RcxFunded(amount);
    }

    /// @notice Calculates the USD cost (6 decimals) for a given amount of RCX.
    /// @param rcxAmount18 Amount of RCX tokens (18 decimals).
    /// @return cost6 Cost in USD (6 decimals).
    function usdCost6(uint256 rcxAmount18) public view returns (uint256) {
        // rcxAmount * price (6d) / 1e18 -> 6d
        // return (rcxAmount18 * tokenPriceUsd6) / 1e18;
        (uint256 cost, bool canPurchase) = calculateCostAcrossStages(rcxAmount18);
        require(canPurchase, "Exceeds available allocation");
        return cost;
    }

    /// @notice Sets the maximum time allowed for the price feed to be considered fresh.
    /// @param tolerance Maximum allowed staleness duration in seconds.
    function setPriceStalenessTolerance(uint256 tolerance) external onlyOwner {
        if (tolerance == 0) revert PublicSale__InvalidTolerance();
        priceStalenessTolerance = tolerance;
    }

    //------------>>>  STAGE PRICE FUNCTUONS

    /// @notice Initialize all presale stages based on CSV data
    /// @param _pricesUsd6 Array of stage data (priceUsd6, tokenAllocation)
    /// @param _tokenAllocations Number of tokens allocated per stage

    function initializeStages(uint256[] calldata _pricesUsd6, uint256[] calldata _tokenAllocations)
        external
        onlyOwner
    {
        require(_pricesUsd6.length == _tokenAllocations.length, "Array length mismatch");
        require(_pricesUsd6.length > 0, "At least one stage required");

        // Clear existing stages
        delete stages;

        // Add new stages
        for (uint256 i = 0; i < _pricesUsd6.length; i++) {
            stages.push(Stage({priceUsd6: _pricesUsd6[i], tokenAllocation: _tokenAllocations[i], tokensSold: 0}));

            emit StageInitialized(i, _pricesUsd6[i], _tokenAllocations[i]);
        }

        currentStageIndex = 0;
    }

    ///
    /// @notice Calculate total USD cost for purchasing RCX across multiple stages
    /// @param rcxAmount18 Total RCX amount to purchase (18 decimals)
    /// @return totalCostUsd6 Total cost in USD (6 decimals)
    /// @return canPurchase Whether the purchase is possible

    function calculateCostAcrossStages(uint256 rcxAmount18)
        public
        view
        returns (uint256 totalCostUsd6, bool canPurchase)
    {
        if (stages.length == 0) {
            // Fallback to single price
            return (usdCost6(rcxAmount18), totalSold + rcxAmount18 <= PRESALE_CAP);
        }

        uint256 remaining = rcxAmount18;
        uint256 totalCost = 0;
        uint256 stageIdx = currentStageIndex;

        while (remaining > 0 && stageIdx < stages.length) {
            Stage memory stage = stages[stageIdx];
            uint256 availableInStage = stage.tokenAllocation - stage.tokensSold;

            if (availableInStage == 0) {
                stageIdx++;
                continue;
            }

            uint256 tokensFromThisStage = remaining > availableInStage ? availableInStage : remaining;
            uint256 costFromThisStage = (tokensFromThisStage * stage.priceUsd6) / 1e18;

            totalCost += costFromThisStage;
            remaining -= tokensFromThisStage;
            stageIdx++;
        }

        return (totalCost, remaining == 0);
    }

    function _updateStageProgress(uint256 tokensPurchased) internal {
        if (stages.length == 0) return;

        uint256 remaining = tokensPurchased;

        while (remaining > 0 && currentStageIndex < stages.length) {
            Stage storage currentStage = stages[currentStageIndex];
            uint256 availableInCurrentStage = currentStage.tokenAllocation - currentStage.tokensSold;

            if (availableInCurrentStage == 0) {
                currentStageIndex++;
                continue;
            }

            uint256 tokensToCurrentStage = remaining > availableInCurrentStage ? availableInCurrentStage : remaining;

            currentStage.tokensSold += tokensToCurrentStage;
            remaining -= tokensToCurrentStage;

            // Check if stage is completed
            if (currentStage.tokensSold >= currentStage.tokenAllocation) {
                emit StageCompleted(currentStageIndex);

                uint256 oldStageIndex = currentStageIndex;
                currentStageIndex++;

                if (currentStageIndex < stages.length) {
                    emit StageAdvanced(oldStageIndex, currentStageIndex);
                }
            }
        }
    }

    function getCurrentStage()
        external
        view
        returns (
            uint256 stageIndex,
            uint256 priceUsd6,
            uint256 tokenAllocation,
            uint256 tokensSold,
            uint256 tokensRemaining
        )
    {
        if (stages.length == 0) {
            return (0, tokenPriceUsd6, PRESALE_CAP, totalSold, PRESALE_CAP - totalSold);
        }

        Stage memory stage = stages[currentStageIndex];
        return (
            currentStageIndex,
            stage.priceUsd6,
            stage.tokenAllocation,
            stage.tokensSold,
            stage.tokenAllocation - stage.tokensSold
        );
    }

    /// @notice Calculates the cost in native token (ETH, BNB, etc.) for a given RCX amount.
    /// @param rcxAmount18 Amount of RCX tokens (18 decimals).
    /// @return costNative Cost in native token (18 decimals).
    // function nativeCost(uint256 rcxAmount18) public view returns (uint256) {
    //     (
    //         uint80 roundId,
    //         int256 price,
    //         // uint256 startedAt
    //         ,
    //         uint256 updatedAt,
    //         uint80 answeredInRound
    //     ) = nativeUsdFeed.latestRoundData();

    //     // Enhanced validations
    //     if(price <= 0) revert PublicSale__PriceInvalid();
    //     if (updatedAt == 0 || block.timestamp - updatedAt >= priceStalenessTolerance) revert PublicSale__PriceStale();
    //     if (answeredInRound < roundId) revert PublicSale__PriceStale();


    //     uint8 feedDecimals = nativeUsdFeed.decimals();
    //     if (feedDecimals > 18) revert PublicSale__InvalidDecimals();

    //     uint256 usdCost = usdCost6(rcxAmount18); // 6 decimals
    //     uint256 usd18 = usdCost * 1e12; // Convert to 18 decimals

    //     uint256 normalizedPrice;
    //     if (feedDecimals <= 18) {
    //         normalizedPrice = uint256(price) * (10 ** (18 - feedDecimals));
    //     } else {
    //         // This shouldn't happen with the require above, but defensive programming
    //         normalizedPrice = uint256(price) / (10 ** (feedDecimals - 18));
    //     }

    //     if (normalizedPrice == 0) revert PublicSale__PriceInvalid();
    //     // return (usd18 * 1e18) / normalizedPrice;
    //     return Math.mulDiv(usd18, 1e18, normalizedPrice);

    // }


    /// @notice Buys RCX tokens using USDT.
    /// @param rcxAmount18 Amount of RCX to purchase (18 decimals).
    function buyWithUSDT(uint256 rcxAmount18) external nonReentrant whenNotPaused {
        if (!saleActive) revert PublicSale__SaleInactive();
        if (rcxAmount18 == 0) revert PublicSale__AmountZero();
        // require(kycApproved[msg.sender], "KYC");
        if (purchased[msg.sender] + rcxAmount18 > maxPerWallet) revert PublicSale__ExceedsWalletCap();
        if (totalSold + rcxAmount18 > PRESALE_CAP) revert PublicSale__ExceedsPresaleCap();

        // uint256 cost6 = usdCost6(rcxAmount18); // USDT has 6 decimals
        (uint256 cost6, bool canPurchase) = calculateCostAcrossStages(rcxAmount18);
        if (!canPurchase) revert PublicSale__ExceedsPresaleCap();

        usdt.safeTransferFrom(msg.sender, address(this), cost6);

        _updateStageProgress(rcxAmount18);

        purchased[msg.sender] += rcxAmount18;
        totalSold += rcxAmount18;

        emit Purchased(msg.sender, rcxAmount18, address(usdt), cost6);
    }

    /// @notice Buys RCX tokens using USDC.
    /// @param rcxAmount18 Amount of RCX to purchase (18 decimals).
    function buyWithUSDC(uint256 rcxAmount18) external nonReentrant whenNotPaused {
        if (!saleActive) revert PublicSale__SaleInactive();
        if (rcxAmount18 == 0) revert PublicSale__AmountZero();
        if (purchased[msg.sender] + rcxAmount18 > maxPerWallet) revert PublicSale__ExceedsWalletCap();
        if (totalSold + rcxAmount18 > PRESALE_CAP) revert PublicSale__ExceedsPresaleCap();

        // uint256 cost6 = usdCost6(rcxAmount18); // same as USDT, since 6 decimals
        (uint256 cost6, bool canPurchase) = calculateCostAcrossStages(rcxAmount18);
        if (!canPurchase) revert PublicSale__ExceedsPresaleCap();

        usdc.safeTransferFrom(msg.sender, address(this), cost6);

        _updateStageProgress(rcxAmount18);

        purchased[msg.sender] += rcxAmount18;
        totalSold += rcxAmount18;

        emit Purchased(msg.sender, rcxAmount18, address(usdc), cost6);
    }

    // event DebugStep(string message);
    // event DebugError(string message);
    // event DebugNativeCost(uint256 cost);

    /// Pay in native coin (ETH/BNB/MATIC) using Chainlink native/USD feed
    /// @notice Buys RCX tokens using native cryptocurrency (e.g., ETH, BNB).
    /// @param rcxAmount18 Amount of RCX to purchase (18 decimals).
    function buyWithNative(uint256 rcxAmount18) external payable nonReentrant whenNotPaused {
        if (!saleActive) revert PublicSale__SaleInactive();
        if (rcxAmount18 == 0) revert PublicSale__AmountZero();
        if (purchased[msg.sender] + rcxAmount18 > maxPerWallet) revert PublicSale__ExceedsWalletCap();
        if (totalSold + rcxAmount18 > PRESALE_CAP) revert PublicSale__ExceedsPresaleCap();

        (uint256 costUsd6, bool canPurchase) = calculateCostAcrossStages(rcxAmount18);
        if (!canPurchase) revert PublicSale__ExceedsPresaleCap();

        uint256 need = _usdToNative(costUsd6);

        if (msg.value < need) revert PublicSale__InsufficientNative();

        _updateStageProgress(rcxAmount18);

        purchased[msg.sender] += rcxAmount18;
        totalSold += rcxAmount18;

        if (msg.value > need) {
            (bool ok,) = payable(msg.sender).call{value: msg.value - need}("");
            if (!ok) revert PublicSale__RefundFailed();
        }

        emit Purchased(msg.sender, rcxAmount18, address(0), need);
    }

    function usdToNative(uint256 usdAmount6) public view returns (uint256) {
        return _usdToNative(usdAmount6);
    }

    function nativeCost(uint256 rcxAmount18) public view returns (uint256) {
        (uint256 cost, bool canPurchase) = calculateCostAcrossStages(rcxAmount18);
        require(canPurchase, "Exceeds available allocation");
        return _usdToNative(cost);
    }

    function _usdToNative(uint256 usdAmount6) internal view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = nativeUsdFeed.latestRoundData();

        if(price <= 0) revert PublicSale__PriceInvalid();
        if (updatedAt == 0 || block.timestamp - updatedAt >= priceStalenessTolerance) revert PublicSale__PriceStale();
        if (answeredInRound < roundId) revert PublicSale__PriceStale();

        uint8 feedDecimals = nativeUsdFeed.decimals();
        if (feedDecimals > 18) revert PublicSale__InvalidDecimals();

        uint256 usd18 = usdAmount6 * 1e12; // Convert to 18 decimals
        uint256 normalizedPrice;
        if (feedDecimals <= 18) {
            normalizedPrice = uint256(price) * (10 ** (18 - feedDecimals));
        } else {
            normalizedPrice = uint256(price) / (10 ** (feedDecimals - 18));
        }

        if (normalizedPrice == 0) revert PublicSale__PriceInvalid();
        return Math.mulDiv(usd18, 1e18, normalizedPrice);
    }

    /**
     * @notice Get information about a specific stage
     */
    function getStage(uint256 stageIndex) external view returns (
        uint256 priceUsd6,
        uint256 tokenAllocation,
        uint256 tokensSold,
        uint256 tokensRemaining
    ) {
        require(stageIndex < stages.length, "Invalid stage index");
        Stage memory stage = stages[stageIndex];
        return (
            stage.priceUsd6,
            stage.tokenAllocation,
            stage.tokensSold,
            stage.tokenAllocation - stage.tokensSold
        );
    }

    /**
     * @notice Get total number of stages
     */
    function getTotalStages() external view returns (uint256) {
        return stages.length;
    }

    /// After TGE, deploy a personal vesting via RCXVestingFactory and fund it with buyer's purchased RCX.
    /// @notice Claims purchased RCX tokens and sends them to a vesting contract.
    /// @dev Deploys a new vesting contract from the factory and transfers tokens.

    function claimToVesting() external nonReentrant whenNotPaused {
        if (block.timestamp < tgeTimestamp) revert PublicSale__Unauthorized();
        // require(kycApproved[msg.sender], "KYC");
        if (claimed[msg.sender]) revert PublicSale__AlreadyClaimed();
        uint256 amount = purchased[msg.sender];
        if (amount == 0) revert PublicSale__NothingToClaim();
        if (rcx.balanceOf(address(this)) < amount) revert PublicSale__InsufficientRCXFunded();

        // Create vesting with Presale preset
        address vesting =  _createPresaleVesting(msg.sender, amount);
        RecurXToken(address(rcx)).setVestingContractExempt(vesting);

        rcx.safeTransfer(vesting, amount);

        claimed[msg.sender] = true;

        totalClaimed += amount; // keep track of totalclaimed tokens by vesting users

        emit ClaimedToVesting(msg.sender, vesting, amount);
    }

    /// @notice Creates a vesting contract for a presale buyer.
    /// @param beneficiary Address of the user receiving the vesting contract.
    /// @param allocation Total RCX allocation to be vested.
    /// @return vesting Address of the newly created vesting contract.
    function _createPresaleVesting(address beneficiary, uint256 allocation) internal returns (address vesting) {
        // RCXVestingFactory.createPresale(token, beneficiary, allocation, tgeTimestamp)

        (bool ok, bytes memory data) = vestingFactory.call(
            abi.encodeWithSignature(
                "createPresale(address,address,uint256,uint256)",
                address(rcx),
                beneficiary,
                allocation,
                tgeTimestamp
            )
        );
        if (!ok || data.length < 32) revert PublicSale__VestingFactoryCallFailed();
        assembly { vesting := mload(add(data, 32)) }
        if (vesting == address(0)) revert PublicSale__VestingZeroAddress();
    }

    // -------- Owner withdrawals --------

    /// @notice Withdraws collected funds (USDT, USDC, native) to a specified address.
    /// @param to Address to receive the proceeds.

    function withdrawProceeds(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert PublicSale__ZeroToAddress();
        uint256 usdtBal = usdt.balanceOf(address(this));
        if (usdtBal > 0) usdt.safeTransfer(to, usdtBal);

        uint256 usdcBal = usdc.balanceOf(address(this));
        if (usdcBal > 0) usdc.safeTransfer(to, usdcBal);

        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) {
            (bool ok, ) = to.call{value: nativeBal}("");
            if (!ok) revert PublicSale__TransferFailed();
        }

        emit ProceedsWithdrawn(to, usdtBal, nativeBal);
    }

    /// @notice Returns the total unclaimed liability in RCX.
    /// @return liability Total amount of unclaimed RCX.
    function unclaimedLiability() external view returns (uint256) {
        return _unclaimedLiability();
    }

    /// @notice Recover tokens mistakenly sent (not RCX unless excess over liabilities)
    /// @param tokenAddr Address of the token to recover.
    /// @param to Address to send the recovered tokens.
    /// @param amount Amount of tokens to recover.
    function recoverTokens(address tokenAddr, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert PublicSale__ZeroToAddress();
        if (amount == 0) revert PublicSale__AmountZero();
        if (tokenAddr == address(rcx)) {
            // only allow recovering *excess* RCX beyond sold but unclaimed liabilities
            uint256 liabilities = _unclaimedLiability();
            uint256 bal = rcx.balanceOf(address(this));
            if (bal <= liabilities) revert PublicSale__NoExcessRCX();
            if (amount > bal - liabilities) revert PublicSale__ExceedsExcess();
        }
        IERC20(tokenAddr).safeTransfer(to, amount);
        emit TokensRecovered(tokenAddr, to, amount);
    }


    function _unclaimedLiability() internal view returns (uint256) {
        // return totalSold;
        return totalSold - totalClaimed;
    }

    /// @notice Authorizes a new implementation for UUPS upgradeability.
    /// @param newImplementation Address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert PublicSale__InvalidImplementation();
    }

    receive() external payable {}
}
