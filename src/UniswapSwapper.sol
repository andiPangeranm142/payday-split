// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISwapper } from "./MockSwapper.sol";
import { IERC20 } from "./IERC20.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount_) external;
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/// @title UniswapSwapper — real ETH -> USDC swap via Uniswap V3 (Base Sepolia).
/// @notice Replaces the v1 MockSwapper (fixed 1 ETH = 2000 pUSD) with a real
///         DEX route: ETH is wrapped to WETH and swapped for Circle USDC in the
///         WETH/USDC 0.3% pool through the official SwapRouter02. The USDC goes
///         straight to the vault (`to_`), which credits it to the user.
/// @dev Slippage protection has two layers:
///      1. A price floor (`minPriceUsdcPerEth`, default $10,000/ETH): the swap
///         reverts if the pool price collapses below it — a sanity bound that
///         needs no oracle and can never brick the swapper on its own.
///      2. A QuoterV2 tightening: when the quoter answers, `amountOutMinimum`
///         is raised to `minOutBps` (default 9700 = 3% slippage) of the quote.
///         The quoter call is wrapped in try/catch — if it ever reverts, the
///         swap still proceeds under the floor instead of bricking the split.
contract UniswapSwapper is ISwapper {
    IWETH9 public immutable weth;
    IERC20 public immutable usdc;
    ISwapRouter02 public immutable router;
    IQuoterV2 public immutable quoter;
    uint24 public immutable fee;
    address public immutable owner;

    /// @notice Minimum USDC (6 decimals) per 1 ETH, as a sanity floor.
    ///         The Base Sepolia WETH/USDC pool prices ETH far above mainnet
    ///         (~$26.5k at v2 launch — testnet pools are seeded arbitrarily);
    ///         $10k sits ~2.6x below that, so only a catastrophic collapse
    ///         trips it.
    uint256 public minPriceUsdcPerEth = 10_000_000_000; // $10,000/ETH
    /// @notice Basis points of the quoted amount accepted as minimum out.
    uint16 public minOutBps = 9700; // 3% max slippage vs the quote

    bool private locked;

    event Swapped(address indexed user, uint256 ethIn, uint256 stableOut, uint256 minOut);
    event MinPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event MinOutBpsUpdated(uint16 oldBps, uint16 newBps);

    error OnlyOwner();
    error OnlyWETH();
    error ZeroAddress();
    error ZeroAmount();
    error Reentrancy();
    error BadBps();

    constructor(address weth_, address usdc_, address router_, address quoter_, uint24 fee_) {
        weth = IWETH9(weth_);
        usdc = IERC20(usdc_);
        router = ISwapRouter02(router_);
        quoter = IQuoterV2(quoter_);
        fee = fee_;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function setMinPrice(uint256 price_) external onlyOwner {
        uint256 old = minPriceUsdcPerEth;
        minPriceUsdcPerEth = price_;
        emit MinPriceUpdated(old, price_);
    }

    function setMinOutBps(uint16 bps_) external onlyOwner {
        if (bps_ == 0 || bps_ > 10_000) revert BadBps();
        uint16 old = minOutBps;
        minOutBps = bps_;
        emit MinOutBpsUpdated(old, bps_);
    }

    /// @inheritdoc ISwapper
    function swap(address to_) external payable returns (uint256 stableOut) {
        if (to_ == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        if (locked) revert Reentrancy();
        locked = true;

        // Layer 1: price floor.
        uint256 minOut = (msg.value * minPriceUsdcPerEth) / 1 ether;

        // Layer 2: tighten against a live quote when the quoter answers.
        // forge-lint: disable-next-line(reentrancy-no-eth) — guarded by `locked`.
        try quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                amountIn: msg.value,
                fee: fee,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 quoted, uint160, uint32, uint256) {
            uint256 tight = (quoted * minOutBps) / 10_000;
            if (tight > minOut) minOut = tight;
        } catch {
            // Quoter unavailable — proceed under the floor.
        }

        weth.deposit{ value: msg.value }();
        // forge-lint: disable-next-line(reentrancy-no-eth) — guarded by `locked`.
        require(weth.approve(address(router), msg.value), "WETH approve failed");
        // forge-lint: disable-next-line(reentrancy-no-eth) — guarded by `locked`.
        stableOut = router.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                fee: fee,
                recipient: to_,
                amountIn: msg.value,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );

        locked = false;
        // Event intentionally emitted after the call: only log swaps that
        // actually executed.
        // forge-lint: disable-next-line(reentrancy-events)
        emit Swapped(to_, msg.value, stableOut, minOut);
    }

    /// @notice Recover stuck ETH / WETH / USDC (testnet housekeeping only).
    function sweepEth(address payable to_) external onlyOwner {
        if (to_ == address(0)) revert ZeroAddress();
        to_.transfer(address(this).balance);
    }

    function sweepToken(address token_, address to_) external onlyOwner {
        if (to_ == address(0)) revert ZeroAddress();
        IERC20 token = IERC20(token_);
        require(token.transfer(to_, token.balanceOf(address(this))), "sweep failed");
    }

    receive() external payable {
        // Accepts ETH back from WETH.withdraw (unused today, kept for safety).
        if (msg.sender != address(weth)) revert OnlyWETH();
    }
}
