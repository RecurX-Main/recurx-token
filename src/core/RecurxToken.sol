// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RecurXToken is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    error RecurXToken__InvalidOwnerAddress();
    error RecurXToken__InvalidAddress();
    error RecurXToken__AmountMustBeGreaterThanZero();
    error RecurXToken__InsufficientBalance();
    error RecurXToken__InsufficientAllowance();
    error RecurXToken__TransferToZeroAddress();
    error RecurXToken__CannotRecoverOwnTokens();
    error RecurXToken__InvalidRecipient();
    error RecurXToken__InvalidAmount();
    error RecurXToken__InvalidImplementation();

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant VESTING_MANAGER_ROLE = keccak256("VESTING_MANAGER_ROLE");

    uint256 public constant TOTAL_SUPPLY = 500_000_000 * 10 ** 18;

    // uint256 public constant BURN_FEE_PERCENT = 1;
    uint256 public constant BURN_FEE_BPS = 1; // 0.001%
    uint256 public constant BPS_DENOMINATOR = 100_000;


    uint256 public s_totalBurned;
    bool public s_burnFeeEnabled;

    mapping(address => bool) public s_burnFeeExempt;

    event BurnFeeToggled(bool enabled);
    event BurnFeeExemptionSet(address indexed account, bool exempt);
    event TokensBurned(address indexed account, uint256 amount, string reason);
    event TokensRecovered(address indexed token, address indexed to, uint256 amount);

    /// @notice Initializes the RecurX token contract with the given owner.
    /// @param initialOwner The address of the initial owner.
    function initialize(address initialOwner) public initializer {
        if (initialOwner == address(0)) revert RecurXToken__InvalidOwnerAddress();

        __ERC20_init("RecurX Token", "RCX");
        __Ownable_init(initialOwner);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(PAUSER_ROLE, initialOwner);
        _grantRole(UPGRADER_ROLE, initialOwner);
        _grantRole(VESTING_MANAGER_ROLE, initialOwner);

        _mint(initialOwner, TOTAL_SUPPLY);

        s_burnFeeEnabled = true;

        s_burnFeeExempt[initialOwner] = true;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Exempts a vesting contract from burn fees.
    /// @param vestingContract The address to exempt.
    function setVestingContractExempt(address vestingContract) external onlyRole(VESTING_MANAGER_ROLE) {
        if (vestingContract == address(0)) revert RecurXToken__InvalidAddress();
        s_burnFeeExempt[vestingContract] = true;
        emit BurnFeeExemptionSet(vestingContract, true);
    }

    // function setVestingContractExempt(address vestingContract) external onlyOwner {
    //     require(vestingContract != address(0), "Invalid address");
    //     s_burnFeeExempt[vestingContract] = true;
    //     emit BurnFeeExemptionSet(vestingContract, true);
    // }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Enables or disables the burn fee mechanism.
    /// @param enabled Boolean to enable or disable burn fee.
    function sets_BurnFeeEnabled(bool enabled) external onlyOwner {
        s_burnFeeEnabled = enabled;
        emit BurnFeeToggled(enabled);
    }

    /// @notice Sets whether an account is exempt from burn fees.
    /// @param account The address to update exemption for.
    /// @param exempt Whether the address is exempt.
    function setBurnFeeExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert RecurXToken__InvalidAddress();
        s_burnFeeExempt[account] = exempt;
        emit BurnFeeExemptionSet(account, exempt);
    }

    /// @notice Sets burn fee exemption for multiple addresses.
    /// @param accounts Array of addresses to update.
    /// @param exempt Whether the addresses are exempt.
    function setBurnFeeExemptBatch(address[] calldata accounts, bool exempt) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) revert RecurXToken__InvalidAddress();
            s_burnFeeExempt[accounts[i]] = exempt;
            emit BurnFeeExemptionSet(accounts[i], exempt);
        }
    }

    /// @notice Burns a specified amount of tokens from the caller’s account.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 amount) external {
        if (amount == 0) revert RecurXToken__AmountMustBeGreaterThanZero();
        if (balanceOf(msg.sender) < amount) revert RecurXToken__InsufficientBalance();

        _burn(msg.sender, amount);
        s_totalBurned += amount;
        emit TokensBurned(msg.sender, amount, "Manual burn");
    }

    /// @notice Burns a specified amount of tokens from another account, using allowance.
    /// @param account The address to burn tokens from.
    /// @param amount The amount to burn.
    function burnFrom(address account, uint256 amount) external {
        if (amount == 0) revert RecurXToken__AmountMustBeGreaterThanZero();
        if (account == address(0)) revert RecurXToken__InvalidAddress();
        if (balanceOf(account) < amount) revert RecurXToken__InsufficientBalance();

        uint256 currentAllowance = allowance(account, msg.sender);
        if (currentAllowance < amount) revert RecurXToken__InsufficientAllowance();

        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
        s_totalBurned += amount;
        emit TokensBurned(account, amount, "Burn from allowance");
    }

    function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        // if (to == address(0)) revert RecurXToken__TransferToZeroAddress();

        // if (from != address(0) && to != address(0) && s_burnFeeEnabled) {
        //     if (!s_burnFeeExempt[from]) {
        //         uint256 burnAmount = (amount * BURN_FEE_PERCENT) / 100;

        //         if (burnAmount > 0) {
        //             super._update(from, address(0), burnAmount);
        //             s_totalBurned += burnAmount;
        //             emit TokensBurned(from, burnAmount, "Transfer burn fee");

        //             amount -= burnAmount;
        //         }
        //     }
        // }

        // super._update(from, to, amount);

        if (from != address(0) && to != address(0) && s_burnFeeEnabled) { 
            if (!s_burnFeeExempt[from]) {

                // uint256 burnAmount = (amount * BURN_FEE_PERCENT) / 100; 
                uint256 burnAmount = (amount * BURN_FEE_BPS) / BPS_DENOMINATOR;
                
                if (burnAmount > 0) {
                    super._update(from, address(0), burnAmount);
                    s_totalBurned += burnAmount;
                    emit TokensBurned(from, burnAmount, "Transfer burn fee");

                    amount -= burnAmount;
                }
            }
        }

        super._update(from, to, amount);
    }

    /// @notice Calculates the actual transfer amount and burn fee for a given amount.
    /// @param amount The original amount intended to be transferred.
    /// @param from The sender’s address.
    /// @return effectiveAmount The final amount after deducting burn fee.
    /// @return burnAmount The fee that would be burned.
    function getEffectiveTransferAmount(uint256 amount, address from)
        external
        view
        returns (uint256 effectiveAmount, uint256 burnAmount)
    {
        if (!s_burnFeeEnabled || s_burnFeeExempt[from]) {
            return (amount, 0);
        }

        // burnAmount = (amount * BURN_FEE_PERCENT) / 100;
        burnAmount = (amount * BURN_FEE_BPS) / BPS_DENOMINATOR;

        effectiveAmount = amount - burnAmount;
        return (effectiveAmount, burnAmount);
    }

    /// @notice Returns the remaining supply after all burned tokens.
    /// @return The current circulating supply.
    function remainingSupply() external view returns (uint256) {
        return TOTAL_SUPPLY - s_totalBurned;
    }

    /// @notice Returns the current burn fee percentage.
    /// @return The burn fee percentage (1%).
    // function getBurnFeePercent() external pure returns (uint256) {
    //     return BURN_FEE_PERCENT;
    // }

    /// @notice Returns the burn fee in basis points.
    function getBurnFeeBps() external pure returns (uint256) {
        return BURN_FEE_BPS;
    }


    /// @notice Checks if an account is exempt from burn fees.
    /// @param account The address to check.
    /// @return True if exempt, false otherwise.
    function isBurnFeeExempt(address account) external view returns (bool) {
        return s_burnFeeExempt[account];
    }

    /// @notice Recovers ERC20 tokens mistakenly sent to this contract.
    /// @param token The address of the token contract.
    /// @param to The recipient of the recovered tokens.
    /// @param amount The amount to recover.
    function recoverTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(this)) revert RecurXToken__CannotRecoverOwnTokens();
        if (to == address(0)) revert RecurXToken__InvalidRecipient();
        if (amount == 0) revert RecurXToken__InvalidAmount();

        IERC20(token).transfer(to, amount);
        emit TokensRecovered(token, to, amount);
    }

    /// @notice Authorizes upgrades of the contract (UUPS pattern).
    /// @param newImplementation The address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert RecurXToken__InvalidImplementation();
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
