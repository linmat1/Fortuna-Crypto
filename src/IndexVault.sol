// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IndexToken} from "./IndexToken.sol";

contract IndexVault is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct Constituent {
        IERC20 token;
        uint16 weightBps; // out of 10_000
    }

    IndexToken public immutable indexToken;
    Constituent[] public constituents;

    uint16 public constant BPS = 10_000;

    event ConstituentsSet(address[] tokens, uint16[] weightsBps);
    event Minted(address indexed user, uint256 shares, uint256[] amountsIn);
    event Redeemed(address indexed user, uint256 shares, uint256[] amountsOut);

    constructor(
        address admin,
        string memory indexName,
        string memory indexSymbol,
        address[] memory tokens,
        uint16[] memory weightsBps
    ) {
        require(tokens.length == weightsBps.length, "length mismatch");
        require(tokens.length > 0, "no constituents");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);

        indexToken = new IndexToken(indexName, indexSymbol, admin);
        indexToken.grantRole(indexToken.MINTER_ROLE(), address(this));

        _setConstituents(tokens, weightsBps);
    }

    function numConstituents() external view returns (uint256) {
        return constituents.length;
    }

    function getConstituents()
        external
        view
        returns (address[] memory tokens, uint16[] memory weightsBps)
    {
        tokens = new address[](constituents.length);
        weightsBps = new uint16[](constituents.length);
        for (uint256 i = 0; i < constituents.length; i++) {
            tokens[i] = address(constituents[i].token);
            weightsBps[i] = constituents[i].weightBps;
        }
    }

    // --- Manager controls ---

    function pause() external onlyRole(MANAGER_ROLE) { _pause(); }
    function unpause() external onlyRole(MANAGER_ROLE) { _unpause(); }

    /// @dev v1: allow updating weights/constituents (use carefully; in production, governance + delay).
    function setConstituents(address[] calldata tokens, uint16[] calldata weightsBps)
        external
        onlyRole(MANAGER_ROLE)
    {
        _setConstituents(tokens, weightsBps);
    }

    function _setConstituents(address[] memory tokens, uint16[] memory weightsBps) internal {
        require(tokens.length == weightsBps.length, "length mismatch");
        require(tokens.length > 0, "no constituents");

        uint256 sum;
        delete constituents;

        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "zero token");
            require(weightsBps[i] > 0, "zero weight");
            constituents.push(Constituent({token: IERC20(tokens[i]), weightBps: weightsBps[i]}));
            sum += weightsBps[i];
        }
        require(sum == BPS, "weights != 100%");
        emit ConstituentsSet(tokens, weightsBps);
    }

    // --- Core math ---
    /// @dev Defines "one share unit" as a pro-rata claim on vault balances.
    /// For first mint, we choose shares = 1e18 for a "unit basket" defined by weights and user-provided amounts.
    function totalShares() public view returns (uint256) {
        return indexToken.totalSupply();
    }

    /// @dev Vault balance for each constituent.
    function vaultBalances() public view returns (uint256[] memory bals) {
        bals = new uint256[](constituents.length);
        for (uint256 i = 0; i < constituents.length; i++) {
            bals[i] = constituents[i].token.balanceOf(address(this));
        }
    }

    // --- Mint / Redeem (in-kind) ---

    /// @notice Mint by depositing each constituent token amount.
    /// @param amountsIn amounts for each constituent (same order as constituents array).
    function mint(uint256[] calldata amountsIn)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 sharesOut)
    {
        require(amountsIn.length == constituents.length, "bad amounts");

        uint256 supply = totalShares();

        if (supply == 0) {
            // Initial mint: user seeds vault. We mint 1e18 shares as a baseline,
            // but require amounts match weights proportionally (within tolerance handled off-chain in v1).
            sharesOut = 1e18;
        } else {
            // Pro-rata mint: user must deposit proportionally to existing balances.
            // sharesOut is limited by the "tightest" constituent ratio.
            sharesOut = type(uint256).max;
            for (uint256 i = 0; i < constituents.length; i++) {
                uint256 bal = constituents[i].token.balanceOf(address(this));
                require(bal > 0, "empty constituent");
                uint256 candidate = (amountsIn[i] * supply) / bal;
                if (candidate < sharesOut) sharesOut = candidate;
            }
            require(sharesOut > 0, "zero shares");
        }

        // Pull tokens in (user must approve first).
        for (uint256 i = 0; i < constituents.length; i++) {
            if (amountsIn[i] > 0) {
                constituents[i].token.safeTransferFrom(msg.sender, address(this), amountsIn[i]);
            }
        }

        indexToken.mint(msg.sender, sharesOut);
        emit Minted(msg.sender, sharesOut, _copy(amountsIn));
    }

    /// @notice Redeem shares for underlying tokens pro-rata.
    function redeem(uint256 sharesIn)
        external
        nonReentrant
        whenNotPaused
        returns (uint256[] memory amountsOut)
    {
        require(sharesIn > 0, "zero shares");
        uint256 supply = totalShares();
        require(supply > 0, "no supply");

        amountsOut = new uint256[](constituents.length);

        // Burn first (prevents reentrancy games around supply)
        indexToken.burn(msg.sender, sharesIn);

        for (uint256 i = 0; i < constituents.length; i++) {
            uint256 bal = constituents[i].token.balanceOf(address(this));
            uint256 out = (bal * sharesIn) / supply;
            amountsOut[i] = out;
            if (out > 0) {
                constituents[i].token.safeTransfer(msg.sender, out);
            }
        }

        emit Redeemed(msg.sender, sharesIn, amountsOut);
    }

    function _copy(uint256[] calldata arr) internal pure returns (uint256[] memory out) {
        out = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) out[i] = arr[i];
    }
}

