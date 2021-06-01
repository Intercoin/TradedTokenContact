// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC777/ERC777Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC777/IERC777RecipientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC1820ImplementerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
//import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "./libs/FixedPoint.sol";

import "./interfaces/ITransferRules.sol";
import "./IntercoinTrait.sol";


import "./interfaces/ITradedTokenContract.sol";


contract TradedTokenContract is IUniswapV2Callee, ITradedTokenContract, ERC777Upgradeable, OwnableUpgradeable, IntercoinTrait, IERC777RecipientUpgradeable, ERC1820ImplementerUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;

    using FixedPoint for *;

    address public uniswapRouter;
    address public uniswapRouterFactory;


    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    /**
     * Configured contract implementing token rule(s).
     * If set, transfer will consult this contract should transfer
     * be allowed after successful authorization signature check.
     * And call doTransfer() in order for rules to decide where fund
     * should end up.
     */
    ITransferRules public _rules;
    
    uint256 public liquidityPercent;

    // stored Sell Price in binary fixed point 112*112
    //uint224 private lastSellPrice_Q112;
    FixedPoint.uq112x112 internal lastMaxSellPrice;
    FixedPoint.uq112x112 internal lastBuyPrice;
    
    
    bool initialPriceAlreadySet;
    
    // predefine owners addresses
    OwnersList[] ownersList;
    
    
    mapping (address => address) invitedBy;
    
    struct recentStruct {
        uint256 sentPercent;
        uint256 balance;
        uint256 timestamp;
        bool exists;
    }
    mapping (address => recentStruct) recentTransfer;
    
    // Taxes
    TransferTax transferTax;
    ProgressiveTax progressiveTax;
    SellTax sellTax;
    BuyTax buyTax;
    
    event RulesUpdated(address rules);

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    
    event SentToInviter(uint256 amount);
    event Received(address sender, uint amount);
    
    event NotEnoughTokenToSell(uint256 amount);
    event NotEnoughETHToBuyTokens(uint256 amount);
    event NoAvailableReserves();
    event NoAvailableReserveToken();
    event NoAvailableReserveETH();
    
    
    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    bool uniswapV2PairReentrant;
    modifier lockTransferFrom {
        uniswapV2PairReentrant = true;
        _;
        uniswapV2PairReentrant = false;
    }
    
    modifier initialPriceSet() {
        require(initialPriceAlreadySet == false, "Initial price has already set");
        initialPriceAlreadySet = true;
        _;
    }
    
    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    
    /*IERC777RecipientUpgradeable*/
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) 
        external 
        override
    {
        //require(msg.sender == address(_token), "Simple777Recipient: Invalid token");

        // do stuff
        //emit DoneStuff(operator, from, to, amount, userData, operatorData);
    }
    
    function uniswapV2Call(
        address sender, 
        uint amount0, 
        uint amount1, 
        bytes calldata data
    ) 
        external
        override
    {
     //   require(1==0, 'Art::here');
    }
    
    
    function initialize(
        string memory name, 
        string memory symbol, 
        address[] memory defaultOperators,
        BulkStruct[] memory _predefinedBalances,
        BuyTax memory _buyTax,
        SellTax memory _sellTax,
        TransferTax memory _transfer,
        ProgressiveTax memory _progressive,
        OwnersList[] memory _ownersList
    ) 
        public 
        virtual 
        override
        initializer 
    {
        (uniswapRouter, uniswapRouterFactory) = networkSettings();

        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC777_init(name, symbol, defaultOperators);
        __ERC1820Implementer_init();
        
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
        
        uint256 totalSupply = 1_000_000_000 * 10 ** 18;
        uint256 tokensLeft = totalSupply;
        
        for (uint256 i = 0; i < _predefinedBalances.length; i++) {
            _mint(_predefinedBalances[i].recipient, _predefinedBalances[i].amount, "", "");
            tokensLeft= tokensLeft.sub(_predefinedBalances[i].amount);
            
        }
        _mint(address(this), tokensLeft, "", "");
        
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(uniswapRouter);
        
         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory)
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
    
        lastMaxSellPrice._x = 0;
    
        buyTax.percentOfTokenAmount = (_buyTax.percentOfTokenAmount == 0 ) ? 0 : _buyTax.percentOfTokenAmount; // token percent of LP to be buy;
        buyTax.priceDecreaseMin = (_buyTax.priceDecreaseMin == 0 ) ? 10 : _buyTax.priceDecreaseMin; // 10%
        buyTax.slippage = (_buyTax.slippage == 0 ) ? 10 : _buyTax.slippage; //10%
        buyTax.percentOfSellPrice = _buyTax.percentOfSellPrice;
        
        sellTax.percentOfTokenAmount = (_sellTax.percentOfTokenAmount == 0 ) ? 0 : _sellTax.percentOfTokenAmount; // token percent of LP to be sell;
        sellTax.priceIncreaseMin = (_sellTax.priceIncreaseMin == 0 ) ? 10 : _sellTax.priceIncreaseMin; // 10%
        sellTax.slippage = (_sellTax.slippage == 0 ) ? 10 : _sellTax.slippage; //10%
        
        transferTax.total = (_transfer.total == 0 ) ? 0 : _transfer.total; // default 0 percent;
        transferTax.toLiquidity = (_transfer.toLiquidity == 0 ) ? 10 : _transfer.toLiquidity; // default 10 percent;
        transferTax.toBurn = (_transfer.toBurn == 0 ) ? 0 : _transfer.toBurn; // default 10 percent;
        
        progressiveTax.from = (_progressive.from == 0 ) ? 5 : _progressive.from; // default 5 percent
        progressiveTax.to = (_progressive.to == 0 ) ? 100 : _progressive.to; // default 100 percent
        progressiveTax.duration = (_progressive.duration == 0 ) ? 3600 : _progressive.duration; // default 3600 seconds;
        
        // proportions (array of percentages which must add up to 100)
        uint256 p = 0;
        for (uint256 i=0; i<_ownersList.length; i++) {
            ownersList.push(_ownersList[i]);
            p = p.add(_ownersList[i].percent);
        }
        require(p == 100, "overall percents for `_ownersList` must equal 100");
        
    }
    
    /**
     * @param price initial price 1 eth token mul by 1e9
     * called only once
     */
    function setInitialPrice(
        uint256 price
    ) 
        public 
        onlyOwner 
        initialPriceSet()
    {
        uint256 ethAmount = address(this).balance;
        require(ethAmount != 0, 'balance is empty');
        //eth/price*1e9/1e18/1e9
        
        //uint256 tokenAmount = ethAmount.mul(price).div(1e9);
        
        //irb(main):114:0> 0.1e18*1e9/1e6 / 1e9
        uint256 tokenAmount = ethAmount.mul(1e9).div(price);
        require(tokenAmount <= balanceOf(address(this)), 'balance is not enough');
        
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        
        // set initial sell price are currentSellPrice + currentSellPrice*sellTax.priceIncreaseMin
        FixedPoint.uq112x112 memory fractionPercent;
        FixedPoint.uq112x112 memory _currentSellPrice;
        (_currentSellPrice,,,) = _currentPrices();
        fractionPercent = _currentSellPrice.muluq(FixedPoint.fraction(uint112(sellTax.priceIncreaseMin), uint112(100)));
        lastMaxSellPrice._x = _currentSellPrice._x + fractionPercent._x;
        
        fractionPercent = lastMaxSellPrice.muluq(FixedPoint.fraction(uint112(buyTax.percentOfSellPrice), uint112(100)));
        lastBuyPrice._x = lastMaxSellPrice._x - fractionPercent._x;
        
        //lastMaxSellPrice._x = 4456;
        // lastBuyPrice._x=123;
    }
     
    /**
     * set restriction for every transfer
     * @param rules address of TransferRules contract
     * @return bool
     */
    function _updateRestrictionsAndRules(
        address rules
    ) 
        public 
        onlyOwner
        returns (bool) 
    {

        _rules = ITransferRules(rules);

        if (rules != address(0)) {
            require(_rules.setERC(address(this)), "ERC777 contract already set in transfer rules");
        }

        emit RulesUpdated(rules);
        return true;
    }
    
    /**
     * @param _bulkStruct array of tuples [recipient, address]
     * @param _data bytes to operatorSend
     */
    function bulkTransfer(
        BulkStruct[] memory _bulkStruct, 
        bytes memory _data
    ) 
        public 
    {
        for (uint256 i = 0; i < _bulkStruct.length; i++) {
            operatorSend(msg.sender, _bulkStruct[i].recipient, _bulkStruct[i].amount, _data, "");
        }
    }
 
    /**
     * ERC777-transfer overroded
     */
    function transfer(
        address recipient, 
        uint256 amount
    ) 
        public 
        virtual 
        override
        /*nonReentrant*/ // 
        returns (bool) 
    {

        bool success;
        
        require(amount > 0, "Transfer amount must be greater than zero");
        
        //### calculate taxes)
        // tax calculated through multiple by TransferTax.toLiquidity 
        uint256 taxLiquidityAmount;
        // tax calculated through multiple by TransferTax.toBurn 
        uint256 taxBurnAmount;
        // bonus to inviter
        uint256 inviterBonusAmount;
/*
        (
            taxLiquidityAmount, 
            taxBurnAmount, 
            inviterBonusAmount
        ) = taxCalculation(recipient, amount);
        
        uint256 totalTaxes = taxLiquidityAmount.add(taxBurnAmount).add(inviterBonusAmount);

        require(amount > (totalTaxes), "Transfer amount left after taxes applied must be greater than zero");
        
        amount = amount.sub(totalTaxes);
        
        //### then make swap (taxLiquidityAmount)

        if (
            taxLiquidityAmount > 0 &&
            !inSwapAndLiquify &&
            _msgSender() != uniswapV2Pair &&
            _msgSender() != address(this) &&
            swapAndLiquifyEnabled
        ) {
            swapAndLiquify(taxLiquidityAmount);
        }
        
        //### then burn taxBurnAmount
        if (taxBurnAmount>0) {
            _burn(_msgSender(),taxBurnAmount, "", "");
        }
        
        //### then send to inviter some bonus(inviterBonusAmount)
        if (inviterBonusAmount>0) {
            super.transfer(invitedBy[recipient], inviterBonusAmount);
        }
*/            
        //### then common ERC777-transfer
        success = super.transfer(recipient, amount);
/**/        
        //### then setup invitedBy
//        setInvitedBy(recipient, _msgSender());
         
         
        if (_msgSender() == uniswapV2Pair && !uniswapV2PairReentrant) {
            
  //          buyTokenCalculation(recipient);
  //if (recipient != address(this)) {
            sellTokenCalculation(amount);
  //}
  
// (
// uint256 tokensShouldToSell,
// uint256 ethWouldToObtain,
// FixedPoint.uq112x112 memory currentSellPrice, 
// FixedPoint.uq112x112 memory currentBuyPrice
// ) = _shouldSell();
// tstSell.push(tokensShouldToSell); 
// ethToObtain.push(ethWouldToObtain);   
        }
/**/        
        
        return success;
    }

    function transferFrom(address holder, address recipient, uint256 amount) public virtual override  returns (bool) {

        
        bool success = super.transferFrom(holder, recipient, amount);
return true;
        //if (holder == uniswapV2Pair && !uniswapV2PairReentrant) {
//         if (recipient == uniswapV2Pair && !uniswapV2PairReentrant ) {    

//             //### then if price exceed -  calculate sellTokenAmount, swap to eth and distributed through owners by percents
// //            sellTokenCalculation(recipient);

//         }

        return success;
        
    }

    /**
     * getting current prices for pair token and eth
     * 
     */
    function _currentPrices(
    ) 
        internal 
        returns(
            FixedPoint.uq112x112 memory _currentSellPrice, 
            FixedPoint.uq112x112 memory _currentBuyPrice,
            uint256 _reserveToken,
            uint256 _reserveEth
    ) {
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, ) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            // Exclude case when reserves are empty
            emit NoAvailableReserves();
        } else {
            
            if (uniswapV2Router.WETH() == IUniswapV2Pair(uniswapV2Pair).token0()) {
                _currentSellPrice = FixedPoint.fraction(reserve0,reserve1);
                _currentBuyPrice = FixedPoint.fraction(reserve1,reserve0);
                _reserveEth = reserve0;
                _reserveToken = reserve1;
            } else {
                _currentSellPrice = FixedPoint.fraction(reserve1,reserve0);
                _currentBuyPrice = FixedPoint.fraction(reserve0,reserve1);
                _reserveEth = reserve1;
                _reserveToken = reserve0;
            }
        
        }
    }
    
    /**
     * calculating how much tokens contract should to sell 
     * and making simple validation before
     */
    function _shouldSell(
        uint256 amountBoughtByUser
    ) 
        internal 
        returns(
            uint256 amount,
            uint256 amountEth,
            FixedPoint.uq112x112 memory _currentSellPrice, 
            FixedPoint.uq112x112 memory _currentBuyPrice
        )
    {
        // get sell/buy prices
        uint256 reserveToken;
        uint256 reserveEth;
        (_currentSellPrice, _currentBuyPrice, reserveToken, reserveEth) = _currentPrices();
        
        
         
        amount = 0;
        amountEth = 0;
        
        
        if (_currentSellPrice._x > lastMaxSellPrice._x) {
        //if (true == true) {
            
            uint256 ethGotFromUser = uniswapV2Router.getAmountOut(amountBoughtByUser, reserveToken, reserveEth);
            uint256 sellTokenAmount = (reserveToken.sub(amountBoughtByUser)).mul(sellTax.percentOfTokenAmount).div(100);
            
            if (sellTokenAmount > 0) {
                
                address[] memory path = new address[](2);
                path[0] = address(this);
                path[1] = uniswapV2Router.WETH();

                // calculating eth amount to get optimal token amounts before calling swap.
 
                // uint256[] memory amounts = uniswapV2Router.getAmountsOut(sellTokenAmount, path);
                // uint256 _amountEth = amounts[amounts.length-1];
                
                reserveToken = reserveToken.sub(amountBoughtByUser);
                reserveEth = reserveEth.add(ethGotFromUser);
                
                uint256 _amountEth = uniswapV2Router.getAmountOut(sellTokenAmount, reserveToken, reserveEth);
            
                _amountEth = _amountEth.sub(_amountEth.mul(sellTax.slippage).div(100));
                
                if (balanceOf(address(this)) >= sellTokenAmount) {
                    
                    if (_amountEth < reserveEth && _amountEth>0) {
                        amount = sellTokenAmount;
                        amountEth = _amountEth;
                        
                        // update lastMaxSellPrice and buy price
                        FixedPoint.uq112x112 memory fractionPercent;
                        
                        fractionPercent = lastMaxSellPrice.muluq(FixedPoint.fraction(uint112(sellTax.priceIncreaseMin), uint112(100)));
                        lastMaxSellPrice._x = lastMaxSellPrice._x + fractionPercent._x;
                          
                        fractionPercent = lastMaxSellPrice.muluq(FixedPoint.fraction(uint112(buyTax.percentOfSellPrice), uint112(100)));
                        lastBuyPrice._x = lastMaxSellPrice._x - fractionPercent._x;
                    } else {
                        emit NoAvailableReserveETH();
                    }
                } else {
                    emit NotEnoughTokenToSell(sellTokenAmount);
                }
                
            } 
            
        }
    }
    
    /**
     * calculating how much tokens contract should to buy back
     */
    function _shouldBuy(
    ) 
        internal 
        returns(
            uint256 amount,
            uint256 amountEth,
            FixedPoint.uq112x112 memory _currentSellPrice, 
            FixedPoint.uq112x112 memory _currentBuyPrice
        )
    {
        uint256 reserveToken;
        // get sell/buy prices 
        (_currentSellPrice, _currentBuyPrice, reserveToken,) = _currentPrices();
        
        amount = 0;
        amountEth = 0;
        
        // if buy.percentOfSellPrice = 0 then it wouldn't buy back.
        if (buyTax.percentOfSellPrice > 0) {
            
            
            if (_currentSellPrice._x < lastBuyPrice._x) {
                
                amount = reserveToken.mul(buyTax.percentOfTokenAmount).div(100);
                
                // generate the uniswap pair path of weth -> token
                address[] memory path = new address[](2);
                path[0] = uniswapV2Router.WETH();
                path[1] = address(this);
    
                // calculating eth amount to get optimal token amounts before calling swap.
                uint256[] memory amounts = uniswapV2Router.getAmountsOut(amount, path);
                amountEth = amounts[amounts.length-1];
                
                if ((address(this).balance) > amountEth) {
                    // all ok
                    
                    // update buyPrice
                    FixedPoint.uq112x112 memory fractionPercent = lastBuyPrice.muluq(FixedPoint.fraction(uint112(buyTax.priceDecreaseMin), uint112(100)));
                    lastBuyPrice._x = lastBuyPrice._x - fractionPercent._x;
                        
                } else {
                    emit NotEnoughETHToBuyTokens(amountEth);
                    amount = 0;
                    amountEth = 0;
                }
            }
            
        }
    }
    
    function buyTokenCalculation(address recipient) internal lockTransferFrom {
        (
            uint256 tokensShouldToBuy,
            uint256 ethNeedToSpend,
            FixedPoint.uq112x112 memory currentSellPrice, 
            FixedPoint.uq112x112 memory currentBuyPrice
        ) = _shouldBuy();
        
        if (tokensShouldToBuy > 0 && ethNeedToSpend > 0) {

            // generate the uniswap pair path of weth -> token
            address[] memory path = new address[](2);
            path[0] = uniswapV2Router.WETH();
            path[1] = address(this);

            uniswapV2Router.swapETHForExactTokens{value: ethNeedToSpend}(
                tokensShouldToBuy,
                path,
                address(this),
                block.timestamp
            );
                
        }
    }
uint256[] tstSell;
uint256[] ethToObtain;
uint256[] rT;
uint256[] rE;
uint112[] sP;
uint112[] bP;
function gett() public view returns(uint256[] memory t,uint256[] memory t2,uint256[] memory t3,uint256[] memory t4,uint112[] memory t5,uint112[] memory t6) {
    return (tstSell,ethToObtain,rT,rE,sP,bP);
}

    function sellTokenCalculation(uint256 amount_to_correction) internal lockTransferFrom {

        (
            uint256 tokensShouldToSell,
            uint256 ethWouldToObtain,
            FixedPoint.uq112x112 memory currentSellPrice, 
            FixedPoint.uq112x112 memory currentBuyPrice
        ) = _shouldSell(amount_to_correction);


        if (tokensShouldToSell > 0 && currentSellPrice._x > 0 && currentBuyPrice._x > 0 && ethWouldToObtain > 0) {

            // generate the uniswap pair path of token -> weth
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = uniswapV2Router.WETH();
            
// tstSell.push(tokensShouldToSell); 
// ethToObtain.push(ethWouldToObtain); 
uint256 trT;
uint256 trE;
(,,trT,trE) = _currentPrices();
tstSell.push(tokensShouldToSell); 
ethToObtain.push(ethWouldToObtain);
rT.push(trT);
rE.push(trE);
sP.push(uint112(currentSellPrice._x));
bP.push(uint112(currentBuyPrice._x));       
          
            _approve(address(this), address(uniswapV2Router), tokensShouldToSell);

            // make the swap
            uint256[] memory amounts = uniswapV2Router.swapExactTokensForETH(
            
                tokensShouldToSell,
                //(sell.tokenAmount).mul(sell.slippage).div(100), //0, // accept any amount of ETH
                //amountEth.sub(amountEth.div(sellTax.slippage)), 
                //ethWouldToObtain, //
                0, // accept any amount of ETH
                
                //
                path,
                address(this),
                block.timestamp
            );

/* */           
            /* 
             !!!! TODO 0: we can not get eth directly. so we must unwrap eth before this manipulations !!!!
            uint256 amountToken0 = amounts[amounts.length-1].mul(transferTax.toLiquidity).div(100);
            
            uint256 amountToken1 = uint256(FixedPoint.decode144(FixedPoint.mul(currentSellPrice, amountToken0)));
            
            ///-----
            if (balanceOf(address(this)) >= amountToken1) {
                //            eth           token
                addLiquidity(amountToken0, amountToken1);
                
                uint256 eth2send = amounts[0].sub(amountToken0);
                
                address payable addr1;
                bool success2;
                for (uint256 i = 0 ; i< ownersList.length; i++) {
                    addr1 = payable(ownersList[i].addr); // correct since Solidity >= 0.6.0
                    (success2, ) = addr1.call{value: eth2send.mul(100).div(ownersList[i].percent)}("");
                    // success2 = addr1.send(eth2send.mul(100).div(ownersList[i].percent));
                    require(success2 == true, 'Transfer ether was failed'); 
                }

                
            }
            */
            
        }

    }
    /**
     * fill invitedBy mapping
     * @param invited person been invited
     * @param inviter person who invited
     * 
     */
    function setInvitedBy(
        address invited, 
        address inviter
    ) 
        internal 
    {
        if (invitedBy[invited] == address(0)) {
            invitedBy[invited] = inviter;
        }
    }
    
    /**
     * return addresses for uniswap/pancake router and factory
     * @dev note that (uniswapV2Router).factory() also get factory's address but crashed in bsc testnet
     */
    function networkSettings(
    ) 
        internal
        view 
        returns(
            address _uniswapRouter, 
            address _uniswapRouterFactory
        ) 
    {
        
        // Ethereum all networks
        // uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        // uniswapRouterFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        
        // BSC TestNet
        // uniswapRouter = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
        // uniswapRouterFactory = 0x6725F303b657a9451d8BA641348b6761A6CC7a17;

        // BSC MainNet
        // uniswapRouter = 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;
        // uniswapRouterFactory = 0xBCfCcbde45cE874adCB698cC183deBcF17952812;
    
        if (block.chainid == 1 || block.chainid == 3 || block.chainid == 4) {
            _uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
            _uniswapRouterFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        } else if (block.chainid == 56) {
            _uniswapRouter = 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;
            _uniswapRouterFactory = 0xBCfCcbde45cE874adCB698cC183deBcF17952812;
        } else if (block.chainid == 97) {
            _uniswapRouter = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
            _uniswapRouterFactory = 0x6725F303b657a9451d8BA641348b6761A6CC7a17;
        } else {
            revert("Chain does not supported");
        }
    }
    
    /**
     * added liquidity 
     * @param ethAmount amount in ETH
     * @param tokenAmount amount in tokens
     */
    function addLiquidity(
        uint256 ethAmount,
        uint256 tokenAmount
    ) 
        internal
    {
       
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        (,, uint256 lpTokens) = uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        
        // IUniswapV2Pair(uniswapV2Pair).burn(address(0));
        if (transferTax.toBurn > 0) {
            IUniswapV2Pair(uniswapV2Pair).transfer(address(0), lpTokens.mul(transferTax.toBurn).div(100));
        }
        
        uint256 lpToSend = lpTokens.sub(lpTokens.mul(transferTax.toBurn).div(100));

        for (uint256 i = 0 ; i< ownersList.length; i++) {
            IUniswapV2Pair(uniswapV2Pair).transfer(ownersList[i].addr, lpToSend.mul(100).div(ownersList[i].percent));
        }
        
    }
    
    /**
     * calculate taxes from amount
     * @param recipient recipient's address
     * @param amount amount of tokens
     * @return taxLiquidity liquidity tax
     * @return taxBurn burn tax
     * @return inviterBonus bonus to inviter
     */
    function taxCalculation(
        address recipient, 
        uint256 amount
    ) 
        internal
        returns(uint256 taxLiquidity, uint256 taxBurn, uint256 inviterBonus) 
    {
        
        if (
            transferTax.total == 0 ||
            (
                _msgSender() != uniswapV2Pair &&
                _msgSender() != address(this) &&
                recipient != uniswapV2Pair &&
                recipient != address(this)
            )
        ) {
            taxLiquidity = 0;
            taxBurn = 0;
            inviterBonus = 0;
        } else {
            if (_msgSender() == address(this) || recipient == uniswapV2Pair) {
                taxLiquidity = 0;
                taxBurn = 0;
                inviterBonus = 0;
            } else {
                
                
                // calculate progressive task 
                if (block.timestamp > (recentTransfer[_msgSender()].exists ? recentTransfer[_msgSender()].timestamp : 0).add(progressiveTax.duration)) {
                    recentTransfer[_msgSender()].timestamp = block.timestamp;
                    recentTransfer[_msgSender()].balance = balanceOf(_msgSender());
                    recentTransfer[_msgSender()].sentPercent = 0;
                }
                
                uint256 sp = recentTransfer[_msgSender()].sentPercent;
                uint256 pt = progressiveTax.to;
                uint256 pf = progressiveTax.from;
                
                uint256 p = recentTransfer[_msgSender()].sentPercent.add(amount.mul(100).div(recentTransfer[_msgSender()].balance));
                
                // TODO:1 (pt-pf) can be<0 ?
                uint256 taxP = p < pf ? 0 : (p.add(sp)).div(2).sub(pf).div(pt.sub(pf)).mul(transferTax.total);
                recentTransfer[_msgSender()].sentPercent = p;
                
                // 
                uint256 transferTaxAmount = amount.mul(taxP).div(100);
                
                if (recipient == address(this)) {
                    // no taxLiquidity and taxBurn
                } else {
                    taxLiquidity = transferTaxAmount.mul(transferTax.toLiquidity).div(100);
                
                    taxBurn =  transferTaxAmount.mul(transferTax.toBurn).div(100);
                    
                    inviterBonus = transferTaxAmount.sub(taxLiquidity).sub(taxBurn);
                    if (invitedBy[recipient] == address(0)) {
                        inviterBonus = 0;
                        taxBurn = taxBurn.add(inviterBonus);
                    }
                }
            }
        }
      
    }
    
    /**
     * @dev Hook that is called before any token transfer. This includes
     * calls to {send}, {transfer}, {operatorSend}, minting and burning.
     * 
     */
    function _beforeTokenTransfer(
        address operator, 
        address from, 
        address to, 
        uint256 amount
    ) 
        internal 
        override 
    { 
        if (address(_rules) != address(0)) {
            
            if (from != address(0) && to != address(0)) {
                require(_rules.applyRuleLockup(from, to, amount), "Transfer failed");
            }
        }
    }
    
    /**
     * @param amountLiquify amountLiquify
     */
    function swapAndLiquify(uint256 amountLiquify) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = amountLiquify.div(2);
        uint256 otherHalf = amountLiquify.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }
    
    /**
     * @param tokenAmount token's amount
     */
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }
   
}