"use client";

import { useAccount, useSwitchChain } from "wagmi";
import { baseSepolia } from "wagmi/chains";

export function NetworkGuard({ children }: { children: React.ReactNode }) {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  // Only show wrong network if we're connected AND have a chainId AND it's wrong
  const isWrongNetwork = isConnected && chainId !== undefined && chainId !== baseSepolia.id;

  if (isWrongNetwork) {
    return (
      <div className="bg-red-900/50 border border-red-600 rounded-xl p-8 text-center">
        <div className="text-4xl mb-4">⚠️</div>
        <h2 className="text-xl font-bold text-red-400 mb-2">Wrong Network</h2>
        <p className="text-gray-400 mb-4">
          Please switch to <strong>Base Sepolia</strong> to use this app.
          <br />
          <span className="text-sm">
            Current chain ID: {chainId} | Required: {baseSepolia.id}
          </span>
        </p>
        <button
          onClick={() => switchChain({ chainId: baseSepolia.id })}
          disabled={isPending}
          className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 rounded-lg font-medium transition-colors"
        >
          {isPending ? "Switching..." : "Switch to Base Sepolia"}
        </button>
        <p className="text-xs text-gray-500 mt-4">
          If the switch doesn&apos;t work, manually add Base Sepolia:
          <br />
          RPC: https://sepolia.base.org | Chain ID: 84532
        </p>
      </div>
    );
  }

  return <>{children}</>;
}
