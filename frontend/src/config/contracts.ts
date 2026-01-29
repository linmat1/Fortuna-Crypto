// Contract addresses on Base Sepolia
export const CONTRACTS = {
  indexVault: "0x63a1e4D395079DdF4A26E46464CDDEAe35FdEdFe" as const,
  indexToken: "0x316070F9100Df0A6a2548B8E8777bFdF8B7B518c" as const,
  indexZap: "0x67F9379D1a884FBE08aD7E9f3feb4Ab5491F19b7" as const,
  mockDex: "0x9a7B7D122fF00B82717fcedE719DEE769DB9590c" as const,
  usdc: "0x3C60d1364F4c572be66f0150F374c820c636D84d" as const,
  weth: "0xDd1A27d7AF147917C199DFcb76daE7732cC24DF2" as const,
  wbtc: "0x10426C4726a7342B0d516f6E96e329E292874231" as const,
  link: "0xe01E03e9D657AeD06B84AfcB50cF0760daE8E96e" as const,
};

export const TOKEN_INFO = {
  [CONTRACTS.usdc]: { symbol: "USDC", decimals: 6 },
  [CONTRACTS.weth]: { symbol: "WETH", decimals: 18 },
  [CONTRACTS.wbtc]: { symbol: "WBTC", decimals: 8 },
  [CONTRACTS.link]: { symbol: "LINK", decimals: 18 },
  [CONTRACTS.indexToken]: { symbol: "FCI", decimals: 18 },
};

// ABIs
export const ERC20_ABI = [
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "decimals",
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "symbol",
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const INDEX_VAULT_ABI = [
  {
    inputs: [],
    name: "getConstituents",
    outputs: [
      { name: "tokens", type: "address[]" },
      { name: "weightsBps", type: "uint16[]" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalShares",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "vaultBalances",
    outputs: [{ name: "bals", type: "uint256[]" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "amountsIn", type: "uint256[]" }],
    name: "mint",
    outputs: [{ name: "sharesOut", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "sharesIn", type: "uint256" }],
    name: "redeem",
    outputs: [{ name: "amountsOut", type: "uint256[]" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "indexToken",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const INDEX_ZAP_ABI = [
  {
    inputs: [
      { name: "usdcAmount", type: "uint256" },
      { name: "swapTargets", type: "address[]" },
      { name: "swapCalldata", type: "bytes[]" },
      { name: "minTokensOut", type: "uint256[]" },
      { name: "minSharesOut", type: "uint256" },
    ],
    name: "zapIn",
    outputs: [{ name: "sharesOut", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "amountsFromSwaps", type: "uint256[]" }],
    name: "previewZap",
    outputs: [{ name: "expectedShares", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export const MOCK_DEX_ABI = [
  {
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
    ],
    name: "rates",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
    ],
    name: "swap",
    outputs: [{ name: "amountOut", type: "uint256" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;
