// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/console.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2Router02.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    UNISWAP_V2_ROUTER02,
    SUSHISWAP_V2_ROUTER02,
    PANCAKESWAP_V2_ROUTER02,
    FRAXSWAP_V2_ROUTER02
} from "test/utils/constant_eth.sol";
import {AutoPump, IAutoPump} from "../src/AutoPump.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AutoPumpTest is Test {
    struct Fees {
        uint256 burnFee;
        uint256 pumpFee;
        uint256 liquifyFee;
    }

    uint256 mainnetFork;
    uint256 totalSupply = 1_000_000 ether;
    uint256 burnFee = 5;
    uint256 liqFee = 2;
    uint256 pumpFee = 3;
    IAutoPump.Fees fees = IAutoPump.Fees(burnFee, pumpFee, liqFee);
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    address owner;
    address dev;
    address buyer;
    address seller;
    address uniswapV2Pair;
    address uniswapV2Pair2;

    AutoPump token;
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Router02 public uniswapV2Router2;

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        owner = makeAddr("owner");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        vm.deal(owner, 200_000 ether);

        vm.prank(owner);
        token = new AutoPump("AutoPump", "PEPUMP", totalSupply, fees, UNISWAP_V2_ROUTER02, SUSHISWAP_V2_ROUTER02);
        uniswapV2Router = IUniswapV2Router02(UNISWAP_V2_ROUTER02);
        uniswapV2Pair = token.uniswapV2Pair();
        uniswapV2Router2 = IUniswapV2Router02(SUSHISWAP_V2_ROUTER02);
        uniswapV2Pair2 = token.uniswapV2Pair2();

        vm.startPrank(owner);
        token.setPumpThreshold(1 ether);
        token.setLiquifyThreshold(totalSupply / 2);
        token.approve(UNISWAP_V2_ROUTER02, type(uint256).max);
        token.approve(SUSHISWAP_V2_ROUTER02, type(uint256).max);
        uniswapV2Router.addLiquidityETH{value: 1 ether}(address(token), totalSupply / 4, 0, 0, owner, block.timestamp);
        uniswapV2Router2.addLiquidityETH{value: 1 ether}(address(token), totalSupply / 4, 0, 0, owner, block.timestamp);
        vm.stopPrank();
    }

    function testSetRouter() public {
        address oldPair = token.uniswapV2Pair();
        vm.prank(owner);
        token.setRouterAddress(PANCAKESWAP_V2_ROUTER02);

        assert(address(token.uniswapV2Pair()) != oldPair);
        assert(address(token.uniswapV2Router()) != UNISWAP_V2_ROUTER02);
        assertEq(address(token.uniswapV2Router()), PANCAKESWAP_V2_ROUTER02);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setRouterAddress(SUSHISWAP_V2_ROUTER02);

        address oldPair2 = token.uniswapV2Pair2();
        vm.prank(owner);
        token.setRouterAddress2(FRAXSWAP_V2_ROUTER02);

        assert(address(token.uniswapV2Pair2()) != oldPair2);
        assert(address(token.uniswapV2Router2()) != SUSHISWAP_V2_ROUTER02);
        assertEq(address(token.uniswapV2Router2()), FRAXSWAP_V2_ROUTER02);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setRouterAddress2(SUSHISWAP_V2_ROUTER02);
    }

    function testSetFees() public {
        IAutoPump.Fees memory fee = IAutoPump.Fees(2, 3, 4);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setFees(fee);

        vm.prank(owner);
        token.setFees(fee);

        (uint256 _burnFee, uint256 _pumpFee, uint256 _liquifyFee) = token.fees();

        assertEq(_burnFee, 2);
        assertEq(_pumpFee, 3);
        assertEq(_liquifyFee, 4);
    }

    function testSetThreshold() public {
        vm.prank(owner);
        token.setPumpThreshold(2 ether);
        vm.prank(owner);
        token.setLiquifyThreshold(2 ether);

        assertEq(token.pumpEthThreshold(), 2 ether);
        assertEq(token.liquifyTokenThreshold(), 2 ether);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setPumpThreshold(1 ether);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setLiquifyThreshold(1 ether);
    }

    function testSetEnable() public {
        vm.prank(owner);
        token.setExcludeFromFee(owner, false);
        vm.prank(owner);
        token.setSwapAndLiquifyEnabled(false);

        assertEq(token.isExcludedFromFee(owner), false);
        assertEq(token.swapAndLiquifyEnabled(), false);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setExcludeFromFee(buyer, true);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        token.setSwapAndLiquifyEnabled(true);
    }

    function testBuy() public {
        vm.deal(buyer, 100 ether);
        uint256 ethBalBefore = buyer.balance;
        uint256 tokenBalBefore = token.balanceOf(buyer);
        swapEthForTokens(buyer, 5e17);
        uint256 ethBalAfter = buyer.balance;
        uint256 tokenBalAfter = token.balanceOf(buyer);

        assert(tokenBalAfter > tokenBalBefore);
        assertEq(ethBalBefore - ethBalAfter, 5e17);
        assertEq(address(token).balance, 0); //no pump eth for swap
    }

    function testSell() public {
        vm.prank(owner);
        uint256 amountToSell = 4000e18;
        token.transfer(buyer, amountToSell);
        vm.prank(buyer);

        uint256 ethBalBefore = buyer.balance;
        uint256 buyerBalBefore = token.balanceOf(buyer);
        uint256 tokenBalBefore = token.balanceOf(address(token));
        uint256 totlaSupplyBefore = token.totalSupply();
        swapTokensForEth(buyer, amountToSell);
        uint256 ethBalAfter = buyer.balance;
        uint256 buyerBalAfter = token.balanceOf(buyer);
        uint256 tokenBalAfter = token.balanceOf(address(token));
        uint256 totlaSupplyAfter = token.totalSupply();

        uint256 expectedLiquifyFee = amountToSell * liqFee / 100;
        uint256 expectedBurnFee = amountToSell * burnFee / 100;

        assert(ethBalAfter > ethBalBefore);
        assertEq(buyerBalBefore - buyerBalAfter, amountToSell);
        assertEq(tokenBalAfter - tokenBalBefore, expectedLiquifyFee);
        assertEq(totlaSupplyBefore - totlaSupplyAfter, expectedBurnFee);
        assertEq(address(token).balance, 0); //no pump eth for swap
    }

    function testTransfer() public {
        vm.prank(owner);
        token.transfer(buyer, 352e15);

        uint256 ethBalBefore = address(token).balance;
        uint256 buyerBalBefore = token.balanceOf(buyer);
        uint256 sellerBalBefore = token.balanceOf(seller);
        address pair = getPair();
        uint256 totalSupplyBefore = token.totalSupply();
        uint256 pairTokenBefore = token.balanceOf(pair);
        vm.prank(buyer);
        token.transfer(seller, 352e15);
        uint256 ethBalAfter = address(token).balance;
        uint256 buyerBalAfter = token.balanceOf(buyer);
        uint256 sellerBalAfter = token.balanceOf(seller);
        uint256 totalSupplyAfter = token.totalSupply();
        uint256 pairTokenAfter = token.balanceOf(pair);

        uint256 amountToTransfer = 352e15;

        assertEq(buyerBalBefore - buyerBalAfter, amountToTransfer);
        assertEq(ethBalBefore, 0);
        assert(ethBalAfter > ethBalBefore);

        uint256 expectedBurnFee = amountToTransfer * burnFee / 100;

        assertEq(totalSupplyBefore - totalSupplyAfter, expectedBurnFee);

        uint256 expectedLiquifyFee = amountToTransfer * liqFee / 100;
        uint256 expectedPumpFee = amountToTransfer * pumpFee / 100;
        uint256 totalFee = expectedPumpFee + expectedBurnFee + expectedLiquifyFee;

        assertEq(sellerBalAfter - sellerBalBefore, amountToTransfer - totalFee);
        assertEq(token.balanceOf(address(token)), expectedLiquifyFee);
        assertEq(pairTokenAfter - pairTokenBefore, expectedPumpFee);
    }

    function testLiquify() public {

        address pair = getPair();
        console.log(block.timestamp % 2);
        _testLiquify(pair);
        skip(1);
        pair = getPair();
        console.log(block.timestamp % 2);
        _testLiquify(pair);
    }

    function testPump() public {
        vm.startPrank(owner);
        token.transfer(buyer, 5_000 ether);
        vm.deal(address(token), 11e17);
        vm.stopPrank();

        address pair = getPair();

        uint256 beforePumpBal = address(token).balance;
        uint256 beforePumpBal2 = IERC20(address(uniswapV2Router.WETH())).balanceOf(pair);
        uint256 beforePumpBal3 = token.balanceOf(pair);
        uint256 beforeTotalSupply = token.totalSupply();
        vm.prank(buyer);
        token.transfer(seller, 100 ether);
        uint256 afterPumpBal = address(token).balance;
        uint256 afterPumpBal2 = IERC20(address(uniswapV2Router.WETH())).balanceOf(pair);
        uint256 afterPumpBal3 = token.balanceOf(pair);
        uint256 afterTotalSupply = token.totalSupply();

        assert(beforePumpBal > afterPumpBal);
        assert(afterPumpBal2 > beforePumpBal2);
        assertApproxEqRel(beforeTotalSupply - afterTotalSupply, beforePumpBal3 - afterPumpBal3, 0.1e15);
    }

    function swapEthForTokens(address account, uint256 ethAmount) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(token);
        vm.prank(account);
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, path, account, block.timestamp
        );
    }

    function swapTokensForEth(address account, uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = uniswapV2Router.WETH();
        vm.prank(account);
        token.approve(UNISWAP_V2_ROUTER02, tokenAmount);
        vm.prank(account);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            account,
            block.timestamp
        );
    }

    function _testLiquify(address pair) private {
        vm.startPrank(owner);
        token.transfer(address(token), 5_001 ether);
        token.transfer(buyer, 100 ether);
        token.setLiquifyThreshold(5_000 ether);
        vm.stopPrank();

        uint256 beforeLiquifyBal = token.balanceOf(address(token));
        uint256 beforeLiquifyBal2 = token.balanceOf(pair);
        vm.prank(buyer);
        token.transfer(seller, 50 ether);
        uint256 afterLiquifyBal = token.balanceOf(address(token));
        uint256 afterLiquifyBal2 = token.balanceOf(pair);
        
        assert(beforeLiquifyBal > afterLiquifyBal);
        assert(afterLiquifyBal2 > beforeLiquifyBal2);

        vm.prank(owner);
        token.setLiquifyThreshold(50_000 ether);
    }

    function getPair() private view returns(address) {
        return block.timestamp % 2 == 0 ? token.uniswapV2Pair() : token.uniswapV2Pair2();
    }
}
