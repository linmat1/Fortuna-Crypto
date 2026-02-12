"use client";

import { useState, useMemo, useEffect } from "react";
import {
  useAccount,
  useChainId,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import {
  CONTRACTS,
  ERC20_ABI,
  INDEX_ZAP_ABI,
  MOCK_DEX_ABI,
  INDEX_VAULT_ABI,
} from "@/config/contracts";
import {
  getMockDexZapQuote,
  getZapQuote,
  CHAIN_ID_BASE_SEPOLIA,
  type ZapQuote,
} from "@/lib/zapQuote";

const BPS = 10_000;
const SLIPPAGE_OPTIONS = [
  { label: "0.5%", bps: 50 },
  { label: "1%", bps: 100 },
  { label: "3%", bps: 300 },
];

export function ZapIn() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const [usdcAmount, setUsdcAmount] = useState("");
  const [isApproving, setIsApproving] = useState(false);
  const [slippageBps, setSlippageBps] = useState(50);
  const [quote, setQuote] = useState<ZapQuote | null>(null);
  const [quoteLoading, setQuoteLoading] = useState(false);
  const [quoteError, setQuoteError] = useState<string | null>(null);

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [address!],
    query: { enabled: isConnected && !!address },
  });

  const { data: usdcAllowance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: [address!, CONTRACTS.indexZap],
    query: { enabled: isConnected && !!address },
  });

  const { data: constituents } = useReadContract({
    address: CONTRACTS.indexVault,
    abi: INDEX_VAULT_ABI,
    functionName: "getConstituents",
  });

  const { data: ratesResult } = useReadContracts({
    contracts: [
      { address: CONTRACTS.mockDex, abi: MOCK_DEX_ABI, functionName: "rates", args: [CONTRACTS.usdc, CONTRACTS.weth] },
      { address: CONTRACTS.mockDex, abi: MOCK_DEX_ABI, functionName: "rates", args: [CONTRACTS.usdc, CONTRACTS.wbtc] },
      { address: CONTRACTS.mockDex, abi: MOCK_DEX_ABI, functionName: "rates", args: [CONTRACTS.usdc, CONTRACTS.link] },
    ],
  });
  const rates = useMemo(
    () =>
      ratesResult?.map((r) =>
        r.status === "success" ? (r.result as bigint) : undefined
      ) ?? [],
    [ratesResult]
  );

  const parsedAmount = usdcAmount ? parseUnits(usdcAmount, 6) : 0n;
  const hasQuoteInputs =
    parsedAmount > 0n &&
    constituents &&
    constituents[0].length > 0 &&
    (chainId === CHAIN_ID_BASE_SEPOLIA ? rates.length >= constituents[0].length : true);

  useEffect(() => {
    if (!hasQuoteInputs) {
      setQuote(null);
      setQuoteError(null);
      return;
    }
    const [tokens, weights] = constituents!;
    const weightsBigInt = weights.map((w) => BigInt(Number(w)));
    if (chainId === CHAIN_ID_BASE_SEPOLIA) {
      setQuoteError(null);
      try {
        const q = getMockDexZapQuote(
          parsedAmount,
          tokens as `0x${string}`[],
          weightsBigInt,
          rates,
          slippageBps
        );
        setQuote(q);
      } catch (e) {
        setQuoteError(e instanceof Error ? e.message : "Failed to build quote");
        setQuote(null);
      }
      return;
    }
    setQuoteLoading(true);
    setQuoteError(null);
    getZapQuote(
      parsedAmount,
      tokens as `0x${string}`[],
      weightsBigInt,
      CONTRACTS.indexZap,
      slippageBps,
      chainId,
      rates
    )
      .then((q) => {
        setQuote(q);
        setQuoteError(null);
      })
      .catch((e) => {
        setQuoteError(e instanceof Error ? e.message : "Quote failed");
        setQuote(null);
      })
      .finally(() => setQuoteLoading(false));
  }, [parsedAmount, constituents, chainId, slippageBps, hasQuoteInputs, rates]);

  const { data: expectedShares } = useReadContract({
    address: CONTRACTS.indexZap,
    abi: INDEX_ZAP_ABI,
    functionName: "previewZap",
    args: quote ? [quote.expectedAmountsOut] : undefined,
    query: { enabled: !!quote && quote.expectedAmountsOut.length > 0 },
  });

  const minSharesOut =
    expectedShares != null
      ? (expectedShares * BigInt(BPS - slippageBps)) / BigInt(BPS)
      : 0n;

  const needsApproval =
    parsedAmount > 0n && (!usdcAllowance || usdcAllowance < parsedAmount);

  const handleApprove = async () => {
    setIsApproving(true);
    try {
      await writeContract({
        address: CONTRACTS.usdc,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [
          CONTRACTS.indexZap,
          BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
        ],
      });
    } finally {
      setIsApproving(false);
    }
  };

  const handleZap = () => {
    if (!quote || !parsedAmount) return;
    writeContract({
      address: CONTRACTS.indexZap,
      abi: INDEX_ZAP_ABI,
      functionName: "zapIn",
      args: [
        parsedAmount,
        quote.swapTargets,
        quote.swapCalldata,
        quote.minTokensOut,
        minSharesOut,
      ],
    });
  };

  const previewAmounts = quote?.expectedAmountsOut ?? [];

  if (!isConnected) return null;

  return (
    <div
      className="rounded-2xl border p-6"
      style={{
        background: "var(--bg-card)",
        borderColor: "var(--border)",
        boxShadow: "var(--shadow)",
      }}
    >
      <h3 className="mb-1 text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]">
        Zap In
      </h3>
      <p className="mb-5 text-sm text-[var(--text-muted)]">
        Deposit USDC → swap into basket → receive FCI
      </p>

      <div className="space-y-4">
        <div>
          <div className="mb-1.5 flex justify-between text-xs">
            <span className="text-[var(--text-dim)]">Amount</span>
            <button
              type="button"
              onClick={() =>
                usdcBalance && setUsdcAmount(formatUnits(usdcBalance, 6))
              }
              className="font-medium text-[var(--accent)] hover:underline"
            >
              Max {usdcBalance ? parseFloat(formatUnits(usdcBalance, 6)).toLocaleString() : "0"}
            </button>
          </div>
          <div className="flex overflow-hidden rounded-xl border" style={{ borderColor: "var(--border)", background: "var(--bg-input)" }}>
            <input
              type="number"
              value={usdcAmount}
              onChange={(e) => setUsdcAmount(e.target.value)}
              placeholder="0"
              className="min-w-0 flex-1 border-0 bg-transparent px-4 py-3 text-[var(--text)] placeholder:text-[var(--text-dim)] focus:ring-2 focus:ring-[var(--accent)]"
            />
            <span className="flex items-center px-4 py-3 text-sm font-medium text-[var(--text-muted)]">
              USDC
            </span>
          </div>
        </div>

        <div className="flex items-center justify-between gap-3">
          <span className="text-xs text-[var(--text-dim)]">Slippage</span>
          <div className="flex gap-1 rounded-lg p-0.5" style={{ background: "var(--bg-elevated)" }}>
            {SLIPPAGE_OPTIONS.map(({ label, bps }) => (
              <button
                key={bps}
                type="button"
                onClick={() => setSlippageBps(bps)}
                className={`rounded-md px-3 py-1.5 text-xs font-medium transition ${
                  slippageBps === bps
                    ? "text-black"
                    : "text-[var(--text-muted)] hover:text-[var(--text)]"
                }`}
                style={
                  slippageBps === bps
                    ? { background: "var(--accent)" }
                    : undefined
                }
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        {quoteLoading && (
          <p className="text-sm text-[var(--text-dim)]">Getting quote…</p>
        )}
        {quoteError && (
          <div
            className="rounded-xl border p-3 text-sm"
            style={{ background: "var(--warning-muted)", borderColor: "rgba(245, 158, 11, 0.3)" }}
          >
            <span className="text-amber-400">{quoteError}</span>
          </div>
        )}

        {quote && parsedAmount > 0n && !quoteError && (
          <div
            className="rounded-xl border p-4"
            style={{ background: "var(--bg-elevated)", borderColor: "var(--border)" }}
          >
            <p className="mb-3 text-xs text-[var(--text-dim)]">You receive ≈</p>
            <div className="grid grid-cols-3 gap-2 text-sm">
              <div className="rounded-lg px-2 py-2" style={{ background: "var(--bg-input)" }}>
                <div className="text-blue-400">WETH</div>
                <div className="font-medium tabular-nums text-[var(--text)]">
                  {previewAmounts[0] != null
                    ? parseFloat(formatUnits(previewAmounts[0], 18)).toFixed(6)
                    : "0"}
                </div>
              </div>
              <div className="rounded-lg px-2 py-2" style={{ background: "var(--bg-input)" }}>
                <div className="text-amber-400">WBTC</div>
                <div className="font-medium tabular-nums text-[var(--text)]">
                  {previewAmounts[1] != null
                    ? parseFloat(formatUnits(previewAmounts[1], 8)).toFixed(6)
                    : "0"}
                </div>
              </div>
              <div className="rounded-lg px-2 py-2" style={{ background: "var(--bg-input)" }}>
                <div className="text-violet-400">LINK</div>
                <div className="font-medium tabular-nums text-[var(--text)]">
                  {previewAmounts[2] != null
                    ? parseFloat(formatUnits(previewAmounts[2], 18)).toFixed(4)
                    : "0"}
                </div>
              </div>
            </div>
            {expectedShares != null && (
              <div className="mt-3 border-t pt-3" style={{ borderColor: "var(--border)" }}>
                <span className="text-xs text-[var(--text-dim)]">Expected FCI </span>
                <span className="font-semibold tabular-nums text-[var(--text)]">
                  {parseFloat(formatUnits(expectedShares, 18)).toFixed(4)}
                </span>
                <span className="ml-2 text-xs text-[var(--text-dim)]">
                  (min {parseFloat(formatUnits(minSharesOut, 18)).toFixed(4)})
                </span>
              </div>
            )}
          </div>
        )}

        {needsApproval ? (
          <button
            type="button"
            onClick={handleApprove}
            disabled={isApproving || isPending || isConfirming}
            className="w-full rounded-xl py-3.5 text-sm font-semibold text-black transition disabled:opacity-50"
            style={{
              background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
              boxShadow: "0 2px 12px rgba(245, 158, 11, 0.3)",
            }}
          >
            {isApproving || isPending || isConfirming ? "Approving…" : "Approve USDC"}
          </button>
        ) : (
          <button
            type="button"
            onClick={handleZap}
            disabled={
              isPending ||
              isConfirming ||
              !usdcAmount ||
              parsedAmount === 0n ||
              !quote ||
              quoteLoading
            }
            className="w-full rounded-xl border border-[var(--border)] py-3.5 text-sm font-semibold text-[var(--text)] transition hover:bg-white/5 disabled:opacity-50 disabled:hover:bg-transparent"
            style={{ background: "var(--bg-elevated)" }}
          >
            {isPending || isConfirming
              ? "Processing…"
              : quoteLoading
                ? "Getting quote…"
                : "Zap In"}
          </button>
        )}

        {isSuccess && (
          <div
            className="rounded-xl border p-3"
            style={{ background: "var(--success-muted)", borderColor: "rgba(16, 185, 129, 0.3)" }}
          >
            <p className="text-sm font-medium text-emerald-400">✓ Zap successful</p>
            <a
              href={`https://sepolia.basescan.org/tx/${hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-1 block text-xs text-[var(--accent)] hover:underline"
            >
              View on Basescan →
            </a>
          </div>
        )}

        {error && (
          <div
            className="rounded-xl border p-3 text-sm"
            style={{ background: "var(--danger-muted)", borderColor: "rgba(239, 68, 68, 0.3)" }}
          >
            <span className="text-red-400">{error.message.slice(0, 120)}…</span>
          </div>
        )}
      </div>
    </div>
  );
}
