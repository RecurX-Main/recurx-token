// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RCXVestingBase.sol";

contract RCXCategoryVesting is RCXVestingBase {
    string public category; // here we'll have >> "Team", "Marketing", "Investor", "Presale", "IDO", "IEO", "Liquidity", "Community", "Development", "Reserve"

    constructor(
        address _token,
        address _beneficiary,
        uint256 _totalAllocation,
        uint16 _tgeBps,
        uint256 _startTimestamp,
        uint256 _tgeReleaseTimestamp,
        uint32 _cliffMonths,
        uint32 _vestingMonths,
        string memory _category
    )
        RCXVestingBase(
            _token,
            _beneficiary,
            _totalAllocation,
            _tgeBps,
            _startTimestamp,
            _tgeReleaseTimestamp,
            _cliffMonths,
            _vestingMonths
        )
    {
        category = _category;
    }
}
