/**
 * zapIn.js - Zap USDC into Index Tokens
 * 
 * This script demonstrates the full flow:
 * 1. Get swap quotes (from MockDEX on testnet, 0x on mainnet)
 * 2. Build the transaction data
 * 3. Execute zapIn on IndexZap contract
 * 
 * Usage:
 *   node zapIn.js <usdcAmount>
 *   Example: node zapIn.js 100  (zaps 100 USDC)
 */

import { ethers } from "ethers";
import dotenv from "dotenv";
import { BASE_SEPOLIA, BASE_MAINNET, getConfig } from "./config.js";

dotenv.config({ path: "../.env" });

// ABIs (minimal for what we need)
const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

const INDEX_ZAP_ABI = [
  "function zapIn(uint256 usdcAmount, address[] swapTargets, bytes[] swapCalldata, uint256[] minTokensOut, uint256 minSharesOut) returns (uint256 sharesOut)",
  "function previewZap(uint256[] amountsFromSwaps) view returns (uint256)",
  "function vault() view returns (address)",
];

const INDEX_VAULT_ABI = [
  "function getConstituents() view returns (address[] tokens, uint16[] weightsBps)",
  "function totalShares() view returns (uint256)",
  "function vaultBalances() view returns (uint256[])",
];

const MOCK_DEX_ABI = [
  "function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut) returns (uint256)",
  "function rates(address tokenIn, address tokenOut) view returns (uint256)",
];

/**
 * Fetch quote from 0x API (mainnet only)
 */
async function get0xQuote(config, sellToken, buyToken, sellAmount) {
  if (!config.zeroXApi) {
    throw new Error("0x API not available on this network");
  }

  const params = new URLSearchParams({
    sellToken,
    buyToken,
    sellAmount: sellAmount.toString(),
    // Add your 0x API key here for production
    // affiliateAddress: "YOUR_ADDRESS", // Optional: earn affiliate fees
  });

  const response = await fetch(
    `${config.zeroXApi}/swap/v1/quote?${params}`,
    {
      headers: {
        "0x-api-key": process.env.ZERO_X_API_KEY || "",
      },
    }
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`0x API error: ${error}`);
  }

  return response.json();
}

/**
 * Build swap calldata for MockDEX (testnet)
 */
function buildMockDexCalldata(tokenIn, tokenOut, amountIn, minAmountOut) {
  const iface = new ethers.Interface(MOCK_DEX_ABI);
  return iface.encodeFunctionData("swap", [
    tokenIn,
    tokenOut,
    amountIn,
    minAmountOut,
  ]);
}

/**
 * Get expected outputs from MockDEX
 * Note: The deployed MockDEX doesn't have getAmountOut, so we calculate manually
 */
async function getMockDexQuotes(provider, config, usdcAmount, constituents, weights) {
  const mockDex = new ethers.Contract(
    config.dex.mockDex,
    MOCK_DEX_ABI,
    provider
  );

  const quotes = [];
  const totalWeight = weights.reduce((a, b) => a + Number(b), 0);

  for (let i = 0; i < constituents.length; i++) {
    // Split USDC according to weights
    const usdcForThisToken = (usdcAmount * BigInt(weights[i])) / BigInt(totalWeight);
    
    // Get rate from MockDEX
    const rate = await mockDex.rates(config.tokens.usdc, constituents[i]);
    
    if (rate === 0n) {
      throw new Error(`No exchange rate set for USDC -> ${constituents[i]}`);
    }

    // Calculate expected output: amountOut = amountIn * rate / 1e18
    const expectedOut = (usdcForThisToken * rate) / BigInt(1e18);

    quotes.push({
      tokenIn: config.tokens.usdc,
      tokenOut: constituents[i],
      amountIn: usdcForThisToken,
      expectedOut,
      minOut: (expectedOut * 95n) / 100n, // 5% slippage tolerance
    });
  }

  return quotes;
}

/**
 * Main zapIn function
 */
async function zapIn(usdcAmountHuman) {
  console.log("\n===========================================");
  console.log("  FORTUNA CRYPTO - ZAP IN");
  console.log("===========================================\n");

  // Setup
  const config = getConfig("sepolia"); // Change to "mainnet" for production
  const provider = new ethers.JsonRpcProvider(config.rpcUrl);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

  console.log("Network:", config.chainId === 84532 ? "Base Sepolia" : "Base Mainnet");
  console.log("Wallet:", wallet.address);

  // Get USDC decimals and convert amount
  const usdc = new ethers.Contract(config.tokens.usdc, ERC20_ABI, wallet);
  const usdcDecimals = await usdc.decimals();
  const usdcAmount = ethers.parseUnits(usdcAmountHuman.toString(), usdcDecimals);

  console.log(`\nZapping ${usdcAmountHuman} USDC into index tokens...\n`);

  // Check USDC balance
  const usdcBalance = await usdc.balanceOf(wallet.address);
  console.log(`USDC Balance: ${ethers.formatUnits(usdcBalance, usdcDecimals)}`);
  
  if (usdcBalance < usdcAmount) {
    throw new Error(`Insufficient USDC balance. Have ${ethers.formatUnits(usdcBalance, usdcDecimals)}, need ${usdcAmountHuman}`);
  }

  // Get vault constituents
  const vault = new ethers.Contract(config.contracts.indexVault, INDEX_VAULT_ABI, provider);
  const [constituents, weights] = await vault.getConstituents();
  
  console.log("\nVault Constituents:");
  for (let i = 0; i < constituents.length; i++) {
    console.log(`  ${i + 1}. ${constituents[i]} (${Number(weights[i]) / 100}%)`);
  }

  // Get swap quotes
  console.log("\nGetting swap quotes...");
  let quotes;
  let swapTargets;
  let swapCalldata;
  let minTokensOut;

  if (config.zeroXApi) {
    // Use 0x API (mainnet)
    console.log("Using 0x API for quotes...");
    // TODO: Implement 0x quote fetching for each constituent
    throw new Error("0x mainnet integration - implement when ready for production");
  } else {
    // Use MockDEX (testnet)
    console.log("Using MockDEX for quotes (testnet)...");
    quotes = await getMockDexQuotes(provider, config, usdcAmount, constituents, weights);
    
    swapTargets = quotes.map(() => config.dex.mockDex);
    swapCalldata = quotes.map(q => 
      buildMockDexCalldata(q.tokenIn, q.tokenOut, q.amountIn, q.minOut)
    );
    minTokensOut = quotes.map(q => q.minOut);
  }

  console.log("\nSwap Quotes:");
  for (let i = 0; i < quotes.length; i++) {
    console.log(`  Swap ${i + 1}: ${ethers.formatUnits(quotes[i].amountIn, usdcDecimals)} USDC → ${ethers.formatUnits(quotes[i].expectedOut, 18)} tokens`);
  }

  // Approve USDC to IndexZap
  console.log("\nApproving USDC to IndexZap...");
  const zap = new ethers.Contract(config.contracts.indexZap, INDEX_ZAP_ABI, wallet);
  
  const currentAllowance = await usdc.allowance(wallet.address, config.contracts.indexZap);
  if (currentAllowance < usdcAmount) {
    const approveTx = await usdc.approve(config.contracts.indexZap, ethers.MaxUint256);
    console.log(`  Approval tx: ${approveTx.hash}`);
    await approveTx.wait();
    console.log("  ✓ Approved");
  } else {
    console.log("  ✓ Already approved");
  }

  // Preview expected shares
  const expectedAmounts = quotes.map(q => q.expectedOut);
  const expectedShares = await zap.previewZap(expectedAmounts);
  const minSharesOut = (expectedShares * 95n) / 100n; // 5% slippage

  console.log(`\nExpected shares: ${ethers.formatEther(expectedShares)}`);
  console.log(`Minimum shares (with slippage): ${ethers.formatEther(minSharesOut)}`);

  // Execute zapIn
  console.log("\nExecuting zapIn...");
  const tx = await zap.zapIn(
    usdcAmount,
    swapTargets,
    swapCalldata,
    minTokensOut,
    minSharesOut
  );
  
  console.log(`  Transaction: ${tx.hash}`);
  console.log("  Waiting for confirmation...");
  
  const receipt = await tx.wait();
  console.log(`  ✓ Confirmed in block ${receipt.blockNumber}`);

  // Check final balance
  const indexToken = new ethers.Contract(config.contracts.indexToken, ERC20_ABI, provider);
  const indexBalance = await indexToken.balanceOf(wallet.address);
  
  console.log("\n===========================================");
  console.log("  ZAP COMPLETE!");
  console.log("===========================================");
  console.log(`Index Token Balance: ${ethers.formatEther(indexBalance)} FCI`);
  console.log(`Transaction: https://sepolia.basescan.org/tx/${tx.hash}`);
  console.log("");
}

// Run
const amount = process.argv[2] || "100";
zapIn(amount).catch(console.error);
