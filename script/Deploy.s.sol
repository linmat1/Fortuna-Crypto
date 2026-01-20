// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {IndexZap} from "../src/IndexZap.sol";
import {IndexToken} from "../src/IndexToken.sol";

/**
 * @title Deploy
 * @notice Deployment script for the Fortuna Crypto Index Protocol
 * @dev Deploys IndexVault (which deploys IndexToken) and IndexZap
 *
 * Usage:
 *   # Dry run (simulation)
 *   forge script script/Deploy.s.sol --rpc-url base_sepolia
 *
 *   # Actual deployment
 *   forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
 *
 *   # With specific private key
 *   forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify --private-key $PRIVATE_KEY
 *
 * Environment variables needed:
 *   - BASE_SEPOLIA_RPC_URL: RPC endpoint for Base Sepolia
 *   - BASESCAN_API_KEY: API key for contract verification
 *   - PRIVATE_KEY: Deployer's private key (or use --ledger/--trezor)
 */
contract Deploy is Script {
    // ─────────────────────────────────────────────────────────────────────
    // CONFIGURATION - Modify these for your deployment
    // ─────────────────────────────────────────────────────────────────────

    // Index token metadata
    string constant INDEX_NAME = "Fortuna Crypto Index";
    string constant INDEX_SYMBOL = "FCI";

    // Base Sepolia token addresses (replace with actual addresses)
    // These are placeholder addresses - you'll need real testnet tokens
    address constant WETH = 0x4200000000000000000000000000000000000006; // Wrapped ETH on Base
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC on Base Sepolia

    // For testnet, you may need to deploy mock tokens first
    // See DeployMocks.s.sol for that

    // DEX Aggregator addresses on Base
    // 0x Exchange Proxy on Base: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF
    address constant ZERO_X_EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    // ─────────────────────────────────────────────────────────────────────
    // DEPLOYMENT
    // ─────────────────────────────────────────────────────────────────────

    function run() external {
        // Get deployer from environment or use default
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer;

        if (deployerPrivateKey != 0) {
            deployer = vm.addr(deployerPrivateKey);
            vm.startBroadcast(deployerPrivateKey);
        } else {
            // For simulation/testing without a real key
            deployer = msg.sender;
            vm.startBroadcast();
        }

        console.log("===========================================");
        console.log("  FORTUNA CRYPTO - DEPLOYMENT SCRIPT");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // ─────────────────────────────────────────────────────────────────
        // Step 1: Deploy IndexVault with initial constituents
        // ─────────────────────────────────────────────────────────────────

        console.log("Step 1: Deploying IndexVault...");

        // For a simple testnet deployment, start with just WETH
        // In production, you'd have multiple constituents
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;

        uint16[] memory weights = new uint16[](1);
        weights[0] = 10000; // 100% WETH for simple test

        IndexVault vault = new IndexVault(
            deployer,           // admin
            INDEX_NAME,
            INDEX_SYMBOL,
            tokens,
            weights
        );

        console.log("  IndexVault deployed at:", address(vault));
        console.log("  IndexToken deployed at:", address(vault.indexToken()));

        // ─────────────────────────────────────────────────────────────────
        // Step 2: Deploy IndexZap
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("Step 2: Deploying IndexZap...");

        address[] memory swapTargets = new address[](1);
        swapTargets[0] = ZERO_X_EXCHANGE_PROXY;

        IndexZap zap = new IndexZap(
            USDC,               // input token
            address(vault),     // vault to deposit into
            deployer,           // admin
            swapTargets         // allowed DEX routers
        );

        console.log("  IndexZap deployed at:", address(zap));

        // ─────────────────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("===========================================");
        console.log("  DEPLOYMENT COMPLETE");
        console.log("===========================================");
        console.log("");
        console.log("Contracts deployed:");
        console.log("  IndexVault:", address(vault));
        console.log("  IndexToken:", address(vault.indexToken()));
        console.log("  IndexZap:  ", address(zap));
        console.log("");
        console.log("Configuration:");
        console.log("  Admin:     ", deployer);
        console.log("  USDC:      ", USDC);
        console.log("  WETH:      ", WETH);
        console.log("  0x Router: ", ZERO_X_EXCHANGE_PROXY);
        console.log("");
        console.log("Next steps:");
        console.log("  1. Verify contracts on Basescan");
        console.log("  2. Test mint/redeem with testnet tokens");
        console.log("  3. Add more constituents via setConstituents()");
        console.log("");

        vm.stopBroadcast();
    }
}

/**
 * @title DeployMocks
 * @notice Deploys mock tokens for testnet testing
 * @dev Use this if you need test tokens on Base Sepolia
 *
 * Usage:
 *   forge script script/Deploy.s.sol:DeployMocks --rpc-url base_sepolia --broadcast
 */
contract DeployMocks is Script {
    function run() external {
        vm.startBroadcast();

        console.log("Deploying mock tokens for testing...");

        // Deploy mock USDC
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        console.log("Mock USDC deployed at:", address(usdc));

        // Deploy mock WETH
        MockERC20 weth = new MockERC20("Mock WETH", "WETH", 18);
        console.log("Mock WETH deployed at:", address(weth));

        // Deploy mock WBTC
        MockERC20 wbtc = new MockERC20("Mock WBTC", "WBTC", 8);
        console.log("Mock WBTC deployed at:", address(wbtc));

        // Deploy mock LINK
        MockERC20 link = new MockERC20("Mock LINK", "LINK", 18);
        console.log("Mock LINK deployed at:", address(link));

        // Mint some tokens to deployer for testing
        address deployer = msg.sender;
        usdc.mint(deployer, 1_000_000 * 10**6);    // 1M USDC
        weth.mint(deployer, 1000 * 10**18);         // 1000 WETH
        wbtc.mint(deployer, 100 * 10**8);           // 100 WBTC
        link.mint(deployer, 10000 * 10**18);        // 10000 LINK

        console.log("");
        console.log("Tokens minted to deployer:", deployer);
        console.log("  USDC: 1,000,000");
        console.log("  WETH: 1,000");
        console.log("  WBTC: 100");
        console.log("  LINK: 10,000");

        vm.stopBroadcast();
    }
}

/**
 * @title DeployWithMocks
 * @notice Complete deployment with mock tokens for testnet
 * @dev Deploys everything needed for a full testnet environment
 *
 * Usage:
 *   forge script script/Deploy.s.sol:DeployWithMocks --rpc-url base_sepolia --broadcast
 */
contract DeployWithMocks is Script {
    string constant INDEX_NAME = "Fortuna Crypto Index";
    string constant INDEX_SYMBOL = "FCI";

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;

        console.log("===========================================");
        console.log("  FULL TESTNET DEPLOYMENT WITH MOCKS");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("");

        // ─────────────────────────────────────────────────────────────────
        // Step 1: Deploy mock tokens
        // ─────────────────────────────────────────────────────────────────

        console.log("Step 1: Deploying mock tokens...");

        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 weth = new MockERC20("Mock WETH", "WETH", 18);
        MockERC20 wbtc = new MockERC20("Mock WBTC", "WBTC", 8);
        MockERC20 link = new MockERC20("Mock LINK", "LINK", 18);

        console.log("  USDC:", address(usdc));
        console.log("  WETH:", address(weth));
        console.log("  WBTC:", address(wbtc));
        console.log("  LINK:", address(link));

        // ─────────────────────────────────────────────────────────────────
        // Step 2: Deploy IndexVault with 3 constituents
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("Step 2: Deploying IndexVault...");

        address[] memory tokens = new address[](3);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);
        tokens[2] = address(link);

        uint16[] memory weights = new uint16[](3);
        weights[0] = 5000;  // 50% WETH
        weights[1] = 3000;  // 30% WBTC
        weights[2] = 2000;  // 20% LINK

        IndexVault vault = new IndexVault(
            deployer,
            INDEX_NAME,
            INDEX_SYMBOL,
            tokens,
            weights
        );

        console.log("  IndexVault:", address(vault));
        console.log("  IndexToken:", address(vault.indexToken()));

        // ─────────────────────────────────────────────────────────────────
        // Step 3: Deploy mock DEX for testing
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("Step 3: Deploying MockDEX...");

        MockDEX dex = new MockDEX();

        // Set exchange rates (simplified for testing)
        // 1 USDC = 0.0005 WETH, 0.00003 WBTC, 1 LINK
        dex.setRate(address(usdc), address(weth), 0.5e12);   // USDC -> WETH
        dex.setRate(address(usdc), address(wbtc), 0.3e2);    // USDC -> WBTC
        dex.setRate(address(usdc), address(link), 1e12);     // USDC -> LINK

        console.log("  MockDEX:", address(dex));

        // ─────────────────────────────────────────────────────────────────
        // Step 4: Deploy IndexZap with mock DEX
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("Step 4: Deploying IndexZap...");

        address[] memory swapTargets = new address[](1);
        swapTargets[0] = address(dex);

        IndexZap zap = new IndexZap(
            address(usdc),
            address(vault),
            deployer,
            swapTargets
        );

        console.log("  IndexZap:", address(zap));

        // ─────────────────────────────────────────────────────────────────
        // Step 5: Mint test tokens to deployer
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("Step 5: Minting test tokens...");

        usdc.mint(deployer, 1_000_000 * 10**6);
        weth.mint(deployer, 1000 * 10**18);
        wbtc.mint(deployer, 100 * 10**8);
        link.mint(deployer, 10000 * 10**18);

        console.log("  Minted to deployer");

        // ─────────────────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────────────────

        console.log("");
        console.log("===========================================");
        console.log("  DEPLOYMENT COMPLETE");
        console.log("===========================================");
        console.log("");
        console.log("Mock Tokens:");
        console.log("  USDC:", address(usdc));
        console.log("  WETH:", address(weth));
        console.log("  WBTC:", address(wbtc));
        console.log("  LINK:", address(link));
        console.log("");
        console.log("Protocol:");
        console.log("  IndexVault:", address(vault));
        console.log("  IndexToken:", address(vault.indexToken()));
        console.log("  IndexZap:  ", address(zap));
        console.log("  MockDEX:   ", address(dex));
        console.log("");

        vm.stopBroadcast();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER CONTRACTS (copied here for deployment convenience)
// ─────────────────────────────────────────────────────────────────────────────

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockDEX {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public rates;

    function setRate(address tokenIn, address tokenOut, uint256 rate) external {
        rates[tokenIn][tokenOut] = rate;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        uint256 rate = rates[tokenIn][tokenOut];
        require(rate > 0, "MockDEX: no rate");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        amountOut = (amountIn * rate) / 1e18;
        require(amountOut >= minAmountOut, "MockDEX: slippage");

        MockERC20(tokenOut).mint(msg.sender, amountOut);
    }
}
