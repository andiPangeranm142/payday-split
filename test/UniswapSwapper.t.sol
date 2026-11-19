// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { UniswapSwapper, IWETH9, ISwapRouter02, IQuoterV2 } from "../src/UniswapSwapper.sol";
import { IERC20 } from "../src/IERC20.sol";

contract MockUSDC is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to_, uint256 amount_) external {
        balanceOf[to_] += amount_;
    }

    function transfer(address to_, uint256 amount_) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount_, "insufficient");
        balanceOf[msg.sender] -= amount_;
        balanceOf[to_] += amount_;
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        require(allowance[from_][msg.sender] >= amount_, "no allowance");
        require(balanceOf[from_] >= amount_, "insufficient");
        allowance[from_][msg.sender] -= amount_;
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        return true;
    }

    function approve(address spender_, uint256 amount_) external override returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        return true;
    }
}

contract MockWETH is IWETH9 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount_) external override {
        require(balanceOf[msg.sender] >= amount_, "insufficient");
        balanceOf[msg.sender] -= amount_;
        payable(msg.sender).transfer(amount_);
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        require(allowance[from_][msg.sender] >= amount_, "no allowance");
        require(balanceOf[from_] >= amount_, "insufficient");
        allowance[from_][msg.sender] -= amount_;
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        return true;
    }

    function transfer(address to_, uint256 amount_) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount_, "insufficient");
        balanceOf[msg.sender] -= amount_;
        balanceOf[to_] += amount_;
        return true;
    }

    function approve(address spender_, uint256 amount_) external override returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        return true;
    }
}

/// @notice Router mock: pulls WETH from the caller, pays a fixed USDC amount,
///         and enforces amountOutMinimum exactly like the real router.
contract MockRouter is ISwapRouter02 {
    MockWETH public immutable weth;
    MockUSDC public immutable usdc;
    uint256 public fixedOut;
    uint256 public lastMinOut;
    uint256 public lastAmountIn;
    address public lastRecipient;

    constructor(MockWETH weth_, MockUSDC usdc_, uint256 fixedOut_) {
        weth = weth_;
        usdc = usdc_;
        fixedOut = fixedOut_;
    }

    function setFixedOut(uint256 out_) external {
        fixedOut = out_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256) {
        lastMinOut = params.amountOutMinimum;
        lastAmountIn = params.amountIn;
        lastRecipient = params.recipient;
        require(fixedOut >= params.amountOutMinimum, "Too little received");
        // Pull WETH from the caller (the swapper approved us).
        weth.transferFrom(msg.sender, address(this), params.amountIn);
        usdc.mint(params.recipient, fixedOut);
        return fixedOut;
    }
}

contract MockQuoter is IQuoterV2 {
    uint256 public quote;
    bool public shouldRevert;

    function setQuote(uint256 quote_) external {
        quote = quote_;
    }

    function setShouldRevert(bool flag_) external {
        shouldRevert = flag_;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory)
        external
        override
        returns (uint256, uint160, uint32, uint256)
    {
        require(!shouldRevert, "quoter down");
        return (quote, 0, 0, 0);
    }
}

contract UniswapSwapperTest is Test {
    MockUSDC usdc;
    MockWETH weth;
    MockRouter router;
    MockQuoter quoter;
    UniswapSwapper swapper;

    address user = address(0xBEEF);
    uint256 constant FEE = 3000;

    function setUp() public {
        usdc = new MockUSDC();
        weth = new MockWETH();
        // Fixed router output: 0.001 ETH -> 26.5 USDC (i.e. ~$26,500/ETH,
        // matching the Base Sepolia pool price at v2 launch).
        router = new MockRouter(weth, usdc, 26_500_000);
        quoter = new MockQuoter();
        quoter.setQuote(26_500_000);
        swapper = new UniswapSwapper(address(weth), address(usdc), address(router), address(quoter), uint24(FEE));
        vm.deal(address(this), 10 ether);
    }

    function testSwapUsesQuoterTightenedMinOut() public {
        uint256 out = swapper.swap{ value: 0.001 ether }(user);
        assertEq(out, 26_500_000);
        assertEq(usdc.balanceOf(user), 26_500_000);
        // Tightened: 97% of 26,500,000 = 25,705,000 (above the $10k floor of 10,000,000).
        assertEq(router.lastMinOut(), 25_705_000);
        assertEq(router.lastAmountIn(), 0.001 ether);
        assertEq(router.lastRecipient(), user);
    }

    function testSwapFallsBackToFloorWhenQuoterReverts() public {
        quoter.setShouldRevert(true);
        uint256 out = swapper.swap{ value: 0.001 ether }(user);
        assertEq(out, 26_500_000);
        // Floor only: 0.001 ETH * $10,000 = 10,000,000 (10 USDC).
        assertEq(router.lastMinOut(), 10_000_000);
    }

    function testSwapFallsBackToFloorWhenQuoteBelowFloor() public {
        // Absurdly low quote (pool price crashed below $10k): floor wins.
        quoter.setQuote(5_000_000);
        uint256 out = swapper.swap{ value: 0.001 ether }(user);
        assertEq(out, 26_500_000);
        assertEq(router.lastMinOut(), 10_000_000);
    }

    function testSwapRevertsOnZeroAmount() public {
        vm.expectRevert(UniswapSwapper.ZeroAmount.selector);
        swapper.swap{ value: 0 }(user);
    }

    function testSwapRevertsWhenRouterOutputBelowMinOut() public {
        // Router pays only 0.5 USDC for 0.001 ETH — below the $10k floor.
        router.setFixedOut(500_000);
        vm.expectRevert("Too little received");
        swapper.swap{ value: 0.001 ether }(user);
    }

    function testSwapRevertsOnZeroAddress() public {
        vm.expectRevert(UniswapSwapper.ZeroAddress.selector);
        swapper.swap{ value: 0.001 ether }(address(0));
    }

    function testSetMinPriceOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(UniswapSwapper.OnlyOwner.selector);
        swapper.setMinPrice(2_000_000_000);
        swapper.setMinPrice(2_000_000_000);
        assertEq(swapper.minPriceUsdcPerEth(), 2_000_000_000);
    }

    function testSetMinOutBpsBounds() public {
        vm.expectRevert(UniswapSwapper.BadBps.selector);
        swapper.setMinOutBps(0);
        vm.expectRevert(UniswapSwapper.BadBps.selector);
        swapper.setMinOutBps(10_001);
        swapper.setMinOutBps(9900);
        assertEq(swapper.minOutBps(), 9900);
    }

    function testReceiveRevertsForNonWeth() public {
        (bool ok,) = address(swapper).call{ value: 0.001 ether }("");
        assertFalse(ok);
    }

    function testSweepToken() public {
        usdc.mint(address(swapper), 123_456);
        swapper.sweepToken(address(usdc), user);
        assertEq(usdc.balanceOf(user), 123_456);
        assertEq(usdc.balanceOf(address(swapper)), 0);
    }
}
