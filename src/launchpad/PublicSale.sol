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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RecurXToken} from "../core/RecurxToken.sol";

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

    uint16 internal constant PRESALE_TGE_BPS = 1500; // 15%
    uint32 internal constant PRESALE_CLIFF_MONTHS = 1;
    uint32 internal constant PRESALE_VESTING_MONTHS = 9;
    uint32 internal constant PRESALE_TGE_RELEASE_OFFSET_MONTHS = 0;

    // -------- Initialization --------
    /// @notice Initializes the PublicSale contract with required parameters.
    /// @param _rcx Address of the RCX token (18 decimals).
    /// @param _usdt Address of the USDT token (6 decimals).
    /// @param _usdc Address of the USDC token (6 decimals).
    /// @param _nativeUsdFeed Chainlink price feed address for native/USD.
    /// @param _vestingFactory Address of the RCX vesting factory.
    /// @param _owner Address of the contract owner.
    /// @param _tokenPriceUsd6 Price of one RCX token in USD (6 decimals).
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
        require(_rcx != address(0) && _usdt != address(0) && _usdc != address(0) && _nativeUsdFeed != address(0) && _vestingFactory != address(0) && _owner != address(0), "Invalid addr");
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
    function setTgeTimestamp(uint256 ts) external onlyOwner { tgeTimestamp = ts; }

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
        return (rcxAmount18 * tokenPriceUsd6) / 1e18;
    }

    /// @notice Sets the maximum time allowed for the price feed to be considered fresh.
    /// @param tolerance Maximum allowed staleness duration in seconds.
    function setPriceStalenessTolerance(uint256 tolerance) external onlyOwner {
        if (tolerance == 0) revert PublicSale__InvalidTolerance();
        priceStalenessTolerance = tolerance;
    }

    /// @notice Calculates the cost in native token (ETH, BNB, etc.) for a given RCX amount.
    /// @param rcxAmount18 Amount of RCX tokens (18 decimals).
    /// @return costNative Cost in native token (18 decimals).
    function nativeCost(uint256 rcxAmount18) public view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            // uint256 startedAt
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = nativeUsdFeed.latestRoundData();

        // Enhanced validations
        if(price <= 0) revert PublicSale__PriceInvalid();
        if (updatedAt == 0 || block.timestamp - updatedAt >= priceStalenessTolerance) revert PublicSale__PriceStale();
        if (answeredInRound < roundId) revert PublicSale__PriceStale();

        
        uint8 feedDecimals = nativeUsdFeed.decimals();
        if (feedDecimals > 18) revert PublicSale__InvalidDecimals();

        uint256 usdCost = usdCost6(rcxAmount18); // 6 decimals
        uint256 usd18 = usdCost * 1e12; // Convert to 18 decimals

        uint256 normalizedPrice;
        if (feedDecimals <= 18) {
            normalizedPrice = uint256(price) * (10 ** (18 - feedDecimals));
        } else {
            // This shouldn't happen with the require above, but defensive programming
            normalizedPrice = uint256(price) / (10 ** (feedDecimals - 18));
        }

        if (normalizedPrice == 0) revert PublicSale__PriceInvalid();
        return (usd18 * 1e18) / normalizedPrice;
    }


    /// @notice Buys RCX tokens using USDT.
    /// @param rcxAmount18 Amount of RCX to purchase (18 decimals).
    function buyWithUSDT(uint256 rcxAmount18) external nonReentrant whenNotPaused {
        if (!saleActive) revert PublicSale__SaleInactive();
        if (rcxAmount18 == 0) revert PublicSale__AmountZero();
         // require(kycApproved[msg.sender], "KYC");
        if (purchased[msg.sender] + rcxAmount18 > maxPerWallet) revert PublicSale__ExceedsWalletCap();
        if (totalSold + rcxAmount18 > PRESALE_CAP) revert PublicSale__ExceedsPresaleCap();


        uint256 cost6 = usdCost6(rcxAmount18); // USDT has 6 decimals
        usdt.safeTransferFrom(msg.sender, address(this), cost6);

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

        uint256 cost6 = usdCost6(rcxAmount18); // same as USDT, since 6 decimals
        usdc.safeTransferFrom(msg.sender, address(this), cost6);

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
        // emit DebugStep("Entered buyWithNative");

        if (!saleActive) {
            // emit DebugError("Sale not active");
            revert PublicSale__SaleInactive();
        }
        // emit DebugStep("Sale active");

        if (rcxAmount18 == 0) {
            // emit DebugError("Amount zero");
            revert PublicSale__AmountZero();
        }
        // emit DebugStep("Amount non-zero");

        if (purchased[msg.sender] + rcxAmount18 > maxPerWallet) {
            // emit DebugError("Exceeds wallet cap");
            revert PublicSale__ExceedsWalletCap();
        }
        // emit DebugStep("Within wallet cap");

        if (totalSold + rcxAmount18 > PRESALE_CAP) {
            // emit DebugError("Exceeds presale cap");
            revert PublicSale__ExceedsPresaleCap();
        }
        // emit DebugStep("Within presale cap");

        uint256 need = nativeCost(rcxAmount18);
        // emit DebugNativeCost(need);

        if (msg.value < need) {
            // emit DebugError("Insufficient native value sent");
            revert PublicSale__InsufficientNative();
        }
        // emit DebugStep("Sufficient native value");


        purchased[msg.sender] += rcxAmount18;
        totalSold += rcxAmount18;

        // dust
        if (msg.value > need) {
            (bool ok, ) = payable(msg.sender).call{value: msg.value - need}("");
            if (!ok) revert PublicSale__RefundFailed();
        }

        emit Purchased(msg.sender, rcxAmount18, address(0), need);
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
        return totalSold;
    }

    /// @notice Authorizes a new implementation for UUPS upgradeability.
    /// @param newImplementation Address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert PublicSale__InvalidImplementation();
    }

    receive() external payable {}
}
