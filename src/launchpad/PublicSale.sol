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
    function initialize(
        address _rcx,
        address _usdt,
        address _nativeUsdFeed,
        address _vestingFactory,
        address _owner,
        uint256 _tokenPriceUsd6,
        uint256 _tgeTimestamp,
        uint256 _maxPerWallet
    ) public initializer {
        require(_rcx != address(0) && _usdt != address(0) && _nativeUsdFeed != address(0) && _vestingFactory != address(0) && _owner != address(0), "Invalid addr");
        __Ownable_init(_owner);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(UPGRADER_ROLE, _owner);

        rcx = IERC20(_rcx);
        usdt = IERC20(_usdt);
        nativeUsdFeed = AggregatorV3Interface(_nativeUsdFeed);
        vestingFactory = _vestingFactory;

        tokenPriceUsd6 = _tokenPriceUsd6; // 6 decimals
        tgeTimestamp = _tgeTimestamp;
        maxPerWallet = _maxPerWallet == 0 ? 100_000e18 : _maxPerWallet; // default 100k RCX

        saleActive = false;
    }

    function startSale() external onlyOwner { saleActive = true; emit SaleStarted(); }
    function stopSale() external onlyOwner { saleActive = false; emit SaleStopped(); }

    function pause() external onlyOwner { _pause(); }
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

    function setTokenPriceUsd6(uint256 usd6) external onlyOwner { tokenPriceUsd6 = usd6; emit PriceUpdated(usd6); }
    function setMaxPerWallet(uint256 maxAmount) external onlyOwner { maxPerWallet = maxAmount; emit MaxPerWalletUpdated(maxAmount); }
    function setTgeTimestamp(uint256 ts) external onlyOwner { tgeTimestamp = ts; }

    function fundRCX(uint256 amount) external onlyOwner {
        rcx.safeTransferFrom(msg.sender, address(this), amount);
        emit RcxFunded(amount);
    }


    function usdCost6(uint256 rcxAmount18) public view returns (uint256) {
        // rcxAmount * price (6d) / 1e18 -> 6d
        return (rcxAmount18 * tokenPriceUsd6) / 1e18;
    }

    // function for avoiding stale data from pricefeed and update tolerance of stale data
    function setPriceStalenessTolerance(uint256 tolerance) external onlyOwner {
        if (tolerance == 0) revert PublicSale__InvalidTolerance();
        priceStalenessTolerance = tolerance;
    }

    /// Native coin cost for rcxAmount (18d) using Chainlink native/USD feed (answer decimals vary)
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

    /// Pay in native coin (ETH/BNB/MATIC) using Chainlink native/USD feed
    event DebugStep(string message);
    event DebugError(string message);
    event DebugNativeCost(uint256 cost);

    function buyWithNative(uint256 rcxAmount18) external payable nonReentrant whenNotPaused {
        emit DebugStep("Entered buyWithNative");

        if (!saleActive) {
            emit DebugError("Sale not active");
            revert PublicSale__SaleInactive();
        }
        emit DebugStep("Sale active");

        if (rcxAmount18 == 0) {
            emit DebugError("Amount zero");
            revert PublicSale__AmountZero();
        }
        emit DebugStep("Amount non-zero");

        if (purchased[msg.sender] + rcxAmount18 > maxPerWallet) {
            emit DebugError("Exceeds wallet cap");
            revert PublicSale__ExceedsWalletCap();
        }
        emit DebugStep("Within wallet cap");

        if (totalSold + rcxAmount18 > PRESALE_CAP) {
            emit DebugError("Exceeds presale cap");
            revert PublicSale__ExceedsPresaleCap();
        }
        emit DebugStep("Within presale cap");

        uint256 need = nativeCost(rcxAmount18);
        emit DebugNativeCost(need);

        if (msg.value < need) {
            emit DebugError("Insufficient native value sent");
            revert PublicSale__InsufficientNative();
        }
        emit DebugStep("Sufficient native value");


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

    function withdrawProceeds(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert PublicSale__ZeroToAddress();
        uint256 usdtBal = usdt.balanceOf(address(this));
        if (usdtBal > 0) usdt.safeTransfer(to, usdtBal);

        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) {
            (bool ok, ) = to.call{value: nativeBal}("");
            if (!ok) revert PublicSale__TransferFailed();
        }

        emit ProceedsWithdrawn(to, usdtBal, nativeBal);
    }

    function unclaimedLiability() external view returns (uint256) {
        return _unclaimedLiability();
    }
    
    /// @notice Recover tokens mistakenly sent (not RCX unless excess over liabilities)
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

    // -------- UUPS --------
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert PublicSale__InvalidImplementation();
    }

    receive() external payable {}
}
