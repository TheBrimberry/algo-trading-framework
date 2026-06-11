//+------------------------------------------------------------------+
//|                                     JazzyLyfe_EA_Template.mq5     |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|     Grade A++ master scaffold every JAZZYLYFE EA conforms to      |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//|                                                                  |
//| Wires the JAZZYLYFE standard stack:                              |
//|   * FTMO guard      (4.5/9 soft, 5/10 hard, daily-anchored)      |
//|   * MTF cascade      D1 -> H4 -> H1 -> M15                       |
//|   * ICT/SMC confluence (OB, FVG, BOS/CHoCH, liquidity sweep)     |
//|   * Kelly sizing     (fractional, hard-capped)                  |
//|   * Inverse Mode + Trade Direction filter  (MANDATORY)          |
//|                                                                  |
//| Drop new strategies into BuildRawSignal() only; the safety,      |
//| sizing and controls layers stay identical across the fleet.      |
//|                                                                  |
//| For open-trade management during soft breach, override           |
//| ManageOpenTrades() in the child EA.                              |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "1.01"
#property strict

#include <Trade/Trade.mqh>
#include "../lib/JazzyLyfe_FTMO_Guard.mqh"
#include "../lib/JazzyLyfe_MTF.mqh"
#include "../lib/JazzyLyfe_ICT.mqh"
#include "../lib/JazzyLyfe_Sizing.mqh"
#include "../lib/JazzyLyfe_Controls.mqh"

//--- inputs -------------------------------------------------------
input long              InpMagic            = 202512250;   // flagship magic
input double            InpStartBalance     = 0.0;         // 0 = use current
input int               InpEmaFast          = 21;
input int               InpEmaSlow          = 50;
input int               InpMinAlign         = 3;           // TFs that must agree
input int               InpMinConfluence    = 2;           // ICT reads required
// Stop distance in POINTS (not pips). Examples:
//   XAUUSD 150-pip stop = 1500 pts (point=0.01)
//   EURUSD  20-pip stop =  200 pts (point=0.00001)
input double            InpStopPoints       = 1500;        // SL distance (points)
input double            InpRRatio           = 2.0;         // reward:risk
input double            InpWinRate          = 0.55;        // edge stats -> Kelly
input double            InpPayoff           = 1.8;
input double            InpMaxRiskPct        = 1.0;        // hard cap / trade
input double            InpKellyFraction     = 0.25;       // fractional Kelly

//--- MANDATORY JAZZYLYFE controls
input bool              InpInverseMode      = false;       // flip all signals
input ENUM_JL_DIRECTION InpDirection        = JL_DIR_BOTH; // Buy/Sell/Both

//--- objects ------------------------------------------------------
CTrade                  trade;
CJazzyLyfeFTMOGuard     guard;
CJazzyLyfeMTF           mtf;
CJazzyLyfeICT           ict;
CJazzyLyfeSizing        sizing;
CJazzyLyfeControls      controls;

datetime                g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);

   guard.Init(InpMagic, InpStartBalance, 4.5, 5.0, 9.0, 10.0);

   if(!mtf.Init(_Symbol, InpEmaFast, InpEmaSlow, InpMinAlign))
     {
      Print("[JL] MTF init failed");
      return(INIT_FAILED);
     }
   ict.Init(_Symbol, PERIOD_M15, 60);
   sizing.Init(_Symbol, InpMaxRiskPct, InpKellyFraction);
   controls.Init(InpInverseMode, InpDirection);

   Print("[JL] JAZZYLYFE EA template armed on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   guard.ResetSession();
   PrintFormat("[JL] EA stopped on %s | reason=%d", _Symbol, reason);
  }

//+------------------------------------------------------------------+
//| Strategy hook: return the RAW directional read.                  |
//| Replace the body for each specific EA; everything else is shared.|
//+------------------------------------------------------------------+
ENUM_JL_BIAS BuildRawSignal()
  {
   ENUM_JL_BIAS bias = mtf.Bias();          // top-down regime + M15 confirm
   if(bias == JL_BIAS_NONE) return(JL_BIAS_NONE);

   int conf = ict.Confluence((int)bias);     // SMC agreement with the bias
   if(conf < InpMinConfluence) return(JL_BIAS_NONE);

   return(bias);
  }

//+------------------------------------------------------------------+
//| Open-trade management hook (trailing stop, breakeven, partials). |
//| Called every new bar even during soft-breach (no new entries).   |
//| Override this in child EAs that need active position management. |
//+------------------------------------------------------------------+
void ManageOpenTrades() {}

//+------------------------------------------------------------------+
bool NewBar()
  {
   datetime t = iTime(_Symbol, PERIOD_M15, 0);
   if(t == g_lastBar) return(false);
   g_lastBar = t;
   return(true);
  }

bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1) SAFETY FIRST: guard runs every tick, can flatten + halt
   ENUM_JL_GUARD_STATE gs = guard.Check();
   if(gs == JL_GUARD_HARD_DAY || gs == JL_GUARD_HARD_MAX) return; // halted
   bool can_open = (gs == JL_GUARD_OK);

   //--- work on closed M15 bars only
   if(!NewBar()) return;

   //--- always run position management (trailing stop, BE, etc.) regardless
   //--- of soft breach - open trades must still be managed
   ManageOpenTrades();

   if(HasOpenPosition()) return;
   if(!can_open) return;          // soft breach -> manage only, no new trades

   //--- 2) raw signal -> controls (inverse + direction) -> final
   ENUM_JL_BIAS raw = BuildRawSignal();
   ENUM_JL_BIAS sig = controls.Apply(raw);
   if(sig == JL_BIAS_NONE) return;

   //--- 3) Kelly-sized lot from edge stats + stop distance
   double lot = sizing.Lot(InpWinRate, InpPayoff, InpStopPoints);
   if(lot <= 0) return;

   //--- 4) execute with SL/TP
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(sig == JL_BIAS_BUY)
     {
      double sl = ask - InpStopPoints * point;
      double tp = ask + InpStopPoints * InpRRatio * point;
      trade.Buy(lot, _Symbol, ask, sl, tp, "JAZZYLYFE");
     }
   else if(sig == JL_BIAS_SELL)
     {
      double sl = bid + InpStopPoints * point;
      double tp = bid - InpStopPoints * InpRRatio * point;
      trade.Sell(lot, _Symbol, bid, sl, tp, "JAZZYLYFE");
     }
  }
//+------------------------------------------------------------------+
