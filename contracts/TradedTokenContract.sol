// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC777/ERC777Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./interfaces/ITransferRules.sol";
import "./IntercoinTrait.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC777/IERC777RecipientUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC1820ImplementerUpgradeable.sol";

import "./interfaces/ITradedTokenContract.sol";

contract TradedTokenContract is ITradedTokenContract, ERC777Upgradeable, OwnableUpgradeable, IntercoinTrait, IERC777RecipientUpgradeable, ERC1820ImplementerUpgradeable {
    using SafeMathUpgradeable for uint256;

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
  //  uint256 public excessTokenSellSlippage;
    //uint256 public sellPriceIncreaseMin;
    //uint256 public sellEventsTotal;
    uint256 public currentPrice;
    
    // stored latestCumulative price of WETH
    uint256 private lastSellPrice;
    
    
    bool initialPriceSet;
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
    SellTax sell;
    
    
    
    
    event RulesUpdated(address rules);

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    
    event SentToInviter(uint256 amount);
    

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    function donateETH() public payable {
        
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}
    
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
    /**/
    
    function initialize(
        string memory name, 
        string memory symbol, 
        address[] memory defaultOperators,
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

        __Ownable_init();
        __ERC777_init(name, symbol, defaultOperators);
        __ERC1820Implementer_init();
        
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
        
        _mint(address(this), 1_000_000_000 * 10 ** 18, "", "");
        
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(uniswapRouter);
        
         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory)
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
        
        currentPrice = 0;
        lastSellPrice = 0;
    
        initialPriceSet = false;
    
        sell.eventsTotal = 100; // times to divide
        sell.priceIncreaseMin = 10; // 10%
        sell.slippage = 10; //10%
        
        transferTax.total = (_transfer.total == 0 ) ? 0 : _transfer.total; // default 0 percent;
        transferTax.toLiquidity = (_transfer.toLiquidity == 10 ) ? 0 : _transfer.toLiquidity; // default 10 percent;
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
     */
    function setInitialPrice(
        uint256 price
    ) public onlyOwner {
        require(initialPriceSet == false, 'Initial price has already set');
        uint256 ethAmount = address(this).balance;
        require(ethAmount != 0, 'balance is empty');
        //eth/price*1e9/1e18/1e9
        
        //uint256 tokenAmount = ethAmount.mul(price).div(1e9);
        
        //irb(main):114:0> 0.1e18*1e9/1e6 / 1e9
        uint256 tokenAmount = ethAmount.mul(1e9).div(price);
        require(tokenAmount <= balanceOf(address(this)), 'balance is not enough');
        
        initialPriceSet == true;
        
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        
    }
    
    /**
     * fill invitedBy mapping
     * @param invited person been invited
     * @param inviter person who invited
     * 
     */
    function setInvitedBy(address invited, address inviter) internal {
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
        
        if (transferTax.total == 0) {
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

    function transfer(
        address recipient, 
        uint256 amount
    ) 
        public 
        virtual 
        override 
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
        
        (
            taxLiquidityAmount, 
            taxBurnAmount, 
            inviterBonusAmount
        ) = taxCalculation(recipient, amount);
        
        uint256 totalTaxes = taxLiquidityAmount.add(taxBurnAmount).add(inviterBonusAmount);

        require(amount > (totalTaxes), "Transfer amount left after taxes applied must be greater than zero");
        
        amount = amount.sub(totalTaxes);
        
        //### then make swap (taxLiquidityAmount)
        
        uint256 amountLiquify;// = amount.mul(liquidityPercent).div(100);

        // if(amountLiquify >= _maxTxAmount)
        // {
        //     amountLiquify = _maxTxAmount;
        // }
        // bool overMinTokenBalance = amountLiquify >= numTokensSellToAddToLiquidity;
        if (
           // overMinTokenBalance &&
            !inSwapAndLiquify &&
            _msgSender() != uniswapV2Pair &&
            _msgSender() != address(this) &&
            swapAndLiquifyEnabled
        ) {
            // amountLiquify = amount.mul(liquidityPercent).div(100);
            // amount = amount.sub(amountLiquify);
            //add liquidity
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
            
        //### then common ERC20-transfer
        success = super.transfer(recipient, amount);
        
        //### then setup invitedBy
         setInvitedBy(recipient, _msgSender());
         
        //### then if price exceed -  calculate settTokenAmount, swap to eth and distributed through owners by percents
        // point 4
        if (recipient == uniswapV2Pair) {
            uint256 currentSellPrice;
            if (uniswapV2Router.WETH() == IUniswapV2Pair(uniswapV2Pair).token0()) {
                currentSellPrice = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
            } else {
                currentSellPrice = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
            }
            
            // priceExcess = latestPrice - latestMaxPrice * (1 + sell.afterPriceIncrease). 
            // And if priceExcess > 0 then you are supposed to sell 
            uint256 priceInreased = lastSellPrice.mul(sell.priceIncreaseMin.add(100)).div(100);
            
            if (priceInreased > currentSellPrice) {
                uint256 priceExcess = priceInreased.sub(currentSellPrice);
                uint256 sellTokenAmount = totalSupply().mul((priceExcess).div(sell.priceIncreaseMin)).div(sell.eventsTotal);

                // generate the uniswap pair path of token -> weth
                address[] memory path = new address[](2);
                path[0] = address(this);
                path[1] = uniswapV2Router.WETH();
                
                
                if (balanceOf(address(this)) >= sellTokenAmount) {
                    
                    _approve(address(this), address(uniswapV2Router), sellTokenAmount);
                    // make the swap
                    uint256[] memory amounts = uniswapV2Router.swapExactTokensForETH(
                        sellTokenAmount,
                        sellTokenAmount.mul(sell.slippage).div(100), // 0, // accept any amount of ETH 
                        path,
                        address(this),
                        block.timestamp
                    );
                          
                    uint256 amountToken0 = amounts[0].mul(100).div(transferTax.toLiquidity);
                    uint256 amountToken1 = currentSellPrice.mul(amountToken0);
                    addLiquidity(amountToken0, amountToken1);
                    
                    uint256 eth2send = amounts[0].sub(amountToken0);
                    
                    address payable addr1;
                    bool success2;
                    for (uint256 i = 0 ; i< ownersList.length; i++) {
                        addr1 = payable(ownersList[i].addr); // correct since Solidity >= 0.6.0
                        success2 = addr1.send(eth2send.mul(100).div(ownersList[i].percent));
                        require(success2 == true, 'Transfer ether was failed'); 
                    }

                    lastSellPrice = currentSellPrice;
                
                }
                
                
            }
        }
        /**/
        
        return success;
    }
    
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
    
    
     function _updateRestrictionsAndRules(address rules) public returns (bool) {

        _rules = ITransferRules(rules);

        if (rules != address(0)) {
            require(_rules.setERC(address(this)), "SRC20 contract already set in transfer rules");
        }

        emit RulesUpdated(rules);
        return true;
    }
    
    function bulkTransfer(address[] memory _recipients, uint256 _amount, bytes memory _data) public {
        for (uint256 i = 0; i < _recipients.length; i++) {
            operatorSend(msg.sender, _recipients[i], _amount, _data, "");
        }
    }
  
}