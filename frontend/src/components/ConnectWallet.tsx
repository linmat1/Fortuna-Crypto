"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { baseSepolia } from "wagmi/chains";

export function ConnectWallet() {
  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const isWrongNetwork =
    isConnected && chainId !== undefined && chainId !== baseSepolia.id;

  if (isConnected && isWrongNetwork) {
    return (
      <div className="flex items-center gap-3">
        <span className="text-xs font-medium text-red-400">Wrong network</span>
        <button
          onClick={() => switchChain({ chainId: baseSepolia.id })}
          className="rounded-xl px-4 py-2.5 text-sm font-semibold text-black transition hover:opacity-90"
          style={{
            background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
            boxShadow: "0 2px 8px rgba(245, 158, 11, 0.3)",
          }}
        >
          Switch to Base Sepolia
        </button>
      </div>
    );
  }

  if (isConnected) {
    return (
      <div className="flex items-center gap-2">
        <span
          className="rounded-lg px-3 py-2 text-sm font-medium tabular-nums text-[var(--text-muted)]"
          style={{ background: "var(--bg-elevated)" }}
        >
          {address?.slice(0, 6)}…{address?.slice(-4)}
        </span>
        <button
          onClick={() => disconnect()}
          className="rounded-xl border border-[var(--border)] px-4 py-2.5 text-sm font-medium text-[var(--text-muted)] transition hover:border-red-500/40 hover:bg-red-500/10 hover:text-red-400"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={() => connect({ connector: connectors[0] })}
      className="rounded-xl px-5 py-2.5 text-sm font-semibold text-black transition hover:opacity-90 active:scale-[0.98]"
      style={{
        background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
        boxShadow: "0 2px 12px rgba(245, 158, 11, 0.35)",
      }}
    >
      Connect Wallet
    </button>
  );
}
