"use client";

import { ConnectWallet } from "@/components/ConnectWallet";
import { Dashboard } from "@/components/Dashboard";
import { MintRedeem } from "@/components/MintRedeem";
import { ZapIn } from "@/components/ZapIn";
import { NetworkGuard } from "@/components/NetworkGuard";
import { useAccount } from "wagmi";

export default function Home() {
  const { isConnected } = useAccount();

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-gray-800">
        <div className="max-w-6xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-gradient-to-br from-yellow-400 to-orange-500 rounded-lg flex items-center justify-center font-bold text-black">
              F
            </div>
            <div>
              <h1 className="font-bold text-xl">Fortuna Crypto</h1>
              <p className="text-xs text-gray-400">Index Fund on Base</p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-xs px-2 py-1 bg-blue-900/50 text-blue-400 rounded">
              Base Sepolia
            </span>
            <ConnectWallet />
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-6xl mx-auto px-4 py-8">
        {!isConnected ? (
          <HeroSection />
        ) : (
          <NetworkGuard>
            <div className="space-y-8">
              {/* Dashboard */}
              <Dashboard />

              {/* Action Cards */}
              <div className="grid md:grid-cols-2 gap-6">
                <ZapIn />
                <MintRedeem />
              </div>

              {/* Info Section */}
              <InfoSection />
            </div>
          </NetworkGuard>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-800 mt-16">
        <div className="max-w-6xl mx-auto px-4 py-6 text-center text-gray-500 text-sm">
          <p>Fortuna Crypto Index • Built on Base</p>
          <p className="mt-1">
            <a
              href="https://sepolia.basescan.org/address/0x63a1e4D395079DdF4A26E46464CDDEAe35FdEdFe"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-400 hover:underline"
            >
              View Contracts on Basescan
            </a>
          </p>
        </div>
      </footer>
    </div>
  );
}

function HeroSection() {
  return (
    <div className="text-center py-20">
      <div className="w-24 h-24 bg-gradient-to-br from-yellow-400 to-orange-500 rounded-2xl flex items-center justify-center font-bold text-black text-4xl mx-auto mb-8">
        F
      </div>
      <h2 className="text-4xl font-bold mb-4">
        Diversified Crypto Exposure
        <br />
        <span className="text-transparent bg-clip-text bg-gradient-to-r from-yellow-400 to-orange-500">
          In One Token
        </span>
      </h2>
      <p className="text-gray-400 text-lg max-w-xl mx-auto mb-8">
        Invest in a basket of top crypto assets with a single transaction.
        Fully backed, on-chain, and redeemable anytime.
      </p>

      <div className="grid md:grid-cols-3 gap-6 max-w-3xl mx-auto mt-12">
        <FeatureCard
          title="50% WETH"
          description="Ethereum exposure"
          color="text-blue-400"
        />
        <FeatureCard
          title="30% WBTC"
          description="Bitcoin exposure"
          color="text-orange-400"
        />
        <FeatureCard
          title="20% LINK"
          description="Oracle infrastructure"
          color="text-purple-400"
        />
      </div>

      <p className="text-gray-500 mt-12">Connect your wallet to get started →</p>
    </div>
  );
}

function FeatureCard({
  title,
  description,
  color,
}: {
  title: string;
  description: string;
  color: string;
}) {
  return (
    <div className="bg-gray-800 rounded-xl p-6">
      <div className={`text-2xl font-bold ${color}`}>{title}</div>
      <div className="text-gray-400 text-sm mt-1">{description}</div>
    </div>
  );
}

function InfoSection() {
  return (
    <div className="bg-gray-800/50 rounded-xl p-6">
      <h3 className="font-bold mb-4">How It Works</h3>
      <div className="grid md:grid-cols-3 gap-6 text-sm">
        <div>
          <div className="text-blue-400 font-medium mb-1">1. Zap In</div>
          <p className="text-gray-400">
            Deposit USDC and automatically swap into the index basket. No need to
            buy each token separately.
          </p>
        </div>
        <div>
          <div className="text-green-400 font-medium mb-1">2. Hold FCI</div>
          <p className="text-gray-400">
            Receive FCI tokens representing your share of the index. Transfer or
            hold as you like.
          </p>
        </div>
        <div>
          <div className="text-red-400 font-medium mb-1">3. Redeem</div>
          <p className="text-gray-400">
            Burn your FCI tokens anytime to receive underlying assets
            proportionally.
          </p>
        </div>
      </div>
    </div>
  );
}
