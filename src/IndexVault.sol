// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IndexToken} from "./IndexToken.sol";

/**
 * @title IndexVault
 * @author Fortuna Crypto
 * @notice Holds underlying assets for a crypto index fund and manages mint/redeem operations.
 * @dev This contract implements in-kind accounting only - no swap logic lives here.
 *
 * Architecture:
 * ┌─────────────────────────────────────────────────────────────────────┐
 * │                           IndexVault                                │
 * │  ┌──────────┐  ┌──────────┐  ┌──────────┐                          │
 * │  │ Token A  │  │ Token B  │  │ Token C  │  ← Constituent Tokens    │
 * │  │  40%     │  │  40%     │  │  20%     │    (weights in BPS)      │
 * │  └──────────┘  └──────────┘  └──────────┘                          │
 * │                       ↕ mint/redeem                                 │
 * │              ┌──────────────┐                                       │
 * │              │ IndexToken   │  ← Shares representing ownership     │
 * │              └──────────────┘                                       │
 * └─────────────────────────────────────────────────────────────────────┘
 *
 * Key Design Decisions:
 * 1. In-kind only: Users must deposit/withdraw the exact constituent tokens
 * 2. Pro-rata: Share value is proportional to vault holdings
 * 3. No oracles: No price feeds needed; value is purely based on token balances
 * 4. Bounded arrays: Constituents array is manager-controlled, not user-controlled
 *
 * Security Considerations:
 * - ReentrancyGuard on mint/redeem to prevent reentrancy attacks
 * - Pausable for emergency stops
 * - AccessControl for permissioned operations
 * - SafeERC20 for all token transfers
 * - Burns before transfers in redeem() to prevent supply manipulation
 */
contract IndexVault is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Role for protocol managers who can pause/unpause and update constituents
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Basis points denominator (100% = 10,000 BPS)
    uint16 public constant BPS = 10_000;

    /// @notice Maximum number of constituents to prevent unbounded loops
    /// @dev 20 is reasonable for gas limits; can be adjusted based on testing
    uint8 public constant MAX_CONSTITUENTS = 20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct representing a constituent token and its target weight
    /// @param token The ERC-20 token address
    /// @param weightBps Target weight in basis points (out of 10,000)
    struct Constituent {
        IERC20 token;
        uint16 weightBps;
    }

    /// @notice The index token that represents shares in this vault
    IndexToken public immutable indexToken;

    /// @notice Array of constituent tokens and their weights
    /// @dev Length is bounded by MAX_CONSTITUENTS; only manager can modify
    Constituent[] public constituents;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when constituents are updated
    /// @param tokens Array of constituent token addresses
    /// @param weightsBps Array of weights in basis points
    event ConstituentsSet(address[] tokens, uint16[] weightsBps);

    /// @notice Emitted when a user mints index tokens
    /// @param user Address that received the index tokens
    /// @param shares Amount of index tokens minted
    /// @param amountsIn Amounts of each constituent deposited
    event Minted(address indexed user, uint256 shares, uint256[] amountsIn);

    /// @notice Emitted when a user redeems index tokens
    /// @param user Address that redeemed
    /// @param shares Amount of index tokens burned
    /// @param amountsOut Amounts of each constituent withdrawn
    event Redeemed(address indexed user, uint256 shares, uint256[] amountsOut);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error LengthMismatch();
    error NoConstituents();
    error TooManyConstituents();
    error ZeroAddress();
    error ZeroWeight();
    error WeightsNotComplete();
    error BadAmountsLength();
    error EmptyConstituent();
    error ZeroShares();
    error NoSupply();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys the IndexVault with initial constituents
     * @param admin Address that receives DEFAULT_ADMIN_ROLE and MANAGER_ROLE
     * @param indexName Name for the index token (e.g., "Fortuna Crypto Index")
     * @param indexSymbol Symbol for the index token (e.g., "FCI")
     * @param tokens Array of constituent token addresses
     * @param weightsBps Array of weights in basis points (must sum to 10,000)
     */
    constructor(
        address admin,
        string memory indexName,
        string memory indexSymbol,
        address[] memory tokens,
        uint16[] memory weightsBps
    ) {
        if (tokens.length != weightsBps.length) revert LengthMismatch();
        if (tokens.length == 0) revert NoConstituents();
        if (tokens.length > MAX_CONSTITUENTS) revert TooManyConstituents();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);

        // Deploy the index token and grant this vault minting rights
        indexToken = new IndexToken(indexName, indexSymbol, address(this));
        indexToken.grantRole(indexToken.MINTER_ROLE(), address(this));

        _setConstituents(tokens, weightsBps);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the number of constituents in the index
    function numConstituents() external view returns (uint256) {
        return constituents.length;
    }

    /**
     * @notice Returns all constituents and their weights
     * @return tokens Array of constituent token addresses
     * @return weightsBps Array of weights in basis points
     */
    function getConstituents()
        external
        view
        returns (address[] memory tokens, uint16[] memory weightsBps)
    {
        uint256 len = constituents.length;
        tokens = new address[](len);
        weightsBps = new uint16[](len);
        for (uint256 i = 0; i < len; ++i) {
            tokens[i] = address(constituents[i].token);
            weightsBps[i] = constituents[i].weightBps;
        }
    }

    /**
     * @notice Returns total shares (index tokens) in circulation
     * @return Total supply of the index token
     */
    function totalShares() public view returns (uint256) {
        return indexToken.totalSupply();
    }

    /**
     * @notice Returns the vault's balance of each constituent
     * @return bals Array of balances for each constituent
     */
    function vaultBalances() public view returns (uint256[] memory bals) {
        uint256 len = constituents.length;
        bals = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            bals[i] = constituents[i].token.balanceOf(address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses mint and redeem operations
    /// @dev Only callable by MANAGER_ROLE
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /// @notice Unpauses mint and redeem operations
    /// @dev Only callable by MANAGER_ROLE
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Updates the constituent tokens and weights
     * @param tokens Array of new constituent token addresses
     * @param weightsBps Array of new weights in basis points
     * @dev Only callable by MANAGER_ROLE
     * @dev WARNING: In production, this should have a timelock/governance delay
     *
     * Considerations when updating constituents:
     * 1. Existing vault balances don't automatically rebalance
     * 2. Old tokens remain in vault until redeemed
     * 3. New tokens need to be deposited via mint()
     */
    function setConstituents(
        address[] calldata tokens,
        uint16[] calldata weightsBps
    ) external onlyRole(MANAGER_ROLE) {
        if (tokens.length > MAX_CONSTITUENTS) revert TooManyConstituents();
        _setConstituents(tokens, weightsBps);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to set constituents with validation
     * @param tokens Array of constituent token addresses
     * @param weightsBps Array of weights in basis points
     */
    function _setConstituents(
        address[] memory tokens,
        uint16[] memory weightsBps
    ) internal {
        if (tokens.length != weightsBps.length) revert LengthMismatch();
        if (tokens.length == 0) revert NoConstituents();

        uint256 sum;
        delete constituents;

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            if (weightsBps[i] == 0) revert ZeroWeight();
            constituents.push(
                Constituent({token: IERC20(tokens[i]), weightBps: weightsBps[i]})
            );
            sum += weightsBps[i];
        }

        if (sum != BPS) revert WeightsNotComplete();
        emit ConstituentsSet(tokens, weightsBps);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints index tokens by depositing constituent tokens
     * @param amountsIn Amounts of each constituent to deposit (same order as constituents array)
     * @return sharesOut Amount of index tokens minted
     *
     * @dev MINT MATH EXPLAINED:
     *
     * Case 1: First mint (totalSupply == 0)
     * ─────────────────────────────────────
     * The first depositor "seeds" the vault and receives 1e18 shares.
     * This establishes the initial share price based on their deposit.
     *
     * Example: First user deposits [100 WETH, 50 WBTC, 1000 LINK]
     *          → User receives 1e18 index tokens
     *          → 1 index token = (100/1e18 WETH, 50/1e18 WBTC, 1000/1e18 LINK)
     *
     * Case 2: Subsequent mints (totalSupply > 0)
     * ──────────────────────────────────────────
     * Users must deposit proportionally to existing vault balances.
     * Shares minted = minimum ratio across all constituents.
     *
     * Formula: sharesOut = min( amountsIn[i] * totalSupply / vaultBalance[i] ) for all i
     *
     * Example: Vault has [200 WETH, 100 WBTC], supply = 2e18
     *          User deposits [50 WETH, 30 WBTC]
     *          WETH ratio: 50 * 2e18 / 200 = 0.5e18
     *          WBTC ratio: 30 * 2e18 / 100 = 0.6e18
     *          sharesOut = min(0.5e18, 0.6e18) = 0.5e18
     *
     * Note: If user deposits more of one token than needed, the excess stays
     * in the vault (benefits all shareholders). Off-chain systems should
     * calculate exact proportional amounts to avoid this.
     *
     * @dev Security:
     * - nonReentrant: Prevents reentrancy via malicious token callbacks
     * - whenNotPaused: Allows emergency stops
     * - Tokens pulled AFTER shares calculated to prevent manipulation
     */
    function mint(
        uint256[] calldata amountsIn
    ) external nonReentrant whenNotPaused returns (uint256 sharesOut) {
        uint256 len = constituents.length;
        if (amountsIn.length != len) revert BadAmountsLength();

        uint256 supply = totalShares();

        if (supply == 0) {
            // First mint: bootstrap the vault with 1e18 base shares
            sharesOut = 1e18;
        } else {
            // Pro-rata mint: find the limiting ratio
            sharesOut = type(uint256).max;
            for (uint256 i = 0; i < len; ++i) {
                uint256 bal = constituents[i].token.balanceOf(address(this));
                if (bal == 0) revert EmptyConstituent();
                uint256 candidate = (amountsIn[i] * supply) / bal;
                if (candidate < sharesOut) {
                    sharesOut = candidate;
                }
            }
            if (sharesOut == 0) revert ZeroShares();
        }

        // Pull tokens from user (requires prior approval)
        for (uint256 i = 0; i < len; ++i) {
            if (amountsIn[i] > 0) {
                constituents[i].token.safeTransferFrom(
                    msg.sender,
                    address(this),
                    amountsIn[i]
                );
            }
        }

        // Mint index tokens to user
        indexToken.mint(msg.sender, sharesOut);
        emit Minted(msg.sender, sharesOut, _toMemory(amountsIn));
    }

    /**
     * @notice Redeems index tokens for underlying constituent tokens
     * @param sharesIn Amount of index tokens to burn
     * @return amountsOut Amounts of each constituent received
     *
     * @dev REDEEM MATH EXPLAINED:
     *
     * Each share represents a proportional claim on vault balances.
     *
     * Formula: amountsOut[i] = vaultBalance[i] * sharesIn / totalSupply
     *
     * Example: Vault has [200 WETH, 100 WBTC], supply = 2e18
     *          User redeems 0.5e18 shares (25% of supply)
     *          WETH out: 200 * 0.5e18 / 2e18 = 50 WETH
     *          WBTC out: 100 * 0.5e18 / 2e18 = 25 WBTC
     *
     * @dev Security:
     * - Burns BEFORE transfers: Critical! This prevents reentrancy attacks
     *   where a malicious token callback could manipulate totalSupply
     * - nonReentrant: Additional protection layer
     * - whenNotPaused: Allows emergency stops
     */
    function redeem(
        uint256 sharesIn
    ) external nonReentrant whenNotPaused returns (uint256[] memory amountsOut) {
        if (sharesIn == 0) revert ZeroShares();
        uint256 supply = totalShares();
        if (supply == 0) revert NoSupply();

        uint256 len = constituents.length;
        amountsOut = new uint256[](len);

        // CRITICAL: Burn shares BEFORE calculating/transferring to prevent
        // reentrancy manipulation of totalSupply
        indexToken.burn(msg.sender, sharesIn);

        // Calculate and transfer pro-rata share of each constituent
        for (uint256 i = 0; i < len; ++i) {
            uint256 bal = constituents[i].token.balanceOf(address(this));
            uint256 out = (bal * sharesIn) / supply;
            amountsOut[i] = out;
            if (out > 0) {
                constituents[i].token.safeTransfer(msg.sender, out);
            }
        }

        emit Redeemed(msg.sender, sharesIn, amountsOut);
    }

    /**
     * @dev Converts calldata array to memory array for event emission
     */
    function _toMemory(
        uint256[] calldata arr
    ) internal pure returns (uint256[] memory out) {
        out = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; ++i) {
            out[i] = arr[i];
        }
    }
}
