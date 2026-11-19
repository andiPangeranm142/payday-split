# Payday Split

**Every payday, your crypto splits itself — automatically, on-chain, with no bot to keep running.**

Payday Split is a "set it and forget it" automation built on [Reactive Network](https://reactive.network) for the **Reactive Omni Buildathon** (track: **Set It and Forget It**). Deposit ETH into your Payday Vault and a reactive contract on Reactive Lasna sees the deposit, computes your split, and routes the money for you: a slice into timelocked savings, a slice swapped to stablecoin, the rest stays spendable. You set the rules once; the chain does the rest, forever.

No keeper. No cron job. No off-chain bot. The automation lives entirely on-chain.

> **v2 (current, 19 Nov 2026): the stablecoin leg is now a REAL swap.** `UniswapSwapper` wraps the ETH and swaps it for Circle USDC through Uniswap V3 on Base Sepolia — the demo token is gone. The v1 contracts (mock swapper + pUSD) are still live and documented below, untouched.

## v2: the loop with a real swap (verified live, four times)

```
User deposits ETH ──► PaydayVault v2 (Base Sepolia) ──► DepositReceived event
                                                          │
                                            Reactive Network observes it
                                                          ▼
                                              PaydaySplit v2 (Lasna)
                                         parses rules, computes split,
                                            requests callback
                                                          │
                                                          ▼
                                     SplitExecutor v2 (Base Sepolia, via
                                     Reactive callback proxy)
                                                          │
                              ┌───────────────┬───────────┴───────────┐
                              ▼               ▼                       ▼
                      SavingsVault    UniswapSwapper → USDC   stays spendable
                      (30-day lock)   (real V3 swap, credited  in PaydayVault
                                       to user)              v2
```

The swapper routes WETH → Circle USDC in the WETH/USDC 0.3% pool (the deepest on Base Sepolia) via the official SwapRouter02. Slippage is protected two ways: a $10,000/ETH price floor, and a QuoterV2 quote tightened to 97% (3% max slippage) — if the quoter ever fails, the swap still proceeds under the floor instead of bricking the split. Note: the Base Sepolia pool prices ETH at ~$26,500 — testnet pools are seeded arbitrarily, so the USDC amounts below reflect the testnet price, not mainnet ETH. The route, the quoter and the protection are all real.

**Loop v2-1** — default rules (30% savings / 30% stable / 40% spendable), 0.0002 ETH:

| Leg | Chain | Transaction |
| --- | --- | --- |
| Deposit | Base Sepolia | [`0x23ee6e0b…dc0c`](https://sepolia.basescan.org/tx/0x23ee6e0b00ff24c8d48dd1b50341af213ccfe4a30328411b35f3fcc3ac5edc0c) |
| Reactive `react()` | Lasna | [`0xef91c9b8…ad39`](https://lasna.reactscan.net/tx/0xef91c9b85ac4cb37c40f1dd702b1d6309128ef50c4fd1f5387445daad32ead39) |
| Callback split | Base Sepolia | [`0x3367ff4b…ec38`](https://sepolia.basescan.org/tx/0x3367ff4b8ca8a6dd5e51fa19383614eb8b8ef90e8c2112d52d5ba5e19e81ec38) |

Result: 0.00006 ETH locked in savings (lock #0), **1.593686 real USDC** credited, 0.00008 ETH spendable. Deposit block → callback block: **1 second**.

**Loop v2-2** — custom rules (50% savings / 25% stable / 25% spendable), 0.0002 ETH:

| Leg | Chain | Transaction |
| --- | --- | --- |
| `setRules(5000, 2500)` | Base Sepolia | [`0x98edee53…a8d7`](https://sepolia.basescan.org/tx/0x98edee53b45a9679e2669b74aba1623028ce7aa621be9562ee70602eb3e5a8d7) |
| Deposit | Base Sepolia | [`0xeeba5b5a…837f`](https://sepolia.basescan.org/tx/0xeeba5b5a9d3f1a29a87475c42ff065e786ba6eb2484652269817d3957029837f) |
| Reactive `react()` | Lasna | [`0xa12185ee…236f`](https://lasna.reactscan.net/tx/0xa12185eee005c28ac69a60c38afade04cad702e94727144091ac454adf08236f) |
| Callback split | Base Sepolia | [`0x81b8296e…fd4c`](https://sepolia.basescan.org/tx/0x81b8296eec0144b02224a00920c7a1b29a8be45d1f1a4459b1649d209f29fd4c) |

Result: 0.0001 ETH locked in savings (lock #1), **1.327996 real USDC** credited, 0.00005 ETH spendable. Deposit block → callback block: **1 second**.

**Loop v2-3** — custom rules (10% savings / 80% stable / 10% spendable), 0.0001 ETH:

| Leg | Chain | Transaction |
| --- | --- | --- |
| `setRules(1000, 8000)` | Base Sepolia | [`0xf2c33126…1f60`](https://sepolia.basescan.org/tx/0xf2c33126573c1b9a24a0000cec9d42e4180209440f8f001a6235072ca3f11f60) |
| Deposit | Base Sepolia | [`0x004a75f4…27ecb`](https://sepolia.basescan.org/tx/0x004a75f488790c3907a83a0e6645b4799f2f0465b8418224d7a262af95227ecb) |
| Reactive `react()` | Lasna | [`0x0d409334…63f3`](https://lasna.reactscan.net/tx/0x0d40933441493a60cfdc629f2595f465b5be0adc892c5e07469a5ead813463f3) |
| Callback split | Base Sepolia | [`0x7571eb4d…21c1`](https://sepolia.basescan.org/tx/0x7571eb4dd396ebb0aee1f30bb7a27d4df2b04d95fa2acaed6aa14b96eeef21c1) |

Result: 0.00001 ETH locked in savings (lock #2), **2.124652 real USDC** credited, 0.00001 ETH spendable. Deposit block → callback block: **1 second**. This is the loop filmed in the [v2 demo video](https://youtu.be/4tu7wUEud2c).

**Loop v2-4** — custom rules (10% savings / 80% stable / 10% spendable), 0.0001 ETH:

| Leg | Chain | Transaction |
| --- | --- | --- |
| Deposit | Base Sepolia | [`0x8058e54b…f369`](https://sepolia.basescan.org/tx/0x8058e54bf7cddfa2dcea8a76ad0ba77d99657211438a7287e1f9e8f098a5f369) |
| Reactive `react()` | Lasna | [`0x2277ed74…28ba`](https://lasna.reactscan.net/tx/0x2277ed74db38f141ab5d3116ccab31dd99cf7ad4a010ecb3d728586d879f28ba) |
| Callback split | Base Sepolia | [`0x057aa211…7e05`](https://sepolia.basescan.org/tx/0x057aa2118754163511135c3afbdfacd78be7fad4fe1b91bd66eb2a0600287e05) |

Result: 0.00001 ETH locked in savings (lock #3), **2.160696 real USDC** credited, 0.00001 ETH spendable. Deposit 20 Nov 2026 02:22:00 WIB → callback 03:36:53 WIB: **74 minutes 53 seconds** — the callback was delayed by a network-wide Reactive relayer stall (no relayer callbacks anywhere 18:53–20:36 UTC, 19 Nov 2026; the relayer recovered and cleared the backlog). The split itself executed correctly once the callback landed; v2-1/2/3 each took 1 second.

v2 totals so far: 0.0006 ETH deposited across 4 loops → 0.00018 ETH locked, **7.207030 USDC** out, 0.00015 ETH spendable. The vault holds exactly the USDC it credited (verified on-chain).

## v1: the loop (verified live, five times)

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

Across all five loops: **5 deposits processed, 1 correctly skipped** (a below-minimum deposit, see Edge cases below — `depositsSkipped == 1` on-chain, by design), 5 savings locks created, 0.8 pUSD credited in total — with four different rule sets (default 30/30/40, 50/20/30, 50/25/25, 10/80/10), proving the split follows whatever rules the user set at deposit time.

## Second user (verified live)

The system is multi-user: a second wallet (`0x9e63DCbeF0d0DFA1e1D6E6b7EB320DdC48D10200`) used the same live contracts with its own rules, no deployer involvement in the split:

| Step | Transaction |
| --- | --- |
| Deposit #1 — 0.0001 ETH, default 30/30/40 (Base Sepolia block 60802118) | [`0x8987f5ee…ac92`](https://sepolia.basescan.org/tx/0x8987f5eec4b0f4dfac6734fdca7b3b930f66c4ada382c85de12a328ae45dac92) |
| Reactive (Lasna block 8724914) | [`0xc4001797…c9b8`](https://lasna.reactscan.net/tx/0xc40017973d4d72908cc3002f345a92170483d3d326effeab32a886d8db49c9b8) |
| Callback (block 60802123, ~1s) | [`0xdc4d664f…c595`](https://sepolia.basescan.org/tx/0xdc4d664f831a719f20f64d42fea722e903f4be8c03213d4523cf59a884f7c595) |
| Deposit #2 — 0.0001 ETH, own rules 40/40/20 (block 60802315) | [`0x02906672…f424`](https://sepolia.basescan.org/tx/0x02906672e944983b9139cb9a1b8cb6f855b263484efd198315fd252ccb28f424) |
| Reactive (Lasna block 8724952) | [`0x3c5dbfcc…e9c4`](https://lasna.reactscan.net/tx/0x3c5dbfcc10526d04b505e840478ebeed79f2425e7a16671ec601e1f8340de9c4) |
| Callback (block 60802323, ~2s) | [`0x4903d13a…a3d8`](https://sepolia.basescan.org/tx/0x4903d13a1ad699378d4b47db1910cbf95830ed1a6523e1ee3a7a5bc40301a3d8) |

Result for the second wallet: 2 locks (0.00003 + 0.00004 ETH), 0.14 pUSD, 0.00006 ETH spendable — `splitsRequested` 5 → 7, each user's balances tracked separately.

## Withdrawals (verified live)

Both withdrawal paths have been executed on-chain by the demo wallet — the money actually comes back out:

| Withdrawal | Transaction |
| --- | --- |
| Spendable ETH — `withdraw(0.0001 ETH)` (Base Sepolia block 60779172) | [`0xafefa653…4c16d`](https://sepolia.basescan.org/tx/0xafefa6537897bccdc46db4135f1a33125324fdc8ff2b01464d4d6b8691c4c16d) |
| Stablecoin — `withdrawStable(0.2 pUSD)` (Base Sepolia block 60779179) | [`0x4004d224…bb28a`](https://sepolia.basescan.org/tx/0x4004d224e62f34e39d1de28401fa738b5358eaf0ad1d3d6a8bf78267a09bb28a) |

| Savings lock — `withdraw(0)` on demo SavingsVault `0x51b0D9e3…1048` (Base Sepolia block 60792604) | [`0xa84e80b3…1aa9`](https://sepolia.basescan.org/tx/0xa84e80b3759175c61c1b073b0def98914d511b15ef424956a0c034268c1d1aa9) |

After both: `availableOf` 0.00044 → 0.00034 ETH, `stableOf` 0.8 → 0.6 pUSD, and the wallet holds 0.2 pUSD directly. Savings-lock withdrawal is covered by the Foundry suite — and it has now also been shown live: on 19 Nov 2026 the demo SavingsVault instance `0x51b0D9e32345B4157D3BD34d18C22dCD2c241048` (bytecode-identical to the submitted vault, same codehash `0x532cd1b4…`) released its 1-hour lock #0 (0.0002 ETH, unlocked 16:23 WIB) via [`0xa84e80b3…1aa9`](https://sepolia.basescan.org/tx/0xa84e80b3759175c61c1b073b0def98914d511b15ef424956a0c034268c1d1aa9) (Base Sepolia block 60792604, status success; lock #0 now `withdrawn == true`, deployer balance +0.0002 ETH minus gas). The submitted vault itself still uses the 30-day lock, and its first lock only matures 14 Dec 2026.

## Edge cases (verified live)

- **Dust deposit (below minimum).** A 0.00005 ETH deposit — half the 0.0001 ETH `minDeposit` — was correctly ignored by the reactive contract: [`0x690e52c6…9b744`](https://sepolia.basescan.org/tx/0x690e52c633cceed94a9fe54918695cfb5b59cfae5042e48f4187035987d9b744) (Base Sepolia block 60779239). On Lasna it emitted `DepositSkipped` with reason `below-minimum`: [`0x66f7ea67…94444`](https://lasna.reactscan.net/tx/0x66f7ea679bd3ecdb7db5574b27f8890c87a0e375329cfe97e933dbe8ba694444) (Lasna block 8720620). `depositsSkipped` went 0 → 1, `splitsRequested` stayed 5, and the deposit remains safely spendable in the vault (never split, never lost). The exact boundary is also covered in tests (`testMinDepositBoundary`: `minDeposit - 1` skips, `minDeposit` processes).
- **Rule extremes.** Loops 4–5 ran opposite rule sets (50/25/25 and 10/80/10); the fuzz suite (`testFuzzSplitAccounting`, 256 runs) proves spendable + locked + swapped == deposit for every deposit size and every valid rule combination, including 0/0 (all spendable) and 100% (nothing stays spendable).
- **Pause safety (with a caveat).** A paused reactive contract skips deposits without marking them processed — but v2 has no production path to reprocess them: the deposit event is not re-emitted and `react()` can only be called by the Reactive system contract, so a skipped deposit stays spendable in the vault but is never split. `testReactAfterUnpause` proves the skip logic via a manual call only.

## Reactive funding

The reactive contracts are funded in lREACT for their `react()` calls and callback requests (~0.019 lREACT per loop). **v2** (funded 0.08 lREACT at deploy, 19 Nov 2026; topped up +0.09 lREACT on 20 Nov 2026): balance **0.0938632 lREACT as of 20 Nov 2026**, after 4 loops. **v1** (topped up 19 Nov 2026: +0.05 then +0.04 lREACT; +0.01 lREACT on 20 Nov 2026): balance **0.0339924 lREACT as of 20 Nov 2026**, after 7 loops + 1 dust skip. Outstanding debt is 0 on both reactive contracts and both callback executors — verified 19 Nov 2026 by calling `coverDebt()` on each (v2: [reactive](https://lasna.reactscan.net/tx/0xe8a7ac48f497e8fabf20b66535f5214abf364cee2685ce4e32c2be14c554da94), [executor](https://sepolia.basescan.org/tx/0x61219a1a0143d71d195f964dff7d1a9369c9ac18d66e115ae61232dc6f1ebce6); v1: [reactive](https://lasna.reactscan.net/tx/0x0534d25fc00d97f0211f31a2d119fe67de2574ddfcabbdabda57e8c59eeb7e4c), [executor](https://sepolia.basescan.org/tx/0x20bd725ae7437de76bbffb627a5f183be5d6e1500a0b5bd419c0ae8673944dde)): all balances were unchanged afterwards, proving no debt was outstanding.

📊 **Live dashboard:** https://andipangeranm142.github.io/payday-split/ — rules, live balances, split history, and explorer links, read straight from the public RPCs.

## Deployed contracts (all Sourcify-verified)

### v2 (current — real Uniswap swap)

| Contract | Chain | Address |
| --- | --- | --- |
| `PaydaySplit` (reactive) | Reactive Lasna (5318007) | [`0x973112e077258b0b16a0a20ca237270a8ea6f993`](https://lasna.reactscan.net/address/0x973112e077258b0b16a0a20ca237270a8ea6f993) |
| `PaydayVault` (origin) | Base Sepolia (84532) | [`0x5321c59cfed976f5e3cabb11a9d899593b629e90`](https://sepolia.basescan.org/address/0x5321c59cfed976f5e3cabb11a9d899593b629e90) |
| `SplitExecutor` (callback) | Base Sepolia (84532) | [`0xf654ecc5fbc173e1b7fbf46f870fe549e96d4778`](https://sepolia.basescan.org/address/0xf654ecc5fbc173e1b7fbf46f870fe549e96d4778) |
| `SavingsVault` | Base Sepolia (84532) | [`0x8c17429da93e1545e516216869c0913ac1823303`](https://sepolia.basescan.org/address/0x8c17429da93e1545e516216869c0913ac1823303) |
| `UniswapSwapper` | Base Sepolia (84532) | [`0x379a5a89f007d93ecf70777713cf036690405716`](https://sepolia.basescan.org/address/0x379a5a89f007d93ecf70777713cf036690405716) |
| USDC (Circle) | Base Sepolia (84532) | [`0x036CbD53842c5426634e7929541eC2318f3dCF7e`](https://sepolia.basescan.org/address/0x036CbD53842c5426634e7929541eC2318f3dCF7e) |

### v1 (mock swapper + pUSD — still live, untouched)

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
- **Money only moves through the split path or the user's own withdrawal.** The owner cannot withdraw user balances directly — but this is a single-owner (one EOA) testnet deployment, and the owner does control the parameters around the split: the executor address, the savings lock duration, the swapper price floor, and the callback gas limit. Those controls are documented in the code; a production deployment would put them behind a timelock or multisig.
- **Percentage splits size every leg from the deposit.** Each leg is a share of the deposited amount, so a split never asks for more than was deposited. One honest caveat: the full deposit is spendable from the moment it lands, so a withdrawal in the ~1–2 second window before the callback can leave the vault short and revert the split — the funds stay safe and spendable, but v2 has no retry, so that deposit would never split (see Honest limitations).
- **Withdrawals unlock after 30 days.** `SavingsVault.withdraw()` is covered by the Foundry suite, and a live withdrawal has been demonstrated on the byte-identical demo instance (1-hour lock, same codehash) — see Withdrawals above. No lock on the submitted vault itself has matured yet on testnet (earliest unlock 14 Dec 2026).

## Contracts

| File | Role |
| --- | --- |
| `src/PaydaySplit.sol` | Reactive contract on Lasna. Subscribes to `DepositReceived` on Base Sepolia; computes splits; requests callbacks. |
| `src/PaydayVault.sol` | Origin + funds vault on Base Sepolia. Holds deposits, stores per-user rules, executes splits (executor-only). Stable leg is any ERC-20 via `IERC20` (USDC in v2, pUSD in v1). |
| `src/SplitExecutor.sol` | Callback contract on Base Sepolia. Authenticated entry point for Reactive callbacks; forwards splits to the vault. |
| `src/SavingsVault.sol` | Timelocked savings (default 30-day lock per deposit). |
| `src/UniswapSwapper.sol` | **v2.** Real ETH → USDC swap via Uniswap V3 (SwapRouter02 + QuoterV2, price floor + slippage tightening). |
| `src/MockSwapper.sol` | **v1 only.** Fixed-rate ETH → pUSD swap (see Limitations). Also defines the `ISwapper` interface both swappers implement. |
| `src/PaydayUSD.sol` | **v1 only.** Minimal ERC-20 demo stablecoin (pUSD). |
| `src/IERC20.sol` | Minimal ERC-20 interface (no OpenZeppelin dependency). |

## Try it yourself (Base Sepolia testnet)

You need Base Sepolia ETH (any public faucet) and `cast` (Foundry). These are the **v2** addresses (real USDC swap); v1 is listed above.

```bash
VAULT=0x5321c59cfed976f5e3cabb11a9d899593b629e90
RPC=https://sepolia.base.org

# 1. (Optional) Set your own split — 50% savings, 20% stable, 30% stays.
cast send --rpc-url $RPC --private-key $KEY $VAULT "setRules(uint16,uint16)" 5000 2000

# 2. Deposit. The default rules are 30/30/40 if you never set any.
cast send --rpc-url $RPC --private-key $KEY $VAULT "deposit()" --value 0.001ether

# 3. Wait ~5 seconds, then check the split.
cast call --rpc-url $RPC $VAULT "availableOf(address)(uint256)" $YOU
cast call --rpc-url $RPC $VAULT "stableOf(address)(uint256)" $YOU
cast call --rpc-url $RPC 0x8c17429da93e1545e516216869c0913ac1823303 "lockIdsOf(address)(uint256[])" $YOU
```

Watch the loop live: the deposit emits `DepositReceived`, `PaydaySplit` on Lasna fires `SplitRequested` within a block or two, and the callback lands on Base Sepolia seconds later. Every leg is linked on the [dashboard](https://andipangeranm142.github.io/payday-split/).

## Develop

```bash
forge build
forge test        # 67 tests, 12 suites — vault, swapper, savings, reactive, executor, plus edge-case + fuzz suites and 2 fork tests against the live Uniswap pool
```

Deploy scripts live in `script/` (`DeployBase`, `DeployBaseV2`, `DeployReactive`, `DeployExecutor`). Deploy order matters: Base contracts → reactive contract (needs the vault address) → executor (needs the reactive address) → wire executor on both sides → fund both (reactive in lREACT, executor in Base Sepolia ETH).

## Honest limitations

- **v1's swap is a demo swapper.** `MockSwapper` converts ETH → pUSD at a fixed, owner-set rate (default 1 ETH = 2000 pUSD). It does not route through a DEX. **v2 fixes this**: `UniswapSwapper` swaps ETH → real Circle USDC through Uniswap V3. The v1 contracts stay live for the record.
- **pUSD is a demo token** (v1 only) with no value; it exists so the v1 stablecoin leg produces a real, withdrawable balance.
- **The testnet pool price is not the real ETH price.** The Base Sepolia WETH/USDC pool prices ETH at ~$26,500 — testnet pools are seeded arbitrarily. v2's USDC amounts reflect that pool price; the swap route itself is the production Uniswap path.
- **No callback retry.** If a callback reverts — e.g. a withdrawal in the seconds before it lands leaves the vault short, or a swap slips past the floor — the deposit is already marked processed and v2 has no way to re-request the split. The funds stay safe and spendable in the vault, but the automation for that deposit is done. A retry path is the main thing a v3 would add.
- **Lasna charges 100 gwei base fee**, so each `react()` costs ~0.02 lREACT. The reactive contracts are funded for a handful of demo loops; a production deployment funds them from a treasury or a small fee on splits.
- **Testnet only.** Nothing here has touched mainnet or real funds.

## License

MIT
