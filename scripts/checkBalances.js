/**
 * checkBalances.js - Check all token balances
 * 
 * Usage: node checkBalances.js
 */

import { ethers } from "ethers";
import dotenv from "dotenv";
import { BASE_SEPOLIA } from "./config.js";

dotenv.config({ path: "../.env" });

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
];

async function main() {
  const config = BASE_SEPOLIA;
  const provider = new ethers.JsonRpcProvider(config.rpcUrl);
  const wallet = process.env.PRIVATE_KEY 
    ? new ethers.Wallet(process.env.PRIVATE_KEY, provider)
    : null;

  const address = wallet?.address || "0x64003A3e69E5368D981f86Dde191d093ADE4AE30";

  console.log("\n===========================================");
  console.log("  FORTUNA CRYPTO - BALANCE CHECK");
  console.log("===========================================\n");
  console.log("Address:", address);
  console.log("Network: Base Sepolia\n");

  // Check ETH balance
  const ethBalance = await provider.getBalance(address);
  console.log(`ETH:  ${ethers.formatEther(ethBalance)}`);

  // Check token balances
  const tokens = [
    { name: "USDC", address: config.tokens.usdc, decimals: 6 },
    { name: "WETH", address: config.tokens.weth, decimals: 18 },
    { name: "WBTC", address: config.tokens.wbtc, decimals: 8 },
    { name: "LINK", address: config.tokens.link, decimals: 18 },
    { name: "FCI (Index)", address: config.contracts.indexToken, decimals: 18 },
  ];

  console.log("\nToken Balances:");
  for (const token of tokens) {
    const contract = new ethers.Contract(token.address, ERC20_ABI, provider);
    const balance = await contract.balanceOf(address);
    console.log(`${token.name.padEnd(12)}: ${ethers.formatUnits(balance, token.decimals)}`);
  }

  // Check vault status
  console.log("\n--- Vault Status ---");
  const vaultAbi = [
    "function totalShares() view returns (uint256)",
    "function vaultBalances() view returns (uint256[])",
    "function getConstituents() view returns (address[], uint16[])",
  ];
  const vault = new ethers.Contract(config.contracts.indexVault, vaultAbi, provider);
  
  const totalShares = await vault.totalShares();
  console.log(`Total Shares: ${ethers.formatEther(totalShares)} FCI`);

  const balances = await vault.vaultBalances();
  const [constituents] = await vault.getConstituents();
  
  console.log("\nVault Holdings:");
  const tokenNames = ["WETH", "WBTC", "LINK"];
  const tokenDecimals = [18, 8, 18];
  for (let i = 0; i < balances.length; i++) {
    console.log(`  ${tokenNames[i]}: ${ethers.formatUnits(balances[i], tokenDecimals[i])}`);
  }

  console.log("\n===========================================\n");
}

main().catch(console.error);
