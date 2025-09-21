
// pragma solidity ^0.8.20;

// import "forge-std/Script.sol";
// import {RecurXToken} from "../src/core/RecurxToken.sol";
// import {PublicSale} from "../src/launchpad/PublicSale.sol";
// import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// contract MockAggregator is AggregatorV3Interface {
//     int256 private _price;
//     uint256 private _updatedAt;
//     uint80 private _roundId;

//     constructor(int256 price) {
//         _price = price;
//         _updatedAt = block.timestamp;
//         _roundId = 1;
//     }

//     function decimals() external pure returns (uint8) { return 8; }
//     function description() external pure returns (string memory) { return "Mock BNB/USD"; }
//     function version() external pure returns (uint256) { return 1; }

//     function getRoundData(uint80) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
//         return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
//     }

//     function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
//         return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
//     }

//     function updatePrice(int256 newPrice) external {
//         _price = newPrice;
//         _updatedAt = block.timestamp;
//         _roundId++;
//     }
// }

// contract MockERC20 is IERC20 {
//     string public name;
//     string public symbol;
//     uint8 public decimals;
//     uint256 public totalSupply;
    
//     mapping(address => uint256) public balanceOf;
//     mapping(address => mapping(address => uint256)) public allowance;

//     constructor(string memory _name, string memory _symbol, uint8 _decimals) {
//         name = _name;
//         symbol = _symbol;
//         decimals = _decimals;
//     }

//     function mint(address to, uint256 amount) external {
//         balanceOf[to] += amount;
//         totalSupply += amount;
//     }

//     function transfer(address to, uint256 amount) external returns (bool) {
//         balanceOf[msg.sender] -= amount;
//         balanceOf[to] += amount;
//         return true;
//     }

//     function transferFrom(address from, address to, uint256 amount) external returns (bool) {
//         allowance[from][msg.sender] -= amount;
//         balanceOf[from] -= amount;
//         balanceOf[to] += amount;
//         return true;
//     }

//     function approve(address spender, uint256 amount) external returns (bool) {
//         allowance[msg.sender][spender] = amount;
//         return true;
//     }
// }

// contract PublicSaleTestnetDeploy is Script {
//     address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828;
//     uint256 constant TGE_TIMESTAMP = 1735689600;
//     uint256 constant TOKEN_PRICE_USD6 = 100000;
//     uint256 constant MAX_PER_WALLET = 100000e18;
//     int256 constant MOCK_BNB_PRICE = 2000e8; // $2000 BNB
    
//     // address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828; // testnet

//     address constant RCX_TOKEN = 0xD8299478cd7C5e2fe638Fc6dBAf32349B00FB491;  // testnet

//     address constant RCX_VESTING_FACTORY = 0xcBB0262F993AB73dE5Aa295580BbfF349C5e091d; // testnet

//     address constant USDT_BSC = 0x0719c5e01262b7Cd68Dec84ae8fA58D9263a239D; // BSC USDT

//     address constant USDC_BSC = 0x4cCc5033FeA1D45FE6270e0C78534DAf0C505eE6; // BSC USDC

//     // Your stage data arrays here (same as before)
//     uint256[] public stagePrices = [
//         60000, // Stage 1: $0.06
//         61000, // Stage 2: $0.061
//         63000, // Stage 3: $0.063
//         64000, // Stage 4: $0.064
//         66000, // Stage 5: $0.066
//         67000, // Stage 6: $0.067
//         69000, // Stage 7: $0.069
//         71000, // Stage 8: $0.071
//         72000, // Stage 9: $0.072
//         74000, // Stage 10: $0.074
//         76000, // Stage 11: $0.076
//         78000, // Stage 12: $0.078
//         80000, // Stage 13: $0.08
//         81000, // Stage 14: $0.081
//         83000, // Stage 15: $0.083
//         85000, // Stage 16: $0.085
//         87000, // Stage 17: $0.087
//         90000, // Stage 18: $0.09
//         92000, // Stage 19: $0.092
//         94000, // Stage 20: $0.094
//         96000, // Stage 21: $0.096
//         98000, // Stage 22: $0.098
//         101000, // Stage 23: $0.101
//         103000, // Stage 24: $0.103
//         106000, // Stage 25: $0.106
//         108000, // Stage 26: $0.108
//         111000, // Stage 27: $0.111
//         113000, // Stage 28: $0.113
//         116000, // Stage 29: $0.116
//         119000, // Stage 30: $0.119
//         122000, // Stage 31: $0.122
//         124000, // Stage 32: $0.124
//         127000, // Stage 33: $0.127
//         130000, // Stage 34: $0.13
//         134000, // Stage 35: $0.134
//         137000, // Stage 36: $0.137
//         140000, // Stage 37: $0.14
//         143000, // Stage 38: $0.143
//         147000, // Stage 39: $0.147
//         150000, // Stage 40: $0.15
//         154000, // Stage 41: $0.154
//         157000, // Stage 42: $0.157
//         161000, // Stage 43: $0.161
//         165000, // Stage 44: $0.165
//         169000, // Stage 45: $0.169
//         173000, // Stage 46: $0.173
//         177000, // Stage 47: $0.177
//         181000, // Stage 48: $0.181
//         186000, // Stage 49: $0.186
//         190000 // Stage 50: $0.19
//     ];

//     // Stage allocations in RCX tokens based on CSV data
//     // Total: 80,000,000 RCX (80M tokens)
//     uint256[] public stageAllocations = [
//         1096182e18, // Stage 1: 1,096,182 RCX
//         1083591e18, // Stage 2: 1,083,591 RCX
//         1062119e18, // Stage 3: 1,062,119 RCX
//         1064712e18, // Stage 4: 1,064,712 RCX
//         1056814e18, // Stage 5: 1,056,814 RCX
//         1070395e18, // Stage 6: 1,070,395 RCX
//         1072839e18, // Stage 7: 1,072,839 RCX
//         1079799e18, // Stage 8: 1,079,799 RCX
//         1105915e18, // Stage 9: 1,105,915 RCX
//         1120242e18, // Stage 10: 1,120,242 RCX
//         1137821e18, // Stage 11: 1,137,821 RCX
//         1158322e18, // Stage 12: 1,158,322 RCX
//         1181455e18, // Stage 13: 1,181,455 RCX
//         1221867e18, // Stage 14: 1,221,867 RCX
//         1249505e18, // Stage 15: 1,249,505 RCX
//         1279122e18, // Stage 16: 1,279,122 RCX
//         1310537e18, // Stage 17: 1,310,537 RCX
//         1328661e18, // Stage 18: 1,328,661 RCX
//         1363157e18, // Stage 19: 1,363,157 RCX
//         1399005e18, // Stage 20: 1,399,005 RCX
//         1436091e18, // Stage 21: 1,436,091 RCX
//         1474311e18, // Stage 22: 1,474,311 RCX
//         1498587e18, // Stage 23: 1,498,587 RCX
//         1538706e18, // Stage 24: 1,538,706 RCX
//         1564798e18, // Stage 25: 1,564,798 RCX
//         1606488e18, // Stage 26: 1,606,488 RCX
//         1634063e18, // Stage 27: 1,634,063 RCX
//         1677059e18, // Stage 28: 1,677,059 RCX
//         1705850e18, // Stage 29: 1,705,850 RCX
//         1735230e18, // Stage 30: 1,735,230 RCX
//         1765139e18, // Stage 31: 1,765,139 RCX
//         1810007e18, // Stage 32: 1,810,007 RCX
//         1840729e18, // Stage 33: 1,840,729 RCX
//         1871851e18, // Stage 34: 1,871,851 RCX
//         1889130e18, // Stage 35: 1,889,130 RCX
//         1921019e18, // Stage 36: 1,921,019 RCX
//         1953199e18, // Stage 37: 1,953,199 RCX
//         1985642e18, // Stage 38: 1,985,642 RCX
//         2004594e18, // Stage 39: 2,004,594 RCX
//         2037548e18, // Stage 40: 2,037,548 RCX
//         2057247e18, // Stage 41: 2,057,247 RCX
//         2090610e18, // Stage 42: 2,090,610 RCX
//         2110935e18, // Stage 43: 2,110,935 RCX
//         2131630e18, // Stage 44: 2,131,630 RCX
//         2152663e18, // Stage 45: 2,152,663 RCX
//         2174004e18, // Stage 46: 2,174,004 RCX
//         2195628e18, // Stage 47: 2,195,628 RCX
//         2217510e18, // Stage 48: 2,217,510 RCX
//         2227588e18, // Stage 49: 2,227,588 RCX
//         2250084e18 // Stage 50: 2,250,084 RCX
//     ];


//     function run() external {
//         vm.startBroadcast();

//         // 1. Deploy RCX Token
//         // RecurXToken rcxImplementation = new RecurXToken();
//         // bytes memory rcxInitData = abi.encodeWithSignature("initialize(address)", OWNER);
//         // ERC1967Proxy rcxProxy = new ERC1967Proxy(address(rcxImplementation), rcxInitData);
//         RecurXToken rcx = RecurXToken(RCX_TOKEN);

//         // 2. Deploy Mock Contracts
//         MockERC20 usdt = new MockERC20("Mock USDT", "mUSDT", 6);
//         MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
//         MockAggregator bnbUsdFeed = new MockAggregator(MOCK_BNB_PRICE);

//         // 3. Deploy Vesting Factory
//         RCXVestingFactory vestingFactory = new RCXVestingFactory();

//         // 4. Deploy PublicSale
//         PublicSale saleImpl = new PublicSale();
//         bytes memory initData = abi.encodeWithSelector(
//             PublicSale.initialize.selector,
//             address(rcx),
//             address(usdt),
//             address(usdc),
//             address(bnbUsdFeed),
//             address(vestingFactory),
//             OWNER,
//             TOKEN_PRICE_USD6,
//             TGE_TIMESTAMP,
//             MAX_PER_WALLET
//         );
//         ERC1967Proxy proxy = new ERC1967Proxy(address(saleImpl), initData);
//         PublicSale sale = PublicSale(payable(address(proxy)));

//         // 5. Setup
//         rcx.grantRole(rcx.VESTING_MANAGER_ROLE(), address(sale));
//         vestingFactory.transferOwnership(address(sale));
//         rcx.setBurnFeeExempt(address(sale), true);
//         rcx.setBurnFeeExempt(address(vestingFactory), true);

//         // 6. Initialize Stages
//         sale.initializeStages(stagePrices, stageAllocations);

//         // 7. Fund and Start
//         // rcx.mint(OWNER, 80_000_000e18);
//         rcx.transfer(address(sale), 80_000_000e18);
//         sale.startSale();

//         console.log("PublicSale deployed at:", address(sale));
//         console.log("Mock BNB/USD Feed:", address(bnbUsdFeed));
//         console.log("Mock USDT:", address(usdt));
//         console.log("Mock USDC:", address(usdc));

//         vm.stopBroadcast();
//     }
// }


    /////////////////////////////////////////
    //////////////// TESTNET ////////////////
    /////////////////////////////////////////
    // address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828; // testnet

    // address constant RCX_TOKEN = 0xD8299478cd7C5e2fe638Fc6dBAf32349B00FB491;  // testnet

    // address constant RCX_VESTING_FACTORY = 0xcBB0262F993AB73dE5Aa295580BbfF349C5e091d; // testnet

    // address constant USDT_BSC = 0x0719c5e01262b7Cd68Dec84ae8fA58D9263a239D; // BSC USDT

    // address constant USDC_BSC = 0x4cCc5033FeA1D45FE6270e0C78534DAf0C505eE6; // BSC USDC

    // // address constant BNB_USD_FEED = 0x9fF61118637B492ACEE674c4F38a121ae486aA4e;
    // uint256 public constant INITIAL_BSC_PRICE = 1000e8;
    // MockAggregator public pricefeed = new MockAggregator(int256(INITIAL_BSC_PRICE));  // 0x9fF61118637B492ACEE674c4F38a121ae486aA4e;
    // address BNB_USD_FEED = address(pricefeed);


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {RecurXToken} from "../src/core/RecurxToken.sol";
import {PublicSale} from "../src/launchpad/PublicSale.sol";
import {RCXVestingFactory} from "../src/vesting/RCXVestingFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint256 private _updatedAt;
    uint80 private _roundId;

    constructor(int256 price) {
        _price = price;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    function decimals() external pure returns (uint8) { return 8; }
    function description() external pure returns (string memory) { return "Mock BNB/USD"; }
    function version() external pure returns (uint256) { return 1; }

    function getRoundData(uint80) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function updatePrice(int256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
        _roundId++;
    }
}

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}


contract PublicSaleTestnetDeploy is Script {
    address constant OWNER = 0xbA391F0B052Eacdc3Bf9a2ee1ebD091f8f9c3828;
    uint256 constant TGE_TIMESTAMP = 1735689600;
    uint256 constant TOKEN_PRICE_USD6 = 100000;
    uint256 constant MAX_PER_WALLET = 100000e18;
    int256 constant MOCK_BNB_PRICE = 2000e8; // $2000 BNB
    
    address constant RCX_TOKEN = 0xD8299478cd7C5e2fe638Fc6dBAf32349B00FB491;  // testnet
    address constant RCX_VESTING_FACTORY = 0xcBB0262F993AB73dE5Aa295580BbfF349C5e091d; // testnet
    address constant USDT_BSC = 0x0719c5e01262b7Cd68Dec84ae8fA58D9263a239D; // BSC USDT
    address constant USDC_BSC = 0x4cCc5033FeA1D45FE6270e0C78534DAf0C505eE6; // BSC USDC

    // Your stage data arrays here (same as before)
    uint256[] public stagePrices = [
        60000, // Stage 1: $0.06
        61000, // Stage 2: $0.061
        63000, // Stage 3: $0.063
        64000, // Stage 4: $0.064
        66000, // Stage 5: $0.066
        67000, // Stage 6: $0.067
        69000, // Stage 7: $0.069
        71000, // Stage 8: $0.071what there any funcitonality to make the sale inactive 
        72000, // Stage 9: $0.072
        74000, // Stage 10: $0.074
        76000, // Stage 11: $0.076
        78000, // Stage 12: $0.078
        80000, // Stage 13: $0.08
        81000, // Stage 14: $0.081
        83000, // Stage 15: $0.083
        85000, // Stage 16: $0.085
        87000, // Stage 17: $0.087
        90000, // Stage 18: $0.09
        92000, // Stage 19: $0.092
        94000, // Stage 20: $0.094
        96000, // Stage 21: $0.096
        98000, // Stage 22: $0.098
        101000, // Stage 23: $0.101
        103000, // Stage 24: $0.103
        106000, // Stage 25: $0.106
        108000, // Stage 26: $0.108
        111000, // Stage 27: $0.111
        113000, // Stage 28: $0.113
        116000, // Stage 29: $0.116
        119000, // Stage 30: $0.119
        122000, // Stage 31: $0.122
        124000, // Stage 32: $0.124
        127000, // Stage 33: $0.127
        130000, // Stage 34: $0.13
        134000, // Stage 35: $0.134
        137000, // Stage 36: $0.137
        140000, // Stage 37: $0.14
        143000, // Stage 38: $0.143
        147000, // Stage 39: $0.147
        150000, // Stage 40: $0.15
        154000, // Stage 41: $0.154
        157000, // Stage 42: $0.157
        161000, // Stage 43: $0.161
        165000, // Stage 44: $0.165
        169000, // Stage 45: $0.169
        173000, // Stage 46: $0.173
        177000, // Stage 47: $0.177
        181000, // Stage 48: $0.181
        186000, // Stage 49: $0.186
        190000 // Stage 50: $0.19
    ];
uint256[] public stageAllocations = [
        1096182e18, // Stage 1: 1,096,182 RCX
        1083591e18, // Stage 2: 1,083,591 RCX
        1062119e18, // Stage 3: 1,062,119 RCX
        1064712e18, // Stage 4: 1,064,712 RCX
        1056814e18, // Stage 5: 1,056,814 RCX
        1070395e18, // Stage 6: 1,070,395 RCX
        1072839e18, // Stage 7: 1,072,839 RCX
        1079799e18, // Stage 8: 1,079,799 RCX
        1105915e18, // Stage 9: 1,105,915 RCX
        1120242e18, // Stage 10: 1,120,242 RCX
        1137821e18, // Stage 11: 1,137,821 RCX
        1158322e18, // Stage 12: 1,158,322 RCX
        1181455e18, // Stage 13: 1,181,455 RCX
        1221867e18, // Stage 14: 1,221,867 RCX
        1249505e18, // Stage 15: 1,249,505 RCX
        1279122e18, // Stage 16: 1,279,122 RCX
        1310537e18, // Stage 17: 1,310,537 RCX
        1328661e18, // Stage 18: 1,328,661 RCX
        1363157e18, // Stage 19: 1,363,157 RCX
        1399005e18, // Stage 20: 1,399,005 RCX
        1436091e18, // Stage 21: 1,436,091 RCX
        1474311e18, // Stage 22: 1,474,311 RCX
        1498587e18, // Stage 23: 1,498,587 RCX
        1538706e18, // Stage 24: 1,538,706 RCX
        1564798e18, // Stage 25: 1,564,798 RCX
        1606488e18, // Stage 26: 1,606,488 RCX
        1634063e18, // Stage 27: 1,634,063 RCX
        1677059e18, // Stage 28: 1,677,059 RCX
        1705850e18, // Stage 29: 1,705,850 RCX
        1735230e18, // Stage 30: 1,735,230 RCX
        1765139e18, // Stage 31: 1,765,139 RCX
        1810007e18, // Stage 32: 1,810,007 RCX
        1840729e18, // Stage 33: 1,840,729 RCX
        1871851e18, // Stage 34: 1,871,851 RCX
        1889130e18, // Stage 35: 1,889,130 RCX
        1921019e18, // Stage 36: 1,921,019 RCX
        1953199e18, // Stage 37: 1,953,199 RCX
        1985642e18, // Stage 38: 1,985,642 RCX
        2004594e18, // Stage 39: 2,004,594 RCX
        2037548e18, // Stage 40: 2,037,548 RCX
        2057247e18, // Stage 41: 2,057,247 RCX
        2090610e18, // Stage 42: 2,090,610 RCX
        2110935e18, // Stage 43: 2,110,935 RCX
        2131630e18, // Stage 44: 2,131,630 RCX
        2152663e18, // Stage 45: 2,152,663 RCX
        2174004e18, // Stage 46: 2,174,004 RCX
        2195628e18, // Stage 47: 2,195,628 RCX
        2217510e18, // Stage 48: 2,217,510 RCX
        2227588e18, // Stage 49: 2,227,588 RCX
        2250084e18 // Stage 50: 2,250,084 RCX
    ];

    function run() external {
        vm.startBroadcast();

        // 1. Deploy RCX Token
        RecurXToken rcx = RecurXToken(RCX_TOKEN);

        // 2. Deploy Mock Contracts
        MockERC20 usdt = new MockERC20("Mock USDT", "mUSDT", 6);
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        MockAggregator bnbUsdFeed = new MockAggregator(MOCK_BNB_PRICE);

        // 3. Deploy Vesting Factory
        RCXVestingFactory vestingFactory = new RCXVestingFactory();

        // 4. Deploy PublicSale
        PublicSale saleImpl = new PublicSale();
        bytes memory initData = abi.encodeWithSelector(
            PublicSale.initialize.selector,
            address(rcx),
            address(usdt),
            address(usdc),
            address(0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526),
            address(vestingFactory),
            OWNER,
            TOKEN_PRICE_USD6,
            TGE_TIMESTAMP,
            MAX_PER_WALLET
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(saleImpl), initData);
        PublicSale sale = PublicSale(payable(address(proxy)));

        // 5. Setup
        rcx.grantRole(rcx.VESTING_MANAGER_ROLE(), address(sale));
        vestingFactory.transferOwnership(address(sale));
        rcx.setBurnFeeExempt(address(sale), true);
        rcx.setBurnFeeExempt(address(vestingFactory), true);

        // 6. Initialize Stages
        sale.initializeStages(stagePrices, stageAllocations);

        // 7. Fund and Start
        rcx.transfer(address(sale), 70_000_000e18);
        sale.startSale();

        console.log("PublicSale deployed at:", address(sale));
        console.log("Mock BNB/USD Feed:", address(bnbUsdFeed));
        console.log("Mock USDT:", address(usdt));
        console.log("Mock USDC:", address(usdc));

        vm.stopBroadcast();
    }
}