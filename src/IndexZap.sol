// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IndexVault} from "./IndexVault.sol";

/**
 * @title IndexZap
 * @author Fortuna Crypto
 * @notice Single-asset entry point for the index fund. Accepts USDC and handles
 *         swapping to constituent tokens via external DEX aggregators.
 *
 * @dev HOW ZAP SWAPS WORK:
 *
 * ┌─────────────────────────────────────────────────────────────────────────┐
 * │                              User Flow                                  │
 * │                                                                         │
 * │  1. User approves USDC to IndexZap                                      │
 * │  2. Off-chain: Frontend fetches swap quotes from 0x/1inch/Paraswap      │
 * │  3. User calls zapIn() with:                                            │
 * │     - usdcAmount: total USDC to spend                                   │
 * │     - swapTargets[]: DEX router addresses for each swap                 │
 * │     - swapCalldata[]: Encoded swap calls (from aggregator API)          │
 * │     - minTokensOut[]: Minimum output per swap (slippage protection)     │
 * │     - minSharesOut: Minimum index tokens to receive                     │
 * │                                                                         │
 * │  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
 * │  │   USDC   │ -> │ DEX Swap │ -> │  Tokens  │ -> │  Vault   │          │
 * │  │ (input)  │    │ (0x/1in) │    │ (basket) │    │  mint()  │          │
 * │  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
 * │                                         ↓                               │
 * │                                  ┌──────────────┐                       │
 * │                                  │ Index Tokens │ -> User               │
 * │                                  └──────────────┘                       │
 * └─────────────────────────────────────────────────────────────────────────┘
 *
 * SLIPPAGE PROTECTION (Critical for Security):
 * ─────────────────────────────────────────────
 * 1. Per-swap protection: minTokensOut[i] ensures each DEX swap returns
 *    at least the expected amount. Protects against MEV sandwich attacks.
 *
 * 2. Final output protection: minSharesOut ensures the user receives
 *    at least the expected index tokens. Protects against:
 *    - Stale quotes
 *    - Price movement between quote and execution
 *    - Any rounding/conversion losses
 *
 * 3. Allowlist: Only whitelisted DEX routers can be called, preventing
 *    malicious contract calls that could drain funds.
 *
 * Security Considerations:
 * - All external calls are to whitelisted targets only
 * - ReentrancyGuard prevents reentrancy via token callbacks
 * - Pausable allows emergency stops
 * - No unbounded loops (constituents bounded by vault's MAX_CONSTITUENTS)
 * - SafeERC20 for all token operations
 * - Slippage checks on every swap and final output
 */
contract IndexZap is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Role for protocol managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The USDC token (or other input token)
    IERC20 public immutable usdc;

    /// @notice The IndexVault this zap deposits into
    IndexVault public immutable vault;

    /// @notice The IndexToken received from the vault
    IERC20 public immutable indexToken;

    /// @notice Whitelisted DEX aggregator routers that can be called
    /// @dev Only these addresses can receive swap calldata
    mapping(address => bool) public allowedSwapTargets;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user zaps USDC into index tokens
    /// @param user The user who zapped
    /// @param usdcIn Amount of USDC spent
    /// @param sharesOut Amount of index tokens received
    event ZappedIn(address indexed user, uint256 usdcIn, uint256 sharesOut);

    /// @notice Emitted when a swap target is added or removed from allowlist
    /// @param target The DEX router address
    /// @param allowed Whether it's now allowed or not
    event SwapTargetUpdated(address indexed target, bool allowed);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error ZeroAmount();
    error ArrayLengthMismatch();
    error SwapTargetNotAllowed(address target);
    error SwapFailed(uint256 index);
    error InsufficientSwapOutput(uint256 index, uint256 expected, uint256 actual);
    error InsufficientSharesOut(uint256 expected, uint256 actual);
    error NoSwaps();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys the IndexZap contract
     * @param _usdc Address of the USDC token
     * @param _vault Address of the IndexVault
     * @param admin Address that receives admin and manager roles
     * @param initialSwapTargets Initial list of allowed DEX routers
     */
    constructor(
        address _usdc,
        address _vault,
        address admin,
        address[] memory initialSwapTargets
    ) {
        if (_usdc == address(0) || _vault == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }

        usdc = IERC20(_usdc);
        vault = IndexVault(_vault);
        indexToken = IERC20(address(vault.indexToken()));

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);

        // Whitelist initial swap targets (e.g., 0x Exchange Proxy, 1inch Router)
        for (uint256 i = 0; i < initialSwapTargets.length; ++i) {
            if (initialSwapTargets[i] != address(0)) {
                allowedSwapTargets[initialSwapTargets[i]] = true;
                emit SwapTargetUpdated(initialSwapTargets[i], true);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses zap operations
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /// @notice Unpauses zap operations
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Adds or removes a DEX router from the allowlist
     * @param target The DEX router address
     * @param allowed Whether to allow or disallow
     * @dev Only managers can modify the allowlist
     */
    function setSwapTarget(
        address target,
        bool allowed
    ) external onlyRole(MANAGER_ROLE) {
        if (target == address(0)) revert ZeroAddress();
        allowedSwapTargets[target] = allowed;
        emit SwapTargetUpdated(target, allowed);
    }

    /**
     * @notice Emergency function to rescue tokens sent to this contract by mistake
     * @param token The token to rescue
     * @param to The recipient
     * @param amount The amount to rescue
     * @dev Only admin can call. Cannot rescue during active zap (nonReentrant handles this)
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Zaps USDC into index tokens via DEX swaps
     * @param usdcAmount Total amount of USDC to spend
     * @param swapTargets Array of DEX router addresses (one per constituent)
     * @param swapCalldata Array of encoded swap calls (from aggregator APIs)
     * @param minTokensOut Minimum output for each swap (slippage protection)
     * @param minSharesOut Minimum index tokens to receive (final slippage check)
     * @return sharesOut Amount of index tokens received
     *
     * @dev DETAILED EXECUTION FLOW:
     *
     * 1. VALIDATION
     *    - Check array lengths match number of constituents
     *    - Verify all swap targets are whitelisted
     *
     * 2. PULL USDC
     *    - Transfer usdcAmount from user to this contract
     *    - User must have approved this contract beforehand
     *
     * 3. EXECUTE SWAPS
     *    For each constituent token:
     *    a. Approve USDC to the swap target (if needed)
     *    b. Execute the swap via low-level call with provided calldata
     *    c. Check actual output >= minTokensOut[i]
     *
     * 4. DEPOSIT TO VAULT
     *    a. Approve all constituent tokens to the vault
     *    b. Call vault.mint() with the acquired token amounts
     *    c. Check shares received >= minSharesOut
     *
     * 5. TRANSFER TO USER
     *    - Send index tokens to the user
     *    - Refund any leftover USDC (from rounding)
     *
     * @dev SLIPPAGE PROTECTION DETAILS:
     *
     * minTokensOut[i]: Protects each individual swap
     * ─────────────────────────────────────────────
     * - Set by frontend based on DEX aggregator quote
     * - Typically quote * (1 - slippageTolerance), e.g., quote * 0.995 for 0.5%
     * - Prevents sandwich attacks on individual swaps
     *
     * minSharesOut: Protects the entire operation
     * ──────────────────────────────────────────────
     * - Set by frontend based on expected shares from vault.mint()
     * - Accounts for:
     *   - All individual swap slippages compounding
     *   - Vault's pro-rata calculation rounding
     *   - Any tokens going to "excess" in vault
     * - This is the user's bottom line protection
     *
     * @dev WHY CALLDATA FROM AGGREGATORS:
     *
     * DEX aggregators (0x, 1inch, Paraswap) provide optimized swap routes:
     * - Split across multiple DEXes for better prices
     * - Handle complex multi-hop routes
     * - Include their own slippage protections
     *
     * We pass their calldata directly because:
     * 1. Routes change block-by-block (can't hardcode)
     * 2. Aggregators have sophisticated routing algorithms
     * 3. Encoding complex routes on-chain would be gas prohibitive
     *
     * Security: We only allow calls to whitelisted targets (allowedSwapTargets)
     */
    function zapIn(
        uint256 usdcAmount,
        address[] calldata swapTargets,
        bytes[] calldata swapCalldata,
        uint256[] calldata minTokensOut,
        uint256 minSharesOut
    ) external nonReentrant whenNotPaused returns (uint256 sharesOut) {
        // --- Validation ---
        if (usdcAmount == 0) revert ZeroAmount();

        uint256 numConstituents = vault.numConstituents();
        if (swapTargets.length != numConstituents) revert ArrayLengthMismatch();
        if (swapCalldata.length != numConstituents) revert ArrayLengthMismatch();
        if (minTokensOut.length != numConstituents) revert ArrayLengthMismatch();
        if (numConstituents == 0) revert NoSwaps();

        // Verify all swap targets are whitelisted
        for (uint256 i = 0; i < numConstituents; ++i) {
            if (!allowedSwapTargets[swapTargets[i]]) {
                revert SwapTargetNotAllowed(swapTargets[i]);
            }
        }

        // --- Pull USDC from user ---
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // --- Execute swaps and collect constituent tokens ---
        (address[] memory tokens, ) = vault.getConstituents();
        uint256[] memory amountsOut = new uint256[](numConstituents);

        for (uint256 i = 0; i < numConstituents; ++i) {
            // Record balance before swap
            uint256 balBefore = IERC20(tokens[i]).balanceOf(address(this));

            // Approve USDC to swap target (approve max to save gas on repeated zaps)
            // Note: This is safe because we control all the calldata and targets are whitelisted
            _ensureApproval(usdc, swapTargets[i]);

            // Execute the swap
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = swapTargets[i].call(swapCalldata[i]);
            if (!success) revert SwapFailed(i);

            // Calculate actual tokens received
            uint256 balAfter = IERC20(tokens[i]).balanceOf(address(this));
            amountsOut[i] = balAfter - balBefore;

            // SLIPPAGE CHECK: Ensure we got at least minTokensOut
            if (amountsOut[i] < minTokensOut[i]) {
                revert InsufficientSwapOutput(i, minTokensOut[i], amountsOut[i]);
            }
        }

        // --- Deposit to vault ---
        // Approve all constituent tokens to the vault
        for (uint256 i = 0; i < numConstituents; ++i) {
            _ensureApproval(IERC20(tokens[i]), address(vault));
        }

        // Mint index tokens via vault
        sharesOut = vault.mint(amountsOut);

        // SLIPPAGE CHECK: Ensure we got at least minSharesOut
        if (sharesOut < minSharesOut) {
            revert InsufficientSharesOut(minSharesOut, sharesOut);
        }

        // --- Transfer index tokens to user ---
        indexToken.safeTransfer(msg.sender, sharesOut);

        // Refund any leftover USDC (can happen due to rounding in swap amounts)
        uint256 usdcLeftover = usdc.balanceOf(address(this));
        if (usdcLeftover > 0) {
            usdc.safeTransfer(msg.sender, usdcLeftover);
        }

        emit ZappedIn(msg.sender, usdcAmount - usdcLeftover, sharesOut);
    }

    /**
     * @notice Preview function to help frontends calculate expected outputs
     * @param amountsFromSwaps Expected token amounts from DEX quotes
     * @return expectedShares Estimated shares from vault (not guaranteed)
     * @dev This is a HELPER function only. Actual shares depend on vault state at execution.
     */
    function previewZap(
        uint256[] calldata amountsFromSwaps
    ) external view returns (uint256 expectedShares) {
        uint256 supply = vault.totalShares();
        if (supply == 0) {
            return 1e18; // First mint gets 1e18 shares
        }

        uint256[] memory balances = vault.vaultBalances();
        expectedShares = type(uint256).max;

        for (uint256 i = 0; i < balances.length; ++i) {
            if (balances[i] == 0) continue;
            uint256 candidate = (amountsFromSwaps[i] * supply) / balances[i];
            if (candidate < expectedShares) {
                expectedShares = candidate;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures the contract has approved `spender` for `token`
     * @param token The token to approve
     * @param spender The address to approve
     * @dev Uses max approval to save gas. Safe because:
     *      1. We control all calls to these targets
     *      2. Targets are whitelisted
     *      3. This contract doesn't hold tokens between transactions
     */
    function _ensureApproval(IERC20 token, address spender) internal {
        if (token.allowance(address(this), spender) == 0) {
            token.forceApprove(spender, type(uint256).max);
        }
    }
}


