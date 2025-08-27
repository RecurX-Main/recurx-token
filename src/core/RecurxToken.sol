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

contract RecurXToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
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

    uint256 public constant TOTAL_SUPPLY = 500_000_000 * 10**18;
    uint256 public constant BURN_FEE_PERCENT = 1;

    uint256 public s_totalBurned;
    bool public s_burnFeeEnabled;
    
    mapping(address => bool) public s_burnFeeExempt;
    
    event BurnFeeToggled(bool enabled);
    event BurnFeeExemptionSet(address indexed account, bool exempt);
    event TokensBurned(address indexed account, uint256 amount, string reason);
    event TokensRecovered(address indexed token, address indexed to, uint256 amount);


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

 
    function sets_BurnFeeEnabled(bool enabled) external onlyOwner {
        s_burnFeeEnabled = enabled;
        emit BurnFeeToggled(enabled);
    }

    function setBurnFeeExempt(address account, bool exempt) external onlyOwner {
        if (account == address(0)) revert RecurXToken__InvalidAddress();
        s_burnFeeExempt[account] = exempt;
        emit BurnFeeExemptionSet(account, exempt);
    }


    function setBurnFeeExemptBatch(address[] calldata accounts, bool exempt) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == address(0)) revert RecurXToken__InvalidAddress();
            s_burnFeeExempt[accounts[i]] = exempt;
            emit BurnFeeExemptionSet(accounts[i], exempt);
        }
    }

    function burn(uint256 amount) external {
        if (amount == 0) revert RecurXToken__AmountMustBeGreaterThanZero();
        if (balanceOf(msg.sender) < amount) revert RecurXToken__InsufficientBalance();
        
        _burn(msg.sender, amount);
        s_totalBurned += amount;
        emit TokensBurned(msg.sender, amount, "Manual burn");
    }

  
    function burnFrom(address account, uint256 amount) external {
        if (amount == 0) revert RecurXToken__AmountMustBeGreaterThanZero();
        if (account == address(0)) revert RecurXToken__InvalidAddress();
        
        uint256 currentAllowance = allowance(account, msg.sender);
        if (currentAllowance < amount) revert RecurXToken__InsufficientAllowance();
        
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
        s_totalBurned += amount;
        emit TokensBurned(account, amount, "Burn from allowance");
    }

    
    function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        if (to == address(0)) revert RecurXToken__TransferToZeroAddress();
        
        if (from != address(0) && to != address(0) && s_burnFeeEnabled) {
            
            if (!s_burnFeeExempt[from]) {
                uint256 burnAmount = (amount * BURN_FEE_PERCENT) / 100;
                
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


    function getEffectiveTransferAmount(uint256 amount, address from) 
        external 
        view 
        returns (uint256 effectiveAmount, uint256 burnAmount) 
    {
        if (!s_burnFeeEnabled || s_burnFeeExempt[from]) {
            return (amount, 0);
        }
        
        burnAmount = (amount * BURN_FEE_PERCENT) / 100;
        effectiveAmount = amount - burnAmount;
        return (effectiveAmount, burnAmount);
    }

    function remainingSupply() external view returns (uint256) {
        return TOTAL_SUPPLY - s_totalBurned;
    }

    function getBurnFeePercent() external pure returns (uint256) {
        return BURN_FEE_PERCENT;
    }

    function isBurnFeeExempt(address account) external view returns (bool) {
        return s_burnFeeExempt[account];
    }

    function recoverTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(this)) revert RecurXToken__CannotRecoverOwnTokens();
        if (to == address(0)) revert RecurXToken__InvalidRecipient();
        if (amount == 0) revert RecurXToken__InvalidAmount();
        
        IERC20(token).transfer(to, amount);
        emit TokensRecovered(token,to,amount);
    }


    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(UPGRADER_ROLE) {
        if (newImplementation == address(0)) revert RecurXToken__InvalidImplementation();
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

}