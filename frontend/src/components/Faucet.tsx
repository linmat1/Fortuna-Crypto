"use client";

import { useState } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits } from "viem";
import { CONTRACTS } from "@/config/contracts";

const MOCK_ERC20_ABI = [
  {
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "mint",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const FAUCET_OPTIONS = [
  { token: "usdc" as const, label: "1,000 USDC", amount: "1000", decimals: 6, color: "emerald" },
  { token: "weth" as const, label: "1 WETH", amount: "1", decimals: 18, color: "blue" },
  { token: "wbtc" as const, label: "0.1 WBTC", amount: "0.1", decimals: 8, color: "amber" },
  { token: "link" as const, label: "10 LINK", amount: "10", decimals: 18, color: "violet" },
];

export function Faucet() {
  const { address, isConnected } = useAccount();
  const [mintingToken, setMintingToken] = useState<string | null>(null);

  const { writeContract, data: hash, isPending, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  if (!isConnected) return null;

  const mintToken = (
    token: "usdc" | "weth" | "wbtc" | "link",
    amount: string,
    decimals: number
  ) => {
    setMintingToken(token);
    const tokenAddress = {
      usdc: CONTRACTS.usdc,
      weth: CONTRACTS.weth,
      wbtc: CONTRACTS.wbtc,
      link: CONTRACTS.link,
    }[token];
    writeContract({
      address: tokenAddress,
      abi: MOCK_ERC20_ABI,
      functionName: "mint",
      args: [address!, parseUnits(amount, decimals)],
    });
  };

  const isLoading = isPending || isConfirming;

  return (
    <div
      className="rounded-2xl border p-6"
      style={{
        background: "var(--bg-card)",
        borderColor: "var(--border)",
        boxShadow: "var(--shadow)",
      }}
    >
      <div className="mb-1 flex items-center gap-2">
        <span className="text-lg">🚰</span>
        <h3 className="text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]">
          Testnet faucet
        </h3>
      </div>
      <p className="mb-4 text-sm text-[var(--text-muted)]">
        Get free test tokens to try the protocol
      </p>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {FAUCET_OPTIONS.map((opt) => (
          <button
            key={opt.token}
            onClick={() => mintToken(opt.token, opt.amount, opt.decimals)}
            disabled={isLoading}
            className="rounded-xl border border-[var(--border)] px-4 py-3 text-sm font-medium text-[var(--text)] transition hover:bg-white/5 disabled:opacity-50"
            style={{ background: "var(--bg-elevated)" }}
          >
            {isLoading && mintingToken === opt.token ? "Minting…" : `Get ${opt.label}`}
          </button>
        ))}
      </div>

      {isSuccess && (
        <div
          className="mt-4 flex items-center justify-between rounded-xl border p-3"
          style={{
            background: "var(--success-muted)",
            borderColor: "rgba(16, 185, 129, 0.3)",
          }}
        >
          <span className="text-sm font-medium text-emerald-400">✓ Tokens minted</span>
          <button
            onClick={() => {
              reset();
              setMintingToken(null);
            }}
            className="rounded-lg px-2 py-1 text-xs font-medium text-[var(--text-muted)] hover:bg-white/5"
          >
            Dismiss
          </button>
        </div>
      )}
    </div>
  );
}
