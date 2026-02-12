"use client";

import { useState } from "react";
import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { CONTRACTS, ERC20_ABI, INDEX_VAULT_ABI } from "@/config/contracts";

type Tab = "mint" | "redeem";

export function MintRedeem() {
  const [tab, setTab] = useState<Tab>("mint");
  const { isConnected } = useAccount();

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
        Mint & Redeem
      </h3>
      <p className="mb-5 text-sm text-[var(--text-muted)]">
        Deposit basket or burn FCI for underlying assets
      </p>
      <div
        className="mb-5 flex gap-1 rounded-xl p-1"
        style={{ background: "var(--bg-elevated)" }}
      >
        <button
          type="button"
          onClick={() => setTab("mint")}
          className={`flex-1 rounded-lg py-2.5 text-sm font-semibold transition ${
            tab === "mint"
              ? "text-black"
              : "text-[var(--text-muted)] hover:text-[var(--text)]"
          }`}
          style={tab === "mint" ? { background: "var(--success)" } : undefined}
        >
          Mint
        </button>
        <button
          type="button"
          onClick={() => setTab("redeem")}
          className={`flex-1 rounded-lg py-2.5 text-sm font-semibold transition ${
            tab === "redeem"
              ? "text-black"
              : "text-[var(--text-muted)] hover:text-[var(--text)]"
          }`}
          style={tab === "redeem" ? { background: "#f87171" } : undefined}
        >
          Redeem
        </button>
      </div>

      {tab === "mint" ? <MintForm /> : <RedeemForm />}
    </div>
  );
}

function MintForm() {
  const { address } = useAccount();
  const [amounts, setAmounts] = useState({ weth: "", wbtc: "", link: "" });
  const [isApproving, setIsApproving] = useState(false);

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const { data: wethAllowance } = useReadContract({
    address: CONTRACTS.weth,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: [address!, CONTRACTS.indexVault],
  });
  const { data: wbtcAllowance } = useReadContract({
    address: CONTRACTS.wbtc,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: [address!, CONTRACTS.indexVault],
  });
  const { data: linkAllowance } = useReadContract({
    address: CONTRACTS.link,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: [address!, CONTRACTS.indexVault],
  });

  const needsApproval = () => {
    const wethAmount = amounts.weth ? parseUnits(amounts.weth, 18) : 0n;
    const wbtcAmount = amounts.wbtc ? parseUnits(amounts.wbtc, 8) : 0n;
    const linkAmount = amounts.link ? parseUnits(amounts.link, 18) : 0n;
    return (
      (wethAmount > 0n && (!wethAllowance || wethAllowance < wethAmount)) ||
      (wbtcAmount > 0n && (!wbtcAllowance || wbtcAllowance < wbtcAmount)) ||
      (linkAmount > 0n && (!linkAllowance || linkAllowance < linkAmount))
    );
  };

  const approveAll = async () => {
    setIsApproving(true);
    try {
      const maxApproval = BigInt(
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      );
      if (amounts.weth && (!wethAllowance || wethAllowance < parseUnits(amounts.weth, 18))) {
        await writeContract({
          address: CONTRACTS.weth,
          abi: ERC20_ABI,
          functionName: "approve",
          args: [CONTRACTS.indexVault, maxApproval],
        });
      }
    } finally {
      setIsApproving(false);
    }
  };

  const handleMint = () => {
    const amountsIn = [
      amounts.weth ? parseUnits(amounts.weth, 18) : 0n,
      amounts.wbtc ? parseUnits(amounts.wbtc, 8) : 0n,
      amounts.link ? parseUnits(amounts.link, 18) : 0n,
    ];
    writeContract({
      address: CONTRACTS.indexVault,
      abi: INDEX_VAULT_ABI,
      functionName: "mint",
      args: [amountsIn],
    });
  };

  return (
    <div className="space-y-4">
      <p className="text-sm text-[var(--text-muted)]">
        Deposit WETH, WBTC, and LINK in proportion to mint FCI.
      </p>

      <div className="space-y-3">
        <TokenInput
          label="WETH"
          value={amounts.weth}
          onChange={(v) => setAmounts({ ...amounts, weth: v })}
        />
        <TokenInput
          label="WBTC"
          value={amounts.wbtc}
          onChange={(v) => setAmounts({ ...amounts, wbtc: v })}
        />
        <TokenInput
          label="LINK"
          value={amounts.link}
          onChange={(v) => setAmounts({ ...amounts, link: v })}
        />
      </div>

      {needsApproval() ? (
        <button
          type="button"
          onClick={approveAll}
          disabled={isApproving}
          className="w-full rounded-xl py-3.5 text-sm font-semibold text-black transition disabled:opacity-50"
          style={{
            background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
            boxShadow: "0 2px 12px rgba(245, 158, 11, 0.3)",
          }}
        >
          {isApproving ? "Approving…" : "Approve tokens"}
        </button>
      ) : (
        <button
          type="button"
          onClick={handleMint}
          disabled={isPending || isConfirming || !amounts.weth}
          className="w-full rounded-xl border border-[var(--border)] py-3.5 text-sm font-semibold text-[var(--text)] transition hover:bg-white/5 disabled:opacity-50"
          style={{ background: "var(--bg-elevated)" }}
        >
          {isPending || isConfirming ? "Processing…" : "Mint FCI"}
        </button>
      )}

      {isSuccess && (
        <div
          className="rounded-xl border p-3 text-sm font-medium text-emerald-400"
          style={{ background: "var(--success-muted)", borderColor: "rgba(16, 185, 129, 0.3)" }}
        >
          ✓ Mint confirmed
        </div>
      )}
    </div>
  );
}

function RedeemForm() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  const { data: balance } = useReadContract({
    address: CONTRACTS.indexToken,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [address!],
  });

  const handleRedeem = () => {
    if (!amount) return;
    writeContract({
      address: CONTRACTS.indexVault,
      abi: INDEX_VAULT_ABI,
      functionName: "redeem",
      args: [parseUnits(amount, 18)],
    });
  };

  return (
    <div className="space-y-4">
      <p className="text-sm text-[var(--text-muted)]">
        Burn FCI to receive underlying WETH, WBTC, and LINK proportionally.
      </p>

      <div>
        <div className="mb-1.5 flex justify-between text-xs">
          <span className="text-[var(--text-dim)]">FCI amount</span>
          <button
            type="button"
            onClick={() => balance && setAmount(formatUnits(balance, 18))}
            className="font-medium text-[var(--accent)] hover:underline"
          >
            Max {balance ? parseFloat(formatUnits(balance, 18)).toFixed(4) : "0"}
          </button>
        </div>
        <div className="flex overflow-hidden rounded-xl border" style={{ borderColor: "var(--border)", background: "var(--bg-input)" }}>
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0"
            className="min-w-0 flex-1 border-0 bg-transparent px-4 py-3 text-[var(--text)] placeholder:text-[var(--text-dim)] focus:ring-2 focus:ring-[var(--accent)]"
          />
          <span className="flex items-center px-4 py-3 text-sm font-medium text-[var(--text-muted)]">
            FCI
          </span>
        </div>
      </div>

      <button
        type="button"
        onClick={handleRedeem}
        disabled={isPending || isConfirming || !amount}
        className="w-full rounded-xl border border-red-500/30 bg-red-500/10 py-3.5 text-sm font-semibold text-red-400 transition hover:bg-red-500/20 disabled:opacity-50"
      >
        {isPending || isConfirming ? "Processing…" : "Redeem"}
      </button>

      {isSuccess && (
        <div
          className="rounded-xl border p-3 text-sm font-medium text-emerald-400"
          style={{ background: "var(--success-muted)", borderColor: "rgba(16, 185, 129, 0.3)" }}
        >
          ✓ Redemption complete. Tokens sent to your wallet.
        </div>
      )}
    </div>
  );
}

function TokenInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  decimals?: number;
}) {
  return (
    <div className="flex overflow-hidden rounded-xl border" style={{ borderColor: "var(--border)", background: "var(--bg-input)" }}>
      <span className="flex w-16 shrink-0 items-center justify-center border-r text-sm font-medium text-[var(--text-muted)]" style={{ borderColor: "var(--border)" }}>
        {label}
      </span>
      <input
        type="number"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="0"
        className="min-w-0 flex-1 border-0 bg-transparent px-4 py-3 text-[var(--text)] placeholder:text-[var(--text-dim)] focus:ring-2 focus:ring-[var(--accent)]"
      />
    </div>
  );
}
