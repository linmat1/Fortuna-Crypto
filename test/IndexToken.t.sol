// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IndexToken} from "../src/IndexToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title IndexTokenTest
 * @notice Comprehensive tests for the IndexToken contract
 */
contract IndexTokenTest is Test {
    IndexToken public token;

    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public user = makeAddr("user");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        vm.prank(admin);
        token = new IndexToken("Fortuna Index", "FCI", admin);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment_Name() public view {
        assertEq(token.name(), "Fortuna Index");
    }

    function test_Deployment_Symbol() public view {
        assertEq(token.symbol(), "FCI");
    }

    function test_Deployment_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_Deployment_InitialSupply() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_Deployment_AdminHasAdminRole() public view {
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    function test_Deployment_AdminDoesNotHaveMinterRole() public view {
        assertFalse(token.hasRole(MINTER_ROLE, admin));
    }

    /*//////////////////////////////////////////////////////////////
                          ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GrantMinterRole() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        assertTrue(token.hasRole(MINTER_ROLE, minter));
    }

    function test_RevokeMinterRole() public {
        vm.startPrank(admin);
        token.grantRole(MINTER_ROLE, minter);
        token.revokeRole(MINTER_ROLE, minter);
        vm.stopPrank();

        assertFalse(token.hasRole(MINTER_ROLE, minter));
    }

    function test_RevertWhen_NonAdminGrantsRole() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                DEFAULT_ADMIN_ROLE
            )
        );
        token.grantRole(MINTER_ROLE, minter);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        // Setup: grant minter role
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        // Mint tokens
        vm.prank(minter);
        token.mint(user, 1000e18);

        assertEq(token.balanceOf(user), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_Mint_EmitsTransferEvent() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user, 1000e18);
        token.mint(user, 1000e18);
    }

    function test_Mint_MultipleMints() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.startPrank(minter);
        token.mint(user, 500e18);
        token.mint(user, 300e18);
        token.mint(makeAddr("user2"), 200e18);
        vm.stopPrank();

        assertEq(token.balanceOf(user), 800e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_RevertWhen_NonMinterMints() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                MINTER_ROLE
            )
        );
        token.mint(user, 1000e18);
    }

    function test_RevertWhen_AdminWithoutMinterRoleMints() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                MINTER_ROLE
            )
        );
        token.mint(user, 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                              BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn_Success() public {
        // Setup: grant minter role and mint tokens
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        // Burn tokens
        vm.prank(minter);
        token.burn(user, 400e18);

        assertEq(token.balanceOf(user), 600e18);
        assertEq(token.totalSupply(), 600e18);
    }

    function test_Burn_EmitsTransferEvent() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(0), 400e18);
        token.burn(user, 400e18);
    }

    function test_Burn_EntireBalance() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        vm.prank(minter);
        token.burn(user, 1000e18);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_RevertWhen_NonMinterBurns() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                MINTER_ROLE
            )
        );
        token.burn(user, 500e18);
    }

    function test_RevertWhen_BurnExceedsBalance() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        vm.prank(minter);
        vm.expectRevert(); // ERC20InsufficientBalance
        token.burn(user, 1001e18);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount < type(uint128).max);

        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testFuzz_MintAndBurn(address to, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(to != address(0));
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(burnAmount <= mintAmount);

        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(to, mintAmount);

        vm.prank(minter);
        token.burn(to, burnAmount);

        assertEq(token.balanceOf(to), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 BASIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        address recipient = makeAddr("recipient");
        vm.prank(user);
        token.transfer(recipient, 300e18);

        assertEq(token.balanceOf(user), 700e18);
        assertEq(token.balanceOf(recipient), 300e18);
    }

    function test_Approve_And_TransferFrom() public {
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, minter);

        vm.prank(minter);
        token.mint(user, 1000e18);

        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");

        vm.prank(user);
        token.approve(spender, 500e18);

        vm.prank(spender);
        token.transferFrom(user, recipient, 300e18);

        assertEq(token.balanceOf(user), 700e18);
        assertEq(token.balanceOf(recipient), 300e18);
        assertEq(token.allowance(user, spender), 200e18);
    }
}


