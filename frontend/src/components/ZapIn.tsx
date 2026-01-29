"use client";

import { useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { parseUnits, formatUnits, encodeFunctionData } from "viem";
import {
  CONTRACTS,
  ERC20_ABI,
  INDEX_ZAP_ABI,
  MOCK_DEX_ABI,
  INDEX_VAULT_ABI,
} from "@/config/contracts";

export function ZapIn() {
  const { address, isConnected } = useAccount();
  const [usdcAmount, setUsdcAmount] = useState("");
  const [isApproving, setIsApproving] = useState(false);

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  });

  // Get USDC balance
  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [address!],
    query: { enabled: isConnected && !!address },
  });

  // Get USDC allowance for IndexZap
  const { data: usdcAllowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: [address!, CONTRACTS.indexZap],
    query: { enabled: isConnected && !!address },
  });

  // Get vault constituents
  const { data: constituents } = useReadContract({
    address: CONTRACTS.indexVault,
    abi: INDEX_VAULT_ABI,
    functionName: "getConstituents",
  });

  // Get exchange rates from MockDEX
  const { data: rates } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.mockDex,
        abi: MOCK_DEX_ABI,
        functionName: "rates",
        args: [CONTRACTS.usdc, CONTRACTS.weth],
      },
      {
        address: CONTRACTS.mockDex,
        abi: MOCK_DEX_ABI,
        functionName: "rates",
        args: [CONTRACTS.usdc, CONTRACTS.wbtc],
      },
      {
        address: CONTRACTS.mockDex,
        abi: MOCK_DEX_ABI,
        functionName: "rates",
        args: [CONTRACTS.usdc, CONTRACTS.link],
      },
    ],
  });

  if (!isConnected) return null;

  const parsedAmount = usdcAmount ? parseUnits(usdcAmount, 6) : 0n;
  const needsApproval = parsedAmount > 0n && (!usdcAllowance || usdcAllowance < parsedAmount);

  const handleApprove = async () => {
    setIsApproving(true);
    try {
      await writeContract({
        address: CONTRACTS.usdc,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [CONTRACTS.indexZap, BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")],
      });
    } finally {
      setIsApproving(false);
    }
  };

  const handleZap = () => {
    if (!parsedAmount || !constituents || !rates) return;

    const [tokens, weights] = constituents;
    const totalWeight = weights.reduce((a, b) => a + Number(b), 0);

    // Calculate swap amounts and expected outputs
    const swapAmounts: bigint[] = [];
    const expectedOuts: bigint[] = [];

    for (let i = 0; i < tokens.length; i++) {
      const usdcForToken = (parsedAmount * BigInt(weights[i])) / BigInt(totalWeight);
      swapAmounts.push(usdcForToken);

      const rate = rates[i]?.result as bigint || 0n;
      const expectedOut = (usdcForToken * rate) / BigInt(1e18);
      expectedOuts.push(expectedOut);
    }

    // Build swap calldata for MockDEX
    const swapTargets = tokens.map(() => CONTRACTS.mockDex);
    const swapCalldata = tokens.map((token, i) =>
      encodeFunctionData({
        abi: MOCK_DEX_ABI,
        functionName: "swap",
        args: [
          CONTRACTS.usdc,
          token,
          swapAmounts[i],
          (expectedOuts[i] * 95n) / 100n, // 5% slippage
        ],
      })
    );
    const minTokensOut = expectedOuts.map((out) => (out * 95n) / 100n);

    writeContract({
      address: CONTRACTS.indexZap,
      abi: INDEX_ZAP_ABI,
      functionName: "zapIn",
      args: [parsedAmount, swapTargets, swapCalldata, minTokensOut, 0n],
    });
  };

  // Calculate preview
  const getPreview = () => {
    if (!parsedAmount || !rates || !constituents) return null;

    const [, weights] = constituents;
    const totalWeight = weights.reduce((a, b) => a + Number(b), 0);

    const outputs = [];
    for (let i = 0; i < 3; i++) {
      const usdcForToken = (parsedAmount * BigInt(weights[i])) / BigInt(totalWeight);
      const rate = rates[i]?.result as bigint || 0n;
      const expectedOut = (usdcForToken * rate) / BigInt(1e18);
      outputs.push(expectedOut);
    }

    return outputs;
  };

  const preview = getPreview();

  return (
    <div className="bg-gray-800 rounded-xl p-6">
      <h2 className="text-xl font-bold mb-2">Zap In with USDC</h2>
      <p className="text-gray-400 text-sm mb-4">
        Deposit USDC and automatically swap into the index basket
      </p>

      <div className="space-y-4">
        {/* USDC Input */}
        <div>
          <div className="flex justify-between text-sm mb-1">
            <span className="text-gray-400">USDC Amount</span>
            <button
              onClick={() => usdcBalance && setUsdcAmount(formatUnits(usdcBalance, 6))}
              className="text-blue-400 hover:text-blue-300"
            >
              Max: {usdcBalance ? parseFloat(formatUnits(usdcBalance, 6)).toLocaleString() : "0"}
            </button>
          </div>
          <div className="flex">
            <input
              type="number"
              value={usdcAmount}
              onChange={(e) => setUsdcAmount(e.target.value)}
              placeholder="0.0"
              className="flex-1 bg-gray-700 rounded-l-lg px-4 py-3 outline-none focus:ring-2 focus:ring-blue-500 text-lg"
            />
            <span className="bg-gray-600 px-4 py-3 rounded-r-lg text-green-400 font-medium">
              USDC
            </span>
          </div>
        </div>

        {/* Preview */}
        {preview && parsedAmount > 0n && (
          <div className="bg-gray-700/50 rounded-lg p-4 space-y-2">
            <div className="text-sm text-gray-400 mb-2">You will receive approximately:</div>
            <div className="grid grid-cols-3 gap-2 text-sm">
              <div className="bg-gray-700 p-2 rounded">
                <div className="text-blue-400">WETH</div>
                <div>{parseFloat(formatUnits(preview[0], 18)).toFixed(6)}</div>
              </div>
              <div className="bg-gray-700 p-2 rounded">
                <div className="text-orange-400">WBTC</div>
                <div>{parseFloat(formatUnits(preview[1], 8)).toFixed(6)}</div>
              </div>
              <div className="bg-gray-700 p-2 rounded">
                <div className="text-purple-400">LINK</div>
                <div>{parseFloat(formatUnits(preview[2], 18)).toFixed(4)}</div>
              </div>
            </div>
          </div>
        )}

        {/* Action Button */}
        {needsApproval ? (
          <button
            onClick={handleApprove}
            disabled={isApproving || isPending || isConfirming}
            className="w-full py-3 bg-yellow-600 hover:bg-yellow-700 disabled:bg-gray-600 rounded-lg font-medium transition-colors"
          >
            {isApproving || isPending || isConfirming ? "Processing..." : "Approve USDC"}
          </button>
        ) : (
          <button
            onClick={handleZap}
            disabled={isPending || isConfirming || !usdcAmount || parsedAmount === 0n}
            className="w-full py-3 bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 disabled:from-gray-600 disabled:to-gray-600 rounded-lg font-medium transition-all"
          >
            {isPending || isConfirming ? "Processing..." : "Zap In"}
          </button>
        )}

        {/* Success Message */}
        {isSuccess && (
          <div className="p-3 bg-green-900/50 border border-green-600 rounded-lg text-green-400 text-sm">
            ✓ Zap successful! Index tokens have been minted to your wallet.
            <a
              href={`https://sepolia.basescan.org/tx/${hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="block mt-1 text-blue-400 hover:underline"
            >
              View transaction →
            </a>
          </div>
        )}

        {/* Error Message */}
        {error && (
          <div className="p-3 bg-red-900/50 border border-red-600 rounded-lg text-red-400 text-sm">
            Error: {error.message.slice(0, 100)}...
          </div>
        )}
      </div>
    </div>
  );
}
