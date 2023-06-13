// SPDX-License-Identifier: MIT


pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import  "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract DSCEngine is ReentrancyGuard {

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine_TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 _healthFactor);
    error DSCEngine_MintFailed();

     DecentralizedStableCoin private immutable i_dsc;
     uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
      uint256 private constant PRECISION = 1e18;
      uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
      uint256 private constant LIQUIDATION_PRECISION = 100;
      uint256 private constant MIN_HEALTH_FACTOR = 1;


       event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;



       modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine__NotAllowedToken();
        }
      _;
    }

        constructor(address[] memory tokenAddresses,
              address[] memory priceFeedAddresses,
              address dscAddress) 
              {
                //USD PRICE Feeds

       if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        //For example ETH / USD, BTC/USD, MKR/USD, etc
        for (uint256 i =0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);

    }


    function depositCollateralAndMintDsc() external {}



/* address of token to deposit
/* amount of collateral to deposit
*/
   function depositCollateral(
    address tokenCollateralAddress,
    uint256 amountCollateral
) external 
   moreThanZero(amountCollateral)
   isAllowedToken(tokenCollateralAddress)
    nonReentrant 
 {
     s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
     emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
     bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
     if (!success) {
        revert DSCEngine_TransferFailed();
     }
}


function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
    s_DSCMinted[msg.sender] += amountDscToMint;
    //if they minted too much
    revertIfHealthFactorIsBroken(msg.sender);
    bool minted = i_dsc.mint(msg.sender, amountDscToMint);
    if(!minted) {
        revert DSCEngine__MintFailed();
    }
}

function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
    totalDscMinted = s_DSCMinted[user];
    collateralValueInUsd = getAccountCollateralValue(user);
}


function _healthFactor (address user) private view returns (uint256) {
    // total DSC minted
    // total collateral VALUE
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) /  LIQUIDATION_PRECISION;
    return(collateralAdjustedForThreshold * PRECISION) - totalDscMinted;   
    

    // $150 ETH / 100 DSC = 1.5
    // 150 * 50 = 7500 / 100 = (75 / 100) < 1
    // 1000 ETH * 50 = 50,000 / 100 = (500 / 100) > 1
    //return (collateralValueInUsd / totalDscMinted); // ()
}


function revertIfHealthFactorIsBroken(address user) internal view {
    uint256 userHealthFactor = _healthFactor(user);
    if (userHealthFactor < MIN_HEALTH_FACTOR)
    revert DSCEngine__BreaksHealthFactor(userHealthFactor);
    // check do they have enough collateral
    // revert if they don't

}

function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
    // loop through each collateral token, get amount, they have deposited and map it to
    // the price, to get the USD value
    for(uint256 i = 0; i<s_collateralTokens.length; i++) {
        address token = s_collateralTokens[i];
        uint256 amount = s_collateralDeposited[user][token];
        totalCollateralValueInUsd += getUsdValue(token, amount);
    
    }
    return totalCollateralValueInUsd;

}

function getUsdValue(address token, uint256 amount) public view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price, , , ) = priceFeed.latestRoundData();
    // 1 ETH = $1000
    // The returned value from Chainlink will be 1000 * 1e8
    // 1e8 = 1 * 10^8 = 100000000
    return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (1000 * 1e8 * (1e10)) * 1000 * 1e18;
}


}