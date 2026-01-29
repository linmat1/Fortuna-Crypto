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
    <div className="bg-gradient-to-r from-purple-900/50 to-blue-900/50 border border-purple-600/50 rounded-xl p-6">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-2xl">🚰</span>
        <h2 className="text-xl font-bold">Testnet Faucet</h2>
      </div>
      <p className="text-gray-400 text-sm mb-4">
        Get free test tokens to try out the protocol
      </p>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <FaucetButton
          label="1,000 USDC"
          color="bg-green-600 hover:bg-green-700"
          onClick={() => mintToken("usdc", "1000", 6)}
          isLoading={isLoading && mintingToken === "usdc"}
          disabled={isLoading}
        />
        <FaucetButton
          label="1 WETH"
          color="bg-blue-600 hover:bg-blue-700"
          onClick={() => mintToken("weth", "1", 18)}
          isLoading={isLoading && mintingToken === "weth"}
          disabled={isLoading}
        />
        <FaucetButton
          label="0.1 WBTC"
          color="bg-orange-600 hover:bg-orange-700"
          onClick={() => mintToken("wbtc", "0.1", 8)}
          isLoading={isLoading && mintingToken === "wbtc"}
          disabled={isLoading}
        />
        <FaucetButton
          label="10 LINK"
          color="bg-purple-600 hover:bg-purple-700"
          onClick={() => mintToken("link", "10", 18)}
          isLoading={isLoading && mintingToken === "link"}
          disabled={isLoading}
        />
      </div>

      {isSuccess && (
        <div className="mt-4 p-3 bg-green-900/50 border border-green-600 rounded-lg text-green-400 text-sm flex items-center justify-between">
          <span>✓ Tokens minted successfully!</span>
          <button
            onClick={() => {
              reset();
              setMintingToken(null);
            }}
            className="text-xs bg-green-800 hover:bg-green-700 px-2 py-1 rounded"
          >
            Dismiss
          </button>
        </div>
      )}
    </div>
  );
}

function FaucetButton({
  label,
  color,
  onClick,
  isLoading,
  disabled,
}: {
  label: string;
  color: string;
  onClick: () => void;
  isLoading: boolean;
  disabled: boolean;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`${color} disabled:bg-gray-600 py-3 px-4 rounded-lg font-medium transition-colors text-sm`}
    >
      {isLoading ? "Minting..." : `Get ${label}`}
    </button>
  );
}
