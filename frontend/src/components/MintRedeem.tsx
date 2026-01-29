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
    <div className="bg-gray-800 rounded-xl p-6">
      <div className="flex gap-2 mb-6">
        <button
          onClick={() => setTab("mint")}
          className={`flex-1 py-2 rounded-lg font-medium transition-colors ${
            tab === "mint"
              ? "bg-green-600 text-white"
              : "bg-gray-700 text-gray-400 hover:bg-gray-600"
          }`}
        >
          Mint
        </button>
        <button
          onClick={() => setTab("redeem")}
          className={`flex-1 py-2 rounded-lg font-medium transition-colors ${
            tab === "redeem"
              ? "bg-red-600 text-white"
              : "bg-gray-700 text-gray-400 hover:bg-gray-600"
          }`}
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

  // Check allowances
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

      // Approve WETH
      if (amounts.weth && (!wethAllowance || wethAllowance < parseUnits(amounts.weth, 18))) {
        writeContract({
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
      <p className="text-gray-400 text-sm">
        Deposit tokens to mint index shares. All three tokens are required in proportion.
      </p>

      <div className="space-y-3">
        <TokenInput
          label="WETH"
          value={amounts.weth}
          onChange={(v) => setAmounts({ ...amounts, weth: v })}
          decimals={18}
        />
        <TokenInput
          label="WBTC"
          value={amounts.wbtc}
          onChange={(v) => setAmounts({ ...amounts, wbtc: v })}
          decimals={8}
        />
        <TokenInput
          label="LINK"
          value={amounts.link}
          onChange={(v) => setAmounts({ ...amounts, link: v })}
          decimals={18}
        />
      </div>

      {needsApproval() ? (
        <button
          onClick={approveAll}
          disabled={isApproving}
          className="w-full py-3 bg-yellow-600 hover:bg-yellow-700 disabled:bg-gray-600 rounded-lg font-medium transition-colors"
        >
          {isApproving ? "Approving..." : "Approve Tokens"}
        </button>
      ) : (
        <button
          onClick={handleMint}
          disabled={isPending || isConfirming || !amounts.weth}
          className="w-full py-3 bg-green-600 hover:bg-green-700 disabled:bg-gray-600 rounded-lg font-medium transition-colors"
        >
          {isPending || isConfirming ? "Processing..." : "Mint Index Tokens"}
        </button>
      )}

      {isSuccess && (
        <div className="p-3 bg-green-900/50 border border-green-600 rounded-lg text-green-400 text-sm">
          ✓ Transaction confirmed!
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

  // Get user's index token balance
  const { data: balance } = useReadContract({
    address: CONTRACTS.indexToken,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: [address!],
  });

  const handleRedeem = () => {
    if (!amount) return;
    const sharesIn = parseUnits(amount, 18);

    writeContract({
      address: CONTRACTS.indexVault,
      abi: INDEX_VAULT_ABI,
      functionName: "redeem",
      args: [sharesIn],
    });
  };

  const setMax = () => {
    if (balance) {
      setAmount(formatUnits(balance, 18));
    }
  };

  return (
    <div className="space-y-4">
      <p className="text-gray-400 text-sm">
        Burn index tokens to receive underlying assets proportionally.
      </p>

      <div>
        <div className="flex justify-between text-sm mb-1">
          <span className="text-gray-400">Amount to Redeem</span>
          <button onClick={setMax} className="text-blue-400 hover:text-blue-300">
            Max: {balance ? parseFloat(formatUnits(balance, 18)).toFixed(4) : "0"} FCI
          </button>
        </div>
        <div className="flex">
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.0"
            className="flex-1 bg-gray-700 rounded-l-lg px-4 py-3 outline-none focus:ring-2 focus:ring-red-500"
          />
          <span className="bg-gray-600 px-4 py-3 rounded-r-lg text-gray-400">
            FCI
          </span>
        </div>
      </div>

      <button
        onClick={handleRedeem}
        disabled={isPending || isConfirming || !amount}
        className="w-full py-3 bg-red-600 hover:bg-red-700 disabled:bg-gray-600 rounded-lg font-medium transition-colors"
      >
        {isPending || isConfirming ? "Processing..." : "Redeem"}
      </button>

      {isSuccess && (
        <div className="p-3 bg-green-900/50 border border-green-600 rounded-lg text-green-400 text-sm">
          ✓ Redemption successful! Tokens sent to your wallet.
        </div>
      )}
    </div>
  );
}

function TokenInput({
  label,
  value,
  onChange,
  decimals,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  decimals: number;
}) {
  return (
    <div className="flex">
      <span className="bg-gray-600 px-4 py-3 rounded-l-lg text-gray-400 w-20">
        {label}
      </span>
      <input
        type="number"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder="0.0"
        className="flex-1 bg-gray-700 rounded-r-lg px-4 py-3 outline-none focus:ring-2 focus:ring-blue-500"
      />
    </div>
  );
}
