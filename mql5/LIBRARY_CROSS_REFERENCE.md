# JAZZYLYFE MT5 Library Cross-Reference
## Version: 2026-08-17 | Maintained by: JAZZYLYFE / Brimberry LLC

---

## 🔧 Shared Libraries (`mql5/lib/`)

| Library | Version | Purpose | Used By |
|---------|---------|---------|--------|
| `JazzyLyfe_FTMO_Guard.mqh` | v1.0 | Prop-firm drawdown guard (4.5/5% daily, 9/10% total), max trades/day, Friday close, weekend block | Template, Unified EA |
| `JazzyLyfe_MTF.mqh` | v1.0 | Multi-timeframe cascade D1→H4→H1→M15 (EMA bias scoring) | Template, Unified EA |
| `JazzyLyfe_ICT.mqh` | v1.0 | ICT/SMC confluence: FVG, Order Block, BOS/CHoCH, Liquidity Sweep | Template, Unified EA |
| `JazzyLyfe_Sizing.mqh` | v1.0 | Fractional Kelly position sizing, broker-constraint lot normalization | Template, Unified EA |
| `JazzyLyfe_Controls.mqh` | v1.0 | Inverse Mode + Direction Filter (MANDATORY on every EA) | Template, Unified EA |
| `JazzyLyfe_TradeManager.mqh` | v1.0 | Spread filter, breakeven, trailing stop, partial close, CSV journal | Template, Unified EA |

### Dependency Chain
```
JazzyLyfe_Controls.mqh ──imports──> JazzyLyfe_MTF.mqh (for ENUM_JL_BIAS)
All other libs are standalone (no cross-lib dependencies)
All libs depend on <Trade/Trade.mqh> (MQL5 standard)
```

### Enum Definitions (shared across all code)
| Enum | Defined In | Values |
|------|-----------|--------|
| `ENUM_JL_BIAS` | MTF.mqh | `JL_BIAS_SELL(-1)`, `JL_BIAS_NONE(0)`, `JL_BIAS_BUY(1)` |
| `ENUM_JL_DIRECTION` | Controls.mqh | `JL_DIR_BOTH(0)`, `JL_DIR_BUY_ONLY(1)`, `JL_DIR_SELL_ONLY(2)` |
| `ENUM_JL_GUARD_STATE` | FTMO_Guard.mqh | `OK(0)`, `SOFT_DAY(1)`, `SOFT_MAX(2)`, `HARD_DAY(3)`, `HARD_MAX(4)`, `MAX_TRADES(5)`, `WEEKEND(6)` |

---

## 📊 Expert Advisors

### 1. JAZZYLYFE_UltimateProfit_Unified.mq5 (v8.10)
- **Path:** `mql5/experts/UltimateProfit_Series/`
- **Magic:** 202512250
- **Edge:** XAUUSD, long-biased
- **Lineage:** Consolidation of V2–V7 feature set
- **Libs used:** ALL 6 (FTMO_Guard, MTF, ICT, Sizing, Controls, TradeManager)
- **Extra features beyond template:**
  - 7-signal ensemble voting (RSI, MACD, EMA cross, price/EMA, MTF, MACD slope, ICT)
  - ICT killzone session filter (London 07-10, NY 12-15)
  - Recovery mode (cut risk after N consecutive losses, weekly Monday reset)
- **Indicators created:** RSI(14), MACD(12,26,9), EMA(21), EMA(50), ATR(14)

### 2. JazzyLyfe_EA_Template.mq5 (v1.02)
- **Path:** `mql5/templates/`
- **Purpose:** Master scaffold — every new EA starts by cloning this
- **Libs used:** ALL 6
- **Strategy hook:** `BuildRawSignal()` — override body per EA
- **Management hook:** `ManageOpenTrades()` — defaults to `tm.Manage()`

---

## 📈 Indicators

### 1. PinBarMagic_Ultimate_v2.mq5 (v2.00)
- **Path:** `mql5/indicators/`
- **Purpose:** Advanced pin bar detection with SMC integration, ICT killzones, MTF confirmation, on-chart dashboard
- **Standalone:** Does not use shared libs (self-contained)

---

## 🐍 Python Bridge

### phemex_bridge.py (v1.0)
- **Path:** `python-bots/`
- **Purpose:** FastAPI relay: MT5 EA → Phemex exchange (HMAC-SHA256 auth)
- **Known gaps:** No FTMO guard integration, single-timeframe

---

## ✅ Standard Safety Stack (MANDATORY for every new EA)

Every JAZZYLYFE EA **must** wire these in `OnInit()`:

```mql5
// 1) FTMO Guard — call guard.Check() every tick BEFORE signals
guard.Init(InpMagic, InpStartBalance, 4.5, 5.0, 9.0, 10.0,
           InpMaxTradesDay, InpFridayCloseHour, InpWeekendBlock);

// 2) MTF Cascade — directional bias
mtf.Init(_Symbol, InpEmaFast, InpEmaSlow, InpMinAlign);

// 3) ICT Confluence — SMC confirmation
ict.Init(_Symbol, PERIOD_M15, 60);

// 4) Kelly Sizing — position sizing
sizing.Init(_Symbol, InpMaxRiskPct, InpKellyFraction);

// 5) Controls — inverse + direction (MANDATORY)
controls.Init(InpInverseMode, InpDirection);

// 6) Trade Manager — post-entry management
tm.Init(_Symbol, InpMagic, InpMaxSpreadPts,
        InpUseBreakeven, InpBEBufferPts,
        InpUseTrailing, InpTrailStepPts,
        InpUsePartial, InpPartialPct,
        InpUseJournal);
```

### OnTick() Flow
```
1. guard.Check()          → halt / soft-block / OK
2. NewBar() gate          → work on confirmed M15 bars only
3. tm.Manage()            → breakeven / trail / partial for open positions
4. HasOpenPosition()      → one trade at a time
5. tm.SpreadOK()          → skip if spread too wide
6. BuildRawSignal()       → MTF + ICT + custom logic
7. controls.Apply(raw)    → invert + direction filter
8. sizing.Lot(...)        → Kelly lot
9. trade.Buy/Sell(...)    → execute
10. guard.RecordTrade()   → count toward daily cap
11. tm.RegisterOpen(...)  → register for BE/trail/partial tracking
```

---

## 🚫 Security & Safety Rules

- **Never commit:** API keys, FTMO credentials, live account numbers, broker passwords
- **Blacklisted symbol:** BCHUSD (never trade)
- **Disabled EAs:** HFT Aggressive v2, AGI EA v2 (catastrophic drawdown — keep off)
- **Forbidden patterns:** Martingale, grid, hedging, no-stop-loss, lots > 2% account risk
- **Manual override modes that bypass FTMO guards** are forbidden

---

## 📁 MT5 Data Folder Layout (for deployment)

```
MQL5/
  Include/JazzyLyfe/          ← all 6 .mqh libs
  Experts/JazzyLyfe/          ← template + subfolder per series
    JazzyLyfe_EA_Template.mq5
    UltimateProfit/
      JAZZYLYFE_UltimateProfit_Unified.mq5
  Indicators/JazzyLyfe/
    PinBarMagic_Ultimate_v2.mq5
```

**Include paths in deployed EAs use:** `#include <JazzyLyfe/JazzyLyfe_X.mqh>`
**Include paths in repo EAs use:** `#include "../../lib/JazzyLyfe_X.mqh"` (relative)

---

## 🆕 How to Add a New EA

1. Copy `mql5/templates/JazzyLyfe_EA_Template.mq5` into `mql5/experts/<SeriesName>/`
2. Rename and update `#property version`, magic number, description
3. Replace `BuildRawSignal()` body with your custom strategy logic
4. Override `ManageOpenTrades()` only if custom post-entry logic is needed
5. Add any new indicator handles in `OnInit()` and release in `OnDeinit()`
6. Test in Strategy Tester before live deployment
7. Update this cross-reference document

---

*Last updated: 2026-08-17 by Claude Code session*
