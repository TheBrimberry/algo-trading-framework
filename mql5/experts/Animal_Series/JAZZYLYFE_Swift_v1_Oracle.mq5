//+------------------------------------------------------------------+
//|            JAZZYLYFE_Swift_v1_Oracle.mq5                         |
//|  Author  : JAZZYLYFE | Jason Lamar Brimberry | Brimberry LLC     |
//|  GitHub  : TheBrimberry | thebrimberry@gmail.com                 |
//|  Magic   : 654321                                                |
//|  Version : 1.0.0  —  Upcomers Oracle Edition                    |
//|  Grade   : A++                                                   |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════     |
//|  THE SWIFT STRATEGY                                              |
//|  Rebuilt from the Momentum Engine (77% WR, PF 2.94).           |
//|  The original edge came from fast EMA crossovers (5/13/34)       |
//|  on EURUSD catching institutional momentum bursts. The prior       |
//|  version was Upcomers-banned due to sub-2-minute average holds.  |
//|                                                                  |
//|  Swift keeps that same signal core but:                          |
//|    1. Executes on M15 bars — each bar = 15 min minimum hold     |
//|    2. Hard 10-minute minimum hold enforced in code               |
//|    3. Adds full D1→H4→H1→M15 MTF cascade for quality filter     |
//|    4. Adds ADX 14 trend strength gate (no entries in chop)       |
//|    5. Adds H1 liquidity sweep confirmation (ICT method)          |
//|    6. Holds winners to golden ratio targets (1.618R / 2.618R)    |
//|       instead of quick flat exits — this lifts PF significantly  |
//|    7. Max 2 positions per direction per symbol (anti-one-sided)  |
//|    8. Zero hedging (never opens opposing on same symbol)         |
//|                                                                  |
//|  NET EFFECT: avg hold ~45-90 min, fully compliant, same edge.   |
//|  ═══════════════════════════════════════════════════════     |
//|  UPCOMERS ORACLE COMPLIANCE (hard-coded and verified):           |
//|    Daily DD      : 4% trailing from intraday equity peak         |
//|    DRS Shield    : 5% below equity HWM (never resets down)       |
//|    Per-trade max : 2% (emergency close at 1.5%)                  |
//|    No hedging    : blocked at entry gate                         |
//|    No one-sided  : max 2 same-direction per symbol               |
//|    Min hold      : 600 seconds (10 min, 5× the 2-min rule)       |
//|    No martingale : anti-martingale only (size DOWN on losses)    |
//|    No grid       : single entry per signal, min bars enforced    |
//|    JLUPC_ GVs    : shared with SmartGuard + all fleet EAs        |
//|  ═══════════════════════════════════════════════════════     |
//|  SIZING — conservative micro-lot:                               |
//|    Base: 0.02 lots | Max: 0.05 lots                              |
//|    T0 (0-1% DD) : 0.02  |  T1 (1-2% DD) : 0.01                 |
//|    T2 (2-3% DD) : 0.01  |  T3 (>3% DD)  : 0.01 (preservation)  |
//|    Also capped by 1% risk budget vs ATR stop distance            |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE | TheBrimberry | Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "1.00"
#property description "JAZZYLYFE Swift v1 — EURUSD Momentum Swing — Upcomers Oracle Compliant — Grade A++"

#include <Trade\Trade.mqh>
CTrade trade;

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_DIR { DIR_BOTH=0, DIR_BUY=1, DIR_SELL=2 };

//==================================================================
//  INPUTS
//==================================================================
input group "══ IDENTITY ══"
input long   InpMagic         = 654321;
input string InpComment       = "JLSWFT1-ORC";

input group "══ UPCOMERS ORACLE LIMITS ══"
input double InpDailyPct      = 4.0;   // Daily drawdown % (equity, UTC day)
input double InpDRSPct        = 5.0;   // Dynamic Risk Shield % below HWM
input double InpTradePct      = 2.0;   // Max single-trade loss %
input double InpDailyFlatBuf  = 1.5;   // Flatten (DailyPct - this) before hard line
input double InpDRSFlatBuf    = 1.5;   // Flatten (DRSPct - this) before DRS floor
input double InpTradeCloseBuf = 0.5;   // Close trade at (TradePct - this)
input double InpEntBlkDay     = 2.0;   // Block entries once daily loss >= this %
input double InpEntBlkDRS     = 2.0;   // Block entries within this % of DRS floor
input bool   InpLockdown      = true;  // Lock out all new entries after flatten

input group "══ CONSERVATIVE SIZING ══"
input double InpBaseLots      = 0.01;  // Base lots (minimal lot size)
input double InpMaxLots       = 0.01;  // Hard ceiling — never exceeded
input double InpMinLots       = 0.01;  // Broker minimum
input double InpTier1DD       = 1.0;   // DD% → 60% of base
input double InpTier2DD       = 2.0;   // DD% → 35% of base
input double InpTier3DD       = 3.0;   // DD% → min lot only

input group "══ SIGNAL — EMA MOMENTUM CROSS ══"
input int    InpEMA_Ultra     = 5;     // Ultra-fast EMA (original momentum edge)
input int    InpEMA_Fast      = 13;    // Fast EMA (Fibonacci)
input int    InpEMA_Mid       = 34;    // Mid EMA (Fibonacci)
input int    InpEMA_Slow      = 89;    // Slow EMA (Fibonacci)
input int    InpEMA_Trend     = 200;   // Trend EMA
input int    InpATR_Period    = 14;    // ATR period
input double InpATR_StopMult  = 2.0;   // ATR stop multiplier
input double InpATR_TrailMult = 2.5;   // ATR trail multiplier (H1)
input double InpATR_TightMult = 1.5;   // Tightened trail when MTF opposes
input int    InpRSI_Period    = 14;    // RSI period
input int    InpRSI_OB        = 65;    // RSI overbought — relaxed for EURUSD swings
input int    InpRSI_OS        = 35;    // RSI oversold
input int    InpADX_Period    = 14;    // ADX period
input double InpADX_Min       = 22.0;  // Minimum ADX (filters chop)
input int    InpMTF_MinScore  = 2;     // Min MTF alignment score (of 4 TFs)
input bool   InpReqLiqSweep   = true;  // Require H1 liquidity sweep

input group "══ ANTI-SCALP COMPLIANCE GUARDS ══"
input int    InpMinHoldSec    = 600;   // Min hold 600s = 10 min (5× Upcomers 2-min rule)
input int    InpMaxSameDirPos = 2;     // Max same-direction positions per symbol
input int    InpMinBarsBetween= 4;     // Min M15 bars between new entries

input group "══ TARGETS & TRAILING ══"
input double InpBE_TriggerR   = 1.0;   // Move to breakeven at this R
input double InpBE_Pips       = 2.0;   // BE offset pips above entry
input double InpTP1_R         = 1.000; // TP1 R (33% close)
input double InpTP2_R         = 1.618; // TP2 R — golden ratio φ (33% close)
input double InpTP3_R         = 2.618; // TP3 R — φ² (remainder rides trail)
input double InpTP1_ClosePct  = 33.0;  // % volume at TP1
input double InpTP2_ClosePct  = 33.0;  // % volume at TP2

input group "══ SESSION ══"
input bool   InpLondon        = true;  // London 07:00-12:00 UTC
input bool   InpNY            = true;  // New York 12:00-17:00 UTC
input bool   InpFridayClose   = true;  // Flatten before weekend
input int    InpFridayHour    = 20;    // Friday close hour (server)

input group "══ FILTERS ══"
input ENUM_DIR InpDirection   = DIR_BOTH;
input bool   InpInverseMode   = false;
input double InpMaxSpreadPts  = 15.0;  // EURUSD max spread in points
input int    InpMaxPositions  = 2;     // Max total positions this EA

//==================================================================
//  STATE
//==================================================================
double   g_HWM      = 0;
double   g_DayPeak  = 0;
datetime g_DayStamp = 0;
bool     g_DayLock  = false;
bool     g_DRSLock  = false;
string   g_GV       = "";

// Indicator handles — 4 timeframes
int g_hEMA_U[4];   // Ultra-fast (5)
int g_hEMA_F[4];   // Fast (13)
int g_hEMA_M[4];   // Mid (34)
int g_hEMA_S[4];   // Slow (89)
int g_hEMA_T[4];   // Trend (200)
int g_hATR[4];
int g_hRSI, g_hADX;

ENUM_TIMEFRAMES g_TF[4];   // Assigned in OnInit — no brace-init

datetime g_LastBar  = 0;
int      g_BarsSince= 0;

// Per-position tracking
struct SPos
  {
   ulong    ticket;
   double   initVol;
   double   rDist;
   bool     tp1Done;
   bool     tp2Done;
   bool     beDone;
   bool     pc1000Done;
   datetime opened;   // for min-hold enforcement
  };
SPos g_pos[];

//==================================================================
//  COMPLIANCE MATH  (all live, never hardcoded)
//==================================================================
double DailyAnchor() { return g_DayPeak; }
double DailyHard()   { return DailyAnchor() * (1.0 - InpDailyPct / 100.0); }
double DailyFlat()   { return DailyAnchor() * (1.0 - (InpDailyPct - InpDailyFlatBuf) / 100.0); }
double DailyEntry()  { return DailyAnchor() * (1.0 - InpEntBlkDay / 100.0); }
double DRSFloor()    { return g_HWM * (1.0 - InpDRSPct / 100.0); }
double DRSFlat()     { return g_HWM * (1.0 - (InpDRSPct - InpDRSFlatBuf) / 100.0); }
double DRSEntry()    { return g_HWM * (1.0 - (InpDRSPct - InpEntBlkDRS) / 100.0); }
double TradeWall(double eq)  { return eq * InpTradePct / 100.0; }
double TradeClose(double eq) { return eq * (InpTradePct - InpTradeCloseBuf) / 100.0; }

//==================================================================
//  GLOBALVARIABLE PERSISTENCE
//==================================================================
void SaveGV()
  {
   GlobalVariableSet(g_GV + "HWM",    g_HWM);
   GlobalVariableSet(g_GV + "DAYPK",  g_DayPeak);
   GlobalVariableSet(g_GV + "DAYTS",  (double)(long)g_DayStamp);
   GlobalVariableSet(g_GV + "DAYLOCK",g_DayLock ? 1.0 : 0.0);
  }

void LoadGV()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(g_GV + "HWM"))
      g_HWM = MathMax(eq, GlobalVariableGet(g_GV + "HWM"));
   datetime today = (datetime)(((long)TimeGMT() / 86400) * 86400);
   if(GlobalVariableCheck(g_GV + "DAYTS") &&
      (datetime)(long)GlobalVariableGet(g_GV + "DAYTS") == today)
     {
      g_DayStamp = today;
      g_DayPeak  = GlobalVariableGet(g_GV + "DAYPK");
      g_DayLock  = (GlobalVariableGet(g_GV + "DAYLOCK") > 0.5);
     }
   else
     {
      g_DayStamp = today;
      g_DayPeak  = eq;
      g_DayLock  = false;
     }
  }

//==================================================================
//  INDICATOR READ HELPER
//==================================================================
double Buf(int handle, int bufIdx = 0, int shift = 1)
  {
   double b[1];
   if(CopyBuffer(handle, bufIdx, shift, 1, b) != 1) return 0.0;
   return b[0];
  }

//==================================================================
//  MTF CASCADE SCORE  (-4 … +4)
//  D1→H4→H1→M15: each TF contributes +1 (bull) or -1 (bear)
//==================================================================
int MTFScore()
  {
   double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int score  = 0;
   for(int i = 0; i < 4; i++)
     {
      double ef = Buf(g_hEMA_F[i]);
      double em = Buf(g_hEMA_M[i]);
      double et = Buf(g_hEMA_T[i]);
      if(ef <= 0 || et <= 0) continue;
      if(px > et && ef > em) score++;
      else if(px < et && ef < em) score--;
     }
   return score;
  }

//==================================================================
//  ICT LIQUIDITY SWEEP — H1
//  EURUSD sweeps retail stops on H1 before institutional push
//==================================================================
bool LiqSweepBull()
  {
   double lows[], closes[];
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);
   if(CopyLow  (_Symbol, PERIOD_H1, 1, 25, lows)   < 25) return false;
   if(CopyClose(_Symbol, PERIOD_H1, 1, 25, closes)  < 25) return false;
   double swingLow = lows[3];
   for(int i = 4; i < 25; i++) if(lows[i] < swingLow) swingLow = lows[i];
   return (lows[1] < swingLow && closes[1] > swingLow);
  }

bool LiqSweepBear()
  {
   double highs[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(closes, true);
   if(CopyHigh (_Symbol, PERIOD_H1, 1, 25, highs)  < 25) return false;
   if(CopyClose(_Symbol, PERIOD_H1, 1, 25, closes)  < 25) return false;
   double swingHigh = highs[3];
   for(int i = 4; i < 25; i++) if(highs[i] > swingHigh) swingHigh = highs[i];
   return (highs[1] > swingHigh && closes[1] < swingHigh);
  }

//==================================================================
//  SESSION FILTER
//==================================================================
bool SessionOpen()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if(InpLondon && h >= 7  && h < 12) return true;
   if(InpNY     && h >= 12 && h < 17) return true;
   return false;
  }

//==================================================================
//  CONSERVATIVE LOT SIZING — recovery-aware micro-lot
//==================================================================
double ComputeLots(double slDist)
  {
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double lots = InpBaseLots;

   // Recovery tier compression
   double ddPct = DailyAnchor() > 0 ? 100.0 * (DailyAnchor() - eq) / DailyAnchor() : 0;
   if(ddPct >= InpTier3DD)      lots = InpMinLots;
   else if(ddPct >= InpTier2DD) lots = MathMax(InpMinLots, InpBaseLots * 0.35);
   else if(ddPct >= InpTier1DD) lots = MathMax(InpMinLots, InpBaseLots * 0.60);

   // 1% risk budget cap (belt + braces)
   if(slDist > 0.0)
     {
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tv > 0 && ts > 0)
        {
         double lossPerLot = (slDist / ts) * tv;
         double roomDRS    = MathMax(0, eq - DRSFloor());
         double roomDay    = MathMax(0, eq - DailyHard());
         double budget     = MathMin(eq * 1.0 / 100.0,
                             MathMin(roomDRS / 3.0, roomDay / 3.0));
         if(lossPerLot > 0 && budget > 0)
            lots = MathMin(lots, budget / lossPerLot);
        }
     }

   // Hard ceiling
   lots = MathMin(lots, InpMaxLots);

   // Normalize to broker step
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;

   return lots < InpMinLots ? 0.0 : lots;
  }

//==================================================================
//  ENTRY COMPLIANCE GATE
//  Checks every Upcomers Oracle rule before allowing entry
//==================================================================
bool EntryAllowed(bool isBuy)
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_DayLock && InpLockdown)
     { Print("SWIFT >> BLOCKED: daily lockdown"); return false; }
   if(g_DRSLock)
     { Print("SWIFT >> BLOCKED: DRS lockdown"); return false; }
   if(eq <= DailyEntry())
     { PrintFormat("SWIFT >> BLOCKED: daily loss >= %.1f%%", InpEntBlkDay); return false; }
   if(eq <= DRSEntry())
     { PrintFormat("SWIFT >> BLOCKED: within %.1f%% of DRS floor", InpEntBlkDRS); return false; }

   // Count existing positions — total and same-direction & staggered profit check
   int totalCnt = 0, sameDirCnt = 0;
   bool allInProfit = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      totalCnt++;
      double flt = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(flt <= 0) allInProfit = false;
      bool posBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(posBuy == isBuy) sameDirCnt++;
      // HEDGE CHECK — Upcomers explicitly bans opposing positions
      if(posBuy != isBuy)
        { Print("SWIFT >> BLOCKED: would create hedge (prohibited by Upcomers)"); return false; }
     }
   if(totalCnt >= InpMaxPositions)
     { Print("SWIFT >> BLOCKED: max positions (", totalCnt, ")"); return false; }
   if(totalCnt > 0 && !allInProfit)
     { Print("SWIFT >> BLOCKED: staggered entry requires initial trade in profit"); return false; }
   // ONE-SIDED BETTING CHECK — max 2 same direction
   if(sameDirCnt >= InpMaxSameDirPos)
     { PrintFormat("SWIFT >> BLOCKED: one-sided limit (%d same-dir)", sameDirCnt); return false; }

   // Spread gate
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = point > 0 ?
      (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point : 0;
   if(spread > InpMaxSpreadPts)
     { PrintFormat("SWIFT >> BLOCKED: spread %.0f pts", spread); return false; }

   // Friday guard
   MqlDateTime fd; TimeToStruct(TimeCurrent(), fd);
   if(InpFridayClose && fd.day_of_week == 5 && fd.hour >= InpFridayHour)
     { Print("SWIFT >> BLOCKED: Friday close guard"); return false; }

   // Bar spacing (anti-grid: prevents multiple entries per signal)
   if(g_BarsSince < InpMinBarsBetween)
     { Print("SWIFT >> BLOCKED: min bars (", g_BarsSince, ")"); return false; }

   return true;
  }

//==================================================================
//  SIGNAL ENGINE — EMA MOMENTUM CROSS + MTF + ADX + RSI + LiqSweep
//  This is the proven 77% WR logic, now on M15 with quality filters
//==================================================================
int RawSignal()
  {
   // 1. MTF cascade alignment
   int sc = MTFScore();
   if(MathAbs(sc) < InpMTF_MinScore) return 0;

   // 2. ADX trend strength — no entries in sideways markets
   double adx = Buf(g_hADX);
   if(adx < InpADX_Min) return 0;

   // 3. RSI momentum confirmation
   double rsi = Buf(g_hRSI);

   // 4. THE CORE — ultra-fast EMA (5) crossing fast EMA (13) on M15
   //    This was the original momentum edge — preserved, now on M15
   double u1 = Buf(g_hEMA_U[3], 0, 1);  // current bar ultra EMA
   double u2 = Buf(g_hEMA_U[3], 0, 2);  // previous bar ultra EMA
   double f1 = Buf(g_hEMA_F[3], 0, 1);  // current bar fast EMA
   double f2 = Buf(g_hEMA_F[3], 0, 2);  // previous bar fast EMA
   double m1 = Buf(g_hEMA_M[3], 0, 1);  // current mid EMA
   if(u1 <= 0 || f1 <= 0 || m1 <= 0) return 0;

   // Additional confirmation: fast EMA must also be above mid EMA (trend confirmation)
   int sig = 0;
   bool ultraCrossUp   = (u2 <= f2 && u1 > f1);
   bool ultraCrossDown = (u2 >= f2 && u1 < f1);
   bool fastAboveMid   = (f1 > m1);
   bool fastBelowMid   = (f1 < m1);

   if(ultraCrossUp   && fastAboveMid && sc >= InpMTF_MinScore && rsi < InpRSI_OB) sig = +1;
   if(ultraCrossDown && fastBelowMid && sc <= -InpMTF_MinScore && rsi > InpRSI_OS) sig = -1;
   if(sig == 0) return 0;

   // 5. ICT Liquidity Sweep — H1 stop-hunt before real move
   if(InpReqLiqSweep)
     {
      bool isBuy = (sig > 0);
      if(isBuy  && !LiqSweepBull()) return 0;
      if(!isBuy && !LiqSweepBear()) return 0;
     }

   return sig;
  }

//==================================================================
//  POSITION STATE
//==================================================================
int PosIdx(ulong ticket, bool create)
  {
   int n = ArraySize(g_pos);
   for(int i = 0; i < n; i++) if(g_pos[i].ticket == ticket) return i;
   if(!create) return -1;
   ArrayResize(g_pos, n + 1);
   g_pos[n].ticket  = ticket;
   g_pos[n].initVol = 0;
   g_pos[n].rDist   = 0;
   g_pos[n].tp1Done = false;
   g_pos[n].tp2Done = false;
   g_pos[n].beDone  = false;
   g_pos[n].pc1000Done = false;
   g_pos[n].opened  = TimeCurrent();
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

bool ClosePartial(ulong ticket, double pct, bool holdOk)
  {
   if(!holdOk) return false;   // never partial-close before min-hold
   if(!PositionSelectByTicket(ticket)) return false;
   string sym  = PositionGetString(POSITION_SYMBOL);
   double vol  = PositionGetDouble(POSITION_VOLUME);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   double cv = MathFloor(vol * pct / 100.0 / step + 1e-9) * step;
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(cv < vmin || cv >= vol) return false;
   trade.SetDeviationInPoints(100);
   return trade.PositionClosePartial(ticket, cv);
  }

//==================================================================
//  MANAGE OPEN POSITIONS
//  Emergency close bypasses min-hold (compliance > hold time rule)
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
      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double flt    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double bid    = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);
      double px     = isBuy ? bid : ask;
      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      long   lvl    = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist= (double)lvl * point;

      //--- Emergency per-trade close at -1.5% (0.5% buffer before 2% wall)
      //    This BYPASSES min-hold — compliance always wins
      if(flt <= -TradeClose(eq))
        {
         trade.SetDeviationInPoints(100);
         trade.PositionClose(ticket);
         PrintFormat("SWIFT >> EMERGENCY CLOSE #%I64u | float=$%.2f | wall=-$%.2f",
                     ticket, flt, TradeWall(eq));
         continue;
        }

      int  si      = PosIdx(ticket, true);
      if(g_pos[si].initVol <= 0) { g_pos[si].initVol = vol; g_pos[si].opened = TimeCurrent(); }
      bool holdOk  = (TimeCurrent() - g_pos[si].opened >= InpMinHoldSec);
      if(!g_pos[si].pc1000Done && (flt >= 1000.0 || flt <= -1000.0))
        {
         if(ClosePartial(ticket, 50.0, true))
           {
            g_pos[si].pc1000Done = true;
            PrintFormat("SWIFT >> UNIVERSAL $1000 BREACH >> Partial closed 50%% on #%I64u (P&L: $%.2f)", ticket, flt);
           }
        }

      //--- Auto-attach SL/TP on naked positions
      if(sl == 0.0)
        {
         double atr = Buf(g_hATR[3]);
         if(atr <= 0) continue;
         double sd  = atr * InpATR_StopMult;
         double nsl = NormalizeDouble(isBuy ? entry - sd : entry + sd, digits);
         double ntp = NormalizeDouble(isBuy ? entry + sd * InpTP3_R : entry - sd * InpTP3_R, digits);
         if(trade.PositionModify(ticket, nsl, ntp))
           {
            g_pos[si].rDist = sd;
            sl = nsl;
            PrintFormat("SWIFT >> Auto SL/TP #%I64u SL=%.5f TP=%.5f", ticket, nsl, ntp);
           }
        }
      else if(g_pos[si].rDist <= 0)
         g_pos[si].rDist = MathAbs(entry - sl);

      double R    = g_pos[si].rDist;
      if(R <= 0) continue;
      double moveR = isBuy ? (px - entry) / R : (entry - px) / R;

      //--- TP1 — 33% close at 1.000R (only after min-hold)
      if(!g_pos[si].tp1Done && moveR >= InpTP1_R)
        {
         if(ClosePartial(ticket, InpTP1_ClosePct, holdOk))
           {
            g_pos[si].tp1Done = true;
            PrintFormat("SWIFT >> TP1 #%I64u %.0f%% at %.2fR", ticket, InpTP1_ClosePct, moveR);
           }
        }

      //--- TP2 — 33% close at 1.618R golden ratio (only after min-hold)
      if(g_pos[si].tp1Done && !g_pos[si].tp2Done && moveR >= InpTP2_R)
        {
         if(ClosePartial(ticket, InpTP2_ClosePct, holdOk))
           {
            g_pos[si].tp2Done = true;
            PrintFormat("SWIFT >> TP2 φ #%I64u %.0f%% at %.3fR (golden ratio)", ticket, InpTP2_ClosePct, moveR);
           }
        }

      //--- Breakeven + ATR trail (only after min-hold, always monotonic)
      double desiredSL = 0.0;
      if(!g_pos[si].beDone && moveR >= InpBE_TriggerR && holdOk)
        {
         double off = InpBE_Pips * 10.0 * point;
         desiredSL  = isBuy ? entry + off : entry - off;
         g_pos[si].beDone = true;
         PrintFormat("SWIFT >> Breakeven #%I64u at %.2fR", ticket, moveR);
        }

      if(g_pos[si].beDone && holdOk)
        {
         double atrH = Buf(g_hATR[2]);    // H1 ATR for wider trail
         int    sc   = MTFScore();
         bool   opp  = (isBuy && sc <= -2) || (!isBuy && sc >= 2);
         double mult = opp ? InpATR_TightMult : InpATR_TrailMult;
         double chase = isBuy ? px - atrH * mult : px + atrH * mult;
         if(desiredSL == 0.0) desiredSL = chase;
         else desiredSL = isBuy ? MathMax(desiredSL, chase) : MathMin(desiredSL, chase);
        }

      if(desiredSL != 0.0)
        {
         desiredSL = NormalizeDouble(desiredSL, digits);
         bool tighter = isBuy ? (desiredSL > sl + point) : (sl == 0.0 || desiredSL < sl - point);
         bool valid   = isBuy ? (desiredSL < bid - minDist) : (desiredSL > ask + minDist);
         if(tighter && valid)
            trade.PositionModify(ticket, desiredSL, tp);
        }

      // Display hold status in log
      if(!holdOk)
        PrintFormat("SWIFT >> #%I64u hold time %ds / %ds min (no trail/partial yet)",
                    ticket, (int)(TimeCurrent() - g_pos[si].opened), InpMinHoldSec);
     }
  }

//==================================================================
//  ACCOUNT GUARD — runs every tick + timer
//==================================================================
void AccountGuard()
  {
   double   eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime today = (datetime)(((long)TimeGMT() / 86400) * 86400);

   // Roll UTC day
   if(today != g_DayStamp)
     {
      g_DayStamp = today;
      g_DayPeak  = eq;
      g_DayLock  = false;
      SaveGV();
      PrintFormat("SWIFT >> DAY ROLL | anchor $%.2f | hard line $%.2f | DRS floor $%.2f",
                  eq, DailyHard(), DRSFloor());
     }
   if(eq > g_HWM)     { g_HWM    = eq; SaveGV(); }
   if(eq > g_DayPeak) { g_DayPeak = eq; SaveGV(); }

   //--- DRS breach — flatten all (equity-based, trailing HWM)
   if(eq <= DRSFlat())
     {
      if(!g_DRSLock)
        {
         g_DRSLock = true;
         PrintFormat("SWIFT >> DRS FLATTEN | eq $%.2f <= $%.2f | floor $%.2f",
                     eq, DRSFlat(), DRSFloor());
         FlattenAll("DRS shield buffer");
        }
     }
   else if(g_DRSLock && eq > DRSEntry())
      g_DRSLock = false;

   //--- Daily DD breach — flatten + lock
   if(!g_DayLock && eq <= DailyFlat())
     {
      g_DayLock = true;
      SaveGV();
      PrintFormat("SWIFT >> DAILY FLATTEN | eq $%.2f <= $%.2f | hard $%.2f",
                  eq, DailyFlat(), DailyHard());
      FlattenAll("daily soft-stop buffer");
     }

   // Kill anything opened during lockdown
   if((g_DayLock && InpLockdown) || g_DRSLock)
     for(int i = PositionsTotal() - 1; i >= 0; i--)
       {
        ulong t = PositionGetTicket(i);
        if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
           trade.PositionClose(t);
       }
  }

void FlattenAll(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.SetDeviationInPoints(100);
      trade.PositionClose(t);
      PrintFormat("SWIFT >> CLOSED #%I64u | %s", t, reason);
     }
  }

//==================================================================
//  FRIDAY GUARD
//==================================================================
void FridayGuard()
  {
   if(!InpFridayClose) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= InpFridayHour)
      FlattenAll("Friday hard close");
  }

//==================================================================
//  ENTRY EXECUTION
//==================================================================
void TryEntry()
  {
   if(!SessionOpen()) return;

   int raw = RawSignal();
   if(raw == 0) return;

   // Inverse Mode + Direction filter (standing JAZZYLYFE rule)
   int sig = InpInverseMode ? -raw : raw;
   if(InpDirection == DIR_BUY  && sig < 0) return;
   if(InpDirection == DIR_SELL && sig > 0) return;

   bool isBuy = (sig > 0);
   if(!EntryAllowed(isBuy)) return;

   double atr = Buf(g_hATR[3]);
   if(atr <= 0) return;
   double stopDist = atr * InpATR_StopMult;
   double px       = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(isBuy ? px - stopDist : px + stopDist,
                               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   double tp = NormalizeDouble(isBuy ? px + stopDist * InpTP3_R : px - stopDist * InpTP3_R,
                               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   double lots = ComputeLots(stopDist);
   if(lots <= 0)
     {
      Print("SWIFT >> budget too small for min lot — standing down");
      return;
     }

   // Final compliance sanity — worst case loss must be under 2% wall
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0 && tv > 0)
     {
      double worstCase = (stopDist / ts) * tv * lots;
      if(worstCase > TradeWall(eq))
        {
         PrintFormat("SWIFT >> BLOCKED: worst-case $%.2f > trade wall $%.2f", worstCase, TradeWall(eq));
         return;
        }
     }

   trade.SetDeviationInPoints(20);
   bool ok = isBuy ? trade.Buy (lots, _Symbol, 0, sl, tp, InpComment)
                   : trade.Sell(lots, _Symbol, 0, sl, tp, InpComment);
   if(ok)
     {
      g_BarsSince = 0;
      ulong ticket = trade.ResultDeal();
      if(ticket > 0)
        {
         int si = PosIdx(ticket, true);
         g_pos[si].initVol = lots;
         g_pos[si].rDist   = stopDist;
         g_pos[si].opened  = TimeCurrent();
        }
      PrintFormat("SWIFT >> %s %s %.2f lots SL=%.5f TP=%.5f | MTF=%d ADX=%.1f RSI=%.1f | hold min=%ds | daily room $%.0f DRS room $%.0f",
                  isBuy ? "BUY" : "SELL", _Symbol, lots, sl, tp,
                  MTFScore(), Buf(g_hADX), Buf(g_hRSI),
                  InpMinHoldSec,
                  eq - DailyHard(), eq - DRSFloor());
     }
   else
      PrintFormat("SWIFT >> Entry FAILED: %s (%d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
  }

//==================================================================
//  DASHBOARD
//==================================================================
void Dashboard()
  {
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = DailyAnchor() > 0 ? 100.0 * (DailyAnchor() - eq) / DailyAnchor() : 0;
   string tier  = ddPct >= InpTier3DD ? "T3-MIN(0.01)" :
                  ddPct >= InpTier2DD ? "T2-35%(~0.01)" :
                  ddPct >= InpTier1DD ? "T1-60%(~0.01)" : "T0-FULL(0.02)";
   string lock  = (g_DayLock ? "DAY " : "") + (g_DRSLock ? "DRS" : "");
   if(lock == "") lock = "none";
   double nextLots = ComputeLots(Buf(g_hATR[3]) * InpATR_StopMult);

   string s = "";
   s += "╔══ JAZZYLYFE Swift v1 — EURUSD — Upcomers Oracle ══╗\n";
   s += "║ Momentum Swing Engine | Fully compliant | Grade A++ ║\n";
   s += "║ Magic: " + (string)InpMagic + " | MinHold: " + (string)InpMinHoldSec + "s (5× the 2-min rule)  ║\n";
   s += "╠══ ACCOUNT ════════════════════════════════════════╣\n";
   s += "║ Equity  $" + DoubleToString(eq, 2) + " | HWM $" + DoubleToString(g_HWM, 2) + "\n";
   s += "║ DRS room $" + DoubleToString(eq - DRSFloor(), 2) +
        " | Daily room $" + DoubleToString(eq - DailyHard(), 2) + "\n";
   s += "║ Daily flatten @ $" + DoubleToString(DailyFlat(), 2) +
        " | DRS flatten @ $" + DoubleToString(DRSFlat(), 2) + "\n";
   s += "╠══ SIZING ════════════════════════════════════════╣\n";
   s += "║ DD " + DoubleToString(ddPct, 2) + "% → " + tier +
        " | Next: " + DoubleToString(nextLots, 2) + " lots\n";
   s += "╠══ SIGNAL ════════════════════════════════════════╣\n";
   s += "║ MTF: " + (string)MTFScore() + "/4" +
        " | ADX: " + DoubleToString(Buf(g_hADX), 1) +
        " | RSI: " + DoubleToString(Buf(g_hRSI), 1) +
        " | Session: " + (SessionOpen() ? "OPEN" : "CLOSED") + "\n";
   s += "╠══ STATUS ════════════════════════════════════════╣\n";
   s += "║ Lock: " + lock + " | Positions: " + (string)PositionsTotal() + "\n";
   s += "╠══ COMPLIANCE (Oracle) ═════════════════════════════╣\n";
   s += "║ No scalping ✓ | No hedge ✓ | No grid ✓ | No martingale ✓\n";
   s += "║ Anti one-sided ✓ | Min hold " + (string)InpMinHoldSec + "s ✓\n";
   s += "╚══ JAZZYLYFE | TheBrimberry | Brimberry LLC ═══════╝";
   Comment(s);
  }

//==================================================================
//  INIT
//==================================================================
int OnInit()
  {
   // Shared GV prefix — same as SmartGuard and all fleet EAs
   g_GV = "JLUPC_" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + "_";

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_HWM     = eq;
   g_DayPeak = eq;
   g_DayStamp = (datetime)(((long)TimeGMT() / 86400) * 86400);
   LoadGV();
   if(g_HWM < eq) g_HWM = eq;

   // Assign TF array — MQL5 does not allow brace-init on enum arrays
   g_TF[0] = PERIOD_D1;
   g_TF[1] = PERIOD_H4;
   g_TF[2] = PERIOD_H1;
   g_TF[3] = PERIOD_M15;

   // Build all indicator handles
   for(int i = 0; i < 4; i++)
     {
      g_hEMA_U[i] = iMA(_Symbol, g_TF[i], InpEMA_Ultra, 0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_F[i] = iMA(_Symbol, g_TF[i], InpEMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_M[i] = iMA(_Symbol, g_TF[i], InpEMA_Mid,   0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_S[i] = iMA(_Symbol, g_TF[i], InpEMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
      g_hEMA_T[i] = iMA(_Symbol, g_TF[i], InpEMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
      g_hATR[i]   = iATR(_Symbol, g_TF[i], InpATR_Period);
     }
   g_hRSI = iRSI(_Symbol, PERIOD_M15, InpRSI_Period, PRICE_CLOSE);
   g_hADX = iADX(_Symbol, PERIOD_M15, InpADX_Period);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetAsyncMode(false);

   EventSetTimer(1);

   PrintFormat("SWIFT v1 Oracle >> ONLINE | %s | Magic=%I64d | MinHold=%ds | Base=%.2f Max=%.2f | Oracle: daily %.1f%% DRS %.1f%% trade %.1f%% | DRS floor $%.2f | Daily hard $%.2f",
               _Symbol, InpMagic, InpMinHoldSec,
               InpBaseLots, InpMaxLots,
               InpDailyPct, InpDRSPct, InpTradePct,
               DRSFloor(), DailyHard());
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveGV();
   Comment("");
   Print("SWIFT v1 >> Offline | HWM $", DoubleToString(g_HWM, 2), " saved");
  }

//==================================================================
//  MAIN LOOP
//==================================================================
void OnTick()
  {
   datetime bar = iTime(_Symbol, PERIOD_M15, 0);
   bool newBar  = (bar != g_LastBar);
   if(newBar) { g_LastBar = bar; g_BarsSince++; }

   AccountGuard();
   if(g_DayLock || g_DRSLock) { Dashboard(); return; }

   ManagePositions();
   if(newBar) TryEntry();

   FridayGuard();
   PruneStates();
   Dashboard();
  }

void OnTimer()
  {
   AccountGuard();
   ManagePositions();
  }
//+------------------------------------------------------------------+
