// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title IndexToken
 * @author Fortuna Crypto
 * @notice ERC-20 token representing proportional ownership in the IndexVault basket.
 * @dev This token is mintable/burnable only by addresses with MINTER_ROLE (the vault).
 *
 * Architecture:
 * - The IndexVault deploys this token and grants itself MINTER_ROLE
 * - Users receive IndexTokens when depositing into the vault
 * - Users burn IndexTokens when redeeming from the vault
 * - The token itself holds no assets; it's purely an accounting mechanism
 *
 * Security:
 * - Only MINTER_ROLE can mint/burn (enforced via OpenZeppelin AccessControl)
 * - DEFAULT_ADMIN_ROLE can grant/revoke roles
 * - No upgrade mechanism (immutable deployment)
 */
contract IndexToken is ERC20, AccessControl {
    /// @notice Role identifier for addresses allowed to mint and burn tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Deploys the IndexToken with a given name, symbol, and admin
     * @param name_ The name of the index token (e.g., "Fortuna Crypto Index")
     * @param symbol_ The symbol of the index token (e.g., "FCI")
     * @param admin The address that will receive DEFAULT_ADMIN_ROLE
     * @dev The admin can later grant MINTER_ROLE to the vault contract
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address admin
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Mints new index tokens to a recipient
     * @param to The address receiving the minted tokens
     * @param amount The amount of tokens to mint (18 decimals)
     * @dev Only callable by addresses with MINTER_ROLE (the vault)
     *
     * Mint Math (in vault context):
     * - First mint: user receives 1e18 shares for seeding the vault
     * - Subsequent mints: shares = min((amountIn[i] * totalSupply) / vaultBalance[i]) for all i
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns index tokens from a holder
     * @param from The address whose tokens will be burned
     * @param amount The amount of tokens to burn (18 decimals)
     * @dev Only callable by addresses with MINTER_ROLE (the vault)
     * @dev The vault calls this during redemption before transferring underlying assets
     *
     * Burn Math (in vault context):
     * - amountOut[i] = (vaultBalance[i] * sharesBurned) / totalSupply
     * - Burning happens BEFORE transfers to prevent reentrancy manipulation of totalSupply
     */
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }
}
