# Payday Split

**Every payday, your crypto splits itself — automatically, on-chain, with no bot to keep running.**

Payday Split is a "set it and forget it" automation built on [Reactive Network](https://reactive.network) for the **Reactive Omni Buildathon** (track: **Set It and Forget It**). Deposit ETH into your Payday Vault and a reactive contract on Reactive Lasna sees the deposit, computes your split, and routes the money for you: a slice into timelocked savings, a slice swapped to stablecoin, the rest stays spendable. You set the rules once; the chain does the rest, forever.

No keeper. No cron job. No off-chain bot. The automation lives entirely on-chain.

## The loop (verified live, five times)

```
User deposits ETH ──► PaydayVault (Base Sepolia) ──► DepositReceived event
                                                          │
                                            Reactive Network observes it
                                                          ▼
                                              PaydaySplit (Lasna)
                                         parses rules, computes split,
                                            requests callback
                                                          │
                                                          ▼
                                     SplitExecutor (Base Sepolia, via
                                     Reactive callback proxy)
                                                          │
                              ┌───────────────┬───────────┴───────────┐
                              ▼               ▼                       ▼
                      SavingsVault    MockSwapper → pUSD      stays spendable
                      (30-day lock)   (credited to user)      in PaydayVault
```

**Loop 1** — default rules (30% savings / 30% stable / 40% spendable), 0.0005 ETH:

| Leg | Chain | Transaction |
| --- | --- | --- |
| Deposit | Base Sepolia | [`0xa14ec0b9…f7400`](https://sepolia.basescan.org/tx/0xa14ec0b9c0d93a24cc7735b17646d92ee240ff7c216d8c920f377b5fb90f7400) |
| Reactive `react()` | Lasna | [`0x0487d431…c94c`](https://lasna.reactscan.net/tx/0x0487d4312546a879d8077b24857e04c371fe302b3d49d6ede78621b52113c94c) |
| Callback split | Base Sepolia | [`0x27cfe0f7…1300`](https://sepolia.basescan.org/tx/0x27cfe0f7d539c3ae0ea176bdb9f11251cd2d499e5efe85473849e96696bc1300) |

Result: 0.00015 ETH locked in savings (lock #0, 30 days), 0.3 pUSD credited, 0.0002 ETH spendable. Deposit block → callback block: **~2 seconds**.

**Loop 2** — custom rules (50% savings / 20% stable / 30% spendable), 0.0005 ETH:

| Leg | Chain | Transaction |
| --- | --- | --- |
| `setRules(5000, 2000)` | Base Sepolia | [`0xdff702c1…319d`](https://sepolia.basescan.org/tx/0xdff702c14d9fc7ca54b3c8a4ee66a21557bb7af5bd8a6019d9a0e4e9fdac319d) |
| Deposit | Base Sepolia | [`0x6ae873c1…02fe`](https://sepolia.basescan.org/tx/0x6ae873c127f5b858915299f48d6a40fe102ac7f4092388e89c22c3fdfba402fe) |
| Reactive `react()` | Lasna | [`0x4486d455…a3a8`](https://lasna.reactscan.net/tx/0x4486d455bc1ec7f4537cb617d90be0d75ad6f6de9306599dc7c34eba03c0a3a8) |
| Callback split | Base Sepolia | [`0xfbaf3ca2…2a88`](https://sepolia.basescan.org/tx/0xfbaf3ca2710087b7e0aafbcff00fc47df8b343f299cd1583d9f477f01db12a88) |

Result: 0.00025 ETH locked in savings (lock #1), 0.2 pUSD credited, 0.00015 ETH spendable. Same user, different rules — the reactive contract read the new rules straight from the deposit event. Deposit block → callback block: **3 seconds**.

**Loop 3** — custom rules (50% savings / 20% stable / 30% spendable, unchanged from Loop 2), 0.0001 ETH — the demo-video loop:

| Leg | Chain | Transaction |
| --- | --- | --- |
| Deposit | Base Sepolia | [`0x66775dfc…02368`](https://sepolia.basescan.org/tx/0x66775dfc09b7e8a26f4e73a90688814d3ca276e8869d4c6bbd1aff303b802368) |
| Reactive `react()` | Lasna | [`0x48d57819…3b375`](https://lasna.reactscan.net/tx/0x48d578197932182723df51ff9e60fe26c59cf30ecdec5fd3c280c6d6aed3b375) |
| Callback split | Base Sepolia | [`0x0c7c436d…c951d`](https://sepolia.basescan.org/tx/0x0c7c436d0a2b8f46f5c9fb086903a9e8c948880ae1ece947bec834ac60ac951d) |

Result: 0.00005 ETH locked in savings (lock #2), 0.04 pUSD credited, 0.00003 ETH spendable. Deposit block → callback block: **2 seconds**. This is the loop filmed in the [demo video](https://www.youtube.com/watch?v=6j7lKUyHwgo).

**Loop 4** — custom rules (50% savings / 25% stable / 25% spendable), 0.0002 ETH — larger deposit, different rules:

| Leg | Chain | Transaction |
| --- | --- | --- |
| `setRules(5000, 2500)` | Base Sepolia | [`0xca0af53a…c224`](https://sepolia.basescan.org/tx/0xca0af53a6f7a297356c1902db328b070c7893d5a1f42a94a8643fdfbb665c224) |
| Deposit | Base Sepolia | [`0x6955ff46…f48d0`](https://sepolia.basescan.org/tx/0x6955ff465153da1a6f050a98433bfa831c67143147b4797c48c8c31f992f48d0) |
| Reactive `react()` | Lasna | [`0x1021cd7b…56184`](https://lasna.reactscan.net/tx/0x1021cd7b410d1bfda01abd5a95844bd2a96d1807b02fbc172669e1aa32656184) |
| Callback split | Base Sepolia | [`0xf599a824…c51d`](https://sepolia.basescan.org/tx/0xf599a824fc02b5d629b94a546f2177855a59d5911153b0b18508596dfa15c51d) |

Result: 0.0001 ETH locked in savings (lock #3), 0.1 pUSD credited, 0.00005 ETH spendable. Deposit block → callback block: **2 seconds**.

**Loop 5** — custom rules (10% savings / 80% stable / 10% spendable), 0.0001 ETH — heavy stable allocation, the opposite extreme:

| Leg | Chain | Transaction |
| --- | --- | --- |
| `setRules(1000, 8000)` | Base Sepolia | [`0xcb9a640a…fc18`](https://sepolia.basescan.org/tx/0xcb9a640aa288bdd3921ea7294c56f90b9293384d2382cd2016c6df8e0dd2fc18) |
| Deposit | Base Sepolia | [`0x58c56413…1ff7a`](https://sepolia.basescan.org/tx/0x58c5641349e57c62f72968709eaa1ea63f0571e17730cee4e696f4381511ff7a) |
| Reactive `react()` | Lasna | [`0xdc2fdb0e…b0f1`](https://lasna.reactscan.net/tx/0xdc2fdb0e6c14b2f9d05c5a8b6d66bda8775f858245f834aad30ee08fde6db0f1) |
| Callback split | Base Sepolia | [`0x3f3213ae…c0db0`](https://sepolia.basescan.org/tx/0x3f3213ae8ab3c1d3fe044c49e5399759a1639a90f9786a4158a1f00f8b1c0db0) |

Result: 0.00001 ETH locked in savings (lock #4), 0.16 pUSD credited, 0.00001 ETH spendable. Deposit block → callback block: **1 second**.

Across all five loops: **5 deposits processed, 0 skipped** (`depositsSkipped == 0` on-chain), 5 savings locks created, 0.8 pUSD credited in total — with four different rule sets (default 30/30/40, 50/20/30, 50/25/25, 10/80/10), proving the split follows whatever rules the user set at deposit time.

📊 **Live dashboard:** https://andipangeranm142.github.io/payday-split/ — rules, live balances, split history, and explorer links, read straight from the public RPCs.

## Deployed contracts (all Sourcify-verified)

| Contract | Chain | Address |
| --- | --- | --- |
| `PaydaySplit` (reactive) | Reactive Lasna (5318007) | [`0x8149417d4977284765D3033cd89B1233DB49BcCc`](https://lasna.reactscan.net/address/0x8149417d4977284765D3033cd89B1233DB49BcCc) |
| `PaydayVault` (origin) | Base Sepolia (84532) | [`0x929eb93b766fe9099aEfeF7640E88D89F6bf7936`](https://sepolia.basescan.org/address/0x929eb93b766fe9099aEfeF7640E88D89F6bf7936) |
| `SplitExecutor` (callback) | Base Sepolia (84532) | [`0xfb07307Bc96c3Ea04aa82F74a92e6C5075C549a4`](https://sepolia.basescan.org/address/0xfb07307Bc96c3Ea04aa82F74a92e6C5075C549a4) |
| `SavingsVault` | Base Sepolia (84532) | [`0xa8a343f37119d15d16b16988CAb60A0468608c4e`](https://sepolia.basescan.org/address/0xa8a343f37119d15d16b16988CAb60A0468608c4e) |
| `MockSwapper` | Base Sepolia (84532) | [`0xc423EcEe6E7e33EDed047037Bf95F3f3BAd9caa3`](https://sepolia.basescan.org/address/0xc423EcEe6E7e33EDed047037Bf95F3f3BAd9caa3) |
| `PaydayUSD` (pUSD) | Base Sepolia (84532) | [`0xe78B98f37C6C5CeB1ef81808dDaaE23Ff23bDabb`](https://sepolia.basescan.org/address/0xe78B98f37C6C5CeB1ef81808dDaaE23Ff23bDabb) |

Supporting infrastructure: Base Sepolia callback proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585`, Lasna system contract `0x8888888888888888888888888888888888888888`.

## Why this is a real reactive integration

- **The reactive contract does real work.** `PaydaySplit.react()` parses the deposit log, enforces a minimum-deposit policy and pause switch, deduplicates deposits, computes the split from the rules embedded in the event, and only then requests a callback. Remove it and nothing splits — there is no fallback path.
- **Rules live in the event, not in a second source of truth.** The vault embeds the user's current rules in `DepositReceived`, so the reactive side is stateless w.r.t. rules and always applies exactly what the user set at deposit time.
- **Callbacks are doubly authenticated.** `SplitExecutor` requires both `onlyServiceProvider` (caller is the Reactive callback proxy) and `onlyCallbackSender` (origin is our reactive contract). Nobody else can trigger a split.
- **Money only moves through the split path or the user's own withdrawal.** The owner cannot touch user funds.
- **Percentage splits can't underfund.** Each leg is a share of the deposited amount, so every leg always has exactly what it needs — there is no "insufficient balance" failure path the way a fixed-amount payout has. The reactive contract enforces a minimum deposit instead, so dust deposits never trigger a split.
- **Withdrawals unlock after 30 days.** `SavingsVault.withdraw()` is covered by the Foundry suite; no lock has matured yet on testnet (earliest unlock 14 Dec 2026), so a live withdrawal can't be shown until then.

## Contracts

| File | Role |
| --- | --- |
| `src/PaydaySplit.sol` | Reactive contract on Lasna. Subscribes to `DepositReceived` on Base Sepolia; computes splits; requests callbacks. |
| `src/PaydayVault.sol` | Origin + funds vault on Base Sepolia. Holds deposits, stores per-user rules, executes splits (executor-only). |
| `src/SplitExecutor.sol` | Callback contract on Base Sepolia. Authenticated entry point for Reactive callbacks; forwards splits to the vault. |
| `src/SavingsVault.sol` | Timelocked savings (default 30-day lock per deposit). |
| `src/MockSwapper.sol` | Fixed-rate ETH → pUSD swap (see Limitations). |
| `src/PaydayUSD.sol` | Minimal ERC-20 demo stablecoin (pUSD). |

## Try it yourself (Base Sepolia testnet)

You need Base Sepolia ETH (any public faucet) and `cast` (Foundry).

```bash
VAULT=0x929eb93b766fe9099aEfeF7640E88D89F6bf7936
RPC=https://sepolia.base.org

# 1. (Optional) Set your own split — 50% savings, 20% stable, 30% stays.
cast send --rpc-url $RPC --private-key $KEY $VAULT "setRules(uint16,uint16)" 5000 2000

# 2. Deposit. The default rules are 30/30/40 if you never set any.
cast send --rpc-url $RPC --private-key $KEY $VAULT "deposit()" --value 0.001ether

# 3. Wait ~5 seconds, then check the split.
cast call --rpc-url $RPC $VAULT "availableOf(address)(uint256)" $YOU
cast call --rpc-url $RPC $VAULT "stableOf(address)(uint256)" $YOU
cast call --rpc-url $RPC 0xa8a343f37119d15d16b16988CAb60A0468608c4e "lockIdsOf(address)(uint256[])" $YOU
```

Watch the loop live: the deposit emits `DepositReceived`, `PaydaySplit` on Lasna fires `SplitRequested` within a block or two, and the callback lands on Base Sepolia seconds later. Every leg is linked on the [dashboard](https://andipangeranm142.github.io/payday-split/).

## Develop

```bash
forge build
forge test        # 55 tests, 10 suites — vault, swapper, savings, reactive, executor, plus edge-case + fuzz suites
```

Deploy scripts live in `script/` (`DeployBase`, `DeployReactive`, `DeployExecutor`). Deploy order matters: Base contracts → reactive contract (needs the vault address) → executor (needs the reactive address) → wire executor on both sides → fund both (reactive in lREACT, executor in Base Sepolia ETH).

## Honest limitations

- **The swap is a demo swapper.** `MockSwapper` converts ETH → pUSD at a fixed, owner-set rate (default 1 ETH = 2000 pUSD). It does not route through a DEX. The vault only talks to it through the `ISwapper` interface, so a production deployment plugs in a real DEX adapter with no vault changes. The reactive automation — the point of this project — is fully real.
- **pUSD is a demo token** with no value; it exists so the stablecoin leg produces a real, withdrawable balance.
- **Lasna charges 100 gwei base fee**, so each `react()` costs ~0.02 lREACT. The reactive contract is funded for a handful of demo loops; a production deployment funds it from a treasury or a small fee on splits.
- **Testnet only.** Nothing here has touched mainnet or real funds.

## License

MIT
