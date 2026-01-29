/**
 * Configuration for Fortuna Crypto scripts
 * Update these addresses after deployment
 */

// Base Sepolia Testnet (Chain ID: 84532)
export const BASE_SEPOLIA = {
  chainId: 84532,
  rpcUrl: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
  
  // Your deployed contracts
  contracts: {
    indexVault: "0x63a1e4D395079DdF4A26E46464CDDEAe35FdEdFe",
    indexToken: "0x316070F9100Df0A6a2548B8E8777bFdF8B7B518c",
    indexZap: "0x67F9379D1a884FBE08aD7E9f3feb4Ab5491F19b7",
    mockDex: "0x9a7B7D122fF00B82717fcedE719DEE769DB9590c",
  },
  
  // Mock tokens (deployed with your contracts)
  tokens: {
    usdc: "0x3C60d1364F4c572be66f0150F374c820c636D84d",
    weth: "0xDd1A27d7AF147917C199DFcb76daE7732cC24DF2",
    wbtc: "0x10426C4726a7342B0d516f6E96e329E292874231",
    link: "0xe01E03e9D657AeD06B84AfcB50cF0760daE8E96e",
  },
  
  // DEX routers
  dex: {
    // MockDEX for testnet
    mockDex: "0x9a7B7D122fF00B82717fcedE719DEE769DB9590c",
    // 0x doesn't have official Base Sepolia support, so we use MockDEX
  },

  // 0x API (not available on Sepolia, shown for reference)
  zeroXApi: null, // Would be "https://sepolia.api.0x.org" if supported
};

// Base Mainnet (Chain ID: 8453) - For production use
export const BASE_MAINNET = {
  chainId: 8453,
  rpcUrl: process.env.BASE_MAINNET_RPC_URL || "https://mainnet.base.org",
  
  // You would deploy new contracts for mainnet
  contracts: {
    indexVault: null, // Deploy and fill in
    indexToken: null,
    indexZap: null,
  },
  
  // Real tokens on Base
  tokens: {
    usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // USDC on Base
    weth: "0x4200000000000000000000000000000000000006", // WETH on Base
    // Add more as needed
  },
  
  // DEX routers
  dex: {
    zeroXExchangeProxy: "0xDef1C0ded9bec7F1a1670819833240f027b25EfF",
  },

  // 0x API
  zeroXApi: "https://api.0x.org",
};

// Select network based on environment
export const getConfig = (network = "sepolia") => {
  if (network === "mainnet" || network === "base") {
    return BASE_MAINNET;
  }
  return BASE_SEPOLIA;
};

export default BASE_SEPOLIA;
