// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexZap} from "../src/IndexZap.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {IndexToken} from "../src/IndexToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockDEX} from "./mocks/MockDEX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title IndexZapTest
 * @notice Comprehensive tests for the IndexZap contract
 */
contract IndexZapTest is Test {
    IndexZap public zap;
    IndexVault public vault;
    IndexToken public indexToken;
    MockDEX public dex;

    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;
    MockERC20 public link;

    address public admin = makeAddr("admin");
    address public manager = makeAddr("manager");
    address public user = makeAddr("user");

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    // Exchange rates: output per input, scaled by 1e18
    // Formula: amountOut = amountIn * rate / 1e18
    //
    // USDC (6 dec) -> WETH (18 dec): 1 USDC = 0.0005 WETH
    // For 500e6 USDC -> 0.25e18 WETH: rate = 0.25e18 * 1e18 / 500e6 = 0.5e12
    //
    // USDC (6 dec) -> WBTC (8 dec): 1 USDC = 0.0001 WBTC
    // For 300e6 USDC -> 0.03e8 WBTC: rate = 0.03e8 * 1e18 / 300e6 = 1e16
    //
    // USDC (6 dec) -> LINK (18 dec): 1 USDC = 1 LINK
    // For 200e6 USDC -> 200e18 LINK: rate = 200e18 * 1e18 / 200e6 = 1e30
    uint256 constant WETH_RATE = 0.5e12;   // 0.0005 WETH per 1 USDC
    uint256 constant WBTC_RATE = 1e16;     // 0.0001 WBTC per 1 USDC  
    uint256 constant LINK_RATE = 1e30;     // 1 LINK per 1 USDC

    event ZappedIn(address indexed user, uint256 usdcIn, uint256 sharesOut);
    event SwapTargetUpdated(address indexed target, bool allowed);

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        link = new MockERC20("Chainlink", "LINK", 18);

        // Deploy mock DEX
        dex = new MockDEX();

        // Set exchange rates on DEX
        dex.setRate(address(usdc), address(weth), WETH_RATE);
        dex.setRate(address(usdc), address(wbtc), WBTC_RATE);
        dex.setRate(address(usdc), address(link), LINK_RATE);

        // Setup vault constituents
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

        // Deploy zap with DEX in allowlist
        address[] memory swapTargets = new address[](1);
        swapTargets[0] = address(dex);

        vm.prank(admin);
        zap = new IndexZap(address(usdc), address(vault), admin, swapTargets);

        // Grant manager role
        vm.prank(admin);
        zap.grantRole(MANAGER_ROLE, manager);

        // Mint USDC to user
        usdc.mint(user, 1_000_000e6); // 1M USDC

        // Approve zap to spend user's USDC
        vm.prank(user);
        usdc.approve(address(zap), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_USDCSet() public view {
        assertEq(address(zap.usdc()), address(usdc));
    }

    function test_Deployment_VaultSet() public view {
        assertEq(address(zap.vault()), address(vault));
    }

    function test_Deployment_IndexTokenSet() public view {
        assertEq(address(zap.indexToken()), address(indexToken));
    }

    function test_Deployment_SwapTargetAllowed() public view {
        assertTrue(zap.allowedSwapTargets(address(dex)));
    }

    function test_Deployment_AdminHasRoles() public view {
        assertTrue(zap.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(zap.hasRole(MANAGER_ROLE, admin));
    }

    function test_RevertWhen_DeployWithZeroAddress() public {
        address[] memory swapTargets = new address[](0);

        vm.expectRevert(IndexZap.ZeroAddress.selector);
        new IndexZap(address(0), address(vault), admin, swapTargets);

        vm.expectRevert(IndexZap.ZeroAddress.selector);
        new IndexZap(address(usdc), address(0), admin, swapTargets);

        vm.expectRevert(IndexZap.ZeroAddress.selector);
        new IndexZap(address(usdc), address(vault), address(0), swapTargets);
    }

    /*//////////////////////////////////////////////////////////////
                            ZAP IN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ZapIn_FirstMint() public {
        uint256 usdcAmount = 1000e6; // 1000 USDC

        // Build swap params
        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
            uint256[] memory expectedOut
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        uint256 shares = zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        // First mint should return 1e18 shares
        assertEq(shares, 1e18);
        assertEq(indexToken.balanceOf(user), 1e18);

        // Verify vault received tokens
        assertEq(weth.balanceOf(address(vault)), expectedOut[0]);
        assertEq(wbtc.balanceOf(address(vault)), expectedOut[1]);
        assertEq(link.balanceOf(address(vault)), expectedOut[2]);
    }

    function test_ZapIn_EmitsEvent() public {
        uint256 usdcAmount = 1000e6;

        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit ZappedIn(user, usdcAmount, 1e18);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);
    }

    function test_ZapIn_UserReceivesShares() public {
        uint256 usdcBefore = usdc.balanceOf(user);
        uint256 usdcAmount = 1000e6;

        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        // User should have spent USDC and received index tokens
        assertEq(usdc.balanceOf(user), usdcBefore - usdcAmount);
        assertEq(indexToken.balanceOf(user), 1e18);
    }

    function test_ZapIn_SubsequentMint() public {
        uint256 usdcAmount = 1000e6;

        // First zap
        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        // Second zap - same amount should give same shares
        (swapTargets, swapCalldata, minTokensOut,) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        uint256 shares2 = zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        // Should get ~1e18 shares (proportional)
        assertEq(shares2, 1e18);
        assertEq(indexToken.balanceOf(user), 2e18);
    }

    /*//////////////////////////////////////////////////////////////
                        SLIPPAGE PROTECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_SwapOutputBelowMinimum() public {
        uint256 usdcAmount = 1000e6;

        // Set 10% slippage on DEX
        dex.setSlippage(1000);

        // Build params expecting full output (no slippage tolerance)
        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            ,
            uint256[] memory expectedOut
        ) = _buildSwapParams(usdcAmount);

        // Set minimum to expected (without accounting for slippage)
        uint256[] memory minTokensOut = new uint256[](3);
        minTokensOut[0] = expectedOut[0]; // Will fail - DEX returns 10% less
        minTokensOut[1] = expectedOut[1];
        minTokensOut[2] = expectedOut[2];

        uint256 actualOut = (expectedOut[0] * 9000) / 10000;

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IndexZap.InsufficientSwapOutput.selector, 0, expectedOut[0], actualOut)
        );
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);
    }

    function test_ZapIn_WithSlippageTolerance() public {
        uint256 usdcAmount = 1000e6;

        // Set 5% slippage on DEX
        dex.setSlippage(500);

        // Build params with 10% slippage tolerance
        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            ,
            uint256[] memory expectedOut
        ) = _buildSwapParams(usdcAmount);

        // Set minimums 10% below expected
        uint256[] memory minTokensOut = new uint256[](3);
        minTokensOut[0] = (expectedOut[0] * 9000) / 10000;
        minTokensOut[1] = (expectedOut[1] * 9000) / 10000;
        minTokensOut[2] = (expectedOut[2] * 9000) / 10000;

        vm.prank(user);
        uint256 shares = zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        // Should succeed despite slippage
        assertEq(shares, 1e18);
    }

    function test_RevertWhen_SharesOutputBelowMinimum() public {
        uint256 usdcAmount = 1000e6;

        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        // Set unrealistic minimum shares expectation
        uint256 minSharesOut = 100e18; // Way more than possible

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IndexZap.InsufficientSharesOut.selector, minSharesOut, 1e18)
        );
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, minSharesOut);
    }

    /*//////////////////////////////////////////////////////////////
                        SWAP TARGET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_SwapTargetNotAllowed() public {
        uint256 usdcAmount = 1000e6;
        address maliciousDex = makeAddr("malicious");

        address[] memory swapTargets = new address[](3);
        swapTargets[0] = maliciousDex; // Not in allowlist
        swapTargets[1] = address(dex);
        swapTargets[2] = address(dex);

        bytes[] memory swapCalldata = new bytes[](3);
        swapCalldata[0] = "";
        swapCalldata[1] = "";
        swapCalldata[2] = "";

        uint256[] memory minTokensOut = new uint256[](3);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IndexZap.SwapTargetNotAllowed.selector, maliciousDex)
        );
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);
    }

    function test_SetSwapTarget() public {
        address newDex = makeAddr("newDex");

        vm.prank(manager);
        vm.expectEmit(true, false, false, true);
        emit SwapTargetUpdated(newDex, true);
        zap.setSwapTarget(newDex, true);

        assertTrue(zap.allowedSwapTargets(newDex));

        vm.prank(manager);
        zap.setSwapTarget(newDex, false);

        assertFalse(zap.allowedSwapTargets(newDex));
    }

    function test_RevertWhen_NonManagerSetsSwapTarget() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                MANAGER_ROLE
            )
        );
        zap.setSwapTarget(makeAddr("dex"), true);
    }

    /*//////////////////////////////////////////////////////////////
                          VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ZapWithZeroAmount() public {
        address[] memory swapTargets = new address[](3);
        bytes[] memory swapCalldata = new bytes[](3);
        uint256[] memory minTokensOut = new uint256[](3);

        vm.prank(user);
        vm.expectRevert(IndexZap.ZeroAmount.selector);
        zap.zapIn(0, swapTargets, swapCalldata, minTokensOut, 0);
    }

    function test_RevertWhen_ArrayLengthMismatch() public {
        uint256 usdcAmount = 1000e6;

        address[] memory swapTargets = new address[](2); // Wrong length
        bytes[] memory swapCalldata = new bytes[](3);
        uint256[] memory minTokensOut = new uint256[](3);

        vm.prank(user);
        vm.expectRevert(IndexZap.ArrayLengthMismatch.selector);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);
    }

    function test_RevertWhen_SwapFails() public {
        uint256 usdcAmount = 1000e6;

        // Make DEX fail
        dex.setShouldFail(true);

        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IndexZap.SwapFailed.selector, 0));
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PauseAndUnpause() public {
        vm.prank(manager);
        zap.pause();

        uint256 usdcAmount = 1000e6;
        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        vm.prank(manager);
        zap.unpause();

        vm.prank(user);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);
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
        zap.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        RESCUE TOKENS TEST
    //////////////////////////////////////////////////////////////*/

    function test_RescueTokens() public {
        // Send some tokens to zap by accident
        usdc.mint(address(zap), 1000e6);

        uint256 adminBalanceBefore = usdc.balanceOf(admin);

        vm.prank(admin);
        zap.rescueTokens(address(usdc), admin, 1000e6);

        assertEq(usdc.balanceOf(admin), adminBalanceBefore + 1000e6);
        assertEq(usdc.balanceOf(address(zap)), 0);
    }

    function test_RevertWhen_NonAdminRescues() public {
        usdc.mint(address(zap), 1000e6);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                DEFAULT_ADMIN_ROLE
            )
        );
        zap.rescueTokens(address(usdc), user, 1000e6);
    }

    /*//////////////////////////////////////////////////////////////
                          PREVIEW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PreviewZap_FirstMint() public view {
        uint256[] memory amountsFromSwaps = new uint256[](3);
        amountsFromSwaps[0] = 100e18;
        amountsFromSwaps[1] = 10e8;
        amountsFromSwaps[2] = 1000e18;

        uint256 expectedShares = zap.previewZap(amountsFromSwaps);
        assertEq(expectedShares, 1e18); // First mint returns 1e18
    }

    function test_PreviewZap_SubsequentMint() public {
        // First, do a real zap to seed the vault
        uint256 usdcAmount = 1000e6;
        (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
        ) = _buildSwapParams(usdcAmount);

        vm.prank(user);
        zap.zapIn(usdcAmount, swapTargets, swapCalldata, minTokensOut, 0);

        // Now preview a second zap with half amounts
        uint256[] memory balances = vault.vaultBalances();
        uint256[] memory amountsFromSwaps = new uint256[](3);
        amountsFromSwaps[0] = balances[0] / 2;
        amountsFromSwaps[1] = balances[1] / 2;
        amountsFromSwaps[2] = balances[2] / 2;

        uint256 expectedShares = zap.previewZap(amountsFromSwaps);
        assertEq(expectedShares, 0.5e18); // Half the current supply
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _buildSwapParams(uint256 usdcAmount)
        internal
        view
        returns (
            address[] memory swapTargets,
            bytes[] memory swapCalldata,
            uint256[] memory minTokensOut,
            uint256[] memory expectedOut
        )
    {
        // Split USDC according to weights: 50%, 30%, 20%
        uint256 usdcForWeth = (usdcAmount * 5000) / 10000;
        uint256 usdcForWbtc = (usdcAmount * 3000) / 10000;
        uint256 usdcForLink = (usdcAmount * 2000) / 10000;

        // Calculate expected outputs using DEX rates
        // amountOut = amountIn * rate / 1e18
        expectedOut = new uint256[](3);
        expectedOut[0] = (usdcForWeth * WETH_RATE) / 1e18;
        expectedOut[1] = (usdcForWbtc * WBTC_RATE) / 1e18;
        expectedOut[2] = (usdcForLink * LINK_RATE) / 1e18;

        swapTargets = new address[](3);
        swapTargets[0] = address(dex);
        swapTargets[1] = address(dex);
        swapTargets[2] = address(dex);

        swapCalldata = new bytes[](3);
        swapCalldata[0] = dex.encodeSwap(address(usdc), address(weth), usdcForWeth, 0);
        swapCalldata[1] = dex.encodeSwap(address(usdc), address(wbtc), usdcForWbtc, 0);
        swapCalldata[2] = dex.encodeSwap(address(usdc), address(link), usdcForLink, 0);

        minTokensOut = new uint256[](3);
        minTokensOut[0] = (expectedOut[0] * 95) / 100; // 5% tolerance
        minTokensOut[1] = (expectedOut[1] * 95) / 100;
        minTokensOut[2] = (expectedOut[2] * 95) / 100;
    }
}
