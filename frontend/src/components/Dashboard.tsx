"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import {
  CONTRACTS,
  ERC20_ABI,
  INDEX_VAULT_ABI,
} from "@/config/contracts";

const TOKENS: Array<{
  key: string;
  symbol: string;
  decimals: number;
  color: string;
  highlight?: boolean;
}> = [
  { key: "usdc", symbol: "USDC", decimals: 6, color: "text-emerald-400" },
  { key: "weth", symbol: "WETH", decimals: 18, color: "text-blue-400" },
  { key: "wbtc", symbol: "WBTC", decimals: 8, color: "text-amber-400" },
  { key: "link", symbol: "LINK", decimals: 18, color: "text-violet-400" },
  { key: "fci", symbol: "FCI", decimals: 18, color: "text-amber-300", highlight: true },
];

export function Dashboard() {
  const { address, isConnected } = useAccount();

  const { data: balances } = useReadContracts({
    contracts: [
      { address: CONTRACTS.usdc, abi: ERC20_ABI, functionName: "balanceOf", args: [address!] },
      { address: CONTRACTS.weth, abi: ERC20_ABI, functionName: "balanceOf", args: [address!] },
      { address: CONTRACTS.wbtc, abi: ERC20_ABI, functionName: "balanceOf", args: [address!] },
      { address: CONTRACTS.link, abi: ERC20_ABI, functionName: "balanceOf", args: [address!] },
      { address: CONTRACTS.indexToken, abi: ERC20_ABI, functionName: "balanceOf", args: [address!] },
    ],
    query: { enabled: isConnected && !!address },
  });

  const { data: totalShares } = useReadContract({
    address: CONTRACTS.indexVault,
    abi: INDEX_VAULT_ABI,
    functionName: "totalShares",
  });

  const { data: vaultBalances } = useReadContract({
    address: CONTRACTS.indexVault,
    abi: INDEX_VAULT_ABI,
    functionName: "vaultBalances",
  });

  if (!isConnected) {
    return (
      <div className="rounded-2xl border py-16 text-center" style={{ background: "var(--bg-card)", borderColor: "var(--border)" }}>
        <p className="text-[var(--text-muted)]">Connect your wallet to see your portfolio</p>
      </div>
    );
  }

  const formatBalance = (
    result: { result?: bigint; status: string } | undefined,
    decimals: number
  ) => {
    if (!result || result.status !== "success" || !result.result) return "0";
    return parseFloat(formatUnits(result.result, decimals)).toFixed(4);
  };

  return (
    <div className="space-y-6">
      <div
        className="rounded-2xl border p-6"
        style={{ background: "var(--bg-card)", borderColor: "var(--border)", boxShadow: "var(--shadow)" }}
      >
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]">
          Your balances
        </h3>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-5">
          {TOKENS.map((t, i) => (
            <div
              key={t.key}
              className={`rounded-xl border p-4 ${
                t.highlight
                  ? "border-amber-500/30 bg-amber-500/5"
                  : ""
              }`}
              style={
                !t.highlight
                  ? { background: "var(--bg-elevated)", borderColor: "var(--border)" }
                  : undefined
              }
            >
              <div className={`text-xs font-medium ${t.color}`}>{t.symbol}</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-[var(--text)]" style={{ fontFamily: "var(--font-syne)" }}>
                {formatBalance(balances?.[i], t.decimals)}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div
        className="rounded-2xl border p-6"
        style={{ background: "var(--bg-card)", borderColor: "var(--border)", boxShadow: "var(--shadow)" }}
      >
        <h3 className="mb-4 text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]">
          Vault statistics
        </h3>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <StatRow
            label="Total supply"
            value={totalShares ? formatUnits(totalShares, 18) : "0"}
            suffix="FCI"
          />
          <StatRow
            label="WETH"
            value={vaultBalances ? formatUnits(vaultBalances[0] ?? 0n, 18) : "0"}
            suffix=""
          />
          <StatRow
            label="WBTC"
            value={vaultBalances ? formatUnits(vaultBalances[1] ?? 0n, 8) : "0"}
            suffix=""
          />
          <StatRow
            label="LINK"
            value={vaultBalances ? formatUnits(vaultBalances[2] ?? 0n, 18) : "0"}
            suffix=""
          />
        </div>
      </div>
    </div>
  );
}

function StatRow({
  label,
  value,
  suffix,
}: {
  label: string;
  value: string;
  suffix: string;
}) {
  return (
    <div className="rounded-xl border p-4" style={{ background: "var(--bg-elevated)", borderColor: "var(--border)" }}>
      <div className="text-xs text-[var(--text-dim)]">{label}</div>
      <div className="mt-1 font-semibold tabular-nums text-[var(--text)]">
        {parseFloat(value).toFixed(4)}
        {suffix && <span className="ml-1 text-sm font-normal text-[var(--text-muted)]">{suffix}</span>}
      </div>
    </div>
  );
}
