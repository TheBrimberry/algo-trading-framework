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
//|  This UNIFIED build folds in the documented logic of the series: |
//|   V2  FTMO halt logic            -> lib FTMO guard                |
//|   V3  SMC: OB/FVG/liquidity + MTF -> lib ICT + lib MTF            |
//|   V5  7-signal confluence + Kelly + ICT killzones                |
//|   V7  ensemble voting + recovery mode + dashboard                |
//|  It is a NEW consolidated build, not the historical binaries.    |
//|  Pull the exact originals via experts/UltimateProfit_Series.     |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "8.00"
#property strict
#property description "JAZZYLYFE Ultimate Profit (Unified V2-V7) — Magic 202512250"

#include <Trade/Trade.mqh>
#include "../../lib/JazzyLyfe_FTMO_Guard.mqh"
#include "../../lib/JazzyLyfe_MTF.mqh"
#include "../../lib/JazzyLyfe_ICT.mqh"
#include "../../lib/JazzyLyfe_Sizing.mqh"
#include "../../lib/JazzyLyfe_Controls.mqh"

//--- core inputs --------------------------------------------------
input long              InpMagic          = 202512250;
input double            InpStartBalance   = 0.0;          // 0 = current balance
input double            InpStopPoints     = 1500;         // SL distance (points)
input double            InpRRatio         = 2.0;          // reward:risk
input double            InpWinRate        = 0.55;         // edge stats -> Kelly
input double            InpPayoff         = 1.8;
input double            InpMaxRiskPct     = 1.0;          // hard cap / trade
input double            InpKellyFraction  = 0.25;

//--- MTF / ICT ----------------------------------------------------
input int               InpEmaFast        = 21;
input int               InpEmaSlow        = 50;
input int               InpMinAlign       = 3;            // higher TFs that must agree
input int               InpMinConfluence  = 2;            // ICT reads required (0-4)

//--- V5/V7 ensemble: require N of the classic signals to agree ----
input int               InpMinVotes       = 4;            // of 7 signals
input int               InpRSIPeriod      = 14;

//--- ICT killzone session filter (V5) -----------------------------
input bool              InpUseKillzones   = true;
input int               InpLondonStart    = 7;            // server hour
input int               InpLondonEnd      = 10;
input int               InpNYStart        = 12;
input int               InpNYEnd          = 15;

//--- recovery mode (V7): cut risk after losing streak -------------
input bool              InpRecoveryMode   = true;
input int               InpRecoveryAfter  = 3;            // consecutive losses
input double            InpRecoveryFactor = 0.5;          // risk multiplier

//--- MANDATORY JAZZYLYFE controls ---------------------------------
input bool              InpInverseMode    = false;        // flip all signals
input ENUM_JL_DIRECTION InpDirection      = JL_DIR_BOTH;  // Buy/Sell/Both

//--- objects ------------------------------------------------------
CTrade                  trade;
CJazzyLyfeFTMOGuard     guard;
CJazzyLyfeMTF           mtf;
CJazzyLyfeICT           ict;
CJazzyLyfeSizing        sizing;
CJazzyLyfeControls      controls;

int      g_hRSI = INVALID_HANDLE, g_hMACD = INVALID_HANDLE;
int      g_hEMAf = INVALID_HANDLE, g_hEMAs = INVALID_HANDLE, g_hATR = INVALID_HANDLE;
datetime g_lastBar = 0;
int      g_lossStreak = 0;
double   g_lastClosedProfit = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   guard.Init(InpMagic, InpStartBalance, 4.5, 5.0, 9.0, 10.0);
   if(!mtf.Init(_Symbol, InpEmaFast, InpEmaSlow, InpMinAlign)) return(INIT_FAILED);
   ict.Init(_Symbol, PERIOD_M15, 60);
   sizing.Init(_Symbol, InpMaxRiskPct, InpKellyFraction);
   controls.Init(InpInverseMode, InpDirection);

   g_hRSI  = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   g_hMACD = iMACD(_Symbol, PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   g_hEMAf = iMA(_Symbol, PERIOD_M15, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMAs = iMA(_Symbol, PERIOD_M15, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_hATR  = iATR(_Symbol, PERIOD_M15, 14);
   if(g_hRSI==INVALID_HANDLE||g_hMACD==INVALID_HANDLE||g_hEMAf==INVALID_HANDLE||
      g_hEMAs==INVALID_HANDLE||g_hATR==INVALID_HANDLE) return(INIT_FAILED);

   Print("[JL] Ultimate Profit Unified armed on ", _Symbol);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   guard.ResetSession();
   IndicatorRelease(g_hRSI);  IndicatorRelease(g_hMACD);
   IndicatorRelease(g_hEMAf); IndicatorRelease(g_hEMAs); IndicatorRelease(g_hATR);
   PrintFormat("[JL] Ultimate Profit Unified stopped on %s | reason=%d", _Symbol, reason);
  }

//+------------------------------------------------------------------+
//| 7-signal ensemble vote in direction `dir` (+1 buy / -1 sell).    |
//| Returns how many of the 7 agree.                                 |
//+------------------------------------------------------------------+
int EnsembleVotes(int dir)
  {
   double rsi[1], macd_main[2], macd_sig[2], emaf[1], emas[1];
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
   // 5) MACD vs signal (current confirmed bar)
   if((dir>0 && macd_main[1]>macd_sig[1]) || (dir<0 && macd_main[1]<macd_sig[1])) votes++;
   // 6) MACD slope (current vs previous)
   if((dir>0 && macd_main[1]>macd_main[0]) || (dir<0 && macd_main[1]<macd_main[0])) votes++;
   // 7) ICT confluence (>=1 read in dir)
   if(ict.Confluence(dir) >= 1) votes++;

   return(votes);
  }

//+------------------------------------------------------------------+
bool InKillzone()
  {
   if(!InpUseKillzones) return(true);
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   bool london = (h>=InpLondonStart && h<InpLondonEnd);
   bool ny     = (h>=InpNYStart && h<InpNYEnd);
   return(london || ny);
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
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagic) return(true);
     }
   return(false);
  }

//--- track losing streak for recovery mode (V7)
void UpdateStreakOnHistory()
  {
   if(!InpRecoveryMode) return;
   HistorySelect(TimeCurrent()-7*24*3600, TimeCurrent());
   int deals = HistoryDealsTotal();
   if(deals<=0) return;
   ulong last = HistoryDealGetTicket(deals-1);
   if(last==0) return;
   if(HistoryDealGetInteger(last,DEAL_MAGIC)!=InpMagic) return;
   double profit = HistoryDealGetDouble(last,DEAL_PROFIT);
   if(profit==g_lastClosedProfit) return;     // already counted
   g_lastClosedProfit = profit;
   if(profit < 0) g_lossStreak++; else g_lossStreak = 0;
  }

double RiskMultiplier()
  {
   if(InpRecoveryMode && g_lossStreak >= InpRecoveryAfter) return(InpRecoveryFactor);
   return(1.0);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1) SAFETY FIRST
   ENUM_JL_GUARD_STATE gs = guard.Check();
   if(gs==JL_GUARD_HARD_DAY || gs==JL_GUARD_HARD_MAX) return;
   bool can_open = (gs==JL_GUARD_OK);

   if(!NewBar()) return;
   UpdateStreakOnHistory();
   if(HasOpenPosition()) return;
   if(!can_open) return;
   if(!InKillzone()) return;

   //--- 2) raw direction from MTF + ICT, then ensemble vote
   ENUM_JL_BIAS raw = mtf.Bias();
   if(raw==JL_BIAS_NONE) return;
   if(ict.Confluence((int)raw) < InpMinConfluence) return;
   if(EnsembleVotes((int)raw) < InpMinVotes) return;

   //--- 3) controls (inverse -> direction filter)
   ENUM_JL_BIAS sig = controls.Apply(raw);
   if(sig==JL_BIAS_NONE) return;

   //--- 4) Kelly sizing with recovery-mode multiplier
   double risk = sizing.KellyRiskPct(InpWinRate, InpPayoff) * RiskMultiplier();
   if(risk<=0) return;
   double lot = sizing.LotForRisk(risk, InpStopPoints);
   if(lot<=0) return;

   //--- 5) execute
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(sig==JL_BIAS_BUY)
     {
      double sl=ask-InpStopPoints*point, tp=ask+InpStopPoints*InpRRatio*point;
      trade.Buy(lot,_Symbol,ask,sl,tp,"JAZZYLYFE UP-Unified");
     }
   else if(sig==JL_BIAS_SELL)
     {
      double sl=bid+InpStopPoints*point, tp=bid-InpStopPoints*InpRRatio*point;
      trade.Sell(lot,_Symbol,bid,sl,tp,"JAZZYLYFE UP-Unified");
     }
  }
//+------------------------------------------------------------------+
