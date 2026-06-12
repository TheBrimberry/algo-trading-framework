//+------------------------------------------------------------------+
//|                                     JazzyLyfe_EA_Template.mq5     |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|     Grade A++ master scaffold every JAZZYLYFE EA conforms to      |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//|                                                                  |
//| Wires the JAZZYLYFE standard stack:                              |
//|   * FTMO guard      (4.5/9 soft, 5/10 hard, daily-anchored,      |
//|                      max-trades/day, Friday close, weekend block) |
//|   * MTF cascade      D1 -> H4 -> H1 -> M15                       |
//|   * ICT/SMC confluence (OB, FVG, BOS/CHoCH, liquidity sweep)     |
//|   * Kelly sizing     (fractional, hard-capped)                  |
//|   * Inverse Mode + Trade Direction filter  (MANDATORY)          |
//|   * Trade Manager   (spread filter, breakeven, trail, partial,   |
//|                      trade journal CSV)                          |
//|                                                                  |
//| Drop new strategies into BuildRawSignal() only; the safety,      |
//| sizing and controls layers stay identical across the fleet.      |
//|                                                                  |
//| For open-trade management override ManageOpenTrades() or let     |
//| the built-in TradeManager handle it automatically.               |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "1.02"
#property strict

#include <Trade/Trade.mqh>
#include "../lib/JazzyLyfe_FTMO_Guard.mqh"
#include "../lib/JazzyLyfe_MTF.mqh"
#include "../lib/JazzyLyfe_ICT.mqh"
#include "../lib/JazzyLyfe_Sizing.mqh"
#include "../lib/JazzyLyfe_Controls.mqh"
#include "../lib/JazzyLyfe_TradeManager.mqh"

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
input double            InpMaxRiskPct       = 1.0;         // hard cap / trade
input double            InpKellyFraction    = 0.25;        // fractional Kelly

//--- FTMO guard extras
input int               InpMaxTradesDay     = 6;           // 0 = unlimited
input int               InpFridayCloseHour  = 20;          // server hour (Friday flatten)
input bool              InpWeekendBlock     = true;        // block Sat/Sun entries

//--- spread filter
input double            InpMaxSpreadPts     = 80;          // 0 = disabled (XAUUSD ~20 normal)

//--- trade manager
input bool              InpUseBreakeven     = true;        // move SL to entry at 1R
input double            InpBEBufferPts      = 50;          // buffer above entry for BE SL
input bool              InpUseTrailing      = true;        // trail stop once in BE
input double            InpTrailStepPts     = 150;         // trail step in points
input bool              InpUsePartial       = true;        // close 50% at 1R
input double            InpPartialPct       = 0.5;         // fraction to close at 1R
input bool              InpUseJournal       = true;        // write trade journal CSV

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
CJazzyLyfeTradeManager  tm;

datetime                g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);

   guard.Init(InpMagic, InpStartBalance, 4.5, 5.0, 9.0, 10.0,
              InpMaxTradesDay, InpFridayCloseHour, InpWeekendBlock);

   if(!mtf.Init(_Symbol, InpEmaFast, InpEmaSlow, InpMinAlign))
     {
      Print("[JL] MTF init failed");
      return(INIT_FAILED);
     }
   ict.Init(_Symbol, PERIOD_M15, 60);
   sizing.Init(_Symbol, InpMaxRiskPct, InpKellyFraction);
   controls.Init(InpInverseMode, InpDirection);
   tm.Init(_Symbol, InpMagic,
           InpMaxSpreadPts,
           InpUseBreakeven, InpBEBufferPts,
           InpUseTrailing,  InpTrailStepPts,
           InpUsePartial,   InpPartialPct,
           InpUseJournal);

   Print("[JL] JAZZYLYFE EA template v1.02 armed on ", _Symbol);
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
   ENUM_JL_BIAS bias = mtf.Bias();
   if(bias == JL_BIAS_NONE) return(JL_BIAS_NONE);
   int conf = ict.Confluence((int)bias);
   if(conf < InpMinConfluence) return(JL_BIAS_NONE);
   return(bias);
  }

//+------------------------------------------------------------------+
//| Open-trade management hook — default delegates to TradeManager.  |
//| Override in child EAs only if custom logic is needed.            |
//+------------------------------------------------------------------+
void ManageOpenTrades()
  {
   tm.Manage();
  }

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
   if(gs == JL_GUARD_HARD_DAY || gs == JL_GUARD_HARD_MAX) return;
   bool can_open = (gs == JL_GUARD_OK);

   //--- work on closed M15 bars only
   if(!NewBar()) return;

   //--- always manage open trades regardless of soft breach
   ManageOpenTrades();

   if(HasOpenPosition()) return;
   if(!can_open) return;

   //--- 2) spread check
   if(!tm.SpreadOK()) return;

   //--- 3) raw signal -> controls -> final
   ENUM_JL_BIAS raw = BuildRawSignal();
   ENUM_JL_BIAS sig = controls.Apply(raw);
   if(sig == JL_BIAS_NONE) return;

   //--- 4) Kelly-sized lot
   double lot = sizing.Lot(InpWinRate, InpPayoff, InpStopPoints);
   if(lot <= 0) return;

   //--- 5) execute with SL/TP
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(sig == JL_BIAS_BUY)
     {
      double sl = ask - InpStopPoints * point;
      double tp = ask + InpStopPoints * InpRRatio * point;
      if(trade.Buy(lot, _Symbol, ask, sl, tp, "JAZZYLYFE"))
        {
         guard.RecordTrade();
         tm.RegisterOpen(trade.ResultDeal(), ask, sl, tp, "BUY", lot);
        }
     }
   else if(sig == JL_BIAS_SELL)
     {
      double sl = bid + InpStopPoints * point;
      double tp = bid - InpStopPoints * InpRRatio * point;
      if(trade.Sell(lot, _Symbol, bid, sl, tp, "JAZZYLYFE"))
        {
         guard.RecordTrade();
         tm.RegisterOpen(trade.ResultDeal(), bid, sl, tp, "SELL", lot);
        }
     }
  }
//+------------------------------------------------------------------+
