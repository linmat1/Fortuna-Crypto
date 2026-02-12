"use client";

import { ConnectWallet } from "@/components/ConnectWallet";
import { Dashboard } from "@/components/Dashboard";
import { MintRedeem } from "@/components/MintRedeem";
import { ZapIn } from "@/components/ZapIn";
import { NetworkGuard } from "@/components/NetworkGuard";
import { Faucet } from "@/components/Faucet";
import { useAccount } from "wagmi";

export default function Home() {
  const { isConnected } = useAccount();

  return (
    <div className="relative z-10 min-h-screen flex flex-col">
      <header className="sticky top-0 z-50 border-b border-[var(--border)] bg-[var(--bg)]/80 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-4 sm:px-6">
          <a href="/" className="flex items-center gap-3">
            <div
              className="flex h-10 w-10 items-center justify-center rounded-xl font-bold text-black"
              style={{
                background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
                boxShadow: "0 2px 12px rgba(245, 158, 11, 0.35)",
              }}
            >
              F
            </div>
            <div>
              <span
                className="block text-lg font-bold tracking-tight"
                style={{ fontFamily: "var(--font-syne)" }}
              >
                Fortuna
              </span>
              <span className="block text-[11px] uppercase tracking-wider text-[var(--text-dim)]">
                Index on Base
              </span>
            </div>
          </a>
          <div className="flex items-center gap-3">
            <span
              className="hidden rounded-full border border-[var(--border)] px-2.5 py-1 text-xs text-[var(--text-muted)] sm:inline-block"
              style={{ background: "var(--bg-elevated)" }}
            >
              Base Sepolia
            </span>
            <ConnectWallet />
          </div>
        </div>
      </header>

      <main className="flex-1 px-4 pb-20 pt-8 sm:px-6 md:pt-12">
        <div className="mx-auto max-w-5xl">
          {!isConnected ? (
            <HeroSection />
          ) : (
            <NetworkGuard>
              <div className="space-y-10 md:space-y-14">
                <section>
                  <h2
                    className="mb-6 text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]"
                    style={{ fontFamily: "var(--font-syne)" }}
                  >
                    Portfolio
                  </h2>
                  <Dashboard />
                </section>

                <section>
                  <h2
                    className="mb-6 text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]"
                    style={{ fontFamily: "var(--font-syne)" }}
                  >
                    Testnet Faucet
                  </h2>
                  <Faucet />
                </section>

                <section>
                  <h2
                    className="mb-6 text-sm font-semibold uppercase tracking-wider text-[var(--text-dim)]"
                    style={{ fontFamily: "var(--font-syne)" }}
                  >
                    Actions
                  </h2>
                  <div className="grid gap-6 lg:grid-cols-2">
                    <ZapIn />
                    <MintRedeem />
                  </div>
                </section>

                <HowItWorks />
              </div>
            </NetworkGuard>
          )}
        </div>
      </main>

      <footer className="mt-auto border-t border-[var(--border)] py-8">
        <div className="mx-auto max-w-5xl px-4 text-center text-sm text-[var(--text-dim)] sm:px-6">
          <p className="font-medium text-[var(--text-muted)]">
            Fortuna Crypto Index · Built on Base
          </p>
          <a
            href="https://sepolia.basescan.org/address/0x63a1e4D395079DdF4A26E46464CDDEAe35FdEdFe"
            target="_blank"
            rel="noopener noreferrer"
            className="mt-2 inline-block text-[var(--accent)] transition hover:text-[var(--accent-hover)]"
          >
            View contracts on Basescan →
          </a>
        </div>
      </footer>
    </div>
  );
}

function HeroSection() {
  return (
    <div className="mx-auto max-w-2xl text-center">
      <div
        className="mb-8 inline-flex h-20 w-20 items-center justify-center rounded-2xl text-3xl font-bold text-black"
        style={{
          background: "linear-gradient(135deg, #f59e0b 0%, #d97706 100%)",
          boxShadow: "0 8px 32px rgba(245, 158, 11, 0.3)",
        }}
      >
        F
      </div>
      <h1
        className="mb-4 text-4xl font-bold leading-tight tracking-tight sm:text-5xl md:text-6xl"
        style={{ fontFamily: "var(--font-syne)" }}
      >
        <span className="text-[var(--text)]">Diversified crypto</span>
        <br />
        <span
          className="bg-clip-text text-transparent"
          style={{
            backgroundImage: "linear-gradient(135deg, #fbbf24 0%, #f59e0b 50%, #d97706 100%)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
          }}
        >
          in one token
        </span>
      </h1>
      <p className="mx-auto mb-12 max-w-lg text-lg leading-relaxed text-[var(--text-muted)]">
        Invest in a basket of top assets with a single transaction. Fully backed,
        on-chain, redeemable anytime.
      </p>

      <div className="mb-14 grid gap-4 sm:grid-cols-3">
        <HeroCard label="50% WETH" sub="Ethereum" color="" borderColor="" />
        <HeroCard label="30% WBTC" sub="Bitcoin" color="" borderColor="" />
        <HeroCard label="20% LINK" sub="Oracle" color="" borderColor="" />
      </div>

      <p className="text-sm text-[var(--text-dim)]">
        Connect your wallet to get started
      </p>
    </div>
  );
}

function HeroCard({
  label,
  sub,
}: {
  label: string;
  sub: string;
  color: string;
  borderColor: string;
}) {
  return (
    <div
      className="rounded-xl border p-5"
      style={{ background: "var(--bg-card)", borderColor: "var(--border)" }}
    >
      <div className="text-2xl font-bold text-[var(--text)]" style={{ fontFamily: "var(--font-syne)" }}>
        {label}
      </div>
      <div className="mt-1 text-sm text-[var(--text-dim)]">{sub}</div>
    </div>
  );
}

function HowItWorks() {
  const steps = [
    {
      num: "1",
      title: "Zap In",
      desc: "Deposit USDC and get swapped into the index basket in one transaction.",
      color: "var(--accent)",
    },
    {
      num: "2",
      title: "Hold FCI",
      desc: "Your share of the index. Transfer or hold like any ERC‑20.",
      color: "var(--success)",
    },
    {
      num: "3",
      title: "Redeem",
      desc: "Burn FCI anytime and receive the underlying assets proportionally.",
      color: "#f87171",
    },
  ];
  return (
    <section
      className="rounded-2xl border p-6 md:p-8"
      style={{
        background: "var(--bg-card)",
        borderColor: "var(--border)",
        boxShadow: "var(--shadow)",
      }}
    >
      <h3
        className="mb-6 text-base font-semibold text-[var(--text)]"
        style={{ fontFamily: "var(--font-syne)" }}
      >
        How it works
      </h3>
      <div className="grid gap-6 md:grid-cols-3">
        {steps.map((s) => (
          <div key={s.num} className="flex gap-4">
            <div
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl text-sm font-bold text-black"
              style={{ background: s.color }}
            >
              {s.num}
            </div>
            <div>
              <div className="font-semibold text-[var(--text)]">{s.title}</div>
              <p className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
                {s.desc}
              </p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
