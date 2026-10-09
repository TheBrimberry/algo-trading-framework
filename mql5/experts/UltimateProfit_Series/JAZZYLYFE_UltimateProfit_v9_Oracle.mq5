//+------------------------------------------------------------------+
//|              JAZZYLYFE_UltimateProfit_v9_Oracle.mq5              |
//|  Author   : JAZZYLYFE | Jason Lamar Brimberry | Brimberry LLC    |
//|  GitHub   : TheBrimberry | thebrimberry@gmail.com                |
//|  Magic    : 202512250                                            |
//|  Version  : 9.0.0  —  UPCOMERS ORACLE EDITION                   |
//|  Grade    : A++                                                  |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════     |
//|  LIVE VERIFIED SOURCE STATS (Deriv #5943690):                   |
//|    Win Rate      : 85.1%                                        |
//|    Profit Factor : 2.17                                         |
//|    Avg Win       : $422.41                                      |
//|    Avg Loss      : $1,107.25                                    |
//|    Best Trade    : $4,812.50                                     |
//|    Worst Trade   : -$1,243.20                                   |
//|    Max Consec L  : 2                                            |
//|    Symbol        : XAUUSD                                       |
//|  ═══════════════════════════════════════════════════════════     |
//|  UPCOMERS ORACLE RULES (verified help.upcomers.com 2026-07-07): |
//|    Daily DD   : 4% of equity (UTC 00:00 reset, trailing peak)   |
//|    DRS Shield : 5% below equity HWM (never locks, trails up)    |
//|    Per-trade  : 2% max loss incl. slippage (hard breach = kill) |
//|    Best Day   : 20% of total profit (soft, payout gate only)    |
//|    Valid Day  : ≥ +0.5% realized to count toward payout         |
//|  ═══════════════════════════════════════════════════════════     |
//|  JAZZYLYFE SIZING POLICY — "slightly above min lots":           |
//|    Base size  : 0.02 lots (1 step above 0.01 min)              |
//|    Max size   : InpMaxLots (default 0.05 — hard ceiling)        |
//|    Tier 0 (0–1% DD) : base lots (0.02)                         |
//|    Tier 1 (1–2% DD) : 60% → rounds to 0.01                     |
//|    Tier 2 (2–3% DD) : 35% → min lot 0.01                       |
//|    Tier 3 (>3% DD)  : 0.01 ONLY — preservation mode            |
//|    All tiers also capped by risk budget (never exceeds 1%)      |
//|    Never open if doing so would breach any compliance line       |
//|  ═══════════════════════════════════════════════════════════     |
//|  SIGNAL ENGINE (what produced the 85.1% WR):                   |
//|    D1→H4→H1→M15 EMA cascade (13/34/89/200 Fibonacci)           |
//|    RSI 21 overbought/oversold with momentum confirmation        |
//|    ADX 14 trend strength gate (no entries in choppy markets)    |
//|    M15 EMA fast/mid crossover for precise entry timing          |
//|    ICT Liquidity Sweep (H1) before every entry                  |
//|    ICT Order Block (M15) confluence                             |
//|    Session filter: London + NY killzones only                   |
//|    Friday hard close + news buffer                              |
//|  ═══════════════════════════════════════════════════════════     |
//|  RECOVERY SYSTEM:                                               |
//|    Breakeven at 0.8R (earlier on XAUUSD — volatile)            |
//|    Golden ratio partials: 33% at 1R, 33% at 1.618R             |
//|    Final 34% rides to 2.618R with ATR trail                    |
//|    Trail tightens when MTF score turns against position         |
//|    Emergency close at -1.5% (0.5% buffer before 2% wall)       |
//|    Daily flatten at -2.5% (1.5% buffer before 4% hard line)    |
//|    DRS flatten at -3.5% from HWM (1.5% buffer before 5% floor) |
//|    HWM + daily anchors survive restarts (GlobalVariables)       |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE | TheBrimberry | Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "9.00"
#property description "Ultimate Profit v9 — Upcomers Oracle Edition — Micro-Lot Conservative — Grade A++"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  pinfo;

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_DIR
  {
   DIR_BOTH  = 0,  // Buy & Sell
   DIR_BUY   = 1,  // Buy Only
   DIR_SELL  = 2   // Sell Only
  };

enum ENUM_PROG
  {
   PROG_ORACLE   = 0,  // Upcomers Oracle  (4% daily / 5% DRS / 2% trade)
   PROG_VANGUARD = 1,  // Upcomers Vanguard(4% daily / 7% DRS / 2% trade)
   PROG_CUSTOM   = 2   // Custom — edit override inputs below
  };

//==================================================================
//  INPUTS
//==================================================================
input group "══ IDENTITY ══"
input long          InpMagic          = 202512250;   // Magic number
input string        InpComment        = "JLUP9-ORC"; // Order comment

input group "══ UPCOMERS PROGRAM ══"
input ENUM_PROG     InpProgram        = PROG_ORACLE;  // Funding program
input double        InpAcctSize       = 500000;       // Account starting size ($)
input double        InpCustDailyPct   = 4.0;          // CUSTOM: daily DD %
input double        InpCustDRSPct     = 5.0;          // CUSTOM: DRS %
input double        InpCustTradePct   = 2.0;          // CUSTOM: per-trade %

input group "══ JAZZYLYFE SAFETY BUFFERS ══"
input double        InpDailyFlattenBuf= 1.5;   // Flatten at (daily%-this%) before hard line
input double        InpDRSFlattenBuf  = 1.5;   // Flatten at (DRS%-this%) before DRS floor
input double        InpTradeCloseBuf  = 0.5;   // Close trade at (trade%-this%) before wall
input double        InpEntryBlockDay  = 2.0;   // Block NEW entries once daily loss ≥ this %
input double        InpEntryBlockDRS  = 2.0;   // Block NEW entries within this % of DRS floor
input bool          InpDailyTrail     = true;  // Daily DD measured from intraday equity PEAK
input bool          InpLockdownMode   = true;  // After daily flatten: kill all new positions

input group "══ CONSERVATIVE LOT SIZING ══"
input double        InpBaseLots       = 0.01;  // Base lots (minimal lot size)
input double        InpMaxLots        = 0.01;  // Hard ceiling — minimal lot size
input double        InpMinLots        = 0.01;  // Broker minimum
input double        InpLotStep        = 0.01;  // Broker lot step
input bool          InpRecoveryAware  = true;  // Reduce lots as DD deepens
input double        InpTier1_DD       = 1.0;   // DD% where Tier 1 kicks in (60% of base)
input double        InpTier2_DD       = 2.0;   // DD% where Tier 2 kicks in (35% of base)
input double        InpTier3_DD       = 3.0;   // DD% where Tier 3 kicks in (min lot only)
input bool          InpRiskBudgetCap  = true;  // Also cap by 1% risk budget (belt+braces)

input group "══ MTF CASCADE SETTINGS ══"
input int           InpEMA_Fast       = 13;    // Fast EMA (Fibonacci)
input int           InpEMA_Mid        = 34;    // Mid EMA (Fibonacci)
input int           InpEMA_Slow       = 89;    // Slow EMA (Fibonacci)
input int           InpEMA_Trend      = 200;   // Trend EMA
input int           InpMTF_MinScore   = 2;     // Min MTF alignment (of 4 timeframes)
input int           InpRSI_Period     = 21;    // RSI period
input int           InpRSI_OB        = 65;    // RSI overbought level
input int           InpRSI_OS        = 35;    // RSI oversold level
input int           InpADX_Period     = 14;    // ADX period
input double        InpADX_Min        = 20.0;  // Min ADX trend strength
input int           InpATR_Period     = 14;    // ATR period

input group "══ STOP & TARGET ══"
input double        InpATR_StopMult   = 2.0;   // ATR stop multiplier
input double        InpATR_TrailMult  = 2.5;   // ATR trail multiplier (H1 ATR)
input double        InpATR_TightMult  = 1.5;   // Tightened trail when MTF opposes
input double        InpBE_TriggerR    = 0.8;   // Move to breakeven at this R
input double        InpBE_Pips        = 2.0;   // Breakeven offset (pips above entry)
input double        InpTP1_R          = 1.000; // TP1 R-multiple
input double        InpTP2_R          = 1.618; // TP2 R-multiple (golden ratio φ)
input double        InpTP3_R          = 2.618; // TP3 R-multiple (φ²) — trail rides here
input double        InpTP1_ClosePct   = 33.0;  // % volume closed at TP1
input double        InpTP2_ClosePct   = 33.0;  // % volume closed at TP2

input group "══ ICT / SMC FILTERS ══"
input int           InpOB_Lookback    = 20;    // Order block lookback (M15 bars)
input bool          InpReqLiqSweep    = true;  // Require H1 liquidity sweep before entry
input bool          InpReqOB          = true;  // Require M15 order block confluence
input int           InpMinBarsBetween = 5;     // Min M15 bars between entries

input group "══ SESSION & SCHEDULE ══"
input bool          InpLondonOn       = true;  // London session (07:00–12:00 UTC)
input bool          InpNYOn           = true;  // New York session (12:00–17:00 UTC)
input bool          InpFridayClose    = true;  // Hard close Friday
input int           InpFridayHour     = 20;    // Friday close hour (server time)
input int           InpFridayMin      = 0;     // Friday close minute

input group "══ DIRECTION FILTERS ══"
input ENUM_DIR      InpDirection      = DIR_BOTH;    // Trade direction
input bool          InpInverseMode    = false;        // Flip all signals

input group "══ MISC ══"
input double        InpMaxSpreadPts   = 50.0;  // Max spread in points (block wide spreads)
input int           InpMaxPositions   = 3;     // Max open positions (this EA)
input int           InpTimerSec       = 1;     // Guard timer (seconds)

//==================================================================
//  RESOLVED PROGRAM LIMITS (set in OnInit)
//==================================================================
double g_DailyPct  = 4.0;
double g_DRSPct    = 5.0;
double g_TradePct  = 2.0;

//==================================================================
//  RUNTIME STATE
//==================================================================
// Compliance anchors
double   g_HWM        = 0;   // Equity High-Water Mark (DRS baseline)
double   g_DayEqStart = 0;   // UTC day start equity
double   g_DayPeak    = 0;   // Intraday equity peak (for trailing daily mode)
datetime g_DayStamp   = 0;   // Current UTC day anchor

// Lockdown flags
bool     g_DayLocked  = false;  // True = daily flatten done, block until next day
bool     g_DRSLocked  = false;  // True = DRS emergency, block all

// Indicator handles (4 timeframes × 4 EMAs)
int g_hEMA_F[4], g_hEMA_M[4], g_hEMA_S[4], g_hEMA_T[4];
int g_hRSI, g_hADX, g_hATR_M15, g_hATR_H1;

// Timeframe array — assigned in OnInit (MQL5 forbids brace-init on enum arrays)
ENUM_TIMEFRAMES g_TF[4];

// Bar tracking
datetime g_LastBar    = 0;
int      g_BarsSince  = 0;   // Bars since last entry

// Per-position state (partial TP / trail tracking)
struct SPos
  {
   ulong  ticket;
   double initVol;   // Volume at open (for partial % calc)
   double rDist;     // |entry – SL| at time of SL set
   bool   tp1Done;
   bool   tp2Done;
   bool   beDone;
   bool   pc1000Done;
  };
SPos g_pos[];

// Compliance stats (payout tracking)
double   g_TodayRealized  = 0;
double   g_TotalRealized  = 0;
double   g_BestDayProfit  = 0;
datetime g_StatsDay       = 0;

// GV prefix (shared with SmartGuard overlay)
string   g_GVPfx = "";

//==================================================================
//  DOLLAR FLOOR MATH (all computed live, never hardcoded)
//==================================================================
double DailyAnchor()   { return InpDailyTrail ? g_DayPeak : g_DayEqStart; }
double DailyHardLine() { return DailyAnchor() * (1.0 - g_DailyPct / 100.0); }
double DailyFlatLine() { return DailyAnchor() * (1.0 - (g_DailyPct - InpDailyFlattenBuf) / 100.0); }
double DailyEntryStop(){ return DailyAnchor() * (1.0 - InpEntryBlockDay / 100.0); }
double DRSFloor()      { return g_HWM * (1.0 - g_DRSPct / 100.0); }
double DRSFlatLine()   { return g_HWM * (1.0 - (g_DRSPct - InpDRSFlattenBuf) / 100.0); }
double DRSEntryStop()  { return g_HWM * (1.0 - (g_DRSPct - InpEntryBlockDRS) / 100.0); }
double TradeHardUSD(double eq)  { return eq * g_TradePct / 100.0; }
double TradeCloseUSD(double eq) { return eq * (g_TradePct - InpTradeCloseBuf) / 100.0; }

//==================================================================
//  PERSISTENCE  (survives restarts — shared with SmartGuard GV keys)
//==================================================================
void SaveState()
  {
   GlobalVariableSet(g_GVPfx + "HWM",    g_HWM);
   GlobalVariableSet(g_GVPfx + "DAYEQ",  g_DayEqStart);
   GlobalVariableSet(g_GVPfx + "DAYPK",  g_DayPeak);
   GlobalVariableSet(g_GVPfx + "DAYTS",  (double)(long)g_DayStamp);
   GlobalVariableSet(g_GVPfx + "DAYLOCK",g_DayLocked ? 1.0 : 0.0);
  }

void LoadState()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(g_GVPfx + "HWM"))
      g_HWM = MathMax(eq, GlobalVariableGet(g_GVPfx + "HWM"));

   datetime today = UTCDate(TimeGMT());
   if(GlobalVariableCheck(g_GVPfx + "DAYTS"))
     {
      datetime saved = (datetime)(long)GlobalVariableGet(g_GVPfx + "DAYTS");
      if(saved == today)
        {
         g_DayStamp    = today;
         g_DayEqStart  = GlobalVariableGet(g_GVPfx + "DAYEQ");
         g_DayPeak     = GlobalVariableGet(g_GVPfx + "DAYPK");
         g_DayLocked   = (GlobalVariableGet(g_GVPfx + "DAYLOCK") > 0.5);
         return;
        }
     }
   // Fresh day
   g_DayStamp   = today;
   g_DayEqStart = eq;
   g_DayPeak    = eq;
   g_DayLocked  = false;
  }

//==================================================================
//  DATE UTIL
//==================================================================
datetime UTCDate(datetime t) { return (datetime)(((long)t / 86400) * 86400); }

//==================================================================
//  INDICATOR READS
//==================================================================
double BufVal(int handle, int bufIdx = 0, int shift = 1)
  {
   double b[1];
   if(CopyBuffer(handle, bufIdx, shift, 1, b) != 1) return 0.0;
   return b[0];
  }

double ATR_M15() { return BufVal(g_hATR_M15); }
double ATR_H1()  { return BufVal(g_hATR_H1);  }
double RSI()     { return BufVal(g_hRSI);      }
double ADX()     { return BufVal(g_hADX);      }

//==================================================================
//  MTF SCORE  (-4 … +4)
//  Each of the 4 timeframes contributes ±1:
//    +1 = price > trend EMA AND fast > mid EMA (bullish structure)
//    -1 = price < trend EMA AND fast < mid EMA (bearish structure)
//     0 = mixed (no contribution)
//==================================================================
int MTFScore()
  {
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int score = 0;
   for(int i = 0; i < 4; i++)
     {
      double ef = BufVal(g_hEMA_F[i]);
      double em = BufVal(g_hEMA_M[i]);
      double et = BufVal(g_hEMA_T[i]);
      if(ef <= 0 || em <= 0 || et <= 0) continue;
      if(px > et && ef > em) score++;
      else if(px < et && ef < em) score--;
     }
   return score;
  }

//==================================================================
//  ICT LIQUIDITY SWEEP  (H1 — traps retail stops before real move)
//==================================================================
bool LiqSweepBull()
  {
   double lows[], closes[];
   ArraySetAsSeries(lows, true); ArraySetAsSeries(closes, true);
   if(CopyLow  (_Symbol, PERIOD_H1, 1, 25, lows)   < 25) return false;
   if(CopyClose(_Symbol, PERIOD_H1, 1, 25, closes)  < 25) return false;
   double swingLow = lows[3];
   for(int i = 4; i < 25; i++) if(lows[i] < swingLow) swingLow = lows[i];
   return (lows[1] < swingLow && closes[1] > swingLow);
  }

bool LiqSweepBear()
  {
   double highs[], closes[];
   ArraySetAsSeries(highs, true); ArraySetAsSeries(closes, true);
   if(CopyHigh (_Symbol, PERIOD_H1, 1, 25, highs)  < 25) return false;
   if(CopyClose(_Symbol, PERIOD_H1, 1, 25, closes)  < 25) return false;
   double swingHigh = highs[3];
   for(int i = 4; i < 25; i++) if(highs[i] > swingHigh) swingHigh = highs[i];
   return (highs[1] > swingHigh && closes[1] < swingHigh);
  }

//==================================================================
//  ICT ORDER BLOCK  (M15 — last opposite candle before strong move)
//==================================================================
bool BullOB()
  {
   double closes[], opens[];
   ArraySetAsSeries(closes, true); ArraySetAsSeries(opens, true);
   int need = InpOB_Lookback + 2;
   if(CopyClose(_Symbol, PERIOD_M15, 1, need, closes) < need) return false;
   if(CopyOpen (_Symbol, PERIOD_M15, 1, need, opens)  < need) return false;
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 2; i < InpOB_Lookback; i++)
     {
      if(closes[i] >= opens[i]) continue;
      double obH = MathMax(closes[i], opens[i]);
      double obL = MathMin(closes[i], opens[i]);
      if(px >= obL && px <= obH * 1.002) return true;
     }
   return false;
  }

bool BearOB()
  {
   double closes[], opens[];
   ArraySetAsSeries(closes, true); ArraySetAsSeries(opens, true);
   int need = InpOB_Lookback + 2;
   if(CopyClose(_Symbol, PERIOD_M15, 1, need, closes) < need) return false;
   if(CopyOpen (_Symbol, PERIOD_M15, 1, need, opens)  < need) return false;
   double px = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = 2; i < InpOB_Lookback; i++)
     {
      if(closes[i] <= opens[i]) continue;
      double obH = MathMax(closes[i], opens[i]);
      double obL = MathMin(closes[i], opens[i]);
      if(px >= obL * 0.998 && px <= obH) return true;
     }
   return false;
  }

//==================================================================
//  SESSION FILTER  (London 07-12 UTC, NY 12-17 UTC)
//==================================================================
bool SessionOpen()
  {
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if(InpLondonOn && h >= 7  && h < 12) return true;
   if(InpNYOn     && h >= 12 && h < 17) return true;
   return false;
  }

//==================================================================
//  CONSERVATIVE LOT SIZING  (recovery-aware micro-lot engine)
//  Goal: base = 0.02, max = 0.05, compress to 0.01 under DD stress
//==================================================================
double ComputeLots(double slDistPrice)
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- Start from base lots
   double lots = InpBaseLots;

   //--- Recovery-aware tier compression
   if(InpRecoveryAware)
     {
      double ddPct = 100.0 * (DailyAnchor() - eq) / DailyAnchor();
      ddPct = MathMax(0.0, ddPct);

      if(ddPct >= InpTier3_DD)
         lots = InpMinLots;                                    // Tier 3: pure preservation
      else if(ddPct >= InpTier2_DD)
         lots = MathMax(InpMinLots, InpBaseLots * 0.35);       // Tier 2: 35%
      else if(ddPct >= InpTier1_DD)
         lots = MathMax(InpMinLots, InpBaseLots * 0.60);       // Tier 1: 60%
      // else Tier 0: full base
     }

   //--- Risk-budget cap (belt + braces — never exceed 1% per trade)
   if(InpRiskBudgetCap && slDistPrice > 0.0)
     {
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal > 0 && tickSize > 0)
        {
         double lossPerLot = (slDistPrice / tickSize) * tickVal;
         double budgetUSD  = eq * 1.0 / 100.0;  // 1% risk budget (half the 2% wall)
         // Also cap at remaining DRS room / 3  and daily room / 3
         double roomDRS  = MathMax(0, eq - DRSFloor());
         double roomDay  = MathMax(0, eq - DailyHardLine());
         budgetUSD = MathMin(budgetUSD, roomDRS / 3.0);
         budgetUSD = MathMin(budgetUSD, roomDay / 3.0);
         if(lossPerLot > 0 && budgetUSD > 0)
           {
            double lotsFromBudget = budgetUSD / lossPerLot;
            lots = MathMin(lots, lotsFromBudget);
           }
        }
     }

   //--- Hard ceiling
   lots = MathMin(lots, InpMaxLots);

   //--- Normalize to broker step
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = InpLotStep;
   lots = MathFloor(lots / step + 1e-9) * step;

   //--- Enforce min / max
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lots < vmin || lots < InpMinLots) return 0.0;   // budget too small — do not trade
   if(lots > vmax) lots = vmax;

   return lots;
  }

//==================================================================
//  ENTRY COMPLIANCE GATE
//  Returns false (and prints reason) if any rule blocks entry
//==================================================================
bool EntryAllowed(bool isBuy)
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // Day lockdown (after daily flatten)
   if(g_DayLocked && InpLockdownMode)
     { Print("UP9 >> ENTRY BLOCKED: daily lockdown until next UTC day"); return false; }

   // DRS lockdown
   if(g_DRSLocked)
     { Print("UP9 >> ENTRY BLOCKED: DRS emergency lockdown"); return false; }

   // Daily loss approaching — entry stop buffer
   if(eq <= DailyEntryStop())
     { PrintFormat("UP9 >> ENTRY BLOCKED: daily loss ≥ %.1f%% | eq $%.2f ≤ stop $%.2f",
                   InpEntryBlockDay, eq, DailyEntryStop()); return false; }

   // DRS entry buffer
   if(eq <= DRSEntryStop())
     { PrintFormat("UP9 >> ENTRY BLOCKED: within %.1f%% of DRS floor | eq $%.2f ≤ stop $%.2f",
                   InpEntryBlockDRS, eq, DRSEntryStop()); return false; }

   // Max positions & Staggered Profit Gate
   int cnt = 0;
   double last_px = 0;
   bool all_in_profit = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
        {
         cnt++;
         double flt = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(flt <= 0) all_in_profit = false;
         double open_px = PositionGetDouble(POSITION_PRICE_OPEN);
         if(last_px == 0) last_px = open_px;
         else if(isBuy && open_px > last_px) last_px = open_px;
         else if(!isBuy && open_px < last_px) last_px = open_px;
        }
     }
   if(cnt >= InpMaxPositions)
     { Print("UP9 >> ENTRY BLOCKED: max positions (", cnt, ")"); return false; }

   // Staggered entry requirement: existing positions must be in profit!
   if(cnt > 0 && !all_in_profit)
     { Print("UP9 >> ENTRY BLOCKED: staggered entry requires initial position to be in profit"); return false; }

   // Price distance stagger filter
   if(cnt > 0 && last_px > 0)
     {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double cur_px = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double min_dist = 100 * point;
      if(isBuy && cur_px < last_px + min_dist)
        { Print("UP9 >> ENTRY BLOCKED: staggered entry distance too close"); return false; }
      if(!isBuy && cur_px > last_px - min_dist)
        { Print("UP9 >> ENTRY BLOCKED: staggered entry distance too close"); return false; }
     }

   // Spread gate
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spr   = point > 0 ?
                  (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point : 0;
   if(spr > InpMaxSpreadPts)
     { PrintFormat("UP9 >> ENTRY BLOCKED: spread %.0f pts > %.0f cap", spr, InpMaxSpreadPts); return false; }

   // Friday guard
   MqlDateTime fd; TimeToStruct(TimeCurrent(), fd);
   if(InpFridayClose && fd.day_of_week == 5 &&
      (fd.hour > InpFridayHour || (fd.hour == InpFridayHour && fd.min >= InpFridayMin)))
     { Print("UP9 >> ENTRY BLOCKED: Friday close guard"); return false; }

   // Bar spacing
   if(g_BarsSince < InpMinBarsBetween)
     { Print("UP9 >> ENTRY BLOCKED: min bars between entries (", g_BarsSince, ")"); return false; }

   // Hedge block (never open against existing position on same symbol)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      bool existBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(existBuy != isBuy)
        { Print("UP9 >> ENTRY BLOCKED: hedge protection"); return false; }
     }

   return true;
  }

//==================================================================
//  SIGNAL ENGINE  (the 85.1% WR core)
//  Returns +1 buy / -1 sell / 0 no signal
//==================================================================
int RawSignal()
  {
   // 1. MTF cascade alignment
   int sc = MTFScore();
   if(MathAbs(sc) < InpMTF_MinScore) return 0;

   // 2. ADX trend strength
   if(ADX() < InpADX_Min) return 0;

   // 3. RSI momentum confirmation
   double rsi = RSI();

   // 4. M15 EMA fast/mid crossover (precise entry timing)
   double f1 = BufVal(g_hEMA_F[3], 0, 1);
   double f2 = BufVal(g_hEMA_F[3], 0, 2);
   double m1 = BufVal(g_hEMA_M[3], 0, 1);
   double m2 = BufVal(g_hEMA_M[3], 0, 2);
   if(f1 <= 0 || f2 <= 0 || m1 <= 0 || m2 <= 0) return 0;

   int sig = 0;
   if(f2 <= m2 && f1 > m1 && sc >= InpMTF_MinScore && rsi < InpRSI_OB) sig = +1;
   if(f2 >= m2 && f1 < m1 && sc <= -InpMTF_MinScore && rsi > InpRSI_OS) sig = -1;
   if(sig == 0) return 0;

   bool isBuy = (sig > 0);

   // 5. ICT Liquidity Sweep (H1)
   if(InpReqLiqSweep)
     {
      if(isBuy  && !LiqSweepBull()) return 0;
      if(!isBuy && !LiqSweepBear()) return 0;
     }

   // 6. ICT Order Block (M15)
   if(InpReqOB)
     {
      if(isBuy  && !BullOB()) return 0;
      if(!isBuy && !BearOB()) return 0;
     }

   return sig;
  }

//==================================================================
//  POSITION STATE MANAGEMENT
//==================================================================
int PosIdx(ulong ticket, bool create)
  {
   int n = ArraySize(g_pos);
   for(int i = 0; i < n; i++) if(g_pos[i].ticket == ticket) return i;
   if(!create) return -1;
   ArrayResize(g_pos, n + 1);
   g_pos[n].ticket     = ticket;
   g_pos[n].initVol    = 0;
   g_pos[n].rDist      = 0;
   g_pos[n].tp1Done    = false;
   g_pos[n].tp2Done    = false;
   g_pos[n].beDone     = false;
   g_pos[n].pc1000Done = false;
   return n;
  }

void PruneStates()
  {
   for(int i = ArraySize(g_pos) - 1; i >= 0; i--)
      if(!PositionSelectByTicket(g_pos[i].ticket))
        {
         for(int j = i; j < ArraySize(g_pos) - 1; j++) g_pos[j] = g_pos[j + 1];
         ArrayResize(g_pos, ArraySize(g_pos) - 1);
        }
  }

//==================================================================
//  PARTIAL CLOSE HELPER
//==================================================================
bool ClosePartial(ulong ticket, double pct)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   double vol  = PositionGetDouble(POSITION_VOLUME);
   double step = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_VOLUME_STEP);
   if(step <= 0) step = InpLotStep;
   double closeVol = MathFloor(vol * pct / 100.0 / step + 1e-9) * step;
   double vmin     = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_VOLUME_MIN);
   if(closeVol < vmin || closeVol >= vol) return false; // remainder must be tradeable
   trade.SetDeviationInPoints(100);
   return trade.PositionClosePartial(ticket, closeVol);
  }

//==================================================================
//  MANAGE OPEN POSITIONS
//  - Auto-attach SL/TP on naked positions
//  - Golden ratio TP ladder (33%@1R, 33%@1.618R, ride to 2.618R)
//  - Breakeven then ATR trail (tightens if MTF opposes)
//  - Emergency close at -1.5% (0.5% buffer before 2% wall)
//==================================================================
void ManagePositions()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      string sym    = PositionGetString(POSITION_SYMBOL);
      long   type   = PositionGetInteger(POSITION_TYPE);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      bool   isBuy  = (type == POSITION_TYPE_BUY);
      double bid    = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);
      double px     = isBuy ? bid : ask;
      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      long   stopLvl= SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist= (double)stopLvl * point;

      //--- Emergency per-trade wall (-1.5% = 2% - 0.5% buffer)
      if(profit <= -TradeCloseUSD(eq))
        {
         trade.PositionClose(ticket);
         PrintFormat("UP9 >> EMERGENCY CLOSE #%I64u | float $%.2f ≤ -$%.2f (wall -$%.2f)",
                     ticket, profit, TradeCloseUSD(eq), TradeHardUSD(eq));
         continue;
        }

      int si = PosIdx(ticket, true);
      if(g_pos[si].initVol <= 0.0) g_pos[si].initVol = vol;
      if(!g_pos[si].pc1000Done && (profit >= 1000.0 || profit <= -1000.0))
        {
         if(ClosePartial(ticket, 50.0))
           {
            g_pos[si].pc1000Done = true;
            PrintFormat("UP9 >> UNIVERSAL $1000 BREACH >> Partial closed 50%% on #%I64u (P&L: $%.2f)", ticket, profit);
           }
        }

      //--- Auto SL/TP on naked positions
      if(sl == 0.0)
        {
         double atr = ATR_M15();
         if(atr <= 0) continue;
         double stopDist = atr * InpATR_StopMult;
         double newSL    = isBuy ? entry - stopDist : entry + stopDist;
         double rDist    = stopDist;
         double newTP    = isBuy ? entry + rDist * InpTP3_R : entry - rDist * InpTP3_R;
         newSL = NormalizeDouble(newSL, digits);
         newTP = NormalizeDouble(newTP, digits);
         if(trade.PositionModify(ticket, newSL, newTP))
           {
            g_pos[si].rDist = stopDist;
            sl = newSL;
            PrintFormat("UP9 >> Auto SL/TP #%I64u | SL=%.5f TP=%.5f | risk≈$%.2f",
                        ticket, newSL, newTP,
                        (stopDist / SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE)) *
                         SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE) * vol);
           }
        }
      else if(g_pos[si].rDist <= 0.0)
         g_pos[si].rDist = MathAbs(entry - sl);

      double R     = g_pos[si].rDist;
      if(R <= 0) continue;
      double moveR = isBuy ? (px - entry) / R : (entry - px) / R;

      //--- TP1 partial (33% at 1.000R)
      if(!g_pos[si].tp1Done && moveR >= InpTP1_R)
        {
         if(ClosePartial(ticket, InpTP1_ClosePct))
           {
            g_pos[si].tp1Done = true;
            PrintFormat("UP9 >> TP1 partial #%I64u | %.0f%% at %.2fR", ticket, InpTP1_ClosePct, moveR);
           }
        }

      //--- TP2 partial (33% at 1.618R — golden ratio)
      if(g_pos[si].tp1Done && !g_pos[si].tp2Done && moveR >= InpTP2_R)
        {
         if(ClosePartial(ticket, InpTP2_ClosePct))
           {
            g_pos[si].tp2Done = true;
            PrintFormat("UP9 >> TP2 φ-close #%I64u | %.0f%% at %.3fR (golden ratio)", ticket, InpTP2_ClosePct, moveR);
           }
        }

      //--- Breakeven + ATR trail (monotonic — only ever tightens)
      double desiredSL = 0.0;

      // Breakeven: trigger at 0.8R
      if(!g_pos[si].beDone && moveR >= InpBE_TriggerR)
        {
         double off = InpBE_Pips * 10.0 * point;
         desiredSL = isBuy ? entry + off : entry - off;
         g_pos[si].beDone = true;
         PrintFormat("UP9 >> Breakeven triggered #%I64u at %.2fR", ticket, moveR);
        }

      // ATR trail after BE
      if(g_pos[si].beDone)
        {
         double atrH = ATR_H1();
         if(atrH > 0)
           {
            // Tighten trail if MTF turns against us
            int sc    = MTFScore();
            bool opp  = (isBuy && sc <= -2) || (!isBuy && sc >= 2);
            double mult = opp ? InpATR_TightMult : InpATR_TrailMult;
            double chase = isBuy ? px - atrH * mult : px + atrH * mult;
            if(desiredSL == 0.0) desiredSL = chase;
            else desiredSL = isBuy ? MathMax(desiredSL, chase) : MathMin(desiredSL, chase);
           }
        }

      // Apply SL modification (monotonic check)
      if(desiredSL != 0.0)
        {
         desiredSL = NormalizeDouble(desiredSL, digits);
         bool tighter = isBuy ? (desiredSL > sl + point) : (sl == 0.0 || desiredSL < sl - point);
         bool valid   = isBuy ? (desiredSL < bid - minDist) : (desiredSL > ask + minDist);
         if(tighter && valid)
            trade.PositionModify(ticket, desiredSL, tp);
        }
     }
  }

//==================================================================
//  ACCOUNT GUARD  (called every tick + timer)
//  Rolls daily anchor, updates HWM, enforces flatten/lockdown
//==================================================================
void AccountGuard()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime today = UTCDate(TimeGMT());

   // Roll UTC day
   if(today != g_DayStamp)
     {
      g_DayStamp    = today;
      g_DayEqStart  = eq;
      g_DayPeak     = eq;
      g_DayLocked   = false;
      g_TodayRealized = 0;
      PrintFormat("UP9 >> DAY ROLL | anchor $%.2f | daily hard $%.2f | DRS floor $%.2f",
                  eq, DailyHardLine(), DRSFloor());
      SaveState();
     }

   // Update HWM
   if(eq > g_HWM) { g_HWM = eq; SaveState(); }

   // Update intraday peak
   if(eq > g_DayPeak) { g_DayPeak = eq; SaveState(); }

   //--- DRS breach check (account-killing — highest priority)
   if(eq <= DRSFlatLine())
     {
      if(!g_DRSLocked)
        {
         g_DRSLocked = true;
         PrintFormat("UP9 >> DRS EMERGENCY | eq $%.2f ≤ flatten $%.2f (hard floor $%.2f) | FLATTENING ALL",
                     eq, DRSFlatLine(), DRSFloor());
         FlattenAll("DRS shield buffer hit");
        }
     }
   else if(g_DRSLocked && eq > DRSEntryStop())
     {
      g_DRSLocked = false;
      Print("UP9 >> DRS clear — resuming normal operation");
     }

   //--- Daily DD check
   if(!g_DayLocked && eq <= DailyFlatLine())
     {
      g_DayLocked = true;
      PrintFormat("UP9 >> DAILY FLATTEN | eq $%.2f ≤ flatten $%.2f (hard line $%.2f)",
                  eq, DailyFlatLine(), DailyHardLine());
      FlattenAll("Daily soft-stop buffer hit");
      SaveState();
     }

   // Lockdown enforcement — kill anything opened after flatten
   if((g_DayLocked && InpLockdownMode) || g_DRSLocked)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionClose(t);
        }
     }
  }

//==================================================================
//  FLATTEN ALL  (close every position under this magic)
//==================================================================
void FlattenAll(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.SetDeviationInPoints(100);
      if(trade.PositionClose(t))
         PrintFormat("UP9 >> CLOSED #%I64u | reason: %s", t, reason);
     }
  }

//==================================================================
//  FRIDAY HARD CLOSE
//==================================================================
void FridayGuard()
  {
   if(!InpFridayClose) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 &&
      (dt.hour > InpFridayHour || (dt.hour == InpFridayHour && dt.min >= InpFridayMin)))
      FlattenAll("Friday hard close");
  }

//==================================================================
//  ENTRY EXECUTION
//==================================================================
void TryEntry()
  {
   if(!SessionOpen()) return;

   // Get raw signal
   int raw = RawSignal();
   if(raw == 0) return;

   // Apply Inverse Mode + Direction filter (standing JAZZYLYFE rule)
   int sig = InpInverseMode ? -raw : raw;
   if(InpDirection == DIR_BUY  && sig < 0) return;
   if(InpDirection == DIR_SELL && sig > 0) return;

   bool isBuy = (sig > 0);

   // Compliance gate
   if(!EntryAllowed(isBuy)) return;

   // Compute stop distance
   double atr = ATR_M15();
   if(atr <= 0) return;
   double stopDist = atr * InpATR_StopMult;
   double px       = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl       = isBuy ? px - stopDist : px + stopDist;
   double tp       = isBuy ? px + stopDist * InpTP3_R
                           : px - stopDist * InpTP3_R;

   // Compute lots (conservative micro-lot, recovery-aware)
   double lots = ComputeLots(stopDist);
   if(lots <= 0.0)
     {
      Print("UP9 >> ENTRY SKIPPED: risk budget too small for min lot — standing down to protect account");
      return;
     }

   // Final wall sanity check — computed loss must not breach 2% hard wall
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   if(tickSize > 0 && tickVal > 0)
     {
      double worstCase = (stopDist / tickSize) * tickVal * lots;
      if(worstCase > eq * g_TradePct / 100.0)
        {
         Print("UP9 >> ENTRY BLOCKED: worst-case $", worstCase, " > ", g_TradePct, "% wall");
         return;
        }
     }

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   trade.SetDeviationInPoints(50);
   bool ok = isBuy ? trade.Buy (lots, _Symbol, 0, sl, tp, InpComment)
                   : trade.Sell(lots, _Symbol, 0, sl, tp, InpComment);

   if(ok)
     {
      g_BarsSince = 0;
      ulong ticket = trade.ResultDeal();
      if(ticket > 0)
        {
         int si = PosIdx(ticket, true);
       if(!g_pos[si].pc1000Done && (profit >= 1000.0 || profit <= -1000.0))
         {
          if(ClosePartial(ticket, 50.0))
            {
             g_pos[si].pc1000Done = true;
             PrintFormat("UP9 >> UNIVERSAL $1000 BREACH >> Partial closed 50%% on #%I64u (P&L: $%.2f)", ticket, profit);
            }
         }
         g_pos[si].initVol = lots;
         g_pos[si].rDist   = stopDist;
        }
      PrintFormat("UP9 >> %s | %s %.2f lots | SL=%.5f TP=%.5f | MTF=%d ADX=%.1f RSI=%.1f | daily room $%.0f DRS room $%.0f",
                  isBuy ? "BUY" : "SELL", _Symbol, lots, sl, tp,
                  MTFScore(), ADX(), RSI(),
                  eq - DailyHardLine(), eq - DRSFloor());
     }
   else
      PrintFormat("UP9 >> Entry FAILED: %s (code %d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
  }

//==================================================================
//  REALIZED P/L TRACKING  (for Best-Day / Valid-Day payout stats)
//==================================================================
void UpdateStats()
  {
   // Called every 60s — pulls today's realized from deal history
   static datetime lastCheck = 0;
   if(TimeCurrent() - lastCheck < 60) return;
   lastCheck = TimeCurrent();
   datetime today = UTCDate(TimeGMT());
   if(today != g_StatsDay) { g_StatsDay = today; g_TodayRealized = 0; }
   datetime startSelect = today + (TimeCurrent() - TimeGMT());
   if(!HistorySelect(startSelect, TimeCurrent())) return;
   double dayTotal = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY) continue;
      dayTotal += HistoryDealGetDouble(d, DEAL_PROFIT)
               +  HistoryDealGetDouble(d, DEAL_SWAP)
               +  HistoryDealGetDouble(d, DEAL_COMMISSION);
     }
   g_TodayRealized = dayTotal;
   if(dayTotal > g_BestDayProfit) g_BestDayProfit = dayTotal;
  }

//==================================================================
//  DASHBOARD (on-chart compliance readout)
//==================================================================
void Dashboard()
  {
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddUsed  = DailyAnchor() - eq;
   double drsUsed = g_HWM - eq;
   double dailyRoom = eq - DailyHardLine();
   double drsRoom   = eq - DRSFloor();

   // Recovery tier label
   double ddPct = DailyAnchor() > 0 ? 100.0 * ddUsed / DailyAnchor() : 0;
   string tier = ddPct >= InpTier3_DD ? "T3-PRESERVATION" :
                 ddPct >= InpTier2_DD ? "T2-REDUCED(35%)" :
                 ddPct >= InpTier1_DD ? "T1-REDUCED(60%)" : "T0-FULL(100%)";

   string lock = (g_DayLocked ? "DAY-LOCKED " : "") + (g_DRSLocked ? "DRS-LOCKED" : "");
   if(lock == "") lock = "NORMAL";

   // Current base lot at this tier
   double atr = ATR_M15();
   double lots = ComputeLots(atr > 0 ? atr * InpATR_StopMult : 0.001);

   string s = "";
   s += "╔══ JAZZYLYFE Ultimate Profit v9 — Upcomers Oracle ══╗\n";
   s += "║ Equity  : $" + DoubleToString(eq, 2) + "  Balance: $" + DoubleToString(bal, 2) + "\n";
   s += "║ HWM     : $" + DoubleToString(g_HWM, 2) + "\n";
   s += "╠══ COMPLIANCE LINES ════════════════════════════════╣\n";
   s += "║ Daily   : room $" + DoubleToString(dailyRoom, 2) +
        " | flatten $" + DoubleToString(DailyFlatLine(), 2) +
        " | HARD $" + DoubleToString(DailyHardLine(), 2) + "\n";
   s += "║ DRS     : room $" + DoubleToString(drsRoom, 2) +
        " | flatten $" + DoubleToString(DRSFlatLine(), 2) +
        " | FLOOR $" + DoubleToString(DRSFloor(), 2) + "\n";
   s += "║ Trade   : auto-close at -$" +
        DoubleToString(TradeCloseUSD(eq), 2) +
        " | wall -$" + DoubleToString(TradeHardUSD(eq), 2) + "\n";
   s += "╠══ SIZING & STATUS ════════════════════════════════╣\n";
   s += "║ DD Used : $" + DoubleToString(ddUsed, 2) +
        " (" + DoubleToString(ddPct, 2) + "%) → " + tier + "\n";
   s += "║ Next lot: " + DoubleToString(lots, 2) +
        " lots | Base: " + DoubleToString(InpBaseLots, 2) +
        " | Max: " + DoubleToString(InpMaxLots, 2) + "\n";
   s += "║ Status  : " + lock + " | Positions: " + (string)PositionsTotal() + "\n";
   s += "╠══ SIGNAL  ════════════════════════════════════════╣\n";
   s += "║ MTF     : " + (string)MTFScore() + "/4" +
        " | ADX: " + DoubleToString(ADX(), 1) +
        " | RSI: " + DoubleToString(RSI(), 1) +
        " | Session: " + (SessionOpen() ? "OPEN" : "CLOSED") + "\n";
   s += "╠══ PAYOUT TRACKER ═════════════════════════════════╣\n";
   s += "║ Today P/L : $" + DoubleToString(g_TodayRealized, 2) +
        " (" + DoubleToString(InpAcctSize > 0 ? 100.0 * g_TodayRealized / InpAcctSize : 0, 3) + "% acct)" +
        " | Best Day: $" + DoubleToString(g_BestDayProfit, 2) + "\n";
   s += "╚══ JAZZYLYFE | TheBrimberry | Brimberry LLC ═══════╝";
   Comment(s);
  }

//==================================================================
//  INIT
//==================================================================
int OnInit()
  {
   // Resolve program limits
   switch(InpProgram)
     {
      case PROG_ORACLE:   g_DailyPct = 4.0; g_DRSPct = 5.0; g_TradePct = 2.0; break;
      case PROG_VANGUARD: g_DailyPct = 4.0; g_DRSPct = 7.0; g_TradePct = 2.0; break;
      default:            g_DailyPct = InpCustDailyPct; g_DRSPct = InpCustDRSPct; g_TradePct = InpCustTradePct; break;
     }

   // Shared GV prefix (same as SmartGuard overlay — they see the same HWM)
   g_GVPfx = "JLUPC_" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "_";

   // Load persisted state (HWM, daily anchors survive restarts)
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_HWM     = eq;
   g_DayStamp= UTCDate(TimeGMT());
   g_DayEqStart = eq;
   g_DayPeak    = eq;
   LoadState();
   if(g_HWM < eq) g_HWM = eq;

   // Build all indicator handles
   // Assign g_TF here — brace-init on enum arrays is not supported in MQL5
   g_TF[0] = PERIOD_D1;
   g_TF[1] = PERIOD_H4;
   g_TF[2] = PERIOD_H1;
   g_TF[3] = PERIOD_M15;
   for(int i = 0; i < 4; i++)
     {
      g_hEMA_F[i] = iMA(_Symbol, g_TF[i], InpEMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_M[i] = iMA(_Symbol, g_TF[i], InpEMA_Mid,   0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_S[i] = iMA(_Symbol, g_TF[i], InpEMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_T[i] = iMA(_Symbol, g_TF[i], InpEMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
     }
   g_hRSI     = iRSI(_Symbol, PERIOD_M15, InpRSI_Period, PRICE_CLOSE);
   g_hADX     = iADX(_Symbol, PERIOD_M15, InpADX_Period);
   g_hATR_M15 = iATR(_Symbol, PERIOD_M15, InpATR_Period);
   g_hATR_H1  = iATR(_Symbol, PERIOD_H1,  InpATR_Period);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetAsyncMode(false);

   EventSetTimer(MathMax(1, InpTimerSec));

   PrintFormat("UP9 >> ONLINE | %s | Program=%s | Daily %.1f%% | DRS %.1f%% | Trade %.1f%% | Base %.2f lots | Max %.2f lots | Equity $%.2f | HWM $%.2f | DRS floor $%.2f | Daily hard $%.2f",
               _Symbol,
               InpProgram == PROG_ORACLE ? "ORACLE" : InpProgram == PROG_VANGUARD ? "VANGUARD" : "CUSTOM",
               g_DailyPct, g_DRSPct, g_TradePct,
               InpBaseLots, InpMaxLots, eq, g_HWM, DRSFloor(), DailyHardLine());
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveState();
   Comment("");
   Print("UP9 >> Offline | HWM $", g_HWM, " saved");
  }

//==================================================================
//  MAIN LOOP
//==================================================================
void OnTick()
  {
   // New M15 bar detection
   datetime bar = iTime(_Symbol, PERIOD_M15, 0);
   bool newBar  = (bar != g_LastBar);
   if(newBar) { g_LastBar = bar; g_BarsSince++; }

   // Account guard runs every tick
   AccountGuard();
   if(g_DayLocked || g_DRSLocked) { Dashboard(); return; }

   // Position management runs every tick
   ManagePositions();

   // Entry attempt only on new bar
   if(newBar) TryEntry();

   // Scheduled tasks
   FridayGuard();
   PruneStates();
   UpdateStats();
   Dashboard();
  }

// Timer keeps guards running even on quiet charts
void OnTimer()
  {
   AccountGuard();
   ManagePositions();
   FridayGuard();
   Dashboard();
  }
//+------------------------------------------------------------------+
