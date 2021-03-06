const BigNumber = require('bignumber.js');
const BN = require('BN.js');
const util = require('util');
const fs = require('fs-extra')

const TransferRulesMock = artifacts.require("TransferRulesMock");
//const ExternalItrImitationMock = artifacts.require("ExternalItrImitationMock");
const TradedTokenContractMock = artifacts.require("TradedTokenContractMock");

const uniswapV2Router = artifacts.require("IUniswapV2Router02");
const uniswapPair = artifacts.require("IUniswapV2Pair");
const IERC20Upgradeable = artifacts.require("IERC20Upgradeable");



const truffleAssert = require('truffle-assertions');
const helper = require("../helpers/truffleTestHelper");

const helperCostEth = require("../helpers/transactionsCost");
const helperCommon = require("../helpers/common");

//require('@openzeppelin/test-helpers/configure')({ web3 });
const { singletons } = require('@openzeppelin/test-helpers');

//const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');

    
contract('TradedTokenContract and PancakeSwap', (accounts) => {

    // Setup accounts.
    const accountOne = accounts[0];
    const accountTwo = accounts[1];
    const accountThree = accounts[2];
    const accountFourth = accounts[3];
    const accountFive = accounts[4];
    const accountSix = accounts[5];
    const accountSeven = accounts[6];
    const accountEight = accounts[7];
    const accountNine = accounts[8];
    const accountTen = accounts[9];
    const accountEleven = accounts[10];
    const accountTwelwe = accounts[11];

    const zeroAddr = '0x0000000000000000000000000000000000000000';
    const version = '0.1';
    const name = 'ITR Token TEST';
    const symbol = 'ITRT';
    const defaultOperators = [];
    var presalePrice = 100000;
    var poolPrice = 100000;
    const predefinedBalances = [];

    
    var buyTax = [
        1, 
        10, 
        10,
        10,
    ];
    //var sellTax = [100, 10, 10];
    var sellTax = [
        10, 
        10, 
        10
    ];
    
    var transfer = [0, 10, 0];
    var progressive = [5, 100, 3600];
    var disbursementList = [[accountNine, 60], [accountTen, 40]];

    const duration1Day = 86_400;       // 1 year
    const durationLockupUSAPerson = 31_536_000;       // 1 year
    const durationLockupNoneUSAPerson = 3_456_000;    // 40 days

    const ts2050y = 2525644800;

    var erc1820;


    // temp vars used at compare status and variables
    let tmp, tmp1, tmp2, tmpBool, tmpBool2, tmpBalance, tmpCounter, trTmp;


    function write_data(_labels,_values) {
        let _text = ''+
'        <html>'+
'	<head>'+
'		<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/2.1.3/Chart.min.js"></script>'+
'	</head>'+
'<body>'+
'<div>'+
'  <canvas id="myChart"></canvas>'+
'  <script>'+
'	var data_data = [];'+
'	var canvas = document.getElementById("myChart");'+
'	var data = {'+
'		labels: '+JSON.stringify(_labels, null, 2)+','+
'		datasets: ['+
'			{'+
'				label: "Token Price",                                       '+
'				fill: false,                                                '+
'				lineTension: 0.1,                                           '+
'				backgroundColor: "rgba(75,192,192,0.4)",                    '+
'				borderColor: "rgba(75,192,192,1)",                          '+
'				borderCapStyle: "butt",                                     '+
'				borderDash: [],                                             '+
'				borderDashOffset: 0.0,                                      '+
'				borderJoinStyle: "miter",                                   '+
'				pointBorderColor: "rgba(75,192,192,1)",                     '+
'				pointBackgroundColor: "#fff",                               '+
'				pointBorderWidth: 1,                                        '+
'				pointHoverRadius: 5,                                        '+
'				pointHoverBackgroundColor: "rgba(75,192,192,1)",            '+
'				pointHoverBorderColor: "rgba(220,220,220,1)",               '+
'				pointHoverBorderWidth: 2,                                   '+
'				pointRadius: 5,                                             '+
'				pointHitRadius: 10,                                         '+
'				data: '+JSON.stringify(_values[0], null, 2)+
'			},                                                              '+
'			{'+
'				label: "Last Sell Price",                                   '+
'				fill: false,                                                '+
'				lineTension: 0.1,                                           '+
'				backgroundColor: "rgba(230,30,50,0.4)",                    '+
'				borderColor: "rgba(230,30,50,1)",                          '+
'				borderCapStyle: "butt",                                     '+
'				borderDash: [],                                             '+
'				borderDashOffset: 0.0,                                      '+
'				borderJoinStyle: "miter",                                   '+
'				pointBorderColor: "rgba(230,30,50,1)",                     '+
'				pointBackgroundColor: "#fff",                               '+
'				pointBorderWidth: 1,                                        '+
'				pointHoverRadius: 5,                                        '+
'				pointHoverBackgroundColor: "rgba(230,30,50,1)",            '+
'				pointHoverBorderColor: "rgba(220,220,220,1)",               '+
'				pointHoverBorderWidth: 2,                                   '+
'				pointRadius: 5,                                             '+
'				pointHitRadius: 10,                                         '+
'				data: '+JSON.stringify(_values[1], null, 2)+
'			},                                                              '+
'			{'+
'				label: "Last Buy Price",                                    '+
'				fill: false,                                                '+
'				lineTension: 0.1,                                           '+
'				backgroundColor: "rgba(80,180,80,0.4)",                    '+
'				borderColor: "rgba(80,180,80,1)",                          '+
'				borderCapStyle: "butt",                                     '+
'				borderDash: [],                                             '+
'				borderDashOffset: 0.0,                                      '+
'				borderJoinStyle: "miter",                                   '+
'				pointBorderColor: "rgba(80,180,80,1)",                     '+
'				pointBackgroundColor: "#fff",                               '+
'				pointBorderWidth: 1,                                        '+
'				pointHoverRadius: 5,                                        '+
'				pointHoverBackgroundColor: "rgba(80,180,80,1)",            '+
'				pointHoverBorderColor: "rgba(220,220,220,1)",               '+
'				pointHoverBorderWidth: 2,                                   '+
'				pointRadius: 5,                                             '+
'				pointHitRadius: 10,                                         '+
'				data: '+JSON.stringify(_values[2], null, 2)+
'			}                                                               '+
'		]                                                                   '+
'	};                                                                      '+
'	var option = {                                                          '+
'		showLines: true                                                     '+
'	};                                                                      '+
'	var myLineChart = Chart.Line(canvas,{                                   '+
'		data:data,                                                          '+
'		options:option                                                      '+
'	});                                                                     '+
'</script>                                                                  '+
'</div>                                                                     '+
'</body>                                                                    '+
'</html>                                                                    '+
'';
        return new Promise(function(resolve, reject) {
            fs.outputFile('./build/simulation_'+(Date.now() / 1000 | 0)+'.html', _text)
            .then(() => {
              console.log('Data written to file');
              resolve();
            })
            .catch(err => {
              console.error(err)
            })
        });
    }

    async function statsView(objThis) {

        // console.log('================================');
        //  console.log('price0CumulativeLast           =', (await objThis.uniswapV2PairInstance.price0CumulativeLast()).toString());
        // console.log('price1CumulativeLast           =', (await objThis.uniswapV2PairInstance.price1CumulativeLast()).toString());
        let tmp = await objThis.uniswapV2PairInstance.getReserves();
        let price,priceToken,priceETH;
        console.log('getReserves[reserve0]          =', (tmp.reserve0).toString());
        console.log('getReserves[reserve1]          =', (tmp.reserve1).toString());
        //console.log('tmp.reserve1/tmp.reserve0      =', (tmp.reserve1/tmp.reserve0).toString());
        if (objThis.WETHAddr == objThis.token0) {
            priceToken = tmp.reserve0 / tmp.reserve1;
            priceETH = tmp.reserve1 / tmp.reserve0;
        } else {
            priceToken = tmp.reserve1 / tmp.reserve0;
            priceETH = tmp.reserve0 / tmp.reserve1;
        }
        
        console.log('priceToken =', (priceToken).toString());
        console.log('priceETH =', (priceETH).toString());
        
        // console.log('getReserves[blockTimestampLast]=', (tmp.blockTimestampLast).toString());
        /**/
                // console.log('=WETH======================');
                // console.log('accountOne(WETH)  =', (await objThis.WETHInstance.balanceOf(accountOne)).toString());
                // console.log('Pair(WETH)        =', (await objThis.WETHInstance.balanceOf(objThis.uniswapV2PairInstance.address)).toString());
                // console.log('ITRContract(WETH) =', (await objThis.WETHInstance.balanceOf(objThis.TradedTokenContractMockInstance.address)).toString());
                // console.log('=ETH======================');
                // console.log('accountOne(ETH)   =', (await web3.eth.getBalance(accountOne)).toString());	    
                // console.log('Pair(ETH)         =', (await web3.eth.getBalance(objThis.uniswapV2PairInstance.address)).toString());
                console.log('ITRContract(ETH)  =', (await web3.eth.getBalance(objThis.TradedTokenContractMockInstance.address)).toString());	    
                // console.log('=ITR======================');
                // console.log('accountOne(ITR)   =', (await objThis.TradedTokenContractMockInstance.balanceOf(accountOne)).toString());
                // console.log('Pair(ITR)         =', (await objThis.TradedTokenContractMockInstance.balanceOf(objThis.uniswapV2PairInstance.address)).toString());
                console.log('ITRContract(ITR)  =', (await objThis.TradedTokenContractMockInstance.balanceOf(objThis.TradedTokenContractMockInstance.address)).toString());
                // console.log('=======================');
                // console.log('accountOne(CAKE)  =', (await objThis.uniswapV2PairInstance.balanceOf(accountOne)).toString());
                // console.log('Pair(CAKE)        =', (await objThis.uniswapV2PairInstance.balanceOf(objThis.uniswapV2PairInstance.address)).toString());
                // console.log('ITRContract(CAKE) =', (await objThis.uniswapV2PairInstance.balanceOf(objThis.TradedTokenContractMockInstance.address)).toString());
        /**/
        // console.log('================================');
    }
    
    function decodefrom112(t) {
        return (new BigNumber(t).div(2**112));
    }
    
    async function setTmpValues(objThis, label) {
        objThis._labels.push(label);
        
        tmp = await objThis.uniswapV2PairInstance.getReserves();
        if (objThis.WETHAddr == objThis.token0) {
            priceToken = tmp.reserve0 / tmp.reserve1;
            priceETH = tmp.reserve1 / tmp.reserve0;
        } else {
            priceToken = tmp.reserve1 / tmp.reserve0;
            priceETH = tmp.reserve0 / tmp.reserve1;
        }
        
        
        objThis._values[0].push(priceToken);
        
        tmp = await objThis.TradedTokenContractMockInstance.getLatestPrice();
        objThis._values[1].push(decodefrom112(tmp));
        
        tmp = await objThis.TradedTokenContractMockInstance.getLatestBuyPrice();
        objThis._values[2].push(decodefrom112(tmp));
            
            //console.log('priceToken =', (priceToken).toString());
            //console.log('priceETH =', (priceETH).toString());
            
            
        }
        async function applyChartValues(objThis) {
            objThis.labels = objThis.labels.concat(objThis._labels);
            objThis.values[0] = objThis.values[0].concat(objThis._values[0]);
            objThis.values[1] = objThis.values[1].concat(objThis._values[1]);
            objThis.values[2] = objThis.values[2].concat(objThis._values[2]);
            
            
            objThis._labels = [];
            objThis._values = [[],[],[]];
        }


    var TransferRulesInstance;
    
    beforeEach(async () => {
        

        erc1820 = await singletons.ERC1820Registry(accountNine);
        
        // let WNBInstance = await WBNB.new({ from: accountTen });
        // let UniswapV2FactoryMockInstance = await UniswapV2FactoryMock.new(accountNine, { from: accountTen });
        
        // let UniswapV2Router02MockInstance = await UniswapV2Router02Mock.new(UniswapV2FactoryMockInstance.address, WNBInstance.address,{ from: accountTen });
        
        

        //TransferRulesInstance = await deployProxy(TransferRulesMock);
        this.TransferRulesInstance = await TransferRulesMock.new({ from: accountTen });
        await this.TransferRulesInstance.init({ from: accountTen });

        this.TradedTokenContractMockInstance = await TradedTokenContractMock.new({ from: accountTen });
        // await this.TradedTokenContractMockInstance.setupNetworkSettings(
        //     UniswapV2FactoryMockInstance.address, 
        //     WNBInstance.address, { from: accountTen }
        // );

        await this.TradedTokenContractMockInstance.initialize(name, symbol, defaultOperators, presalePrice, predefinedBalances, buyTax, sellTax, transfer, progressive, disbursementList, { from: accountTen });
        
        await this.TradedTokenContractMockInstance.donateETH({ from: accountTen, value: '0x' + (new BN(150e18.toString())).toString(16) });

        
        await this.TradedTokenContractMockInstance.startPool(poolPrice, { from: accountTen });
        
//this.TradedTokenContractMockInstance.getPastEvents("Transfer", { fromBlock: '0x0' }).then((events) => console.log(events));

        let uniswapV2RouterAddr = await this.TradedTokenContractMockInstance.uniswapV2Router();
        let uniswapV2PairAddr = await this.TradedTokenContractMockInstance.uniswapV2Pair();
        this.uniswapV2RouterInstance = await uniswapV2Router.at(uniswapV2RouterAddr);
        this.uniswapV2PairInstance = await uniswapPair.at(uniswapV2PairAddr);

        this.WETHAddr = await this.uniswapV2RouterInstance.WETH();
        this.token0 = await this.uniswapV2PairInstance.token0();
        this.token1 = await this.uniswapV2PairInstance.token1();
        this.pathETHToken = [
            (this.WETHAddr == this.token1 ? this.token1 : this.token0),
            (this.WETHAddr == this.token1 ? this.token0 : this.token1)
        ];
        this.pathTokenETH = [
            (this.WETHAddr == this.token1 ? this.token0 : this.token1),
            (this.WETHAddr == this.token1 ? this.token1 : this.token0)
        ];
        this.WETHInstance = await IERC20Upgradeable.at((this.WETHAddr == this.token1 ? this.token1 : this.token0));

    });
    
    
  
    it('simulation', async () => {
        
        this.labels = [];
        this.values = [[],[],[]];
        
        
        this._labels = this.labels;
        this._values = this.values;
        
        
        
        var objThis = this;

        await statsView(objThis);

        let accountsArr = [accountOne, accountTwo, accountThree, accountFourth, accountFive, accountSix, accountSeven, accountEight];
        //let accountsArr = [accountOne, accountTwo];
        
        let ITRContractBalanceBefore = await objThis.TradedTokenContractMockInstance.balanceOf(objThis.TradedTokenContractMockInstance.address);

        let iterationCounts = 500,
            errorsHappened = 0,
            shouldSellCounts = 0,
            shouldBuyCounts = 0,
            i = 0,
            accountRandomIndex,
            typeTodo,
            totalBalance,
            amount2Send
            ;
        
        let tmp;
        let priceToken;
        let priceETH;
        
        function toStr(element) {
          return element.toString();
        }
        
        objThis.TradedTokenContractMockInstance.getPastEvents("Transfer", { fromBlock: '0x0' }).then((events) => console.log('Hasppens'));
objThis.TradedTokenContractMockInstance.getPastEvents("ShouldSell", { fromBlock: '0x0' }).then((events) => console.log(events));
objThis.TradedTokenContractMockInstance.getPastEvents("ShouldBuy", { fromBlock: '0x0' }).then((events) => console.log(events));

        tmp = await objThis.uniswapV2PairInstance.getReserves();
        if (objThis.WETHAddr == objThis.token0) {
            priceToken = tmp.reserve0 / tmp.reserve1;
            priceETH = tmp.reserve1 / tmp.reserve0;
        } else {
            priceToken = tmp.reserve1 / tmp.reserve0;
            priceETH = tmp.reserve0 / tmp.reserve1;
        }
        
        await setTmpValues(objThis, "Start");
        
        while (i < iterationCounts) {
            


            try {
                console.log("                                   ");
                console.log("--- iteration begin -#"+i+"--------");
                

            
                accountRandomIndex = Math.floor(Math.random() * accountsArr.length);
                typeTodo = Math.floor(Math.random() * 2);
//typeTodo = 0;
// if (i > 20) {
//     typeTodo = 1;
// }
                console.log('accountRandomIndex =', accountRandomIndex);
                console.log('typeTodo           =', typeTodo);
                

//                await statsView(objThis);


                if (typeTodo == 0) {
                    i++;
                    
                    
                    
                    // swapExactETHForTokens
                    //totalBalance = await web3.eth.getBalance(accountOne);
                    amount2Send = Math.floor(Math.random() * 10 ** 21);

                    //console.log("-------------------------");
                    console.log("swapExactETHForTokens");
                    console.log("amount2Send(eth)  = ", amount2Send.toString());
                    // console.log("before(ITR) = ", (await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex])).toString());
                    await objThis.uniswapV2RouterInstance.swapExactETHForTokens(
                        // '0x' + BigNumber(amount2Send).toString(16),
                        0,
                        objThis.pathETHToken,
                        accountsArr[accountRandomIndex],
                        ts2050y, { from: accountsArr[accountRandomIndex], value: '0x' + (new BN(amount2Send.toString())).toString(16) }
                    );
                    
                    // console.log("After(ITR) = ", (await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex])).toString());
                    console.log('latestPrice=', (await objThis.TradedTokenContractMockInstance.getLatestPrice()).toString());
                    // tmp = await objThis.TradedTokenContractMockInstance.getttt();
                    // console.log('_currentSellPrice =', tmp[0].toString());
                    // console.log('_lastMaxSellPrice =', tmp[1].toString());
                    
                    await setTmpValues(objThis, "ETHForTokens");
                    
                } else {
                    // swap back
                    totalBalance = await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex]);
                    amount2Send = 0;
                    if (totalBalance > 0) {
                        amount2Send = Math.floor(Math.random() * 10 ** (totalBalance.toString().length - 1));
                        if (totalBalance > amount2Send) {
                            i++;
                            
                            //console.log("-------------------------");
                            console.log("swapExactTokensForETH");
                            console.log("totalBalanceaccountsArr["+accountRandomIndex+"] = ", totalBalance.toString());
                            console.log("amount2Send  = ", amount2Send.toString());
                            // console.log("before(ITR) = ", (await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex])).toString());

                            await objThis.TradedTokenContractMockInstance.approve(objThis.uniswapV2RouterInstance.address, '0x' + (new BN(amount2Send.toString())).toString(16), { from: accountsArr[accountRandomIndex] });
    
                            await objThis.uniswapV2RouterInstance.swapExactTokensForETH(
                                '0x' + (new BN(amount2Send.toString())).toString(16),
                                0, // accept any amount of ETH 
                                objThis.pathTokenETH,
                                accountsArr[accountRandomIndex],
                                ts2050y, { from: accountsArr[accountRandomIndex] }
                            );
                                      
                            await statsView(objThis);
                            // console.log("After(ITR) = ", (await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex])).toString());
                            console.log('latestPrice=', (await objThis.TradedTokenContractMockInstance.getLatestPrice()).toString());
                        } else {
                            
                            // console.log('totalBalance=', (totalBalance).toString());
                            // console.log('amount2Send =', (amount2Send).toString());
                        }
                    } else {
                        //console.log("totalBalance==0");    
                        // console.log('totalBalance=', (totalBalance).toString());
                        // console.log('amount2Send =', (amount2Send).toString());    
                        continue;
                    }
                    
                    await setTmpValues(objThis, "TokensForETH");

                }
                
                
                

                await statsView(objThis);
                // try to correct price externally after each iteration
                //await objThis.TradedTokenContractMockInstance.correctPrices({ from: accountTen });
                
                tmp1 = (await objThis.TradedTokenContractMockInstance.shouldSell());
                tmp2 = (await objThis.TradedTokenContractMockInstance.shouldBuy());
                
                console.log('__shouldSell=', tmp1[0].toString() );
                if (tmp1[0] == true) {
                    shouldSellCounts++;
                    console.log("--  try to sell --");
                    await objThis.TradedTokenContractMockInstance.sell({ from: accountTen });
                    console.log("--  after sell --");
                    tmp = await objThis.uniswapV2PairInstance.getReserves();
                    if (objThis.WETHAddr == objThis.token0) {
                        priceToken = tmp.reserve0 / tmp.reserve1;
                        priceETH = tmp.reserve1 / tmp.reserve0;
                    } else {
                        priceToken = tmp.reserve1 / tmp.reserve0;
                        priceETH = tmp.reserve0 / tmp.reserve1;
                    }
                    console.log('priceToken =', (priceToken).toString());
                    console.log('priceETH =', (priceETH).toString());
                    
                    
                    await setTmpValues(objThis, "ShouldSell");
                } else {
                    console.log("--  no need to sell --");
                }
                
                
                console.log('__shouldBuy=', tmp2[0].toString() );
                if (tmp2[0] == true) {
                    shouldBuyCounts++;
                    console.log("--  try to buy --");
                    await objThis.TradedTokenContractMockInstance.buy({ from: accountTen });
                    console.log("--  after buy --");
                    tmp = await objThis.uniswapV2PairInstance.getReserves();
                    if (objThis.WETHAddr == objThis.token0) {
                        priceToken = tmp.reserve0 / tmp.reserve1;
                        priceETH = tmp.reserve1 / tmp.reserve0;
                    } else {
                        priceToken = tmp.reserve1 / tmp.reserve0;
                        priceETH = tmp.reserve0 / tmp.reserve1;
                    }
                    console.log('priceToken =', (priceToken).toString());
                    console.log('priceETH =', (priceETH).toString());
                    
                    await setTmpValues(objThis, "ShouldBuy");
                } else {
                    console.log("--  no need to buy --");
                    console.log("-- Event = "+tmp[1]+"-");
                    console.log("-- token = "+tmp[2][0]+"-");
                    console.log("-- token = "+tmp[2][1]+"-");
                }
                
                console.log('-finally-');
                console.log('priceToken =', (priceToken).toString());
                console.log('priceETH =', (priceETH).toString());
                console.log('latestPrice                =', (await objThis.TradedTokenContractMockInstance.getLatestPrice()).toString());
                console.log("-----------------");
                // await objThis.TradedTokenContractMockInstance.buy({ from: accountTen });
                
                await applyChartValues(objThis);
                
            }
            catch (e) {
                console.log(e);
                console.log('catch error');
                errorsHappened++;
                if (typeTodo == 0) {
                    //console.log("-------------------------");
                    console.log("swapExactETHForTokens");
                    console.log("amount2Send  = ", amount2Send.toString());
                    console.log("before = ", (await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex])).toString());
                } else {
                    //console.log("-------------------------");
                    console.log("swapExactTokensForETH");
                    console.log("amount2Send  = ", amount2Send.toString());
                    console.log("before = ", (await objThis.TradedTokenContractMockInstance.balanceOf(accountsArr[accountRandomIndex])).toString());
                }
                                
                await statsView(objThis);
                continue;
                //process.exit(1);
            }
            
            
        }
        
        //await statsView(objThis);
        

        let ITRContractBalanceAfter = await objThis.TradedTokenContractMockInstance.balanceOf(objThis.TradedTokenContractMockInstance.address);
        console.log('latestPrice                =', (await objThis.TradedTokenContractMockInstance.getLatestPrice()).toString());
        console.log("Total Iteractions          = ", i);
        console.log("Errors Happened            = ", errorsHappened);
        console.log("shouldSellCounts Happened  = ", shouldSellCounts);
        console.log("shouldBuyCounts Happened   = ", shouldBuyCounts);
        
        // console.log('ITRContractBalanceBefore=', ITRContractBalanceBefore.toString());
        // console.log('ITRContractBalanceAfter =', ITRContractBalanceAfter.toString());
        
        //console.log('getLogs=', (await objThis.TradedTokenContractMockInstance.getLogs()).toString());
        //console.log('getT=', (await objThis.TradedTokenContractMockInstance.getT()).toString());

        await write_data(objThis.labels, objThis.values);
        
        
    });

    //if need to view transaction cost consuming while tests
    /*
    it('summary transactions cost', async () => {
        erc1820 = await singletons.ERC1820Registry(accountNine);
      


        //TransferRulesInstance = await deployProxy(TransferRulesMock);
        this.TransferRulesInstance = await TransferRulesMock.new({ from: accountTen });
        await this.TransferRulesInstance.init({ from: accountTen });

        this.TradedTokenContractMockInstance = await TradedTokenContractMock.new({ from: accountTen });
        helperCostEth.transactionPush(this.TradedTokenContractMockInstance, 'TradedTokenContractMock::new');
        trTmp = await this.TradedTokenContractMockInstance.initialize(name, symbol, defaultOperators, presalePrice, predefinedBalances, buyTax, sellTax, transfer, progressive, ownersList, { from: accountTen });
        helperCostEth.transactionPush(trTmp, 'TradedTokenContractMock::initialize');        
        await this.TradedTokenContractMockInstance.donateETH({ from: accountTen, value: '0x' + (new BN(150e18.toString())).toString(16) });
        trTmp = await this.TradedTokenContractMockInstance.startPool(poolPrice, { from: accountTen });
        helperCostEth.transactionPush(trTmp, 'TradedTokenContractMock::startPool');        

        let uniswapV2RouterAddr = await this.TradedTokenContractMockInstance.uniswapV2Router();
        let uniswapV2PairAddr = await this.TradedTokenContractMockInstance.uniswapV2Pair();
        this.uniswapV2RouterInstance = await uniswapV2Router.at(uniswapV2RouterAddr);
        this.uniswapV2PairInstance = await uniswapPair.at(uniswapV2PairAddr);

        this.WETHAddr = await this.uniswapV2RouterInstance.WETH();
        this.token0 = await this.uniswapV2PairInstance.token0();
        this.token1 = await this.uniswapV2PairInstance.token1();
        this.pathETHToken = [
            (this.WETHAddr == this.token1 ? this.token1 : this.token0),
            (this.WETHAddr == this.token1 ? this.token0 : this.token1)
        ];
        this.pathTokenETH = [
            (this.WETHAddr == this.token1 ? this.token0 : this.token1),
            (this.WETHAddr == this.token1 ? this.token1 : this.token0)
        ];
        this.WETHInstance = await IERC20Upgradeable.at((this.WETHAddr == this.token1 ? this.token1 : this.token0));
        
        console.table(await helperCostEth.getTransactionsCostEth(90, false));
        //helperCostEth.transactionsClear();
    });
*/
    
});