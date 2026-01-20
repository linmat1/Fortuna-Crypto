// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {IndexToken} from "../src/IndexToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title IndexVaultTest
 * @notice Comprehensive tests for the IndexVault contract
 */
contract IndexVaultTest is Test {
    IndexVault public vault;
    IndexToken public indexToken;

    MockERC20 public weth;
    MockERC20 public wbtc;
    MockERC20 public link;

    address public admin = makeAddr("admin");
    address public manager = makeAddr("manager");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint16 public constant BPS = 10_000;

    event ConstituentsSet(address[] tokens, uint16[] weightsBps);
    event Minted(address indexed user, uint256 shares, uint256[] amountsIn);
    event Redeemed(address indexed user, uint256 shares, uint256[] amountsOut);

    function setUp() public {
        // Deploy mock tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        link = new MockERC20("Chainlink", "LINK", 18);

        // Setup constituent arrays
        address[] memory tokens = new address[](3);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);
        tokens[2] = address(link);

        uint16[] memory weights = new uint16[](3);
        weights[0] = 5000; // 50% WETH
        weights[1] = 3000; // 30% WBTC
        weights[2] = 2000; // 20% LINK

        // Deploy vault
        vm.prank(admin);
        vault = new IndexVault(admin, "Fortuna Index", "FCI", tokens, weights);
        indexToken = vault.indexToken();

        // Grant manager role
        vm.prank(admin);
        vault.grantRole(MANAGER_ROLE, manager);

        // Mint tokens to users for testing
        weth.mint(user, 1000e18);
        wbtc.mint(user, 100e8);
        link.mint(user, 10000e18);

        weth.mint(user2, 1000e18);
        wbtc.mint(user2, 100e8);
        link.mint(user2, 10000e18);

        // Approve vault for user
        vm.startPrank(user);
        weth.approve(address(vault), type(uint256).max);
        wbtc.approve(address(vault), type(uint256).max);
        link.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Approve vault for user2
        vm.startPrank(user2);
        weth.approve(address(vault), type(uint256).max);
        wbtc.approve(address(vault), type(uint256).max);
        link.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_IndexTokenDeployed() public view {
        assertTrue(address(indexToken) != address(0));
        assertEq(indexToken.name(), "Fortuna Index");
        assertEq(indexToken.symbol(), "FCI");
    }

    function test_Deployment_VaultHasMinterRole() public view {
        bytes32 minterRole = indexToken.MINTER_ROLE();
        assertTrue(indexToken.hasRole(minterRole, address(vault)));
    }

    function test_Deployment_AdminHasRoles() public view {
        assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(vault.hasRole(MANAGER_ROLE, admin));
    }

    function test_Deployment_ConstituentsSet() public view {
        assertEq(vault.numConstituents(), 3);

        (address[] memory tokens, uint16[] memory weights) = vault.getConstituents();
        assertEq(tokens[0], address(weth));
        assertEq(tokens[1], address(wbtc));
        assertEq(tokens[2], address(link));
        assertEq(weights[0], 5000);
        assertEq(weights[1], 3000);
        assertEq(weights[2], 2000);
    }

    function test_RevertWhen_DeployWithMismatchedArrays() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);

        uint16[] memory weights = new uint16[](3);
        weights[0] = 5000;
        weights[1] = 3000;
        weights[2] = 2000;

        vm.expectRevert(IndexVault.LengthMismatch.selector);
        new IndexVault(admin, "Test", "TST", tokens, weights);
    }

    function test_RevertWhen_DeployWithNoConstituents() public {
        address[] memory tokens = new address[](0);
        uint16[] memory weights = new uint16[](0);

        vm.expectRevert(IndexVault.NoConstituents.selector);
        new IndexVault(admin, "Test", "TST", tokens, weights);
    }

    function test_RevertWhen_DeployWithIncompleteWeights() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);

        uint16[] memory weights = new uint16[](2);
        weights[0] = 5000;
        weights[1] = 3000; // Only 80%, not 100%

        vm.expectRevert(IndexVault.WeightsNotComplete.selector);
        new IndexVault(admin, "Test", "TST", tokens, weights);
    }

    function test_RevertWhen_DeployWithZeroAddress() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(0);

        uint16[] memory weights = new uint16[](2);
        weights[0] = 5000;
        weights[1] = 5000;

        vm.expectRevert(IndexVault.ZeroAddress.selector);
        new IndexVault(admin, "Test", "TST", tokens, weights);
    }

    function test_RevertWhen_DeployWithZeroWeight() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);

        uint16[] memory weights = new uint16[](2);
        weights[0] = 10000;
        weights[1] = 0;

        vm.expectRevert(IndexVault.ZeroWeight.selector);
        new IndexVault(admin, "Test", "TST", tokens, weights);
    }

    /*//////////////////////////////////////////////////////////////
                           FIRST MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FirstMint_Success() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;  // 100 WETH
        amounts[1] = 10e8;    // 10 WBTC
        amounts[2] = 1000e18; // 1000 LINK

        vm.prank(user);
        uint256 shares = vault.mint(amounts);

        // First mint always returns 1e18 shares
        assertEq(shares, 1e18);
        assertEq(indexToken.balanceOf(user), 1e18);
        assertEq(indexToken.totalSupply(), 1e18);

        // Verify vault received tokens
        assertEq(weth.balanceOf(address(vault)), 100e18);
        assertEq(wbtc.balanceOf(address(vault)), 10e8);
        assertEq(link.balanceOf(address(vault)), 1000e18);
    }

    function test_FirstMint_EmitsMintedEvent() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit Minted(user, 1e18, amounts);
        vault.mint(amounts);
    }

    function test_RevertWhen_MintWithWrongArrayLength() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 10e8;

        vm.prank(user);
        vm.expectRevert(IndexVault.BadAmountsLength.selector);
        vault.mint(amounts);
    }

    /*//////////////////////////////////////////////////////////////
                        SUBSEQUENT MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SubsequentMint_ProRata() public {
        // First mint to seed vault
        uint256[] memory firstAmounts = new uint256[](3);
        firstAmounts[0] = 100e18;
        firstAmounts[1] = 10e8;
        firstAmounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(firstAmounts);

        // Second mint - deposit same proportion
        uint256[] memory secondAmounts = new uint256[](3);
        secondAmounts[0] = 100e18;  // Same as first
        secondAmounts[1] = 10e8;
        secondAmounts[2] = 1000e18;

        vm.prank(user2);
        uint256 shares = vault.mint(secondAmounts);

        // Should get exactly 1e18 shares (same proportion)
        assertEq(shares, 1e18);
        assertEq(indexToken.balanceOf(user2), 1e18);
        assertEq(indexToken.totalSupply(), 2e18);
    }

    function test_SubsequentMint_LimitedByTightestRatio() public {
        // First mint
        uint256[] memory firstAmounts = new uint256[](3);
        firstAmounts[0] = 100e18;
        firstAmounts[1] = 10e8;
        firstAmounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(firstAmounts);

        // Second mint - deposit half of first for all
        uint256[] memory secondAmounts = new uint256[](3);
        secondAmounts[0] = 50e18;  // 50% of vault
        secondAmounts[1] = 5e8;    // 50% of vault
        secondAmounts[2] = 500e18; // 50% of vault

        vm.prank(user2);
        uint256 shares = vault.mint(secondAmounts);

        // Should get 0.5e18 shares (half of supply)
        assertEq(shares, 0.5e18);
    }

    function test_SubsequentMint_TightestRatioWins() public {
        // First mint
        uint256[] memory firstAmounts = new uint256[](3);
        firstAmounts[0] = 100e18;
        firstAmounts[1] = 10e8;
        firstAmounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(firstAmounts);

        // Second mint - unbalanced deposit
        uint256[] memory secondAmounts = new uint256[](3);
        secondAmounts[0] = 100e18;  // 100% ratio
        secondAmounts[1] = 5e8;     // 50% ratio <- this is the limiting factor
        secondAmounts[2] = 1000e18; // 100% ratio

        vm.prank(user2);
        uint256 shares = vault.mint(secondAmounts);

        // Should get 0.5e18 shares (limited by WBTC ratio)
        assertEq(shares, 0.5e18);
    }

    function test_RevertWhen_MintWithZeroShares() public {
        // First mint
        uint256[] memory firstAmounts = new uint256[](3);
        firstAmounts[0] = 100e18;
        firstAmounts[1] = 10e8;
        firstAmounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(firstAmounts);

        // Try to mint with extremely small amounts
        uint256[] memory tinyAmounts = new uint256[](3);
        tinyAmounts[0] = 0;
        tinyAmounts[1] = 0;
        tinyAmounts[2] = 0;

        vm.prank(user2);
        vm.expectRevert(IndexVault.ZeroShares.selector);
        vault.mint(tinyAmounts);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Redeem_FullBalance() public {
        // Mint first
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts);

        // Record balances before redeem
        uint256 wethBefore = weth.balanceOf(user);
        uint256 wbtcBefore = wbtc.balanceOf(user);
        uint256 linkBefore = link.balanceOf(user);

        // Redeem all shares
        vm.prank(user);
        uint256[] memory amountsOut = vault.redeem(1e18);

        // Verify received tokens
        assertEq(amountsOut[0], 100e18);
        assertEq(amountsOut[1], 10e8);
        assertEq(amountsOut[2], 1000e18);

        assertEq(weth.balanceOf(user), wethBefore + 100e18);
        assertEq(wbtc.balanceOf(user), wbtcBefore + 10e8);
        assertEq(link.balanceOf(user), linkBefore + 1000e18);

        // Verify shares burned
        assertEq(indexToken.balanceOf(user), 0);
        assertEq(indexToken.totalSupply(), 0);
    }

    function test_Redeem_PartialBalance() public {
        // Mint first
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts);

        // Redeem half
        vm.prank(user);
        uint256[] memory amountsOut = vault.redeem(0.5e18);

        // Verify received 50% of each
        assertEq(amountsOut[0], 50e18);
        assertEq(amountsOut[1], 5e8);
        assertEq(amountsOut[2], 500e18);

        // Verify shares remaining
        assertEq(indexToken.balanceOf(user), 0.5e18);
    }

    function test_Redeem_MultipleUsers() public {
        // First user mints
        uint256[] memory amounts1 = new uint256[](3);
        amounts1[0] = 100e18;
        amounts1[1] = 10e8;
        amounts1[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts1);

        // Second user mints same amount
        uint256[] memory amounts2 = new uint256[](3);
        amounts2[0] = 100e18;
        amounts2[1] = 10e8;
        amounts2[2] = 1000e18;

        vm.prank(user2);
        vault.mint(amounts2);

        // Verify both have 1e18 shares
        assertEq(indexToken.balanceOf(user), 1e18);
        assertEq(indexToken.balanceOf(user2), 1e18);

        // First user redeems
        vm.prank(user);
        uint256[] memory out1 = vault.redeem(1e18);

        // Should get half of vault (50%)
        assertEq(out1[0], 100e18);
        assertEq(out1[1], 10e8);
        assertEq(out1[2], 1000e18);
    }

    function test_Redeem_EmitsEvent() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts);

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit Redeemed(user, 1e18, amounts);
        vault.redeem(1e18);
    }

    function test_RevertWhen_RedeemZeroShares() public {
        vm.prank(user);
        vm.expectRevert(IndexVault.ZeroShares.selector);
        vault.redeem(0);
    }

    function test_RevertWhen_RedeemWithNoSupply() public {
        vm.prank(user);
        vm.expectRevert(IndexVault.NoSupply.selector);
        vault.redeem(1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_And_Unpause() public {
        vm.prank(manager);
        vault.pause();

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.mint(amounts);

        vm.prank(manager);
        vault.unpause();

        vm.prank(user);
        vault.mint(amounts);
        assertEq(indexToken.balanceOf(user), 1e18);
    }

    function test_RevertWhen_NonManagerPauses() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                MANAGER_ROLE
            )
        );
        vault.pause();
    }

    function test_SetConstituents() public {
        // Create new token
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        address[] memory newTokens = new address[](2);
        newTokens[0] = address(weth);
        newTokens[1] = address(newToken);

        uint16[] memory newWeights = new uint16[](2);
        newWeights[0] = 6000;
        newWeights[1] = 4000;

        vm.prank(manager);
        vault.setConstituents(newTokens, newWeights);

        (address[] memory tokens, uint16[] memory weights) = vault.getConstituents();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(weth));
        assertEq(tokens[1], address(newToken));
        assertEq(weights[0], 6000);
        assertEq(weights[1], 4000);
    }

    function test_RevertWhen_NonManagerSetsConstituents() public {
        address[] memory newTokens = new address[](1);
        newTokens[0] = address(weth);

        uint16[] memory newWeights = new uint16[](1);
        newWeights[0] = 10000;

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                MANAGER_ROLE
            )
        );
        vault.setConstituents(newTokens, newWeights);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_VaultBalances() public {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts);

        uint256[] memory balances = vault.vaultBalances();
        assertEq(balances[0], 100e18);
        assertEq(balances[1], 10e8);
        assertEq(balances[2], 1000e18);
    }

    function test_TotalShares() public {
        assertEq(vault.totalShares(), 0);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts);

        assertEq(vault.totalShares(), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_MintAndRedeem(uint256 wethAmount, uint256 wbtcAmount, uint256 linkAmount) public {
        // Bound to reasonable amounts
        wethAmount = bound(wethAmount, 1e18, 100e18);
        wbtcAmount = bound(wbtcAmount, 1e6, 10e8);
        linkAmount = bound(linkAmount, 100e18, 1000e18);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = wethAmount;
        amounts[1] = wbtcAmount;
        amounts[2] = linkAmount;

        vm.prank(user);
        uint256 shares = vault.mint(amounts);

        assertEq(shares, 1e18); // First mint

        // Redeem all
        vm.prank(user);
        uint256[] memory out = vault.redeem(shares);

        assertEq(out[0], wethAmount);
        assertEq(out[1], wbtcAmount);
        assertEq(out[2], linkAmount);
    }

    function testFuzz_MultipleMintsAndRedeems(uint8 numOps) public {
        numOps = uint8(bound(numOps, 2, 10));

        // First mint
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 10e8;
        amounts[2] = 1000e18;

        vm.prank(user);
        vault.mint(amounts);

        uint256 totalShares = 1e18;

        // Multiple mints by user2
        for (uint8 i = 0; i < numOps; i++) {
            uint256[] memory mintAmounts = new uint256[](3);
            mintAmounts[0] = 10e18;
            mintAmounts[1] = 1e8;
            mintAmounts[2] = 100e18;

            vm.prank(user2);
            uint256 newShares = vault.mint(mintAmounts);
            totalShares += newShares;
        }

        assertEq(vault.totalShares(), totalShares);
    }
}



