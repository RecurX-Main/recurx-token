// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RCXCategoryVesting.sol";

contract RCXVestingFactory {
    struct Record {
        address vesting;
        string category;
        address beneficiary;
        uint256 allocation;
    }

    error RCXVestingFactory__NotOwner();
    error RCXVestingFactory__ZeroAddress();


    address public owner;
    uint256 public constant MONTH = 30 days;

    Record[] public records;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event VestingCreated(address indexed vesting, string category, address indexed beneficiary, uint256 allocation);

    modifier onlyOwner() {
        if(msg.sender != owner) revert RCXVestingFactory__NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if(newOwner == address(0)) revert RCXVestingFactory__ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }


    function _deploy(
        string memory category,
        address token,
        address beneficiary,
        uint256 allocation,
        uint16 tgeBps,
        uint256 tgeTimestamp,
        uint32 cliffMonths,
        uint32 vestingMonths,
        uint32 tgeReleaseMonthOffset
    ) internal returns (address deployed) {
        uint256 tgeReleaseTs = tgeTimestamp + uint256(tgeReleaseMonthOffset) * MONTH;
        RCXCategoryVesting vest = new RCXCategoryVesting(
            token,
            beneficiary,
            allocation,
            tgeBps,
            tgeTimestamp,
            tgeReleaseTs,
            cliffMonths,
            vestingMonths,
            category
        );
        deployed = address(vest);
        records.push(Record(deployed, category, beneficiary, allocation));
        emit VestingCreated(deployed, category, beneficiary, allocation);
    }

    // All functions take: token, beneficiary, allocation (token units), tgeTimestamp (unix seconds)

    function createPresale(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Presale", token, beneficiary, allocation, 1500, tgeTimestamp, 1, 9, 0); }

    function createIDO(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("IDO", token, beneficiary, allocation, 1500, tgeTimestamp, 1, 9, 0); }

    function createIEO(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("IEO", token, beneficiary, allocation, 1500, tgeTimestamp, 1, 9, 0); }

    function createInvestor(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Investor", token, beneficiary, allocation, 0,    tgeTimestamp, 6, 24, 0); }

    function createLiquidity(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Liquidity", token, beneficiary, allocation, 6000, tgeTimestamp, 1, 12, 0); }

    function createTeam(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Team", token, beneficiary, allocation, 0,    tgeTimestamp, 12, 36, 0); }

    function createMarketing(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Marketing", token, beneficiary, allocation, 800,  tgeTimestamp, 3, 18, 4); }

    function createCommunity(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Community", token, beneficiary, allocation, 1200, tgeTimestamp, 0, 12, 0); }

    function createDevelopment(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Development", token, beneficiary, allocation, 0,  tgeTimestamp, 3, 24, 0); }

    function createReserve(address token, address beneficiary, uint256 allocation, uint256 tgeTimestamp)
        external onlyOwner returns (address)
    { return _deploy("Reserve", token, beneficiary, allocation, 0,      tgeTimestamp, 6, 24, 0); }


    function total() external view returns (uint256) { return records.length; }

    function get(uint256 index) external view returns (Record memory) { return records[index]; }

    function list() external view returns (Record[] memory all) {
        all = new Record[](records.length);
        for (uint256 i = 0; i < records.length; i++) { all[i] = records[i]; }
    }
}
