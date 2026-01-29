"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import {
  CONTRACTS,
  ERC20_ABI,
  INDEX_VAULT_ABI,
  TOKEN_INFO,
} from "@/config/contracts";

export function Dashboard() {
  const { address, isConnected } = useAccount();

  // Read user balances
  const { data: balances } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.usdc,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      {
        address: CONTRACTS.weth,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      {
        address: CONTRACTS.wbtc,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      {
        address: CONTRACTS.link,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
      {
        address: CONTRACTS.indexToken,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [address!],
      },
    ],
    query: { enabled: isConnected && !!address },
  });

  // Read vault data
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
      <div className="text-center py-20">
        <h2 className="text-2xl font-bold mb-4">Welcome to Fortuna Crypto</h2>
        <p className="text-gray-400">Connect your wallet to get started</p>
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
    <div className="space-y-8">
      {/* User Balances */}
      <div className="bg-gray-800 rounded-xl p-6">
        <h2 className="text-xl font-bold mb-4">Your Balances</h2>
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
          <BalanceCard
            symbol="USDC"
            balance={formatBalance(balances?.[0], 6)}
            color="text-green-400"
          />
          <BalanceCard
            symbol="WETH"
            balance={formatBalance(balances?.[1], 18)}
            color="text-blue-400"
          />
          <BalanceCard
            symbol="WBTC"
            balance={formatBalance(balances?.[2], 8)}
            color="text-orange-400"
          />
          <BalanceCard
            symbol="LINK"
            balance={formatBalance(balances?.[3], 18)}
            color="text-purple-400"
          />
          <BalanceCard
            symbol="FCI"
            balance={formatBalance(balances?.[4], 18)}
            color="text-yellow-400"
            highlight
          />
        </div>
      </div>

      {/* Vault Stats */}
      <div className="bg-gray-800 rounded-xl p-6">
        <h2 className="text-xl font-bold mb-4">Vault Statistics</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard
            label="Total Shares"
            value={totalShares ? formatUnits(totalShares, 18) : "0"}
            suffix="FCI"
          />
          <StatCard
            label="WETH Holdings"
            value={
              vaultBalances ? formatUnits(vaultBalances[0] || 0n, 18) : "0"
            }
            suffix="WETH"
          />
          <StatCard
            label="WBTC Holdings"
            value={vaultBalances ? formatUnits(vaultBalances[1] || 0n, 8) : "0"}
            suffix="WBTC"
          />
          <StatCard
            label="LINK Holdings"
            value={
              vaultBalances ? formatUnits(vaultBalances[2] || 0n, 18) : "0"
            }
            suffix="LINK"
          />
        </div>
      </div>
    </div>
  );
}

function BalanceCard({
  symbol,
  balance,
  color,
  highlight,
}: {
  symbol: string;
  balance: string;
  color: string;
  highlight?: boolean;
}) {
  return (
    <div
      className={`p-4 rounded-lg ${highlight ? "bg-yellow-900/30 border border-yellow-600" : "bg-gray-700"}`}
    >
      <div className={`text-sm ${color}`}>{symbol}</div>
      <div className="text-xl font-bold">{balance}</div>
    </div>
  );
}

function StatCard({
  label,
  value,
  suffix,
}: {
  label: string;
  value: string;
  suffix: string;
}) {
  return (
    <div className="p-4 bg-gray-700 rounded-lg">
      <div className="text-sm text-gray-400">{label}</div>
      <div className="text-lg font-bold">
        {parseFloat(value).toFixed(4)} <span className="text-sm text-gray-400">{suffix}</span>
      </div>
    </div>
  );
}
