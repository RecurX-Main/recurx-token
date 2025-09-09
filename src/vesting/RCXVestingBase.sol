// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract RCXVestingBase {
    error RCXVestingBase__NotOwner();
    error RCXVestingBase__Paused();
    error RCXVestingBase__ZeroTokenAddress();
    error RCXVestingBase__ZeroBeneficiaryAddress();
    error RCXVestingBase__InvalidBasisPoints();
    error RCXVestingBase__OnlyBeneficiary();
    error RCXVestingBase__NothingToClaim();
    error RCXVestingBase__TransferFailed();
    error RCXVestingBase__ZeroAddress();
    error RCXVestingBase__RescueFailed();
    error RCXVestingBase__AmountZero();
    error RCXVestingBase__InvalidTgeReleaseTimestamp();

    IERC20 public immutable token;
    address public beneficiary;
    uint256 public immutable totalAllocation; // amount of tokens (in token units)
    uint16 public immutable tgeBps;          // basis points (10000 = 100%)
    uint256 public immutable startTimestamp; // TGE timestamp (unix seconds)
    uint256 public immutable tgeReleaseTimestamp; // When TGE portion becomes claimable
    uint32 public immutable cliffMonths;     // months before linear starts
    uint32 public immutable vestingMonths;   // linear vesting duration in months (excludes cliff)

    uint256 public s_claimed;
    bool public s_paused;
    address public owner;

    uint256 private constant BPS = 10_000;
    uint256 private constant MONTH = 30 days;

    // Events
    event Claimed(address indexed beneficiary, uint256 amount);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);
    event Paused(bool isPaused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Rescue(address indexed to, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert RCXVestingBase__NotOwner();
        _;
    }

    modifier notPaused() {
        if (s_paused) revert RCXVestingBase__Paused();
        _;
    }

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
        if (_tgeReleaseTimestamp < _startTimestamp) revert RCXVestingBase__InvalidTgeReleaseTimestamp();
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


    function tgeAmount() public view returns (uint256) {
        return (totalAllocation * tgeBps) / BPS;
    }

    function linearAmountTotal() public view returns (uint256) {
        return totalAllocation - tgeAmount();
    }

    function linearStart() public view returns (uint256) {
        return startTimestamp + uint256(cliffMonths) * MONTH;
    }

    function linearEnd() public view returns (uint256) {
        return linearStart() + uint256(vestingMonths) * MONTH;
    }

    function vestedAt(uint256 timestamp) public view returns (uint256) {
        uint256 vestedTGE = timestamp >= tgeReleaseTimestamp ? tgeAmount() : 0;

        if (timestamp <= linearStart()) {
            return vestedTGE;
        }
        uint256 ls = linearStart();
        uint256 le = linearEnd();
        if (timestamp >= le) {
            return vestedTGE + linearAmountTotal();
        }

        uint256 elapsed = timestamp - ls;
        uint256 duration = le - ls; 
        if (duration == 0) {
            return vestedTGE;
        }
        uint256 vestedLinear = (linearAmountTotal() * elapsed) / duration;
        return vestedTGE + vestedLinear;
    }

    function vested() public view returns (uint256) {
        return vestedAt(block.timestamp);
    }

    function claimable() public view returns (uint256) {
        uint256 v = vested();
        if (v <= s_claimed) return 0;
        return v - s_claimed;
    }

    function claim() external notPaused {
        if (msg.sender != beneficiary) revert RCXVestingBase__OnlyBeneficiary();
        uint256 amount = claimable();
        if (amount == 0) revert RCXVestingBase__NothingToClaim();
        s_claimed += amount;
        if (!token.transfer(beneficiary, amount)) revert RCXVestingBase__TransferFailed();
        emit Claimed(beneficiary, amount);
    }

    function setBeneficiary(address newBeneficiary) external onlyOwner {
        if (newBeneficiary == address(0)) revert RCXVestingBase__ZeroBeneficiaryAddress();
        emit BeneficiaryUpdated(beneficiary, newBeneficiary);
        beneficiary = newBeneficiary;
    }

    function setPaused(bool _s_paused) external onlyOwner {
        s_paused = _s_paused;
        emit Paused(_s_paused);
    }

// check for transfer and claim mechanism
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert RCXVestingBase__ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function rescue(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert RCXVestingBase__AmountZero();
        if (to == address(0)) revert RCXVestingBase__ZeroAddress();
        if (!token.transfer(to, amount)) revert RCXVestingBase__RescueFailed();
        emit Rescue(to, amount);
    }
}
