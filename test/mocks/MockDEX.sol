// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @title MockDEX
 * @notice Mock DEX router for testing IndexZap swap functionality
 * @dev Simulates a DEX aggregator like 0x or 1inch
 *
 * This mock allows us to:
 * 1. Set exchange rates for token pairs
 * 2. Execute swaps with predictable outcomes
 * 3. Test slippage scenarios
 */
contract MockDEX {
    using SafeERC20 for IERC20;

    /// @notice Exchange rate: tokenOut amount per tokenIn amount (scaled by 1e18)
    /// @dev rate[tokenIn][tokenOut] = amount of tokenOut per 1e18 tokenIn
    mapping(address => mapping(address => uint256)) public rates;

    /// @notice If true, the next swap will fail
    bool public shouldFail;

    /// @notice Slippage to apply (in basis points, 10000 = 100%)
    uint256 public slippageBps;

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice Set the exchange rate for a token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param rate Amount of tokenOut (in its native decimals) per 1 unit of tokenIn (in its native decimals)
     *             Scaled by 1e18 for precision
     * @dev Example: For USDC (6 dec) -> WETH (18 dec) at 0.0005 WETH per USDC:
     *              rate = 0.0005e18 = 5e14
     */
    function setRate(address tokenIn, address tokenOut, uint256 rate) external {
        rates[tokenIn][tokenOut] = rate;
    }

    /**
     * @notice Set whether the next swap should fail
     */
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    /**
     * @notice Set slippage to simulate (in basis points)
     * @param _slippageBps Slippage in BPS (e.g., 100 = 1% slippage)
     */
    function setSlippage(uint256 _slippageBps) external {
        slippageBps = _slippageBps;
    }

    /**
     * @notice Execute a swap (called by IndexZap)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input token to swap (in tokenIn's decimals)
     * @param minAmountOut Minimum output (for slippage check simulation)
     * @return amountOut Actual amount of output token received (in tokenOut's decimals)
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        require(!shouldFail, "MockDEX: swap failed");

        uint256 rate = rates[tokenIn][tokenOut];
        require(rate > 0, "MockDEX: no rate set");

        // Pull input tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate output: amountOut = amountIn * rate / 1e18
        amountOut = (amountIn * rate) / 1e18;
        
        if (slippageBps > 0) {
            amountOut = (amountOut * (10000 - slippageBps)) / 10000;
        }

        require(amountOut >= minAmountOut, "MockDEX: insufficient output");

        // Mint output tokens (mock DEX has infinite liquidity)
        MockERC20(tokenOut).mint(msg.sender, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    }

    /**
     * @notice Get expected output for a swap (view function for quotes)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input token
     * @return amountOut Expected output amount
     */
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        uint256 rate = rates[tokenIn][tokenOut];
        amountOut = (amountIn * rate) / 1e18;
        if (slippageBps > 0) {
            amountOut = (amountOut * (10000 - slippageBps)) / 10000;
        }
    }

    /**
     * @notice Encode swap calldata for use with IndexZap
     * @dev This is a helper for tests to generate the calldata that IndexZap expects
     */
    function encodeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external pure returns (bytes memory) {
        return abi.encodeWithSelector(
            this.swap.selector,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
    }
}
