"use client";

import { useAccount, useSwitchChain } from "wagmi";
import { baseSepolia } from "wagmi/chains";

export function NetworkGuard({ children }: { children: React.ReactNode }) {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  const isWrongNetwork =
    isConnected &&
    chainId !== undefined &&
    chainId !== baseSepolia.id;

  if (isWrongNetwork) {
    return (
      <div
        className="rounded-2xl border p-8 text-center md:p-12"
        style={{
          background: "var(--danger-muted)",
          borderColor: "rgba(239, 68, 68, 0.3)",
          boxShadow: "var(--shadow)",
        }}
      >
        <div className="mb-4 text-4xl">⚠️</div>
        <h2
          className="mb-2 text-xl font-semibold text-red-400"
          style={{ fontFamily: "var(--font-syne)" }}
        >
          Wrong network
        </h2>
        <p className="mb-6 max-w-sm mx-auto text-sm leading-relaxed text-[var(--text-muted)]">
          Switch to <strong className="text-[var(--text)]">Base Sepolia</strong> to
          use this app. Current: {chainId} · Required: {baseSepolia.id}
        </p>
        <button
          onClick={() => switchChain({ chainId: baseSepolia.id })}
          disabled={isPending}
          className="rounded-xl px-6 py-3 text-sm font-semibold text-black transition disabled:opacity-50"
          style={{
            background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
            boxShadow: "0 2px 12px rgba(245, 158, 11, 0.3)",
          }}
        >
          {isPending ? "Switching…" : "Switch to Base Sepolia"}
        </button>
        <p className="mt-6 text-xs text-[var(--text-dim)]">
          If the switch fails, add Base Sepolia manually: RPC https://sepolia.base.org · Chain ID 84532
        </p>
      </div>
    );
  }

  return <>{children}</>;
}
