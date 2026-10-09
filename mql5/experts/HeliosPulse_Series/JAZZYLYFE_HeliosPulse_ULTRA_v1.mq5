//+------------------------------------------------------------------+
//| JAZZYLYFE_HeliosPulse_ULTRA_v1.mq5                               |
//| Copyright 2026, JAZZYLYFE Trading Systems                        |
//| Author: JAZZYLYFE (TheBrimberry) | Grade A++ Premium EA          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, JAZZYLYFE Trading Systems"
#property link      "https://github.com/TheBrimberry"
#property version   "2.10"
#property description "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#property description "⚡ JAZZYLYFE HELIOS PULSE ULTRA V2.1 - DEAL & SWAP OPTIMIZED ⚡"
#property description "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#property description "Deal & Swap Optimizer: Max Slippage Cap (1.5 Pips) & Rollover Spread Filter"
#property description "Wednesday 3x Triple Swap Shield & Intraday Zero-Swap Flattening"
#property description "Dynamic Winner Lot Boosting (0.09 -> 0.15 on >=85% Prob/Judas)"
#property description "Breakeven + 5 Pips Profit Lock at 1.0R"
#property description "30-Min Cooldown on 2 Consecutive Symbol Losses"
#property description "Upcomers Oracle Risk Shield Presets (4% Daily / 5% DRS)"
#property description "Full Helios Editing Suite & Visual Customization"
#property description "Multi-TF Confluence, Big Dip, Candle & Session Engine"
#property description "London & NY Open Judas Swing Spike/Dip Catching"
#property description "Partial TP Scaling & Dynamic ATR Profit Trailing Stop"
#property description "Smart R:R Auto-Calculator | Interactive GUI Dashboard"
#property description "Staggered Profit Pyramiding | $1000 Breach Partial Close"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_PROGRAM_PRESET_HP
  {
   PRESET_UPCOMERS_ORACLE   = 0, // Upcomers Oracle (4% Daily DD, 5% Total DRS, 0.50% Risk)
   PRESET_UPCOMERS_VANGUARD = 1, // Upcomers Vanguard (2% Daily DD, 3% Total DRS, 0.25% Risk)
   PRESET_CUSTOM            = 2  // Custom User Inputs
  };

enum ENUM_TRADE_DIRECTION_HP
  {
   HP_DIR_BOTH  = 0, // Both Buy & Sell
   HP_DIR_BUY   = 1, // Buy Only
   HP_DIR_SELL  = 2  // Sell Only
  };

enum ENUM_PROB_THRESHOLD
  {
   PROB_60 = 60, // 60% Confluence
   PROB_70 = 70, // 70% Confluence (Moderate)
   PROB_75 = 75, // 75% Confluence (Recommended)
   PROB_80 = 80, // 80% Confluence (High Quality)
   PROB_85 = 85  // 85% Confluence (Ultra Strict)
  };

enum ENUM_SLTP_MODE
  {
   SLTP_MODE_ATR        = 0, // Smart ATR Dynamic Mode
   SLTP_MODE_FIXED_PIPS = 1  // Fixed Pips Custom Editing Mode
  };

enum ENUM_LOT_MODE_HP
  {
   LOT_MODE_FIXED    = 0, // Fixed / Dynamic Boost Mode (0.09 -> 0.15)
   LOT_MODE_RISK_PCT = 1  // Risk % of Account Equity
  };

enum ENUM_THEME_HP
  {
   THEME_DARK_CYBER    = 0, // Dark Cyber (Slate & Neon Gold)
   THEME_MIDNIGHT_BLUE = 1, // Midnight Blue Glass
   THEME_STEALTH_BLACK = 2, // Stealth Black & Gold
   THEME_CLASSIC_GRAY  = 3  // Classic Gray
  };

struct SPosState
  {
   ulong    ticket;
   double   initVol;
   double   rDist;
   bool     tp1Done;
   bool     tp2Done;
   bool     beDone;
   bool     pc1000Done;
   datetime opened;
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "═══ 🏛️ UPCOMERS ORACLE RISK SHIELD ═══"
input ENUM_PROGRAM_PRESET_HP   InpProgramPreset     = PRESET_UPCOMERS_ORACLE; // Prop Program Risk Preset
input ulong                    InpMagicNumber       = 2026888;         // Magic Number
input ENUM_LOT_MODE_HP         InpLotMode           = LOT_MODE_FIXED;  // Lot Sizing Mode
input double                   InpBaseLots          = 0.09;            // Base Lot Size (Standard)
input bool                     InpEnableLotBoost    = true;            // Enable Winner Lot Boost on High Confluence
input double                   InpHighProbLots      = 0.15;            // Boosted Lot Size (>=85% Prob or Judas)
input double                   InpRiskPercent       = 0.50;            // Risk % per Trade (if Risk Mode)
input double                   InpDailyLossLimit    = 4.0;             // Daily Drawdown Cap % (Oracle: 4.0%)
input double                   InpMaxAccountDD      = 5.0;             // Max Account DRS Cap % (Oracle: 5.0%)
input int                      InpMaxLossCooldown   = 2;               // Consecutive Loss Cooldown Trigger
input int                      InpCooldownMinutes   = 30;              // Cooldown Duration (Minutes)
input bool                     InpFridayFlatten     = true;            // Friday 20:00 Server Flatten

input group "═══ 💰 DEAL EXECUTION & SWAP OPTIMIZER SUITE ═══"
input double                   InpMaxSlippagePips   = 1.5;             // Max Allowed Slippage / Deviation (Pips)
input double                   InpMaxSpreadPips     = 3.0;             // Max Allowed Spread (Pips Filter)
input int                      InpOrderCooldownSec  = 30;              // Min Cooldown Between Orders (Seconds)
input bool                     InpAvoidRolloverSpreads = true;         // Block Trades During 23:45-00:30 Rollover Spreads
input bool                     InpAvoidTripleSwapWed = true;           // Avoid New Trades Before Wednesday 3x Swap
input bool                     InpFilterNegativeSwap = false;          // Block Overnight Trades in Negative Swap Direction

input group "═══ 📊 HELIOS PULSE MTF PROBABILITY ENGINE ═══"
input ENUM_PROB_THRESHOLD      InpProbMinThreshold  = PROB_70;         // Min Win Probability % for Auto-Entry (70%)
input ENUM_TRADE_DIRECTION_HP  InpTradeDirection    = HP_DIR_BOTH;     // Allowed Trade Direction
input int                      InpFastEMA           = 13;              // Fast EMA Period
input int                      InpSlowEMA           = 34;              // Slow EMA Period
input int                      InpTrendEMA          = 200;             // Trend EMA Period
input int                      InpRSIPeriod         = 14;              // RSI Period
input int                      InpADXPeriod         = 14;              // ADX Period
input double                   InpADXMin            = 20.0;            // Minimum ADX Trend Strength

input group "═══ 🇬🇧🇺🇸 LONDON & NY OPEN KILLZONE ENGINE ═══"
input bool                     InpEnableSessionEngine   = true;        // Enable London & NY Open Killzones
input int                      InpLondonOpenHour        = 7;           // London Open Server Hour (07:00)
input int                      InpNYOpenHour            = 13;          // NY Open Server Hour (13:00)
input bool                     InpTradeJudasSwings      = true;        // Catch Judas Swing Dip Reversals

input group "═══ 📉 BIG DIP & REVERSAL PIVOT ENGINE ═══"
input bool                     InpEnableDipAnticipation = true;        // Enable Big Dip & Reversal Catching
input double                   InpDipRSITrigger         = 30.0;        // Oversold Dip Trigger Level (RSI <= 30)
input double                   InpDipATRSpikeMult       = 2.0;         // Dip ATR Expansion Spike Multiplier
input int                      InpSwingLookback         = 20;          // Swing High/Low Pivot Lookback

input group "═══ 🕯️ CANDLESTICK REVERSAL PATTERN ENGINE ═══"
input bool                     InpEnableCandlePatterns = true;        // Enable Candlestick Pattern Recognition
input bool                     InpRequirePatternForDip = false;       // Require Candlestick Pattern for Dip Longs

input group "═══ 🎯 SMART R:R, PARTIAL TP & TRAILING STOP ═══"
input ENUM_SLTP_MODE           InpSLTPMode          = SLTP_MODE_ATR;   // SL / TP Calculation Mode
input int                      InpATRPeriod         = 14;              // ATR Period (if ATR Mode)
input double                   InpATRSLMult         = 1.8;             // Initial Stop Loss = ATR x Mult
input double                   InpRiskRewardRatio   = 2.0;             // Risk:Reward Ratio (e.g. 1:2.0)
input double                   InpBELockPips        = 5.0;             // Breakeven Profit Lock (Pips above Entry)
input double                   InpUniversalBEProfit = 100.0;           // Universal Move-to-Breakeven Profit Threshold ($100)
input double                   InpFixedSLPips       = 25.0;            // Custom Fixed Stop Loss (Pips)
input double                   InpFixedTPPips       = 50.0;            // Custom Fixed Take Profit (Pips)
input bool                     InpUsePartialTP      = true;            // Enable 1R / 2R Partial TP Scaling
input double                   InpTP1_Pct           = 50.0;            // TP1 Partial Close % (1R)
input double                   InpTP2_Pct           = 50.0;            // TP2 Partial Close % (2R)
input bool                     InpEnableTrailingStop= true;            // Enable Dynamic ATR Trailing Stop
input double                   InpTrailStartR       = 1.0;             // Start Trailing Stop after 1.0R Profit
input double                   InpTrailATRMult      = 1.5;             // Trailing Stop Distance (ATR Mult)
input int                      InpTrailStepPoints   = 10;              // Min Step Points before Updating SL

input group "═══ 🪜 STAGGERED PROFIT PYRAMIDING ═══"
input bool                     InpStaggerEntries    = true;            // Require Existing Positions in Profit
input int                      InpMaxPositions      = 5;               // Max Concurrent Open Positions (Pyramiding up to 5)
input double                   InpStaggerATRDist    = 1.0;             // Min Distance Between Entries (ATR)

input group "═══ 🎨 HELIOS VISUAL & DASHBOARD EDITING SUITE ═══"
input bool                     InpAutoTrading       = true;            // Auto-Trading Mode Enabled
input bool                     InpShowDashboard     = true;            // Show On-Screen Interactive GUI
input ENUM_THEME_HP            InpDashTheme         = THEME_DARK_CYBER;// Dashboard Color Theme
input ENUM_BASE_CORNER         InpDashCorner        = CORNER_LEFT_UPPER; // Dashboard Corner Placement
input int                      InpDashX             = 15;              // Dashboard X Offset
input int                      InpDashY             = 15;              // Dashboard Y Offset
input bool                     InpShowSessionAlert  = true;            // Display Session Killzone Badge
input bool                     InpShowDipAlert      = true;            // Display Big Dip & Reversal Badge
input bool                     InpShowCandleAlert   = true;            // Display Candlestick Pattern Badge
input bool                     InpShowMTFMatrix     = true;            // Display Multi-TF Matrix
input bool                     InpShowMetrics       = true;            // Display Account & P&L Metrics
input bool                     InpShowButtons       = true;            // Display Interactive Trade Buttons

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS & VARIABLES                                       |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;
CAccountInfo  accInfo;

// Program Effective Risk Limits
double g_EffectiveDailyLossLimit = 4.0;
double g_EffectiveMaxAccountDD   = 5.0;
double g_EffectiveRiskPercent    = 0.50;

// Consecutive Loss Tracking per Symbol
int      g_ConsecutiveLosses = 0;
datetime g_CooldownUntil     = 0;

// Timeframes for MTF Confluence Matrix
ENUM_TIMEFRAMES g_TF[5] = { PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1 };
string          g_TFName[5] = { "M5", "M15", "H1", "H4", "D1" };

// Indicator handles per timeframe
int g_hFastEMA[5];
int g_hSlowEMA[5];
int g_hTrendEMA[5];
int g_hRSI[5];
int g_hADX[5];
int g_hATR[5];

// Live Matrix Calculations
int    g_TFScore[5];     // +2 Bull, -2 Bear, 0 Neutral per TF
double g_TFProbBull = 0; // Bullish Probability %
double g_TFProbBear = 0; // Bearish Probability %
string g_OverallTrend = "NEUTRAL";
int    g_OverallProb  = 50;

// Big Dip & Reversal Status
bool   g_DipDetected       = false;
bool   g_ReversalConfirmed = false;
string g_DipAlertStatus    = "NORMAL 🟢";

// Candlestick Pattern Status
string g_ActiveCandlePattern = "NONE ⚪";
bool   g_BullishPatternFound = false;
bool   g_BearishPatternFound = false;

// Session & Judas Swing Status
string g_SessionPhase      = "ASIAN RANGE 🌏";
double g_AsianHigh         = 0;
double g_AsianLow          = 999999.0;
bool   g_JudasDipDetected       = false;
bool   g_PreSessionAnticipation = false;

// State Tracking for Partial Closes
SPosState g_pos[];

// Account & Session Variables
double   g_peakEquity     = 0;
double   g_dayStartEquity = 0;
datetime g_dayStamp       = 0;
datetime g_lastBarM15     = 0;
bool     g_autoTradeActive= true;

// Dashboard Theme Colors
color g_clrBg, g_clrBorder, g_clrHdr, g_clrSub;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Set Max Permissible Deviation / Slippage Cap
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pips = (_Digits == 3 || _Digits == 5) ? point * 10.0 : point;
   ulong devPoints = (ulong)MathRound((InpMaxSlippagePips * pips) / point);
   trade.SetDeviationInPoints(devPoints);

   // Auto-detect broker order filling mode
   uint fillType = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_FOK) != 0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillType & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_autoTradeActive = InpAutoTrading;

   // Configure Program Presets
   if(InpProgramPreset == PRESET_UPCOMERS_ORACLE)
     {
      g_EffectiveDailyLossLimit = 4.0; // 4% Daily Drawdown Cap
      g_EffectiveMaxAccountDD   = 5.0; // 5% Total DRS Drawdown Cap
      g_EffectiveRiskPercent    = 0.50;// 0.5% Risk Cap
     }
   else if(InpProgramPreset == PRESET_UPCOMERS_VANGUARD)
     {
      g_EffectiveDailyLossLimit = 2.0; // 2% Daily Drawdown Cap
      g_EffectiveMaxAccountDD   = 3.0; // 3% Total DRS Drawdown Cap
      g_EffectiveRiskPercent    = 0.25;// 0.25% Risk Cap
     }
   else
     {
      g_EffectiveDailyLossLimit = InpDailyLossLimit;
      g_EffectiveMaxAccountDD   = InpMaxAccountDD;
      g_EffectiveRiskPercent    = InpRiskPercent;
     }

   // Setup Theme Colors
   SetupThemeColors();

   // Initialize MTF Indicator Handles
   for(int i = 0; i < 5; i++)
     {
      g_hFastEMA[i]  = iMA(_Symbol, g_TF[i], InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hSlowEMA[i]  = iMA(_Symbol, g_TF[i], InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hTrendEMA[i] = iMA(_Symbol, g_TF[i], InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      g_hRSI[i]      = iRSI(_Symbol, g_TF[i], InpRSIPeriod, PRICE_CLOSE);
      g_hADX[i]      = iADX(_Symbol, g_TF[i], InpADXPeriod);
      g_hATR[i]      = iATR(_Symbol, g_TF[i], InpATRPeriod);

      if(g_hFastEMA[i] == INVALID_HANDLE || g_hSlowEMA[i] == INVALID_HANDLE ||
         g_hTrendEMA[i] == INVALID_HANDLE || g_hRSI[i] == INVALID_HANDLE ||
         g_hADX[i] == INVALID_HANDLE || g_hATR[i] == INVALID_HANDLE)
        {
         PrintFormat("HP_ULTRA >> Error initializing indicator handles for timeframe %s", g_TFName[i]);
         return INIT_FAILED;
        }
     }

   g_peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEquity = g_peakEquity;
   g_dayStamp       = iTime(_Symbol, PERIOD_D1, 0);

   if(InpShowDashboard) CreateDashboard();

   PrintFormat("=== JAZZYLYFE HELIOS PULSE ULTRA V2.1 INITIALIZED (Magic: %I64u | Slippage Cap: %.1f Pips) ===",
               InpMagicNumber, InpMaxSlippagePips);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int i = 0; i < 5; i++)
     {
      if(g_hFastEMA[i] != INVALID_HANDLE) IndicatorRelease(g_hFastEMA[i]);
      if(g_hSlowEMA[i] != INVALID_HANDLE) IndicatorRelease(g_hSlowEMA[i]);
      if(g_hTrendEMA[i] != INVALID_HANDLE) IndicatorRelease(g_hTrendEMA[i]);
      if(g_hRSI[i] != INVALID_HANDLE) IndicatorRelease(g_hRSI[i]);
      if(g_hADX[i] != INVALID_HANDLE) IndicatorRelease(g_hADX[i]);
      if(g_hATR[i] != INVALID_HANDLE) IndicatorRelease(g_hATR[i]);
     }

   ObjectsDeleteAll(0, "HP_GUI_");
   Comment("");
  }

//+------------------------------------------------------------------+
//| THEME CONFIGURATOR                                               |
//+------------------------------------------------------------------+
void SetupThemeColors()
  {
   switch(InpDashTheme)
     {
      case THEME_MIDNIGHT_BLUE:
         g_clrBg     = C'15,25,45';
         g_clrBorder = C'40,75,135';
         g_clrHdr    = clrDeepSkyBlue;
         g_clrSub    = clrLightSteelBlue;
         break;
      case THEME_STEALTH_BLACK:
         g_clrBg     = C'10,10,10';
         g_clrBorder = C'50,50,50';
         g_clrHdr    = clrGold;
         g_clrSub    = clrGray;
         break;
      case THEME_CLASSIC_GRAY:
         g_clrBg     = C'35,38,45';
         g_clrBorder = C'70,75,85';
         g_clrHdr    = clrYellow;
         g_clrSub    = clrSilver;
         break;
      case THEME_DARK_CYBER:
      default:
         g_clrBg     = C'20,24,35';
         g_clrBorder = C'45,55,75';
         g_clrHdr    = clrGold;
         g_clrSub    = clrGray;
         break;
     }
  }

//+------------------------------------------------------------------+
//| POSITION STATE TRACKER                                           |
//+------------------------------------------------------------------+
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
   g_pos[n].opened     = TimeCurrent();
   return n;
  }

void PruneStates()
  {
   for(int i = ArraySize(g_pos) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(g_pos[i].ticket))
        {
         for(int j = i; j < ArraySize(g_pos) - 1; j++) g_pos[j] = g_pos[j + 1];
         ArrayResize(g_pos, ArraySize(g_pos) - 1);
        }
     }
  }

//+------------------------------------------------------------------+
//| ROLLOVER SPREAD & TRIPLE SWAP FILTER                             |
//+------------------------------------------------------------------+
bool IsRolloverOrSwapBlocked(ENUM_ORDER_TYPE proposedType)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // 1. Rollover Spread Filter (23:45 - 00:30 Server Time)
   if(InpAvoidRolloverSpreads)
     {
      if((dt.hour == 23 && dt.min >= 45) || (dt.hour == 0 && dt.min <= 30))
        {
         Print("HP_ULTRA >> TRADE BLOCKED: 23:45-00:30 Rollover spread expansion window.");
         return true;
        }
     }

   // 2. Wednesday Triple Swap Shield (23:15 - 23:59 on Wednesdays)
   if(InpAvoidTripleSwapWed && dt.day_of_week == 3 && dt.hour == 23 && dt.min >= 15)
     {
      Print("HP_ULTRA >> TRADE BLOCKED: Wednesday 3x Triple Swap Window.");
      return true;
     }

   // 3. Negative Swap Filter
   if(InpFilterNegativeSwap)
     {
      double swapLong  = SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG);
      double swapShort = SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT);

      if(proposedType == ORDER_TYPE_BUY && swapLong < 0)
        {
         PrintFormat("HP_ULTRA >> TRADE BLOCKED: Negative Buy Swap (%.2f)", swapLong);
         return true;
        }
      else if(proposedType == ORDER_TYPE_SELL && swapShort < 0)
        {
         PrintFormat("HP_ULTRA >> TRADE BLOCKED: Negative Sell Swap (%.2f)", swapShort);
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| LONDON & NEW YORK SESSION KILLZONE ENGINE                        |
//+------------------------------------------------------------------+
void TrackSessionsAndJudasSwings()
  {
   if(!InpEnableSessionEngine)
     {
      g_SessionPhase = "DISABLED ⚪";
      g_JudasDipDetected = false;
      return;
     }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hr = dt.hour;
   int min = dt.min;

   bool isPreAsian  = (hr == 23 && min >= 45);
   bool isPreLondon = (hr == InpLondonOpenHour - 1 && min >= 45);
   bool isPreNY     = (hr == InpNYOpenHour - 1 && min >= 45);
   bool isPreNYSE   = (hr == InpNYOpenHour && min >= 15 && min < 30);

   if(isPreAsian)
     {
      g_SessionPhase = "⚡ PRE-ASIAN ANTICIPATION 🌏 (15m)";
      g_PreSessionAnticipation = true;
     }
   else if(isPreLondon)
     {
      g_SessionPhase = "⚡ PRE-LONDON ANTICIPATION 🇬🇧 (15m)";
      g_PreSessionAnticipation = true;
     }
   else if(isPreNY)
     {
      g_SessionPhase = "⚡ PRE-NEW YORK ANTICIPATION 🇺🇸 (15m)";
      g_PreSessionAnticipation = true;
     }
   else if(isPreNYSE)
     {
      g_SessionPhase = "⚡ PRE-NYSE OPEN ANTICIPATION 🏛️ (15m)";
      g_PreSessionAnticipation = true;
     }
   else
     {
      g_PreSessionAnticipation = false;
     }

   if(hr >= 0 && hr < InpLondonOpenHour && !isPreLondon)
     {
      g_SessionPhase = "ASIAN RANGE 🌏";
      double h = iHigh(_Symbol, PERIOD_H1, 0);
      double l = iLow(_Symbol, PERIOD_H1, 0);
      if(h > g_AsianHigh || g_AsianHigh == 0) g_AsianHigh = h;
      if(l < g_AsianLow || g_AsianLow == 999999.0) g_AsianLow = l;
     }
   else if(hr >= InpLondonOpenHour && hr < InpLondonOpenHour + 3)
     {
      g_SessionPhase = "🇬🇧 LONDON OPEN KILLZONE";
     }
   else if(hr >= InpNYOpenHour && hr < InpNYOpenHour + 3)
     {
      g_SessionPhase = "🇺🇸 NEW YORK OPEN KILLZONE";
     }
   else if(!isPreLondon && !isPreNY && !isPreNYSE)
     {
      g_SessionPhase = "OFF-PEAK SESSION 🌙";
     }

   if(InpTradeJudasSwings && (hr >= InpLondonOpenHour - 1 && hr < InpNYOpenHour + 3))
     {
      double curLow   = iLow(_Symbol, PERIOD_M15, 1);
      double curClose = iClose(_Symbol, PERIOD_M15, 1);

      if(g_AsianLow > 0 && g_AsianLow < 999999.0 && curLow < g_AsianLow && curClose > g_AsianLow)
        {
         g_JudasDipDetected = true;
         g_SessionPhase += " (JUDAS DIP ⚡)";
        }
      else
        {
         g_JudasDipDetected = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| CANDLESTICK PATTERN RECOGNITION ENGINE                          |
//+------------------------------------------------------------------+
void DetectCandlestickPatterns()
  {
   g_BullishPatternFound  = false;
   g_BearishPatternFound  = false;
   g_ActiveCandlePattern  = "NONE ⚪";

   if(!InpEnableCandlePatterns) return;

   double o1 = iOpen(_Symbol, PERIOD_M15, 1),  c1 = iClose(_Symbol, PERIOD_M15, 1);
   double h1 = iHigh(_Symbol, PERIOD_M15, 1),  l1 = iLow(_Symbol, PERIOD_M15, 1);
   double o2 = iOpen(_Symbol, PERIOD_M15, 2),  c2 = iClose(_Symbol, PERIOD_M15, 2);
   double o3 = iOpen(_Symbol, PERIOD_M15, 3),  c3 = iClose(_Symbol, PERIOD_M15, 3);
   double h3 = iHigh(_Symbol, PERIOD_M15, 3),  l3 = iLow(_Symbol, PERIOD_M15, 3);

   double body1 = MathAbs(c1 - o1);
   double upperWick1 = h1 - MathMax(o1, c1);
   double lowerWick1 = MathMin(o1, c1) - l1;
   double range1 = h1 - l1;
   if(range1 <= 0) return;

   double body2 = MathAbs(c2 - o2);

   if(lowerWick1 >= 2.0 * body1 && upperWick1 <= 0.6 * body1 && c1 > l1 + range1 * 0.5)
     {
      g_BullishPatternFound = true;
      g_ActiveCandlePattern = "🔨 BULLISH PINBAR";
      return;
     }

   if(c2 < o2 && c1 > o1 && c1 > o2 && o1 < c2 && body1 > body2 * 1.1)
     {
      g_BullishPatternFound = true;
      g_ActiveCandlePattern = "🟢 BULLISH ENGULFING";
      return;
     }

   if(c3 < o3 && MathAbs(c2 - o2) < (h3 - l3) * 0.3 && c1 > o1 && c1 > (o3 + c3) * 0.5)
     {
      g_BullishPatternFound = true;
      g_ActiveCandlePattern = "⭐ MORNING STAR";
      return;
     }

   if(upperWick1 >= 2.0 * body1 && lowerWick1 <= 0.6 * body1 && c1 < h1 - range1 * 0.5)
     {
      g_BearishPatternFound = true;
      g_ActiveCandlePattern = "🏹 SHOOTING STAR";
      return;
     }

   if(c2 > o2 && c1 < o1 && c1 < o2 && o1 > c2 && body1 > body2 * 1.1)
     {
      g_BearishPatternFound = true;
      g_ActiveCandlePattern = "🔴 BEARISH ENGULFING";
      return;
     }
  }

//+------------------------------------------------------------------+
//| BIG DIP & REVERSAL PIVOT DETECTION ENGINE                        |
//+------------------------------------------------------------------+
void DetectBigDipsAndReversals()
  {
   TrackSessionsAndJudasSwings();
   DetectCandlestickPatterns();

   if(!InpEnableDipAnticipation)
     {
      g_DipDetected = false;
      g_ReversalConfirmed = false;
      g_DipAlertStatus = "DISABLED ⚪";
      return;
     }

   double rsiM15[2], atrM15[1], fM15[2], sM15[2];
   if(CopyBuffer(g_hRSI[1], 0, 1, 2, rsiM15) < 2) return;
   if(CopyBuffer(g_hATR[1], 0, 1, 1, atrM15) < 1) return;
   if(CopyBuffer(g_hFastEMA[1], 0, 1, 2, fM15) < 2) return;
   if(CopyBuffer(g_hSlowEMA[1], 0, 1, 2, sM15) < 2) return;

   double barRange = iHigh(_Symbol, PERIOD_M15, 1) - iLow(_Symbol, PERIOD_M15, 1);
   double lowM15   = iLow(_Symbol, PERIOD_M15, 1);

   double lowestLow = 999999.0;
   for(int k = 2; k <= InpSwingLookback + 2; k++)
     {
      double l = iLow(_Symbol, PERIOD_M15, k);
      if(l < lowestLow) lowestLow = l;
     }

   bool isOversoldDip = (rsiM15[0] <= InpDipRSITrigger || rsiM15[1] <= InpDipRSITrigger);
   bool isSpikeDip    = (barRange >= atrM15[0] * InpDipATRSpikeMult);
   bool isSweepLow    = (lowM15 < lowestLow);

   g_DipDetected = (isOversoldDip || isSweepLow || g_JudasDipDetected) && isSpikeDip;

   bool rsiHookUp   = (rsiM15[1] <= InpDipRSITrigger && rsiM15[0] > InpDipRSITrigger);
   bool emaCrossUp  = (fM15[0] > sM15[0] && fM15[1] <= sM15[1]);

   bool patternFilterPass = (!InpRequirePatternForDip || g_BullishPatternFound);

   g_ReversalConfirmed = (g_DipDetected || rsiHookUp || g_JudasDipDetected) &&
                         (emaCrossUp || g_BullishPatternFound || g_JudasDipDetected || (rsiHookUp && iClose(_Symbol, PERIOD_M15, 1) > iOpen(_Symbol, PERIOD_M15, 1))) &&
                         patternFilterPass;

   if(g_ReversalConfirmed)
     {
      g_DipAlertStatus = g_JudasDipDetected ? "⚡ JUDAS SWING REVERSAL!" : "🔥 REVERSAL PIVOT DETECTED!";
     }
   else if(g_DipDetected)
     {
      g_DipAlertStatus = "⚠️ BIG DIP / LIQUIDITY SWEEP!";
     }
   else
     {
      g_DipAlertStatus = "NORMAL 🟢";
     }
  }

//+------------------------------------------------------------------+
//| MULTI-TIMEFRAME PROBABILITY MATRIX ENGINE                        |
//+------------------------------------------------------------------+
void CalculateMTFMatrix()
  {
   int totalBullPoints = 0;
   int totalBearPoints = 0;
   int maxPossiblePoints = 5 * 4;

   for(int i = 0; i < 5; i++)
     {
      double f[2], s[2], tr[1], rsi[1], adx[1];
      if(CopyBuffer(g_hFastEMA[i], 0, 1, 2, f) < 2) continue;
      if(CopyBuffer(g_hSlowEMA[i], 0, 1, 2, s) < 2) continue;
      if(CopyBuffer(g_hTrendEMA[i], 0, 1, 1, tr) < 1) continue;
      if(CopyBuffer(g_hRSI[i], 0, 1, 1, rsi) < 1) continue;
      if(CopyBuffer(g_hADX[i], 0, 1, 1, adx) < 1) continue;

      double closePrice = iClose(_Symbol, g_TF[i], 1);
      int score = 0;

      if(f[0] > s[0] && closePrice > tr[0]) { score += 2; totalBullPoints += 2; }
      else if(f[0] < s[0] && closePrice < tr[0]) { score -= 2; totalBearPoints += 2; }

      if(rsi[0] > 50.0 && rsi[0] < 70.0) { score += 1; totalBullPoints += 1; }
      else if(rsi[0] < 50.0 && rsi[0] > 30.0) { score -= 1; totalBearPoints += 1; }

      if(adx[0] >= InpADXMin)
        {
         if(score > 0) { score += 1; totalBullPoints += 1; }
         else if(score < 0) { score -= 1; totalBearPoints += 1; }
        }

      g_TFScore[i] = score;
     }

   if(g_ReversalConfirmed) totalBullPoints += 3;
   if(g_JudasDipDetected) totalBullPoints += 3;
   if(g_BullishPatternFound) totalBullPoints += 2;
   if(g_BearishPatternFound) totalBearPoints += 2;

   g_TFProbBull = MathMin(99.0, ((double)totalBullPoints / maxPossiblePoints) * 100.0);
   g_TFProbBear = MathMin(99.0, ((double)totalBearPoints / maxPossiblePoints) * 100.0);

   if(g_TFProbBull > g_TFProbBear && g_TFProbBull >= 50.0)
     {
      g_OverallTrend = (g_JudasDipDetected || g_ReversalConfirmed) ? "KILLZONE DIP LONG 🚀" : "STRONG BULL 🟢";
      g_OverallProb  = (int)MathRound(g_TFProbBull);
     }
   else if(g_TFProbBear > g_TFProbBull && g_TFProbBear >= 50.0)
     {
      g_OverallTrend = "STRONG BEAR 🔴";
      g_OverallProb  = (int)MathRound(g_TFProbBear);
     }
   else
     {
      g_OverallTrend = "SIDEWAYS ⚪";
      g_OverallProb  = 50;
     }
  }

//+------------------------------------------------------------------+
//| STAGGERED PYRAMIDING & RISK CHECKS                               |
//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         cnt++;
     }
   return cnt;
  }

bool StaggeredProfitCheck()
  {
   if(!InpStaggerEntries) return true;
   int cnt = 0;
   bool allInProfit = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         cnt++;
         double flt = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(flt <= 0.0) allInProfit = false;
        }
     }
   if(cnt > 0 && !allInProfit) return false;
   return true;
  }

bool CheckRiskLimits()
  {
   if(TimeCurrent() < g_CooldownUntil)
     {
      return false; // In Cooldown Period
     }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;

   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today > g_dayStamp)
     {
      g_dayStamp = today;
      g_dayStartEquity = eq;
     }

   double dailyDD = (g_dayStartEquity > 0) ? ((g_dayStartEquity - eq) / g_dayStartEquity) * 100.0 : 0;
   double totalDD = (g_peakEquity > 0) ? ((g_peakEquity - eq) / g_peakEquity) * 100.0 : 0;

   if(dailyDD >= g_EffectiveDailyLossLimit || totalDD >= g_EffectiveMaxAccountDD)
      return false;

   if(InpFridayFlatten)
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= 20) return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| DYNAMIC WINNER LOT BOOSTING CALCULATOR                           |
//+------------------------------------------------------------------+
double CalculateOptimalLotSize(double slDist)
  {
   double lots = InpBaseLots; // Standard 0.09 lots

   // 1. DYNAMIC WINNER BOOST: If Win Probability >= 85% OR Judas Swing Reversal
   if(InpEnableLotBoost && (g_OverallProb >= 85 || g_JudasDipDetected || g_ReversalConfirmed))
     {
      lots = InpHighProbLots; // Boosted to 0.15 lots
      PrintFormat("🚀 HP_ULTRA >> WINNER BOOST ACTIVATED! Confluence %d%% | Judas: %s >> Lot Boosted from %.2f -> %.2f",
                  g_OverallProb, g_JudasDipDetected ? "YES" : "NO", InpBaseLots, InpHighProbLots);
     }

   if(InpLotMode == LOT_MODE_RISK_PCT)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskAmt = eq * (g_EffectiveRiskPercent / 100.0);
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickVal > 0 && tickSize > 0 && slDist > 0)
        {
         double calcLots = riskAmt / ((slDist / tickSize) * tickVal);
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         if(step <= 0) step = 0.01;
         lots = MathFloor(calcLots / step + 1e-9) * step;
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         lots = MathMax(vmin, MathMin(InpHighProbLots, MathMin(vmax, lots)));
        }
     }

   return lots;
  }

//+------------------------------------------------------------------+
//| SMART R:R AUTO-CALCULATOR & TRADE EXECUTION                      |
//+------------------------------------------------------------------+
void ExecuteSmartTrade(ENUM_ORDER_TYPE orderType)
  {
   if(CountOurPositions() >= InpMaxPositions)
     {
      Alert(StringFormat("⚠️ MAX POSITIONS REACHED: %d/%d positions open for %s.", CountOurPositions(), InpMaxPositions, _Symbol));
      return;
     }

   if(IsRolloverOrSwapBlocked(orderType)) return;

   // 1. SPREAD FILTER GUARD
   double pips = (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point;
   long current_spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spread_pips = (current_spread * _Point) / pips;
   if(spread_pips > InpMaxSpreadPips)
     {
      PrintFormat("HP_ULTRA >> TRADE BLOCKED: Current spread (%.1f pips) exceeds max limit (%.1f pips)", spread_pips, InpMaxSpreadPips);
      return;
     }

   // 2. ORDER COOLDOWN GUARD
   static datetime last_trade_sec = 0;
   if(TimeCurrent() - last_trade_sec < InpOrderCooldownSec)
     {
      PrintFormat("HP_ULTRA >> TRADE BLOCKED: Order Cooldown Active (%d sec remaining)", InpOrderCooldownSec - (int)(TimeCurrent() - last_trade_sec));
      return;
     }
   last_trade_sec = TimeCurrent();

   if(!StaggeredProfitCheck())
     {
      Alert("⚠️ STAGGER BLOCKED: Existing positions must be in floating profit before adding Staggered Entry!");
      Print("HP_ULTRA >> Staggered Entry Blocked: Previous positions not in profit.");
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double slDist = 0, tpDist = 0;

   if(InpSLTPMode == SLTP_MODE_ATR)
     {
      double atrBuf[1];
      if(CopyBuffer(g_hATR[1], 0, 1, 1, atrBuf) < 1 || atrBuf[0] <= 0) return;
      slDist = atrBuf[0] * InpATRSLMult;
      tpDist = slDist * InpRiskRewardRatio;
     }
   else
     {
      double pips = (_Digits == 3 || _Digits == 5) ? point * 10.0 : point;
      slDist = InpFixedSLPips * pips;
      tpDist = InpFixedTPPips * pips;
     }

   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - slDist : price + slDist, digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tpDist : price - tpDist, digits);

   double lots = CalculateOptimalLotSize(slDist);
   int posCount = CountOurPositions() + 1;

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY) ok = trade.Buy(lots, _Symbol, price, sl, tp, "HP_ULTRA");
   else if(orderType == ORDER_TYPE_SELL) ok = trade.Sell(lots, _Symbol, price, sl, tp, "HP_ULTRA");

   if(ok)
     {
      ulong t = trade.ResultOrder();
      int si = PosIdx(t, true);
      g_pos[si].rDist = slDist;
      g_pos[si].initVol = lots;
      
      Alert(StringFormat("⚡ SMART %s EXECUTED (Stagger #%d) ⚡\nLots: %.2f | Price: %.5f | SL: %.5f | TP: %.5f",
                         EnumToString(orderType), posCount, lots, price, sl, tp));

      PrintFormat("HP_ULTRA >> Smart Order Executed #%I64u (Stagger #%d) | Type: %s | Lots: %.2f | Price: %.5f | SL: %.5f | TP: %.5f",
                  t, posCount, EnumToString(orderType), lots, price, sl, tp);
     }
  }

void CloseAllOurPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         trade.PositionClose(t);
        }
     }
  }

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT, PARTIAL TP & DYNAMIC TRAILING STOP MODULE    |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   PruneStates();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   double atrBuf[1];
   double currentATR = 0;
   if(CopyBuffer(g_hATR[1], 0, 1, 1, atrBuf) >= 1) currentATR = atrBuf[0];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      bool isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double px     = isBuy ? bid : ask;
      int digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double pips   = (_Digits == 3 || _Digits == 5) ? point * 10.0 : point;

      int si = PosIdx(ticket, true);
      if(g_pos[si].initVol <= 0) g_pos[si].initVol = vol;

      // 1. UNIVERSAL $1,000 BREACH 50% PARTIAL CLOSE
      if(!g_pos[si].pc1000Done && (profit >= 1000.0 || profit <= -1000.0))
        {
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         if(step <= 0) step = 0.01;
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double closeVol = MathFloor((vol * 0.5) / step + 1e-9) * step;

         if(closeVol >= vmin && closeVol < vol)
           {
            if(trade.PositionClosePartial(ticket, closeVol))
              {
               g_pos[si].pc1000Done = true;
               PrintFormat("HP_ULTRA >> UNIVERSAL $1000 BREACH >> Partial closed 50%% (%.2f lots) on #%I64u (P&L: $%.2f)", closeVol, ticket, profit);
              }
           }
        }

      // 2. UNIVERSAL $100 CASH PROFIT LOCK ("KEEP $100 PROFIT")
      if(profit >= InpUniversalBEProfit)
        {
         double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickVal > 0 && tickSize > 0 && vol > 0)
           {
            double lockDistInPoints = (InpUniversalBEProfit / (vol * tickVal)) * tickSize;
            double targetSL = NormalizeDouble(isBuy ? entry + lockDistInPoints : entry - lockDistInPoints, digits);

            double stopLevelPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double minStopDist = (stopLevelPoints > 0) ? stopLevelPoints * point : point * 10.0;

            double validTP = tp;
            if(tp > 0)
              {
               bool tpValid = isBuy ? (tp - bid >= minStopDist) : (ask - tp >= minStopDist);
               if(!tpValid) validTP = 0;
              }

            if((isBuy && targetSL > sl) || (!isBuy && (sl == 0 || targetSL < sl)))
              {
               if(trade.PositionModify(ticket, targetSL, validTP))
                 {
                  Alert(StringFormat("💰 HP_ULTRA >> $100 PROFIT LOCKED #%I64u >> SL moved to %.5f (Guaranteed $100 Profit)", ticket, targetSL));
                  PrintFormat("💰 HP_ULTRA >> $100 CASH PROFIT LOCKED #%I64u >> SL set at %.5f (Floating P&L: $%.2f)", ticket, targetSL, profit);
                 }
              }
           }
        }

      // 3. BREAKEVEN + PROFIT LOCK (+5 PIPS) AT 1.0R
      if(g_pos[si].rDist > 0)
        {
         double R = g_pos[si].rDist;
         double mR = isBuy ? (px - entry) / R : (entry - px) / R;

         if(!g_pos[si].beDone && mR >= 1.0)
           {
            double lockDist = InpBELockPips * pips;
            double newSL = NormalizeDouble(isBuy ? entry + lockDist : entry - lockDist, digits);
            double stopLevelPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double minStopDist = (stopLevelPoints > 0) ? stopLevelPoints * point : point * 10.0;

            double validTP = tp;
            if(tp > 0)
              {
               bool tpValid = isBuy ? (tp - bid >= minStopDist) : (ask - tp >= minStopDist);
               if(!tpValid) validTP = 0;
              }

            if((isBuy && newSL > sl) || (!isBuy && (sl == 0 || newSL < sl)))
              {
               if(trade.PositionModify(ticket, newSL, validTP))
                 {
                  g_pos[si].beDone = true;
                  PrintFormat("🛡️ HP_ULTRA >> BREAKEVEN + PROFIT LOCK (+%.1f Pips) SET on #%I64u at %.5f", InpBELockPips, ticket, newSL);
                 }
              }
           }

         // PARTIAL TAKE PROFIT SCALING (1R / 2R)
         if(InpUsePartialTP)
           {
            if(!g_pos[si].tp1Done && mR >= 1.0)
              {
               double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               if(step <= 0) step = 0.01;
               double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double closeVol = MathFloor((vol * (InpTP1_Pct / 100.0)) / step + 1e-9) * step;

               if(closeVol >= vmin && closeVol < vol)
                 {
                  if(trade.PositionClosePartial(ticket, closeVol))
                    {
                     g_pos[si].tp1Done = true;
                     PrintFormat("HP_ULTRA >> TP1 (1R) Partial close %.2f lots on #%I64u", closeVol, ticket);
                    }
                 }
              }

            if(g_pos[si].tp1Done && !g_pos[si].tp2Done && mR >= 2.0)
              {
               double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               if(step <= 0) step = 0.01;
               double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double closeVol = MathFloor((vol * (InpTP2_Pct / 100.0)) / step + 1e-9) * step;

               if(closeVol >= vmin && closeVol < vol)
                 {
                  if(trade.PositionClosePartial(ticket, closeVol))
                    {
                     g_pos[si].tp2Done = true;
                     PrintFormat("HP_ULTRA >> TP2 (2R) Partial close %.2f lots on #%I64u", closeVol, ticket);
                    }
                 }
              }
           }
        }

      // 3. DYNAMIC ATR TRAILING STOP
      if(InpEnableTrailingStop && currentATR > 0 && g_pos[si].rDist > 0)
        {
         double R = g_pos[si].rDist;
         double mR = isBuy ? (px - entry) / R : (entry - px) / R;

         if(mR >= InpTrailStartR)
           {
            double trailDist = currentATR * InpTrailATRMult;
            double stepDist  = InpTrailStepPoints * point;
            double stopLevelPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double minStopDist = (stopLevelPoints > 0) ? stopLevelPoints * point : point * 10.0;

            double validTP = tp;
            if(tp > 0)
              {
               bool tpValid = isBuy ? (tp - bid >= minStopDist) : (ask - tp >= minStopDist);
               if(!tpValid) validTP = 0;
              }

            if(isBuy)
              {
               double candSL = NormalizeDouble(bid - trailDist, digits);
               if(candSL > sl + stepDist && candSL > entry)
                 {
                  if(trade.PositionModify(ticket, candSL, validTP))
                    {
                     PrintFormat("HP_ULTRA >> TRAILING STOP UPDATED #%I64u >> SL locked at %.5f (Floating Profit: $%.2f)", ticket, candSL, profit);
                    }
                 }
              }
            else
              {
               double candSL = NormalizeDouble(ask + trailDist, digits);
               if((sl == 0 || candSL < sl - stepDist) && candSL < entry)
                 {
                  if(trade.PositionModify(ticket, candSL, validTP))
                    {
                     PrintFormat("HP_ULTRA >> TRAILING STOP UPDATED #%I64u >> SL locked at %.5f (Floating Profit: $%.2f)", ticket, candSL, profit);
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| ON TICK MAIN LOOP                                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   DetectBigDipsAndReversals();
   CalculateMTFMatrix();
   ManageOpenPositions();

   if(InpShowDashboard) UpdateDashboard();

   if(!CheckRiskLimits()) return;
   if(!g_autoTradeActive) return;

   // DYNAMIC KILLZONE & PRE-SESSION TRADE FREQUENCY OPTIMIZER
   int effectiveProbReq = (int)InpProbMinThreshold;
   bool isKillzone = (g_SessionPhase == "🇬🇧 LONDON OPEN KILLZONE" || g_SessionPhase == "🇺🇸 NEW YORK OPEN KILLZONE" || g_PreSessionAnticipation);
   if(isKillzone) effectiveProbReq = 60; // Lower threshold to 60% during Killzones & Pre-Session Anticipation windows!

   // HIGH-FREQUENCY CONTINUOUS AUTOMATED TRADE ENGINE
   if(g_ReversalConfirmed || g_JudasDipDetected || g_OverallProb >= effectiveProbReq)
     {
      if((g_ReversalConfirmed || g_JudasDipDetected || g_OverallTrend == "STRONG BULL 🟢" || g_OverallTrend == "BULLISH 🟢" || g_OverallTrend == "DIP REVERSAL LONG 🚀" || g_OverallTrend == "KILLZONE DIP LONG 🚀") &&
         (InpTradeDirection == HP_DIR_BOTH || InpTradeDirection == HP_DIR_BUY))
        {
         ExecuteSmartTrade(ORDER_TYPE_BUY);
        }
      else if((g_OverallTrend == "STRONG BEAR 🔴" || g_OverallTrend == "BEARISH 🔴") &&
              (InpTradeDirection == HP_DIR_BOTH || InpTradeDirection == HP_DIR_SELL))
        {
         ExecuteSmartTrade(ORDER_TYPE_SELL);
        }
     }
  }

//+------------------------------------------------------------------+
//| ON CHART EVENT (INTERACTIVE DASHBOARD BUTTON HANDLER)            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == "HP_GUI_BTN_BUY")
        {
         ExecuteSmartTrade(ORDER_TYPE_BUY);
         ObjectSetInteger(0, "HP_GUI_BTN_BUY", OBJPROP_STATE, false);
        }
      else if(sparam == "HP_GUI_BTN_SELL")
        {
         ExecuteSmartTrade(ORDER_TYPE_SELL);
         ObjectSetInteger(0, "HP_GUI_BTN_SELL", OBJPROP_STATE, false);
        }
      else if(sparam == "HP_GUI_BTN_AUTO")
        {
         g_autoTradeActive = !g_autoTradeActive;
         ObjectSetString(0, "HP_GUI_BTN_AUTO", OBJPROP_TEXT, g_autoTradeActive ? "⚡ AUTO TRADING: ON" : "⏸️ AUTO TRADING: OFF");
         ObjectSetInteger(0, "HP_GUI_BTN_AUTO", OBJPROP_BGCOLOR, g_autoTradeActive ? clrDarkGreen : clrDarkSlateGray);
         ObjectSetInteger(0, "HP_GUI_BTN_AUTO", OBJPROP_STATE, false);
        }
      else if(sparam == "HP_GUI_BTN_CLOSE")
        {
         CloseAllOurPositions();
         ObjectSetInteger(0, "HP_GUI_BTN_CLOSE", OBJPROP_STATE, false);
        }
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| GUI DASHBOARD RENDERER                                           |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   int x = InpDashX, y = InpDashY;
   int w = 290, h = 410;

   CreateRect("HP_GUI_BG", x, y, w, h, g_clrBg, g_clrBorder);

   CreateLabel("HP_GUI_HDR", x + 15, y + 10, "⚡ HELIOS PULSE ULTRA V2.1 ⚡", g_clrHdr, 10, true);
   CreateLabel("HP_GUI_SUB", x + 15, y + 28, "Deal & Swap Optimizer Active", g_clrSub, 7);

   if(InpShowButtons)
     {
      CreateButton("HP_GUI_BTN_BUY", "🟢 BUY (Smart R:R)", x + 15, y + 305, 125, 25, clrDarkGreen, clrWhite);
      CreateButton("HP_GUI_BTN_SELL", "🔴 SELL (Smart R:R)", x + 150, y + 305, 125, 25, clrMaroon, clrWhite);
      CreateButton("HP_GUI_BTN_AUTO", g_autoTradeActive ? "⚡ AUTO TRADING: ON" : "⏸️ AUTO TRADING: OFF", x + 15, y + 335, 260, 25, g_autoTradeActive ? clrDarkGreen : clrDarkSlateGray, clrWhite);
      CreateButton("HP_GUI_BTN_CLOSE", "🚨 FLATTEN / CLOSE ALL", x + 15, y + 365, 260, 25, clrRed, clrWhite);
     }
  }

void UpdateDashboard()
  {
   int x = InpDashX, y = InpDashY;
   int row = 48;
   int lineH = 17;

   if(InpShowSessionAlert)
     {
      color sessClr = (g_SessionPhase.Find("KILLZONE") >= 0) ? clrGold : clrCyan;
      CreateOrUpdateLabel("HP_GUI_SESS_ALERT", x + 15, y + row, "Session: " + g_SessionPhase, sessClr, 8, true);
      row += lineH;
     }

   if(InpShowDipAlert)
     {
      color dipClr = g_ReversalConfirmed ? clrGold : (g_DipDetected ? clrOrange : clrSpringGreen);
      CreateOrUpdateLabel("HP_GUI_DIP_ALERT", x + 15, y + row, "Dip Status: " + g_DipAlertStatus, dipClr, 8, true);
      row += lineH;
     }

   if(InpShowCandleAlert)
     {
      color patClr = g_BullishPatternFound ? clrLime : (g_BearishPatternFound ? clrRed : clrSilver);
      CreateOrUpdateLabel("HP_GUI_PAT_ALERT", x + 15, y + row, "Candle Pattern: " + g_ActiveCandlePattern, patClr, 8, true);
      row += lineH;
     }

   color trendClr = (g_OverallTrend == "STRONG BULL 🟢" || g_OverallTrend == "DIP REVERSAL LONG 🚀" || g_OverallTrend == "KILLZONE DIP LONG 🚀") ? clrLime : (g_OverallTrend == "STRONG BEAR 🔴") ? clrRed : clrYellow;
   CreateOrUpdateLabel("HP_GUI_OVR_TREND", x + 15, y + row, "Overall Trend: " + g_OverallTrend, trendClr, 9, true);
   row += lineH;

   CreateOrUpdateLabel("HP_GUI_OVR_PROB", x + 15, y + row, StringFormat("Win Probability: %d%% (Req: %d%%)", g_OverallProb, (int)InpProbMinThreshold), clrCyan, 9, true);
   row += lineH + 4;

   if(InpShowMTFMatrix)
     {
      CreateOrUpdateLabel("HP_GUI_MAT_HDR", x + 15, y + row, "── Timeframe Confluence Matrix ──", clrSilver, 8);
      row += lineH;

      for(int i = 0; i < 5; i++)
        {
         string status = (g_TFScore[i] > 0) ? "🟢 BULLISH" : (g_TFScore[i] < 0) ? "🔴 BEARISH" : "⚪ NEUTRAL";
         color stClr = (g_TFScore[i] > 0) ? clrLime : (g_TFScore[i] < 0) ? clrRed : clrSilver;
         CreateOrUpdateLabel(StringFormat("HP_GUI_TF_%d", i), x + 20, y + row, StringFormat("%-4s : %s", g_TFName[i], status), stClr, 8);
         row += 15;
        }
      row += 4;
     }

   if(InpShowMetrics)
     {
      CreateOrUpdateLabel("HP_GUI_POS_HDR", x + 15, y + row, StringFormat("── Oracle Shield (Slippage Cap: %.1fp) ──", InpMaxSlippagePips), clrSilver, 8);
      row += lineH;

      int openCount = CountOurPositions();
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayPnl = eq - g_dayStartEquity;
      color pnlClr = (dayPnl >= 0) ? clrLime : clrRed;

      CreateOrUpdateLabel("HP_GUI_MET_POS", x + 20, y + row, StringFormat("Active Positions: %d / %d", openCount, InpMaxPositions), clrWhite, 8);
      row += 15;
      CreateOrUpdateLabel("HP_GUI_MET_PNL", x + 20, y + row, StringFormat("Daily P&L: $%.2f", dayPnl), pnlClr, 8);
     }

   ChartRedraw();
  }

void CreateRect(string name, int x, int y, int w, int h, color bg, color border)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold=false)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void CreateOrUpdateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold=false)
  {
   CreateLabel(name, x, y, text, clr, fontSize, bold);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void CreateButton(string name, string text, int x, int y, int w, int h, color bg, color textClr)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 30);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }
//+------------------------------------------------------------------+
