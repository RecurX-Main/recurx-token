## <h1> 1. About Shivansh </h1> 

I am a freelance smart contract auditor and security researcher with experience in conducting private audits for companies. I also actively participate in competitive auditing platforms.

My focus is on identifying vulnerabilities, improving code safety, and ensuring that projects can operate securely and reliably. With each audit, I strive to deliver clear and actionable findings that strengthen the overall security of smart contracts and help teams build with confidence.

## <h1> 2. Disclaimer </h1> 

A smart contract audit I provide cannot guarantee the complete absence of vulnerabilities. While I make every effort to uncover as many issues as possible, 100% security cannot be assured. Each audit is a time-bound and resource-bound process, and there may still be undiscovered risks.

For maximum security, I strongly recommend subsequent audits, bug bounty programs, and continuous on-chain monitoring in addition to my review.

## <h1> 3. Risk Classification </h1>

🟥 **Critical** – Issues that can completely break the core functionality of the contract, causing it to stop working properly or become unusable. These vulnerabilities often require immediate attention as they pose a threat to the survival of the protocol.

🔴 **High** – Issues that can cause fund loss, funds being stuck, or other fund-related risks. These are severe financial threats that could directly harm users or the protocol treasury.

🟠 **Medium** – Issues that break the intended functionality of the contract but do not directly result in fund loss. While not immediately dangerous to assets, they can harm protocol behavior, user experience, or trust.

🟡 **Low** – Minor issues that do not pose a direct threat to funds or functionality but could be checked to enhance security or improve best practices. These are often edge cases or improvements.

🟢 **Gas** – Findings related to gas optimization tactics. These do not affect security but can help make the contract more efficient, reducing transaction costs for users and improving scalability.

## <h1> 4. About Recurx </h1> 

RecurX is a blockchain-based platform that streamlines token management, vesting, and presale processes in a secure and transparent way. It provides projects with reliable tools to launch, distribute, and manage tokens while ensuring safety for both teams and investors. By combining strong security practices with efficient mechanics. 

## <h1> 5. Executive Summary </h1>

A time-boxed security review of the **Recurx-token-main/src** repositories was done by Shivansh. 

**Protocol Name :** RECURX-TOKEN-MAIN <br>
**Protocol Type :** Solidity & EVM <br>
**Timeline      :** 31st August 2025 - 4th September 2025 <br>

## <h1> 6. Scope </h1>

1. src/core/RecurxToken.sol
2. src/launchpad/PublicSale.sol
3. src/vesting/RCXCategoryVesting.sol
4. src/vesting/RCXVestingBase.sol
5. src/vesting/RCXVestingFactory.sol 

## <h1> 7. Findings </h1>

🟥 **Critical Findings**<br>
[C-01] Critical Access Control Failure in Vesting Factory Integration. <br>
[C-02] Token Burn Functionality Blocked by Transfer Validation. <br>
[C-03] Unprotected Initialization in Upgradeable Contract. <br>

🔴 **High Findings**<br>
[H-01] Incorrect Burn Fee Implementation - 1000x Higher Than Intended. <br>
[H-02] Centralized Ownership Control. <br>
[H-03] Unclaimed Token Liability Calculation Flaw. <br>
[H-04] Precision Loss in Small Token Transfers Due to Burn Fee. <br>

🟠 **Medium Findings** <br>
[M-01] DoS Risk in Batch Exemption Setting. <br>
[M-02] Integer Overflow Risk in Native Cost Calculation. <br>
[M-03] Gas Limit DoS in Vesting Factory List Function. <br>

🟡 **Low Findings**<br>
[L-01] Missing Validation and Event Emission in setTgeTimestamp. <br>
[L-02] Missing Balance Check in Address Validation. <br>
[L-03] Minor Miner Manipulation Risk with block.timestamp in TGE Check. <br>
[L-04] Missing Presale Cap Check Before Vesting Factory Call. <br>
[L-05] Missing Zero Amount Check in rescue Function. <br>
[L-06] Ownership Transfer Can Be Improved with Two-Step Claim Mechanism. <br>
[L-07] Missing Validation: tgeReleaseTimestamp Should Be Greater Than startTimestamp. <br>

🟢 **Gas Optimization** <br>
[G-01] Gas Optimization: Use require Instead of if-else for Burn Fee Exemption. <br>
[G-02] Gas Optimization: Remove Redundant Presale Constants from PublicSale. <br>
[G-03] Gas Optimization: Remove Redundant Zero Amount Check in claim Function. <br>

## <h1> Critical Findings </h1>

<h2> 🟥 [C-01] Critical Access Control Failure in Vesting Factory Integration </h2> 

In PublicSale contract the function `_createPresaleVesting` attempts to call `createPresale()` on the RCXVestingFactory through a low-level call, but this function has an onlyOwner modifier that will cause all calls to fail. <br> 
Since PublicSale is not the owner of the factory, users who purchase tokens will never be able to claim them through vesting contracts. This completely breaks the token distribution mechanism and locks user funds indefinitely.

```solidity
// In PublicSale._createPresaleVesting:
function _createPresaleVesting(address beneficiary, uint256 allocation) internal returns (address vesting) {
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
    // ...
}

// In RCXVestingFactory.createPresale:
function createPresale(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp) 
    external onlyOwner returns (address) // This modifier blocks PublicSale
{ return _deploy("Presale", token, beneficiary, allocation, 1500, tgeTimestamp, 1, 9, 0); }

```

**Impact** <br>
All users who purchase tokens through the public sale will be unable to claim their tokens after TGE. The claimToVesting() function will always revert, effectively locking all purchased tokens and preventing the entire token distribution mechanism from functioning. This affects 100% of public sale participants.

**Recommendation**

Option 1: Remove onlyOwner from factory's createPresale:

```solidity
function createPresale(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp) 
    external returns (address) // Remove onlyOwner
{ 
    // Add caller validation if needed
    require(msg.sender == publicSaleContract, "Unauthorized");
    return _deploy("Presale", token, beneficiary, allocation, 1500, tgeTimestamp, 1, 9, 0); 
}
```


Option 2: Add PublicSale as authorized caller with new role:

```solidity
bytes32 public constant SALE_ROLE = keccak256("SALE_ROLE");

function createPresale(...) external onlyRole(SALE_ROLE) returns (address) {
    // Grant SALE_ROLE to PublicSale during deployment
}
```


<h2> 🟥 [C-02] Token Burn Functionality Blocked by Transfer Validation </h2> 

The `_update` function prevents any transfer to address(0) by reverting with `RecurXToken__TransferToZeroAddress` error. This directly conflicts with the `burn()` and `burnFrom()` functions which attempt to burn tokens by calling `_burn()`, which internally calls `_update(from, address(0), amount)` . This makes the burn functions completely non-functional. 

```solidity
function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        if (to == address(0)) revert RecurXToken__TransferToZeroAddress(); // c q prevents user to burn token . 
// q amoount != 0 && balanceof(from) >= amount 
        if (from != address(0) && to != address(0) && s_burnFeeEnabled) { // C wrong condition check for burn 
            if (!s_burnFeeExempt[from]) { // C wrong burn formula use this solidity dosent support integer value so use bps instead . So, if fee is 0.001% then cahnge the formula . 
                uint256 burnAmount = (amount * BURN_FEE_PERCENT) / 100; // M If used burnAmount = (amount * BURN_FEE_PERCENT) / 100_000; this formula then amount less then 100_000 will revert zero burn amount 
                if (burnAmount > 0) {
                    super._update(from, address(0), burnAmount);
                    s_totalBurned += burnAmount;
                    emit TokensBurned(from, burnAmount, "Transfer burn fee");

                    amount -= burnAmount;
                }
            }
        }

        super._update(from, to, amount);
```
Line number 152 & 154 : 
```solidity
 if (to == address(0)) revert RecurXToken__TransferToZeroAddress();
```

```solidity
if (from != address(0) && to != address(0) && s_burnFeeEnabled)
```

**Impact** <br>
The burn() and burnFrom() functions are completely broken and will always revert. Users cannot burn their tokens as intended, which breaks the deflationary tokenomics. The s_totalBurned counter will never increase through manual burns, only through transfer fees.

**Recommendation** 

Remove the zero address check . 

```solidity
function _update(address from, address to, uint256 amount) internal override whenNotPaused {
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
```


<h2> 🟥 [C-03] Unprotected Initialization in Upgradeable Contract </h2> 

The contract `RecurxToken.sol` & `PublicSale.sol` uses an initialize function for upgradeable deployment. If the logic contract is deployed without a constructor that disables initializers, anyone can call initialize directly on the logic contract, set themselves as the owner, and potentially exploit the contract (e.g., destruct it or gain privileged access).


**Exploit Scenerio** <br> 

An attacker frontrun and calls initialize on the logic contract, becomes the owner, and can call privileged functions or destruct the contract.

function in `PublicSale.sol`

```solidity
function initialize(  // H anybody can initialize the contract directly  constructor() {_disableInitializers(); }
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
```
Function in `RecurxToken.sol` 

```solidity
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
```

**Impact**
An attacker can take ownership of the logic contract and execute privileged actions, potentially leading to loss of control or destruction of the contract.

**Recommendation** 

Add `disableInitializer`

```solidity
constructor() {
    _disableInitializers();
}
```


<h1> High Findings </h1>

<h2> 🔴 [H-01] Incorrect Burn Fee Implementation - 1000x Higher Than Intended </h2>

The burn fee is implemented as 1% `(BURN_FEE_PERCENT = 1, divided by 100)` but the document indicates it should be 0.001%. This means users are being charged 1000 times more than the intended fee on every transfer. For a 1000 token transfer, users lose 10 tokens instead of 0.01 tokens. This severely impacts token economics and user experience.

In contract `RecurxToken.sol`

```solidity
uint256 public constant BURN_FEE_PERCENT = 1; // 1% // @Audit: H its wrong burn fee is 0.001%
```

Function's `_update` & `getEffectiveTransferAmount` 

```solidity
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
```

```solidity
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
```

**Impact** <br> 

Users lose 1% of their tokens on every transfer instead of 0.001%, resulting in 1000x higher fees than intended. This makes the token economically unviable for frequent transfers and will significantly reduce token velocity. A user transferring 100,000 tokens loses 1,000 tokens instead of 1 token.

**Recommendation** 

Make the fee in BPS(highly recommended) or change the formula  

```solidity
uint256 public constant BURN_FEE_BPS = 1; // 0.001% = 0.1 basis points
uint256 public constant BPS_DENOMINATOR = 100_000; // For 0.001% precision
```


<h2> 🔴 [H-02] Centralized Ownership Control </h2>

The contract relies on a single owner account for all privileged operations. If this owner account is compromised, the attacker gains full control over the contract and its assets.

1. Owner can set the price of token usdc/usdt. Compromised Owner can manipulate the price accordingly. 

```solidity
    function setTokenPriceUsd6(uint256 usd6) external onlyOwner { tokenPriceUsd6 = usd6; }
```

2. Owner recover erc20 token 

```solidity
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
```

3. Owner can rescue tokens 

The factory owner or vesting contract owner can steal all tokens from vesting contracts, including tokens that are already vested and claimable by beneficiaries. This completely undermines the trustless nature of vesting and puts all vested funds at risk.


```solidity
    function rescue(address to, uint256 amount) external onlyOwner { // q L amount shouldnot be zero 
        if (to == address(0)) revert RCXVestingBase__ZeroAddress(); // q can we rescue the rcx token ? or only non-rcx token 
        if (!token.transfer(to, amount)) revert RCXVestingBase__RescueFailed();
        emit Rescue(to, amount);
    }
```


<h2> 🔴 [H-03] Unclaimed Token Liability Calculation Flaw </h2>

The `_unclaimedLiability()` function returns totalSold without accounting for already claimed tokens. This prevents the owner from recovering any excess RCX tokens even after users have claimed their vesting contracts, as the function incorrectly reports all sold tokens as owed, even after users have claimed. This permanently locks excess tokens.

```solidity
function _unclaimedLiability() internal view returns (uint256) {
    return totalSold; // TODO: it should revert that is total sold but not vested , Tokens already vested should be subtracted. 
}

function recoverTokens(address tokenAddr, address to, uint256 amount) external onlyOwner {
    if (tokenAddr == address(rcx)) {
        uint256 liabilities = _unclaimedLiability(); // Always returns totalSold
        uint256 bal = rcx.balanceOf(address(this));
        if (bal <= liabilities) revert PublicSale__NoExcessRCX();
        if (amount > bal - liabilities) revert PublicSale__ExceedsExcess();
    }
    IERC20(tokenAddr).safeTransfer(to, amount);
}
```

**Impact** 
Owner cannot recover legitimate excess RCX tokens sent to the contract. If the owner accidentally sends extra RCX or needs to recover dust, they cannot do so because the liability calculation always shows totalSold as owed, even after users have claimed. This permanently locks excess tokens.

**Recommendation** 

Correct the formula and manage the things like shown below 

```solidity
// Track claimed amounts properly:
mapping(address => uint256) public purchased;
mapping(address => bool) public claimed;
uint256 public totalClaimed; // Add this state variable

function claimToVesting() external nonReentrant whenNotPaused {
    // ... existing checks ...
    uint256 amount = purchased[msg.sender];
    
    // ... create vesting and transfer ...
    
    claimed[msg.sender] = true;
    totalClaimed += amount; // Track claimed amount
    emit ClaimedToVesting(msg.sender, vesting, amount);
}

function _unclaimedLiability() internal view returns (uint256) {
    return totalSold - totalClaimed; // Return actual unclaimed amount
}
```

<h2> 🔴 [H-04] Precision Loss in Small Token Transfers Due to Burn Fee  </h2>

When transferring amounts less than 100 tokens with the current 1% burn fee implementation, the burn amount rounds down to 0, allowing fee-free transfers. With the intended 0.001% fee, `[if formula used burnAmount = (amount * BURN_FEE_PERCENT)/100_000]` transfers under 100,000 tokens would have zero burn. This creates an exploit where users can split large transfers into smaller chunks to avoid fees entirely.



```solidity
function _update(address from, address to, uint256 amount) internal override whenNotPaused {
    if (from != address(0) && to != address(0) && s_burnFeeEnabled) {
        if (!s_burnFeeExempt[from]) {
            uint256 burnAmount = (amount * BURN_FEE_PERCENT) / 100;
            // If amount < 100, burnAmount = 0 due to integer division
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
```
Line:
```solidity
uint256 public constant BURN_FEE_PERCENT = 1; // 1% // @Audit: H its wrong burn fee is 0.001%
```
**Impact** <br>
Users can avoid burn fees by splitting transfers into amounts below the rounding threshold. With 1% fee, transfers under 100 tokens are fee-free. With intended 0.001% fee, transfers under 100,000 tokens would be fee-free. This undermines the deflationary mechanism and allows circumvention of the burn fee.

**Recommendattion** 

Make the fee operations in Bps for more security , tokens can't be deducted in decimals . 



## <h1>  Medium Findings  </h1>

<h2> 🟠 [M-01] DoS Risk in Batch Exemption Setting </h2>

The `setBurnFeeExemptBatch` function reverts entirely if any single address in the array is invalid (address(0)).   This makes it risky to use the batch function with user-provided addresses.

```solidity
function setBurnFeeExemptBatch(address[] calldata accounts, bool exempt) external onlyOwner {
    for (uint256 i = 0; i < accounts.length; i++) {
        if (accounts[i] == address(0)) revert RecurXToken__InvalidAddress();
        s_burnFeeExempt[accounts[i]] = exempt;
        emit BurnFeeExemptionSet(accounts[i], exempt);
    }
}
```

**Impact** 
This could prevent timely updates to exemption lists, especially problematic if trying to exempt multiple vesting contracts or update many addresses urgently. One bad address causes entire batch to fail.

**Recommendation**

Use continue instead of reverting the whole transaction . 

```solidity
function setBurnFeeExemptBatch(address[] calldata accounts, bool exempt) external onlyOwner {
    uint256 updated = 0;
    for (uint256 i = 0; i < accounts.length; i++) {
        if (accounts[i] == address(0)) {
            // Skip invalid addresses instead of reverting
            continue;
        }
        s_burnFeeExempt[accounts[i]] = exempt;
        emit BurnFeeExemptionSet(accounts[i], exempt);
        updated++;
    }
    // Optionally emit summary event
    emit BatchExemptionUpdate(updated, accounts.length);
}
```
 
<h2> 🟠 [M-02] Integer Overflow Risk in Native Cost Calculation </h2>

The nativeCost function performs unchecked multiplication (usd18 * 1e18) which could overflow for large RCX purchase amounts. While unlikely with reasonable token prices, this could cause the transaction to revert unexpectedly . 

```solidity
function nativeCost(uint256 rcxAmount18) public view returns (uint256) {
    // ...
    uint256 usdCost = usdCost6(rcxAmount18); // 6 decimals
    uint256 usd18 = usdCost * 1e12; // Convert to 18 decimals
    
    // ... normalize price ...
    
    return (usd18 * 1e18) / normalizedPrice; // Potential overflow here
}
```

**Impact** 
For very large RCX purchases (e.g., near the 20M cap), the multiplication usd18 * 1e18 could overflow, causing transaction failure or incorrect cost calculation. With a token price of $0.10 and 20M tokens, the calculation would be 2,000,000 * 1e12 * 1e18 = 2e36, which exceeds uint256 max.

**Recommendation** 

```solidity
function nativeCost(uint256 rcxAmount18) public view returns (uint256) {
    // ... get oracle price ...
    
    uint256 usdCost = usdCost6(rcxAmount18);
    
    // Use different calculation order to avoid overflow:
    // Instead of: (usdCost * 1e12 * 1e18) / price
    // Do: (usdCost * 1e30) / price
    // Or better: usdCost * (1e30 / price)
    
    if (normalizedPrice == 0) revert PublicSale__PriceInvalid();
    
    // Safe calculation avoiding intermediate overflow:
    uint256 scaledUsd = usdCost * 1e12; // to 18 decimals
    return (scaledUsd * 1e18) / normalizedPrice;
    
    // Or use mulDiv from a math library:
    // return Math.mulDiv(scaledUsd, 1e18, normalizedPrice);
}
```

<h2> 🟠 [M-03] Gas Limit DoS in Vesting Factory List Function  </h2>

The `list()` function in `RCXVestingFactory` returns all vesting records in a single call, iterating through the entire array. Attacker can create several accounts and vest a dust amount, As more vesting contracts are created, this function will eventually exceed the block gas limit, making it permanently unusable and breaking any integrations that depend on it.


```solidity
function list() external view returns (Record[] memory all) {
    all = new Record[](records.length);
    for (uint256 i = 0; i < records.length; i++) { 
        all[i] = records[i]; // Unbounded loop
    }
}
```

**Impact** 
Once enough vesting contracts are created (likely 1000-5000 depending on gas costs), the list() function becomes permanently unusable due to gas limits. Any UI or integration relying on this function to display all vesting contracts will break. This affects transparency and auditability of the vesting system.

**Recommendation** 

Make the minimum cap for purchasing the token . 

## <h1> Low Findings </h1>

<h2> 🟡 [L-01] Missing Validation and Event Emission in setTgeTimestamp </h2>

The `setTgeTimestamp` function allows the owner to set the TGE timestamp without any validation or event emission. This could lead to accidental or malicious setting of an invalid timestamp, and makes it harder to track changes on-chain.

```solidity
    function setTgeTimestamp(uint256 ts) external onlyOwner { tgeTimestamp = ts; }
```


**Impact**
The owner could set the TGE timestamp to zero or a past value, potentially disrupting the vesting and claim logic. Lack of event emission reduces transparency for users and auditors.

**Recommendation**
Add a check to ensure the timestamp is valid (e.g., greater than the current block timestamp), and emit an event when the TGE timestamp is updated:

```solidity
function setTgeTimestamp(uint256 ts) external onlyOwner {
    require(ts > block.timestamp, "Invalid TGE timestamp");
    tgeTimestamp = ts;
    emit TgeTimestampUpdated(ts);
}
event TgeTimestampUpdated(uint256 ts);
```

<h2> 🟡 [L-02] Missing Balance Check in Address Validation </h2>

In function `burnFrom` The code snippet `if (account == address(0)) revert RecurXToken__InvalidAddress();` only checks for a zero address but does not verify if the account has sufficient balance before proceeding with operations such as transfers or burns.

```solidity
  function burnFrom(address account, uint256 amount) external {
        if (amount == 0) revert RecurXToken__AmountMustBeGreaterThanZero();
        if (account == address(0)) revert RecurXToken__InvalidAddress(); // L check for balance(account) < amount

        uint256 currentAllowance = allowance(account, msg.sender);
        if (currentAllowance < amount) revert RecurXToken__InsufficientAllowance();

        _spendAllowance(account, msg.sender, amount); 
        _burn(account, amount);
        s_totalBurned += amount; // @Audit: L Check for total supply Constraint , if fishy revert 
        emit TokensBurned(account, amount, "Burn from allowance");
    }
```


**Impact**
If the balance of `account` is less than the required `amount`, the function may revert later or behave unexpectedly, leading to poor user experience or unintended errors.

**Recommendation**
Add a check to ensure the account has enough balance before performing operations:

```solidity
if (account == address(0)) revert RecurXToken__InvalidAddress();
if (balanceOf(account) < amount) revert RecurXToken__InsufficientBalance();
```
This ensures that only valid addresses with sufficient balance can proceed, improving reliability and clarity of error handling.

<h2> 🟡 [L-03] Minor Miner Manipulation Risk with block.timestamp in TGE Check </h2>

In function `claimToVesting` the check `if (block.timestamp < tgeTimestamp) revert PublicSale__Unauthorized();` relies on `block.timestamp` to enforce the TGE claim window. Miners can manipulate `block.timestamp` by a few seconds, which could allow claims slightly earlier or later than intended.

```solidity
    function claimToVesting() external nonReentrant whenNotPaused {
        if (block.timestamp < tgeTimestamp) revert PublicSale__Unauthorized();  // q L block.timestamp can be manipulated by miners for fewer seconds 
        // require(kycApproved[msg.sender], "KYC");
        if (claimed[msg.sender]) revert PublicSale__AlreadyClaimed(); 
        uint256 amount = purchased[msg.sender];
        if (amount == 0) revert PublicSale__NothingToClaim();
        if (rcx.balanceOf(address(this)) < amount) revert PublicSale__InsufficientRCXFunded();

        // Create vesting with Presale preset
        address vesting =  _createPresaleVesting(msg.sender, amount);
        RecurXToken(address(rcx)).setVestingContractExempt(vesting);

        rcx.safeTransfer(vesting, amount); // q m purchased[msg.sender] -= amount; is needed  

        claimed[msg.sender] = true;

        emit ClaimedToVesting(msg.sender, vesting, amount);
    }
```


**Impact**
Miners may advance or delay the claim window by a few seconds, but this does not pose a significant risk for vesting or sale logic.

**Recommendation**
This is a known limitation of Ethereum and is generally considered low risk. No action needed unless your use case requires strict timing guarantees.

---

<h2> 🟡 [L-04] Missing Presale Cap Check Before Vesting Factory Call </h2>

In `_createPresaleVesting` the code `(bool ok, bytes memory data) = vestingFactory.call(...)` in `_createPresaleVesting` does not check if `totalSold` is less than the presale cap before creating a new vesting contract. This could allow vesting contracts to be created even after the presale cap is exceeded.

```Solidity

    function _createPresaleVesting(address beneficiary, uint256 allocation) internal returns (address vesting) {
        // RCXVestingFactory.createPresale(token, beneficiary, allocation, tgeTimestamp)
        (bool ok, bytes memory data) = vestingFactory.call( // L check for presale cap , total sold should be less than that 
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
```

**Impact**
If the presale cap is exceeded, additional vesting contracts may be created, resulting in more tokens being allocated than intended and breaking the sale limits.

**Recommendation**
Add a check before the call to ensure `totalSold + allocation <= PRESALE_CAP` to enforce the cap and prevent overallocation:

```solidity
if (totalSold + allocation > PRESALE_CAP) revert PublicSale__ExceedsPresaleCap();
```
This should be done before calling the vesting factory.

---

<h2> 🟡 [L-05] Missing Zero Amount Check in rescue Function </h2>

The `rescue` function allows the owner to transfer tokens to a specified address, but does not check if the `amount` is zero before proceeding. For better security we check all this . 

```solidity
function rescue(address to, uint256 amount) external onlyOwner { // q L amount shouldnot be zero 
        if (to == address(0)) revert RCXVestingBase__ZeroAddress(); 
        if (!token.transfer(to, amount)) revert RCXVestingBase__RescueFailed();
        emit Rescue(to, amount);
    }
```

**Impact**
Calling the function with a zero amount may result in unnecessary transactions, wasted gas, or confusion for users and auditors.

**Recommendation**
Add a check to ensure the amount is greater than zero before transferring:

```solidity
if (amount == 0) revert RCXVestingBase__AmountZero();
```
This improves clarity and prevents pointless transactions.

<h2> 🟡 [L-06] Ownership Transfer Can Be Improved with Two-Step Claim Mechanism </h2>

The `transferOwnership(address newOwner)` function immediately sets the new owner when called by the current owner. This can lead to accidental assignment to an incorrect or unprepared address, potentially locking the contract or exposing it to risk.

```solidity

    function transferOwnership(address newOwner) external onlyOwner { // q L for better security use the claim method . 
        if (newOwner == address(0)) revert RCXVestingBase__ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
```

**Impact**
If the new owner address is incorrect or not controlled by the intended party, the contract could be lost or compromised.

**Recommendation**
Implement a two-step ownership transfer (claimable ownership):
- Owner sets a `pendingOwner`.
- The new address must call `claimOwnership()` to become the owner.
This ensures only the intended address can accept ownership and reduces risk of mistakes.

Example:
```solidity
address public pendingOwner;
function transferOwnership(address newOwner) external onlyOwner {
    pendingOwner = newOwner;
}
function claimOwnership() external {
    require(msg.sender == pendingOwner, "Not pending owner");
    emit OwnershipTransferred(owner, pendingOwner);
    owner = pendingOwner;
    pendingOwner = address(0);
}
```

---

<h2> 🟡 [L-07] Missing Validation: tgeReleaseTimestamp Should Be Greater Than startTimestamp </h2>

In contract `RCXVestingBase.sol` the constructor sets `tgeReleaseTimestamp = _tgeReleaseTimestamp` without checking if it is greater than `startTimestamp`. This could allow the TGE release to be set before the vesting start, leading to logic errors or unexpected behavior.

```solidity
  constructor(
        address _token,
        address _beneficiary,
        uint256 _totalAllocation,
        uint16 _tgeBps, // e.g., 1500 = 15
        uint256 _startTimestamp, 
        uint256 _tgeReleaseTimestamp, // When TGE unlock is claimable (can be == start)
        uint32 _cliffMonths,
        uint32 _vestingMonths
    ) {
        if (_token == address(0)) revert RCXVestingBase__ZeroTokenAddress();
        if (_beneficiary == address(0)) revert RCXVestingBase__ZeroBeneficiaryAddress();
        if (_tgeBps > BPS) revert RCXVestingBase__InvalidBasisPoints();
        owner = msg.sender;
        token = IERC20(_token);
        beneficiary = _beneficiary;
        totalAllocation = _totalAllocation;
        tgeBps = _tgeBps;
        startTimestamp = _startTimestamp; 
        tgeReleaseTimestamp = _tgeReleaseTimestamp; 
        cliffMonths = _cliffMonths;
        vestingMonths = _vestingMonths;
    }
```

**Impact**
If `tgeReleaseTimestamp` is less than or equal to `startTimestamp`, the TGE portion may be claimable too early, breaking the intended vesting schedule and potentially allowing premature claims.

**Recommendation**
Add a check in the constructor to ensure `tgeReleaseTimestamp > startTimestamp`:

```solidity
if (_tgeReleaseTimestamp <= _startTimestamp) revert RCXVestingBase__InvalidTgeReleaseTimestamp();
```
This enforces a proper vesting schedule and prevents configuration mistakes.

<h1> Gas Optimization </h1>

<h2> 🟢 [G-01] Gas Optimization: Use require Instead of if-else for Burn Fee Exemption </h2>

The line `s_burnFeeExempt[account] = exempt;` in `setBurnFeeExempt` can be optimized by using `require` for input validation instead of `if-else` statements. This reduces bytecode size and improves gas efficiency, as require is cheaper than branching logic for simple checks.

**Impact**
Saves gas and simplifies code by avoiding unnecessary branching.

**Recommendation**
Use `require(account != address(0), "Invalid address");` for validation, and directly set the mapping value. This is already implemented in some places of your code, so no further action is needed, but always prefer require for simple input checks.

<h2> 🟢 [G-02] Gas Optimization: Remove Redundant Presale Constants from PublicSale </h2>

The constants `PRESALE_TGE_BPS`, `PRESALE_CLIFF_MONTHS`, `PRESALE_VESTING_MONTHS`, and `PRESALE_TGE_RELEASE_OFFSET_MONTHS` are defined in `PublicSale` but are never used, as these values are already set in `RCXVestingFactory.sol`.

```solidity
 uint16 internal constant PRESALE_TGE_BPS = 1500; // 15% // L gas never used remove it 
    uint32 internal constant PRESALE_CLIFF_MONTHS = 1;
    uint32 internal constant PRESALE_VESTING_MONTHS = 9;
    uint32 internal constant PRESALE_TGE_RELEASE_OFFSET_MONTHS = 0;
```


**Impact**
Unused constants increase bytecode size and deployment cost, leading to unnecessary gas usage.

**Recommendation**
Remove these redundant constants from `PublicSale` to reduce contract size and optimize gas usage.

<h2> 🟢 [G-03] Gas Optimization: Remove Redundant Zero Amount Check in claim Function </h2>

The check `if (amount == 0) revert RCXVestingBase__NothingToClaim();` in the `claim` function is redundant, as the `claimable()` function already returns zero when there is nothing to claim. This extra check increases bytecode size and gas usage without adding security.

**Impact**
Unnecessary condition increases gas cost and contract size.

**Recommendation**
Remove the redundant zero amount check to optimize gas usage and simplify the code.

---







































