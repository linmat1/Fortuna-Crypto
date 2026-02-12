/**
 * Zap quote layer: build swapTargets, swapCalldata, minTokensOut, expectedAmountsOut
 * for IndexZap.zapIn(). Uses MockDEX on Base Sepolia (testnet) and 0x API on Base mainnet.
 */
import { encodeFunctionData, type Address, type Hex } from "viem";
import { CONTRACTS, MOCK_DEX_ABI } from "@/config/contracts";

const BPS = 10_000;

export type ZapQuote = {
  swapTargets: Address[];
  swapCalldata: Hex[];
  minTokensOut: bigint[];
  expectedAmountsOut: bigint[];
};

/** Chain IDs */
export const CHAIN_ID_BASE_SEPOLIA = 84532;
export const CHAIN_ID_BASE = 8453;

/** 0x API base URL per chain (no Base Sepolia endpoint; use MockDEX there) */
const ZERO_X_API_BASE: Record<number, string> = {
  [CHAIN_ID_BASE]: "https://base.api.0x.org",
};

/**
 * Build zap quote using MockDEX (testnet). Uses on-chain rates and encodes swap calldata.
 */
export function getMockDexZapQuote(
  usdcAmount: bigint,
  tokens: readonly Address[],
  weights: readonly bigint[],
  rates: (bigint | undefined)[],
  slippageBps: number
): ZapQuote {
  const totalWeight = weights.reduce((a, b) => a + Number(b), 0);
  const swapTargets: Address[] = [];
  const swapCalldata: Hex[] = [];
  const minTokensOut: bigint[] = [];
  const expectedAmountsOut: bigint[] = [];

  for (let i = 0; i < tokens.length; i++) {
    const usdcForToken = (usdcAmount * weights[i]) / BigInt(totalWeight);
    const rate = rates[i] ?? 0n;
    const expectedOut = (usdcForToken * rate) / BigInt(1e18);
    const minOut = (expectedOut * BigInt(BPS - slippageBps)) / BigInt(BPS);

    swapTargets.push(CONTRACTS.mockDex);
    swapCalldata.push(
      encodeFunctionData({
        abi: MOCK_DEX_ABI,
        functionName: "swap",
        args: [CONTRACTS.usdc, tokens[i], usdcForToken, minOut],
      })
    );
    minTokensOut.push(minOut);
    expectedAmountsOut.push(expectedOut);
  }

  return { swapTargets, swapCalldata, minTokensOut, expectedAmountsOut };
}

/**
 * Fetch zap quote from 0x API (one quote per constituent). Use on Base mainnet.
 * takerAddress must be the IndexZap so the zap contract receives the bought tokens.
 */
export async function get0xZapQuote(
  usdcAmount: bigint,
  tokens: readonly Address[],
  weights: readonly bigint[],
  indexZapAddress: Address,
  slippageBps: number,
  chainId: number,
  sellTokenAddress: Address = CONTRACTS.usdc
): Promise<ZapQuote> {
  const baseUrl = ZERO_X_API_BASE[chainId];
  if (!baseUrl) throw new Error(`0x API not configured for chain ${chainId}`);

  const totalWeight = weights.reduce((a, b) => a + Number(b), 0);
  const slippageFraction = slippageBps / BPS;
  const swapTargets: Address[] = [];
  const swapCalldata: Hex[] = [];
  const minTokensOut: bigint[] = [];
  const expectedAmountsOut: bigint[] = [];

  for (let i = 0; i < tokens.length; i++) {
    const usdcForToken = (usdcAmount * weights[i]) / BigInt(totalWeight);
    if (usdcForToken === 0n) {
      swapTargets.push("0x0000000000000000000000000000000000000000" as Address);
      swapCalldata.push("0x" as Hex);
      minTokensOut.push(0n);
      expectedAmountsOut.push(0n);
      continue;
    }

    const params = new URLSearchParams({
      sellToken: sellTokenAddress,
      buyToken: tokens[i],
      sellAmount: usdcForToken.toString(),
      takerAddress: indexZapAddress,
      slippagePercentage: slippageFraction.toString(),
    });
    const url = `${baseUrl}/swap/v1/quote?${params.toString()}`;
    const res = await fetch(url);
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`0x quote failed (${tokens[i]}): ${res.status} ${text.slice(0, 200)}`);
    }
    const quote = (await res.json()) as {
      to: string;
      data: string;
      buyAmount?: string;
    };
    const buyAmount = BigInt(quote.buyAmount ?? "0");
    const minOut = (buyAmount * BigInt(BPS - slippageBps)) / BigInt(BPS);

    swapTargets.push(quote.to as Address);
    swapCalldata.push(quote.data as Hex);
    minTokensOut.push(minOut);
    expectedAmountsOut.push(buyAmount);
  }

  return { swapTargets, swapCalldata, minTokensOut, expectedAmountsOut };
}

/**
 * Get zap quote for the current chain: MockDEX on Base Sepolia, 0x on Base mainnet.
 */
export async function getZapQuote(
  usdcAmount: bigint,
  tokens: readonly Address[],
  weights: readonly bigint[],
  indexZapAddress: Address,
  slippageBps: number,
  chainId: number,
  mockDexRates?: (bigint | undefined)[]
): Promise<ZapQuote> {
  if (chainId === CHAIN_ID_BASE_SEPOLIA) {
    if (!mockDexRates || mockDexRates.length < tokens.length)
      throw new Error("MockDEX rates required on Base Sepolia");
    return getMockDexZapQuote(usdcAmount, tokens, weights, mockDexRates, slippageBps);
  }
  if (ZERO_X_API_BASE[chainId]) {
    return get0xZapQuote(usdcAmount, tokens, weights, indexZapAddress, slippageBps, chainId);
  }
  throw new Error(`No quote provider for chain ${chainId}`);
}
