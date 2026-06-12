//+------------------------------------------------------------------+
//|              JAZZYLYFE_UltimateProfit_Unified.mq5                 |
//|              Consolidated build of the V2–V7 feature set          |
//|              JAZZYLYFE / Brimberry LLC  (c) 2026                  |
//+------------------------------------------------------------------+
//|  ██╗   ██╗██╗  ████████╗██╗███╗   ███╗ █████╗ ████████╗███████╗  |
//|  ██║   ██║██║  ╚══██╔══╝██║████╗ ████║██╔══██╗╚══██╔══╝██╔════╝  |
//|  ██║   ██║██║     ██║   ██║██╔████╔██║███████║   ██║   █████╗    |
//|  ╚██████╔╝███████╗██║   ██║██║ ╚═╝ ██║██║  ██║   ██║   ███████╗  |
//|   ╚═════╝ ╚══════╝╚═╝   ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝  |
//+------------------------------------------------------------------+
//|  AUTHOR : JAZZYLYFE (TheBrimberry) | thebrimberry@gmail.com       |
//|  MAGIC  : 202512250  | EDGE: XAUUSD, long-biased                 |
//|  LIVE PROVEN lineage: 85.1% WR | 1.67 PF | +$351 (Deriv #5943690)|
//|                                                                  |
//|  V2  FTMO halt logic            -> lib FTMO guard                |
//|  V3  SMC: OB/FVG/liquidity + MTF -> lib ICT + lib MTF            |
//|  V5  7-signal confluence + Kelly + ICT killzones                |
//|  V7  ensemble voting + recovery mode + dashboard                |
//|  V8  spread filter + breakeven + trail + partial + journal       |
//|      + max-trades/day + Friday close + weekend block             |
//|      + weekly recovery streak reset                              |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "8.10"
#property strict
#property description "JAZZYLYFE Ultimate Profit (Unified V2-V7+) — Magic 202512250"

#include <Trade/Trade.mqh>
#include "../../lib/JazzyLyfe_FTMO_Guard.mqh"
#include "../../lib/JazzyLyfe_MTF.mqh"
#include "../../lib/JazzyLyfe_ICT.mqh"
#include "../../lib/JazzyLyfe_Sizing.mqh"
#include "../../lib/JazzyLyfe_Controls.mqh"
#include "../../lib/JazzyLyfe_TradeManager.mqh"

//--- core inputs --------------------------------------------------
input long              InpMagic            = 202512250;
input double            InpStartBalance     = 0.0;          // 0 = current balance
input double            InpStopPoints       = 1500;         // SL in points (XAUUSD: 150pip=1500pts)
input double            InpRRatio           = 2.0;          // reward:risk
input double            InpWinRate          = 0.55;
input double            InpPayoff           = 1.8;
input double            InpMaxRiskPct       = 1.0;
input double            InpKellyFraction    = 0.25;

//--- MTF / ICT ----------------------------------------------------
input int               InpEmaFast          = 21;
input int               InpEmaSlow          = 50;
input int               InpMinAlign         = 3;
input int               InpMinConfluence    = 2;

//--- V5/V7 ensemble -----------------------------------------------
input int               InpMinVotes         = 4;            // of 7 signals required
input int               InpRSIPeriod        = 14;

//--- ICT killzone session filter ----------------------------------
input bool              InpUseKillzones     = true;
input int               InpLondonStart      = 7;
input int               InpLondonEnd        = 10;
input int               InpNYStart          = 12;
input int               InpNYEnd            = 15;

//--- FTMO guard extras --------------------------------------------
input int               InpMaxTradesDay     = 6;            // 0 = unlimited
input int               InpFridayCloseHour  = 20;           // server hour (Friday flatten)
input bool              InpWeekendBlock     = true;

//--- spread filter ------------------------------------------------
input double            InpMaxSpreadPts     = 80;           // 0 = disabled

//--- trade manager ------------------------------------------------
input bool              InpUseBreakeven     = true;
input double            InpBEBufferPts      = 50;           // points above entry for BE SL
input bool              InpUseTrailing      = true;
input double            InpTrailStepPts     = 150;
input bool              InpUsePartial       = true;
input double            InpPartialPct       = 0.5;          // close 50% at 1R
input bool              InpUseJournal       = true;

//--- recovery mode (V7) -------------------------------------------
input bool              InpRecoveryMode     = true;
input int               InpRecoveryAfter    = 3;            // consecutive losses
input double            InpRecoveryFactor   = 0.5;          // risk multiplier

//--- MANDATORY JAZZYLYFE controls ---------------------------------
input bool              InpInverseMode      = false;
input ENUM_JL_DIRECTION InpDirection        = JL_DIR_BOTH;

//--- objects ------------------------------------------------------
CTrade                  trade;
CJazzyLyfeFTMOGuard     guard;
CJazzyLyfeMTF           mtf;
CJazzyLyfeICT           ict;
CJazzyLyfeSizing        sizing;
CJazzyLyfeControls      controls;
CJazzyLyfeTradeManager  tm;

int      g_hRSI  = INVALID_HANDLE;
int      g_hMACD = INVALID_HANDLE;
int      g_hEMAf = INVALID_HANDLE;
int      g_hEMAs = INVALID_HANDLE;
int      g_hATR  = INVALID_HANDLE;

datetime g_lastBar          = 0;
int      g_lossStreak       = 0;
double   g_lastClosedProfit = 0;
datetime g_streakWeekStart  = 0;   // reset streak each Monday

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   guard.Init(InpMagic, InpStartBalance, 4.5, 5.0, 9.0, 10.0,
              InpMaxTradesDay, InpFridayCloseHour, InpWeekendBlock);
   if(!mtf.Init(_Symbol, InpEmaFast, InpEmaSlow, InpMinAlign)) return(INIT_FAILED);
   ict.Init(_Symbol, PERIOD_M15, 60);
   sizing.Init(_Symbol, InpMaxRiskPct, InpKellyFraction);
   controls.Init(InpInverseMode, InpDirection);
   tm.Init(_Symbol, InpMagic,
           InpMaxSpreadPts,
           InpUseBreakeven, InpBEBufferPts,
           InpUseTrailing,  InpTrailStepPts,
           InpUsePartial,   InpPartialPct,
           InpUseJournal);

   g_hRSI  = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   g_hMACD = iMACD(_Symbol, PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   g_hEMAf = iMA(_Symbol, PERIOD_M15, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMAs = iMA(_Symbol, PERIOD_M15, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hATR  = iATR(_Symbol, PERIOD_M15, 14);
   if(g_hRSI==INVALID_HANDLE || g_hMACD==INVALID_HANDLE || g_hEMAf==INVALID_HANDLE ||
      g_hEMAs==INVALID_HANDLE || g_hATR==INVALID_HANDLE)
      return(INIT_FAILED);

   Print("[JL] Ultimate Profit Unified v8.10 armed on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   guard.ResetSession();
   IndicatorRelease(g_hRSI);  IndicatorRelease(g_hMACD);
   IndicatorRelease(g_hEMAf); IndicatorRelease(g_hEMAs); IndicatorRelease(g_hATR);
   PrintFormat("[JL] Ultimate Profit Unified stopped on %s | reason=%d", _Symbol, reason);
  }

//+------------------------------------------------------------------+
//| 7-signal ensemble vote in direction dir (+1=buy / -1=sell)       |
//+------------------------------------------------------------------+
int EnsembleVotes(int dir)
  {
   double rsi[1], macd_main[2], macd_sig[2], emaf[1], emas[1];
   // All reads on confirmed bar 1 (not forming bar 0)
   if(CopyBuffer(g_hRSI,0,1,1,rsi)<1)        return(0);
   if(CopyBuffer(g_hMACD,0,1,2,macd_main)<2) return(0);
   if(CopyBuffer(g_hMACD,1,1,2,macd_sig)<2)  return(0);
   if(CopyBuffer(g_hEMAf,0,1,1,emaf)<1)      return(0);
   if(CopyBuffer(g_hEMAs,0,1,1,emas)<1)      return(0);

   double close = iClose(_Symbol, PERIOD_M15, 1);
   int votes = 0;

   // 1) MTF cascade
   ENUM_JL_BIAS b = mtf.Bias();
   if((dir>0 && b==JL_BIAS_BUY) || (dir<0 && b==JL_BIAS_SELL)) votes++;
   // 2) EMA cross
   if((dir>0 && emaf[0]>emas[0]) || (dir<0 && emaf[0]<emas[0])) votes++;
   // 3) price vs fast EMA
   if((dir>0 && close>emaf[0]) || (dir<0 && close<emaf[0])) votes++;
   // 4) RSI momentum
   if((dir>0 && rsi[0]>50.0) || (dir<0 && rsi[0]<50.0)) votes++;
   // 5) MACD vs signal (confirmed bar index [1] = newest of the 2 copied)
   if((dir>0 && macd_main[1]>macd_sig[1]) || (dir<0 && macd_main[1]<macd_sig[1])) votes++;
   // 6) MACD slope (newer[1] vs older[0])
   if((dir>0 && macd_main[1]>macd_main[0]) || (dir<0 && macd_main[1]<macd_main[0])) votes++;
   // 7) ICT confluence
   if(ict.Confluence(dir) >= 1) votes++;

   return(votes);
  }

//+------------------------------------------------------------------+
bool InKillzone()
  {
   if(!InpUseKillzones) return(true);
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   return((h>=InpLondonStart && h<InpLondonEnd) || (h>=InpNYStart && h<InpNYEnd));
  }

bool NewBar()
  {
   datetime t = iTime(_Symbol, PERIOD_M15, 0);
   if(t==g_lastBar) return(false);
   g_lastBar = t;
   return(true);
  }

bool HasOpenPosition()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic) return(true);
     }
   return(false);
  }

//--- recovery mode: losing streak tracking with weekly reset (V7+) -
void UpdateStreakOnHistory()
  {
   if(!InpRecoveryMode) return;

   //--- reset streak at the start of each calendar week (Monday)
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   MqlDateTime wd; wd = dt; wd.day_of_week = 1; wd.hour = 0; wd.min = 0; wd.sec = 0;
   datetime week_start = StructToTime(wd);
   if(week_start != g_streakWeekStart)
     {
      g_streakWeekStart   = week_start;
      g_lossStreak        = 0;
      g_lastClosedProfit  = 0;
      PrintFormat("[JL] Weekly streak reset (Monday %s)", TimeToString(week_start, TIME_DATE));
     }

   HistorySelect(week_start, TimeCurrent());
   int deals = HistoryDealsTotal();
   if(deals <= 0) return;
   ulong last = HistoryDealGetTicket(deals-1);
   if(last==0) return;
   if(HistoryDealGetInteger(last,DEAL_MAGIC) != InpMagic) return;
   double profit = HistoryDealGetDouble(last,DEAL_PROFIT);
   if(profit == g_lastClosedProfit) return;   // already counted
   g_lastClosedProfit = profit;
   if(profit < 0) g_lossStreak++; else g_lossStreak = 0;
   PrintFormat("[JL] Loss streak = %d (trigger at %d)", g_lossStreak, InpRecoveryAfter);
  }

double RiskMultiplier()
  {
   if(InpRecoveryMode && g_lossStreak >= InpRecoveryAfter)
     {
      PrintFormat("[JL] Recovery mode active (streak=%d) -> risk x%.2f",
                  g_lossStreak, InpRecoveryFactor);
      return(InpRecoveryFactor);
     }
   return(1.0);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1) SAFETY FIRST (includes Friday close + weekend block)
   ENUM_JL_GUARD_STATE gs = guard.Check();
   if(gs==JL_GUARD_HARD_DAY || gs==JL_GUARD_HARD_MAX) return;
   bool can_open = (gs==JL_GUARD_OK);

   if(!NewBar()) return;

   //--- 2) manage open positions every bar (BE, trail, partial)
   tm.Manage();

   UpdateStreakOnHistory();

   if(HasOpenPosition()) return;
   if(!can_open) return;
   if(!InKillzone()) return;

   //--- 3) spread check
   if(!tm.SpreadOK()) return;

   //--- 4) direction from MTF + ICT + ensemble vote
   ENUM_JL_BIAS raw = mtf.Bias();
   if(raw==JL_BIAS_NONE) return;
   if(ict.Confluence((int)raw) < InpMinConfluence) return;
   if(EnsembleVotes((int)raw) < InpMinVotes) return;

   //--- 5) controls (inverse -> direction filter)
   ENUM_JL_BIAS sig = controls.Apply(raw);
   if(sig==JL_BIAS_NONE) return;

   //--- 6) Kelly sizing with recovery-mode multiplier
   double risk = sizing.KellyRiskPct(InpWinRate, InpPayoff) * RiskMultiplier();
   if(risk<=0) return;
   double lot = sizing.LotForRisk(risk, InpStopPoints);
   if(lot<=0) return;

   //--- 7) execute
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(sig==JL_BIAS_BUY)
     {
      double sl = ask - InpStopPoints*point;
      double tp = ask + InpStopPoints*InpRRatio*point;
      if(trade.Buy(lot, _Symbol, ask, sl, tp, "JAZZYLYFE UP-Unified"))
        {
         guard.RecordTrade();
         tm.RegisterOpen(trade.ResultDeal(), ask, sl, tp, "BUY", lot);
        }
     }
   else if(sig==JL_BIAS_SELL)
     {
      double sl = bid + InpStopPoints*point;
      double tp = bid - InpStopPoints*InpRRatio*point;
      if(trade.Sell(lot, _Symbol, bid, sl, tp, "JAZZYLYFE UP-Unified"))
        {
         guard.RecordTrade();
         tm.RegisterOpen(trade.ResultDeal(), bid, sl, tp, "SELL", lot);
        }
     }
  }
//+------------------------------------------------------------------+
