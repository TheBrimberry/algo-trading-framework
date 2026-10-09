//+------------------------------------------------------------------+
//|                      JAZZYLYFE_QuantumIntelligence_V3.mq5        |
//|                         Copyright 2026, JazzyLyfe Trading        |
//|                              https://github.com/JazzyLyfe        |
//+------------------------------------------------------------------+
//|  ╔═══════════════════════════════════════════════════════════╗   |
//|  ║  QUANTUM INTELLIGENCE TRADING SYSTEM V3                   ║   |
//|  ║  Grade A++ | Beyond-World AI | Master Trader Wisdom       ║   |
//|  ╠═══════════════════════════════════════════════════════════╣   |
//|  ║  ★ EINSTEIN ANALYTICS - Relativity of Price & Time        ║   |
//|  ║  ★ ART OF WAR - Strategic Position Management             ║   |
//|  ║  ★ 50-YEAR MASTER - Institutional Trading Wisdom          ║   |
//|  ║  ★ QUANTUM AI - Probabilistic Decision Making             ║   |
//|  ╠═══════════════════════════════════════════════════════════╣   |
//|  ║  FEATURES:                                                 ║   |
//|  ║  • Trend Anticipation & Direction Prediction               ║   |
//|  ║  • Session Intelligence (Asian/London/NY)                  ║   |
//|  ║  • Smart Close vs Hold Decisions                           ║   |
//|  ║  • Auto-Hedging on Adverse Conditions                      ║   |
//|  ║  • Multi-Timeframe Confluence Analysis                     ║   |
//|  ║  • Market Structure Recognition                            ║   |
//|  ║  • Liquidity Zone Detection                                ║   |
//|  ║  • Momentum Exhaustion Detection                           ║   |
//|  ║  • Smart Money Concepts Integration                        ║   |
//|  ╚═══════════════════════════════════════════════════════════╝   |
//|                                                                  |
//|  Author: JazzyLyfe                                               |
//|  Version: 3.0.0 QUANTUM                                          |
//|  Build: 2026.02.04                                               |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, JazzyLyfe Trading"
#property link        "https://github.com/JazzyLyfe"
#property version     "3.00"
#property description "★★★ QUANTUM INTELLIGENCE TRADING SYSTEM ★★★"
#property description "Einstein Analytics | Art of War Strategy | Master Wisdom"
#property description "Trend Anticipation | Session Intelligence | Auto-Hedging"
#property strict

//+------------------------------------------------------------------+
//| INCLUDES                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH = 0,        // Both Directions
   TRADE_BUY_ONLY = 1,    // Buy Only
   TRADE_SELL_ONLY = 2    // Sell Only
};

enum ENUM_SL_MODE
{
   SL_FIXED = 0,          // Fixed Points
   SL_ATR = 1,            // ATR-Based
   SL_STRUCTURE = 2,      // Market Structure
   SL_SESSION_ADR = 3,    // Session ADR
   SL_QUANTUM = 4         // Quantum Adaptive
};

enum ENUM_TP_MODE
{
   TP_FIXED = 0,          // Fixed Points
   TP_RR_RATIO = 1,       // Risk:Reward Ratio
   TP_ATR = 2,            // ATR-Based
   TP_STRUCTURE = 3,      // Structure Target
   TP_TREND_PROJECT = 4,  // Trend Projection
   TP_QUANTUM = 5         // Quantum Adaptive
};

enum ENUM_TRAIL_MODE
{
   TRAIL_NONE = 0,        // No Trailing
   TRAIL_FIXED = 1,       // Fixed Step
   TRAIL_ATR = 2,         // ATR-Based
   TRAIL_PARABOLIC = 3,   // Parabolic SAR
   TRAIL_RATCHET = 4,     // Ratchet Lock
   TRAIL_TREND = 5,       // Trend-Following
   TRAIL_QUANTUM = 6      // Quantum Adaptive
};

enum ENUM_HEDGE_MODE
{
   HEDGE_DISABLED = 0,    // Disabled
   HEDGE_DRAWDOWN = 1,    // On Drawdown Threshold
   HEDGE_REVERSAL = 2,    // On Trend Reversal
   HEDGE_SESSION = 3,     // Session Risk Hedge
   HEDGE_QUANTUM = 4      // Quantum Smart Hedge
};

enum ENUM_CLOSE_DECISION
{
   DECISION_HOLD = 0,     // Hold Position
   DECISION_CLOSE = 1,    // Close Position
   DECISION_PARTIAL = 2,  // Partial Close
   DECISION_HEDGE = 3     // Hedge Position
};

enum ENUM_SESSION
{
   SESSION_ASIAN = 0,     // Asian (Sydney/Tokyo)
   SESSION_LONDON = 1,    // London
   SESSION_NEWYORK = 2,   // New York
   SESSION_OVERLAP = 3,   // London/NY Overlap
   SESSION_DEAD = 4       // Dead Zone (Low Volume)
};

enum ENUM_TREND
{
   TREND_STRONG_BULL = 2,   // Strong Bullish
   TREND_BULL = 1,          // Bullish
   TREND_NEUTRAL = 0,       // Neutral/Ranging
   TREND_BEAR = -1,         // Bearish
   TREND_STRONG_BEAR = -2   // Strong Bearish
};

enum ENUM_MARKET_PHASE
{
   PHASE_ACCUMULATION = 0,  // Accumulation (Smart Money Buying)
   PHASE_MARKUP = 1,        // Markup (Trend Up)
   PHASE_DISTRIBUTION = 2,  // Distribution (Smart Money Selling)
   PHASE_MARKDOWN = 3,      // Markdown (Trend Down)
   PHASE_RANGING = 4        // Ranging/Consolidation
};

enum ENUM_MOMENTUM
{
   MOMENTUM_STRONG = 2,     // Strong Momentum
   MOMENTUM_NORMAL = 1,     // Normal
   MOMENTUM_WEAK = 0,       // Weak/Exhausted
   MOMENTUM_DIVERGENCE = -1 // Divergence Detected
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "═══════════════ ★ QUANTUM INTELLIGENCE V3 ★ ═══════════════"
input string           InpEAComment = "JAZZYLYFE_QUANTUM_V3";        // EA Comment
input int              InpMagicNumber = 20260204;                    // Magic Number

input group "═══════════════ MULTI-SYMBOL MANAGEMENT ═══════════════"
input bool             InpManageAllSymbols = true;                   // Manage ALL Symbols
input bool             InpFilterByMagic = false;                     // Filter by Magic Only
input int              InpFilterMagic = 0;                           // Filter Magic (0=All)

input group "═══════════════ TRADE DIRECTION ═══════════════"
input ENUM_TRADE_DIRECTION InpDirection = TRADE_BOTH;                // Trade Direction
input bool             InpInverseMode = false;                       // Inverse Mode

input group "═══════════════ STOP LOSS ═══════════════"
input ENUM_SL_MODE     InpSLMode = SL_QUANTUM;                       // Stop Loss Mode
input int              InpFixedSL = 50;                              // Fixed SL (Points)
input double           InpATRMultSL = 2.0;                           // ATR Multiplier
input int              InpATRPeriod = 14;                            // ATR Period
input int              InpMinSL = 15;                                // Minimum SL
input int              InpMaxSL = 500;                               // Maximum SL

input group "═══════════════ TAKE PROFIT ═══════════════"
input ENUM_TP_MODE     InpTPMode = TP_QUANTUM;                       // Take Profit Mode
input int              InpFixedTP = 100;                             // Fixed TP (Points)
input double           InpRRRatio = 3.0;                             // Risk:Reward Ratio
input double           InpATRMultTP = 3.0;                           // ATR Multiplier
input int              InpMinTP = 30;                                // Minimum TP
input int              InpMaxTP = 1000;                              // Maximum TP

input group "═══════════════ TRAILING STOP ═══════════════"
input ENUM_TRAIL_MODE  InpTrailMode = TRAIL_QUANTUM;                 // Trailing Mode
input int              InpTrailStart = 25;                           // Trail Start (Points)
input int              InpTrailStep = 15;                            // Trail Step
input double           InpTrailATRMult = 1.5;                        // Trail ATR Mult

input group "═══════════════ BREAKEVEN & RATCHET ═══════════════"
input bool             InpUseBreakeven = true;                       // Enable Breakeven
input int              InpBETrigger = 15;                            // BE Trigger (Points)
input int              InpBEOffset = 2;                              // BE Offset
input bool             InpUseRatchet = true;                         // Enable Ratchet
input int              InpRatchetStep = 20;                          // Ratchet Step

input group "═══════════════ R-LEVEL PROTECTION ═══════════════"
input bool             InpLockAt1R = true;                           // Lock at 1R (BE+)
input bool             InpLockAt2R = true;                           // Lock at 2R
input bool             InpLockAt3R = true;                           // Lock at 3R

input group "═══════════════ ★ TREND ANALYSIS (EINSTEIN) ═══════════════"
input bool             InpUseTrendAnalysis = true;                   // Enable Trend Analysis
input int              InpTrendMA = 200;                             // Trend MA Period
input int              InpFastMA = 21;                               // Fast MA
input int              InpMediumMA = 50;                             // Medium MA
input int              InpSlowMA = 100;                              // Slow MA
input int              InpADXPeriod = 14;                            // ADX Period
input int              InpADXThreshold = 25;                         // ADX Trend Threshold
input int              InpRSIPeriod = 14;                            // RSI Period
input bool             InpUseMTF = true;                             // Multi-Timeframe Confirm
input ENUM_TIMEFRAMES  InpHTF = PERIOD_H4;                           // Higher Timeframe

input group "═══════════════ ★ SESSION INTELLIGENCE ═══════════════"
input bool             InpUseSessionLogic = true;                    // Enable Session Logic
input int              InpAsianStart = 0;                            // Asian Start Hour
input int              InpAsianEnd = 8;                              // Asian End Hour
input int              InpLondonStart = 8;                           // London Start Hour
input int              InpLondonEnd = 16;                            // London End Hour
input int              InpNYStart = 13;                              // NY Start Hour
input int              InpNYEnd = 21;                                // NY End Hour
input double           InpSessionADRPercent = 80.0;                  // Session ADR % Target
input bool             InpReduceInDeadZone = true;                   // Reduce TP in Dead Zone

input group "═══════════════ ★ SMART CLOSE LOGIC ═══════════════"
input bool             InpUseSmartClose = true;                      // Enable Smart Close
input bool             InpCloseOnTrendReversal = true;               // Close on Trend Reversal
input bool             InpCloseOnMomentumLoss = true;                // Close on Momentum Loss
input bool             InpCloseBeforeNews = true;                    // Close Before News
input bool             InpCloseOnSessionEnd = false;                 // Close on Session End
input double           InpProfitToProtect = 50.0;                    // Profit % to Protect
input bool             InpCloseOnExhaustion = true;                  // Close on Exhaustion

input group "═══════════════ ★ AUTO-HEDGING (ART OF WAR) ═══════════════"
input ENUM_HEDGE_MODE  InpHedgeMode = HEDGE_QUANTUM;                 // Hedge Mode
input double           InpHedgeDrawdownPct = 5.0;                    // Hedge at Drawdown %
input double           InpHedgeLotRatio = 0.5;                       // Hedge Lot Ratio
input int              InpHedgeMinProfitPts = 10;                    // Min Points Before Hedge
input bool             InpHedgeOnReversal = true;                    // Hedge on Reversal
input bool             InpCloseHedgeOnRecovery = true;               // Close Hedge on Recovery
input int              InpMaxHedges = 3;                             // Max Hedge Positions

input group "═══════════════ ★ QUANTUM PROBABILITY ═══════════════"
input bool             InpUseQuantumLogic = true;                    // Enable Quantum Logic
input double           InpMinProbability = 0.65;                     // Min Trade Probability
input int              InpLookbackBars = 100;                        // Analysis Lookback
input bool             InpAdaptToVolatility = true;                  // Adapt to Volatility

input group "═══════════════ ★ FTMO / RISK MANAGEMENT ★ ═══════════════"
input bool             InpUseAutoRisk = true;                        // Use Auto Risk %
input double           InpRiskPercent = 0.5;                         // Risk % per Trade (FTMO: 0.5-0.75)

//+------------------------------------------------------------------+
//| DISPLAY & ALERTS                                                  |
//+------------------------------------------------------------------+
input bool             InpShowDashboard = true;                      // Show Dashboard
input bool             InpShowAnalysis = true;                       // Show Analysis Panel
input bool             InpAlertOnAction = true;                      // Alert on Action
input bool             InpPushNotify = false;                        // Push Notifications
input color            InpBullColor = clrLime;                       // Bullish Color
input color            InpBearColor = clrRed;                        // Bearish Color
input color            InpNeutralColor = clrGray;                    // Neutral Color

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES (g_ prefix to avoid MQL5 conflicts)             |
//+------------------------------------------------------------------+
// Trade Objects
CTrade         g_Trade;
CPositionInfo  g_Position;
CSymbolInfo    g_SymbolInfo;
CAccountInfo   g_AccountInfo;

// Performance Tracking
double         g_TotalProfit = 0;
double         g_TotalLoss = 0;
int            g_TotalWins = 0;
int            g_TotalLosses = 0;
double         g_WinRate = 0.5;
double         g_AvgWin = 0;
double         g_AvgLoss = 0;
double         g_RRRatioActual = 1.0;
double         g_KellyPercent = 0.02;
double         g_PeakEquity = 0;
double         g_MaxDrawdown = 0;

// Multi-Symbol Management
string         g_ManagedSymbols[];
int            g_SymbolCount = 0;
ulong          g_PartialClosedTickets[];

bool IsPartiallyClosed(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_PartialClosedTickets); i++)
   {
      if(g_PartialClosedTickets[i] == ticket) return true;
   }
   return false;
}

void MarkPartiallyClosed(ulong ticket)
{
   int size = ArraySize(g_PartialClosedTickets);
   ArrayResize(g_PartialClosedTickets, size + 1);
   g_PartialClosedTickets[size] = ticket;
}

// Per-Symbol Data Structure
struct SymbolData
{
   string         name;
   // Indicator Handles
   int            hATR;
   int            hADX;
   int            hRSI;
   int            hMAFast;
   int            hMAMedium;
   int            hMASlow;
   int            hMATrend;
   int            hBB;
   int            hPSAR;
   int            hStoch;
   int            hMACD;
   int            hMomentum;
   // HTF Handles
   int            hHTF_MA;
   int            hHTF_RSI;
   int            hHTF_ADX;
   // Cached Values
   double         atr;
   double         adx;
   double         plusDI;
   double         minusDI;
   double         rsi;
   double         maFast;
   double         maMedium;
   double         maSlow;
   double         maTrend;
   double         bbUpper;
   double         bbMiddle;
   double         bbLower;
   double         psar;
   double         stochK;
   double         stochD;
   double         macdMain;
   double         macdSignal;
   double         momentum;
   // HTF Values
   double         htfMA;
   double         htfRSI;
   double         htfADX;
   // Analysis Results
   ENUM_TREND     trend;
   ENUM_TREND     htfTrend;
   ENUM_MARKET_PHASE phase;
   ENUM_MOMENTUM  momentumState;
   ENUM_SESSION   currentSession;
   double         trendStrength;      // 0-100
   double         probability;        // 0-1
   double         volatility;         // Normalized
   double         adr;                // Average Daily Range
   double         sessionProgress;    // 0-100% of session ADR used
   int            swingHighBar;
   int            swingLowBar;
   double         swingHigh;
   double         swingLow;
   double         projectedTarget;
   bool           exhaustionDetected;
   bool           reversalSignal;
   bool           hedgeActive;
   int            hedgeCount;
};

SymbolData g_Data[];

// Time Tracking
datetime       g_LastBarTime = 0;
datetime       g_LastRefresh = 0;
bool           g_IsNewBar = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("╔═══════════════════════════════════════════════════════════════════╗");
   Print("║     JAZZYLYFE QUANTUM INTELLIGENCE TRADING SYSTEM V3              ║");
   Print("║     ★ Einstein Analytics ★ Art of War ★ Master Wisdom ★           ║");
   Print("╠═══════════════════════════════════════════════════════════════════╣");
   Print("║  Copyright 2026, JazzyLyfe Trading | Grade A++                    ║");
   Print("╚═══════════════════════════════════════════════════════════════════╝");
   
   // Initialize trade object
   g_Trade.SetExpertMagicNumber(InpMagicNumber);
   g_Trade.SetDeviationInPoints(10);
   g_Trade.SetTypeFilling(ORDER_FILLING_IOC);
   g_Trade.SetAsyncMode(false);
   
   // Initialize peak equity
   g_PeakEquity = g_AccountInfo.Equity();
   
   // Build symbol list and initialize
   BuildSymbolList();
   InitializeAllIndicators();
   
   // Create timer
   if(InpShowDashboard || InpShowAnalysis)
      EventSetTimer(1);
   
   Print("═══════════════════════════════════════════════════════════════════");
   Print("Managing ", g_SymbolCount, " symbols");
   Print("Trend Analysis: ", InpUseTrendAnalysis ? "ENABLED" : "DISABLED");
   Print("Session Logic: ", InpUseSessionLogic ? "ENABLED" : "DISABLED");
   Print("Smart Close: ", InpUseSmartClose ? "ENABLED" : "DISABLED");
   Print("Auto-Hedging: ", EnumToString(InpHedgeMode));
   Print("Quantum Logic: ", InpUseQuantumLogic ? "ENABLED" : "DISABLED");
   Print("═══════════════════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Build list of symbols with open positions                         |
//+------------------------------------------------------------------+
void BuildSymbolList()
{
   ArrayResize(g_ManagedSymbols, 0);
   g_SymbolCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(g_Position.SelectByIndex(i))
      {
         // Apply filter
         if(InpFilterByMagic && InpFilterMagic > 0 && g_Position.Magic() != InpFilterMagic)
            continue;
         
         string posSymbol = g_Position.Symbol();
         
         // Check if already in list
         bool found = false;
         for(int j = 0; j < g_SymbolCount; j++)
         {
            if(g_ManagedSymbols[j] == posSymbol)
            {
               found = true;
               break;
            }
         }
         
         if(!found)
         {
            g_SymbolCount++;
            ArrayResize(g_ManagedSymbols, g_SymbolCount);
            g_ManagedSymbols[g_SymbolCount - 1] = posSymbol;
         }
      }
   }
   
   // Always include current symbol
   if(g_SymbolCount == 0 || !InpManageAllSymbols)
   {
      g_SymbolCount = 1;
      ArrayResize(g_ManagedSymbols, 1);
      g_ManagedSymbols[0] = _Symbol;
   }
}

//+------------------------------------------------------------------+
//| Initialize indicators for all symbols                             |
//+------------------------------------------------------------------+
void InitializeAllIndicators()
{
   ArrayResize(g_Data, g_SymbolCount);
   
   for(int i = 0; i < g_SymbolCount; i++)
   {
      string sym = g_ManagedSymbols[i];
      g_Data[i].name = sym;
      
      // Current timeframe indicators
      g_Data[i].hATR = iATR(sym, PERIOD_CURRENT, InpATRPeriod);
      g_Data[i].hADX = iADX(sym, PERIOD_CURRENT, InpADXPeriod);
      g_Data[i].hRSI = iRSI(sym, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
      g_Data[i].hMAFast = iMA(sym, PERIOD_CURRENT, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
      g_Data[i].hMAMedium = iMA(sym, PERIOD_CURRENT, InpMediumMA, 0, MODE_EMA, PRICE_CLOSE);
      g_Data[i].hMASlow = iMA(sym, PERIOD_CURRENT, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
      g_Data[i].hMATrend = iMA(sym, PERIOD_CURRENT, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
      g_Data[i].hBB = iBands(sym, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
      g_Data[i].hPSAR = iSAR(sym, PERIOD_CURRENT, 0.02, 0.2);
      g_Data[i].hStoch = iStochastic(sym, PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
      g_Data[i].hMACD = iMACD(sym, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
      g_Data[i].hMomentum = iMomentum(sym, PERIOD_CURRENT, 14, PRICE_CLOSE);
      
      // Higher timeframe indicators
      if(InpUseMTF)
      {
         g_Data[i].hHTF_MA = iMA(sym, InpHTF, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
         g_Data[i].hHTF_RSI = iRSI(sym, InpHTF, InpRSIPeriod, PRICE_CLOSE);
         g_Data[i].hHTF_ADX = iADX(sym, InpHTF, InpADXPeriod);
      }
      
      // Initialize other fields
      g_Data[i].trend = TREND_NEUTRAL;
      g_Data[i].htfTrend = TREND_NEUTRAL;
      g_Data[i].phase = PHASE_RANGING;
      g_Data[i].momentumState = MOMENTUM_NORMAL;
      g_Data[i].currentSession = SESSION_DEAD;
      g_Data[i].hedgeActive = false;
      g_Data[i].hedgeCount = 0;
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release all indicator handles
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Data[i].hATR != INVALID_HANDLE) IndicatorRelease(g_Data[i].hATR);
      if(g_Data[i].hADX != INVALID_HANDLE) IndicatorRelease(g_Data[i].hADX);
      if(g_Data[i].hRSI != INVALID_HANDLE) IndicatorRelease(g_Data[i].hRSI);
      if(g_Data[i].hMAFast != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMAFast);
      if(g_Data[i].hMAMedium != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMAMedium);
      if(g_Data[i].hMASlow != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMASlow);
      if(g_Data[i].hMATrend != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMATrend);
      if(g_Data[i].hBB != INVALID_HANDLE) IndicatorRelease(g_Data[i].hBB);
      if(g_Data[i].hPSAR != INVALID_HANDLE) IndicatorRelease(g_Data[i].hPSAR);
      if(g_Data[i].hStoch != INVALID_HANDLE) IndicatorRelease(g_Data[i].hStoch);
      if(g_Data[i].hMACD != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMACD);
      if(g_Data[i].hMomentum != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMomentum);
      if(g_Data[i].hHTF_MA != INVALID_HANDLE) IndicatorRelease(g_Data[i].hHTF_MA);
      if(g_Data[i].hHTF_RSI != INVALID_HANDLE) IndicatorRelease(g_Data[i].hHTF_RSI);
      if(g_Data[i].hHTF_ADX != INVALID_HANDLE) IndicatorRelease(g_Data[i].hHTF_ADX);
   }
   
   EventKillTimer();
   Comment("");
   ObjectsDeleteAll(0, "QI_");
   
   Print("╔═══════════════════════════════════════════════════════════════════╗");
   Print("║  QUANTUM INTELLIGENCE V3 - SHUTDOWN                               ║");
   PrintFormat("║  Total Trades: %d | Wins: %d | Losses: %d", 
               g_TotalWins + g_TotalLosses, g_TotalWins, g_TotalLosses);
   PrintFormat("║  Win Rate: %.1f%% | R:R: %.2f | Kelly: %.2f%%",
               g_WinRate * 100, g_RRRatioActual, g_KellyPercent * 100);
   PrintFormat("║  Net P/L: $%.2f | Max DD: %.2f%%",
               g_TotalProfit - g_TotalLoss, g_MaxDrawdown);
   Print("╚═══════════════════════════════════════════════════════════════════╝");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Refresh symbol list periodically
   if(TimeCurrent() - g_LastRefresh > 60)
   {
      BuildSymbolList();
      InitializeAllIndicators();
      g_LastRefresh = TimeCurrent();
   }
   
   // Update drawdown tracking
   UpdateDrawdownTracking();
   
   // Process each managed symbol
   for(int i = 0; i < g_SymbolCount; i++)
   {
      ProcessSymbol(i);
   }
   
   // Update dashboard
   if(InpShowDashboard)
      DisplayQuantumDashboard();
}

//+------------------------------------------------------------------+
//| Process a single symbol                                           |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx)
{
   if(idx < 0 || idx >= g_SymbolCount) return;
   
   string sym = g_Data[idx].name;
   
   // Update symbol info
   if(!g_SymbolInfo.Name(sym)) return;
   g_SymbolInfo.RefreshRates();
   
   // Update all indicators
   UpdateIndicators(idx);
   
   // Perform analysis
   if(InpUseTrendAnalysis)
      AnalyzeTrend(idx);
   
   if(InpUseSessionLogic)
      AnalyzeSession(idx);
   
   if(InpUseQuantumLogic)
      CalculateProbability(idx);
      
   // Check for new entries
   CheckForEntry(idx);
   
   // Manage all positions for this symbol
   ManagePositionsForSymbol(idx);
}

//+------------------------------------------------------------------+
//| Check for auto entry based on Quantum Logic                       |
//+------------------------------------------------------------------+
void CheckForEntry(int idx)
{
   if(g_Data[idx].probability < InpMinProbability) return;
   
   // Check if we already have a position open for this symbol
   bool hasPosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_Position.SelectByIndex(i))
      {
         if(g_Position.Symbol() == g_Data[idx].name && 
           (!InpFilterByMagic || InpFilterMagic == 0 || g_Position.Magic() == InpFilterMagic))
         {
            hasPosition = true;
            break;
         }
      }
   }
   
   if(hasPosition) return;
   
   // Entry conditions
   string sym = g_Data[idx].name;
   g_SymbolInfo.Name(sym);
   g_SymbolInfo.RefreshRates();
   
   int signal = 0; // 1 for Buy, -1 for Sell
   
   if(g_Data[idx].trend == TREND_STRONG_BULL || g_Data[idx].trend == TREND_BULL)
   {
      if(g_Data[idx].reversalSignal == false && g_Data[idx].exhaustionDetected == false)
      {
         if(g_Data[idx].momentumState != MOMENTUM_DIVERGENCE && g_Data[idx].momentumState != MOMENTUM_WEAK)
         {
            signal = 1;
         }
      }
   }
   else if(g_Data[idx].trend == TREND_STRONG_BEAR || g_Data[idx].trend == TREND_BEAR)
   {
      if(g_Data[idx].reversalSignal == false && g_Data[idx].exhaustionDetected == false)
      {
         if(g_Data[idx].momentumState != MOMENTUM_DIVERGENCE && g_Data[idx].momentumState != MOMENTUM_WEAK)
         {
            signal = -1;
         }
      }
   }
   
   if(InpInverseMode) signal = -signal;
   
   if(signal == 1 && (InpDirection == TRADE_BOTH || InpDirection == TRADE_BUY_ONLY))
   {
      double price = g_SymbolInfo.Ask();
      double sl = CalculateQuantumSL(idx, POSITION_TYPE_BUY, price);
      double tp = CalculateQuantumTP(idx, POSITION_TYPE_BUY, price, sl);
      double lots = CalculateLotSize(sym, MathAbs(price - sl));
      
      if(lots >= g_SymbolInfo.LotsMin())
      {
         if(g_Trade.Buy(lots, sym, price, sl, tp, "QUANTUM_BUY"))
            Print("★ QUANTUM ENTRY: BUY ", sym, " Lots: ", lots);
      }
   }
   else if(signal == -1 && (InpDirection == TRADE_BOTH || InpDirection == TRADE_SELL_ONLY))
   {
      double price = g_SymbolInfo.Bid();
      double sl = CalculateQuantumSL(idx, POSITION_TYPE_SELL, price);
      double tp = CalculateQuantumTP(idx, POSITION_TYPE_SELL, price, sl);
      double lots = CalculateLotSize(sym, MathAbs(price - sl));
      
      if(lots >= g_SymbolInfo.LotsMin())
      {
         if(g_Trade.Sell(lots, sym, price, sl, tp, "QUANTUM_SELL"))
            Print("★ QUANTUM ENTRY: SELL ", sym, " Lots: ", lots);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on FTMO Risk defaults                    |
//+------------------------------------------------------------------+
double CalculateLotSize(string sym, double slDistance)
{
   if(!InpUseAutoRisk || slDistance <= 0) return g_SymbolInfo.LotsMin();
   
   double riskAmount = g_AccountInfo.Equity() * (InpRiskPercent / 100.0);
   double tickValue = g_SymbolInfo.TickValue();
   double tickSize = g_SymbolInfo.TickSize();
   
   if(tickSize == 0 || tickValue == 0) return g_SymbolInfo.LotsMin();
   
   double slPoints = slDistance / tickSize;
   double lotStep = g_SymbolInfo.LotStep();
   double lots = riskAmount / (slPoints * tickValue);
   
   // Align to lot step
   lots = MathFloor(lots / lotStep) * lotStep;
   
   double minLot = g_SymbolInfo.LotsMin();
   double maxLot = g_SymbolInfo.LotsMax();
   
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   return lots;
}

//+------------------------------------------------------------------+
//| Update all indicators for a symbol                                |
//+------------------------------------------------------------------+
void UpdateIndicators(int idx)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   
   // ATR
   if(CopyBuffer(g_Data[idx].hATR, 0, 0, 3, buf) > 0)
      g_Data[idx].atr = buf[0];
   
   // ADX and DI
   if(CopyBuffer(g_Data[idx].hADX, 0, 0, 3, buf) > 0)
      g_Data[idx].adx = buf[0];
   if(CopyBuffer(g_Data[idx].hADX, 1, 0, 3, buf) > 0)
      g_Data[idx].plusDI = buf[0];
   if(CopyBuffer(g_Data[idx].hADX, 2, 0, 3, buf) > 0)
      g_Data[idx].minusDI = buf[0];
   
   // RSI
   if(CopyBuffer(g_Data[idx].hRSI, 0, 0, 3, buf) > 0)
      g_Data[idx].rsi = buf[0];
   
   // Moving Averages
   if(CopyBuffer(g_Data[idx].hMAFast, 0, 0, 3, buf) > 0)
      g_Data[idx].maFast = buf[0];
   if(CopyBuffer(g_Data[idx].hMAMedium, 0, 0, 3, buf) > 0)
      g_Data[idx].maMedium = buf[0];
   if(CopyBuffer(g_Data[idx].hMASlow, 0, 0, 3, buf) > 0)
      g_Data[idx].maSlow = buf[0];
   if(CopyBuffer(g_Data[idx].hMATrend, 0, 0, 3, buf) > 0)
      g_Data[idx].maTrend = buf[0];
   
   // Bollinger Bands
   if(CopyBuffer(g_Data[idx].hBB, 0, 0, 3, buf) > 0)
      g_Data[idx].bbMiddle = buf[0];
   if(CopyBuffer(g_Data[idx].hBB, 1, 0, 3, buf) > 0)
      g_Data[idx].bbUpper = buf[0];
   if(CopyBuffer(g_Data[idx].hBB, 2, 0, 3, buf) > 0)
      g_Data[idx].bbLower = buf[0];
   
   // Parabolic SAR
   if(CopyBuffer(g_Data[idx].hPSAR, 0, 0, 3, buf) > 0)
      g_Data[idx].psar = buf[0];
   
   // Stochastic
   if(CopyBuffer(g_Data[idx].hStoch, 0, 0, 3, buf) > 0)
      g_Data[idx].stochK = buf[0];
   if(CopyBuffer(g_Data[idx].hStoch, 1, 0, 3, buf) > 0)
      g_Data[idx].stochD = buf[0];
   
   // MACD
   if(CopyBuffer(g_Data[idx].hMACD, 0, 0, 3, buf) > 0)
      g_Data[idx].macdMain = buf[0];
   if(CopyBuffer(g_Data[idx].hMACD, 1, 0, 3, buf) > 0)
      g_Data[idx].macdSignal = buf[0];
   
   // Momentum
   if(CopyBuffer(g_Data[idx].hMomentum, 0, 0, 3, buf) > 0)
      g_Data[idx].momentum = buf[0];
   
   // Higher Timeframe
   if(InpUseMTF)
   {
      if(CopyBuffer(g_Data[idx].hHTF_MA, 0, 0, 3, buf) > 0)
         g_Data[idx].htfMA = buf[0];
      if(CopyBuffer(g_Data[idx].hHTF_RSI, 0, 0, 3, buf) > 0)
         g_Data[idx].htfRSI = buf[0];
      if(CopyBuffer(g_Data[idx].hHTF_ADX, 0, 0, 3, buf) > 0)
         g_Data[idx].htfADX = buf[0];
   }
   
   // Calculate volatility
   string sym = g_Data[idx].name;
   double avgATR = 0;
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_Data[idx].hATR, 0, 0, 20, atrBuf) >= 20)
   {
      for(int i = 0; i < 20; i++)
         avgATR += atrBuf[i];
      avgATR /= 20;
      g_Data[idx].volatility = (avgATR > 0) ? g_Data[idx].atr / avgATR : 1.0;
   }
   
   // Calculate ADR (Average Daily Range)
   double dailyRanges = 0;
   for(int i = 1; i <= 20; i++)
   {
      double dayHigh = iHigh(sym, PERIOD_D1, i);
      double dayLow = iLow(sym, PERIOD_D1, i);
      dailyRanges += (dayHigh - dayLow);
   }
   g_Data[idx].adr = dailyRanges / 20;
   
   // Find swing points
   FindSwingPoints(idx);
}

//+------------------------------------------------------------------+
//| EINSTEIN ANALYTICS: Analyze trend with relativity of price/time  |
//+------------------------------------------------------------------+
void AnalyzeTrend(int idx)
{
   string sym = g_Data[idx].name;
   double close = iClose(sym, PERIOD_CURRENT, 0);
   
   // === MA ALIGNMENT (Golden/Death Cross) ===
   bool maAlignedBull = (g_Data[idx].maFast > g_Data[idx].maMedium && 
                         g_Data[idx].maMedium > g_Data[idx].maSlow);
   bool maAlignedBear = (g_Data[idx].maFast < g_Data[idx].maMedium && 
                         g_Data[idx].maMedium < g_Data[idx].maSlow);
   
   // === PRICE vs 200 MA (Trend Filter) ===
   bool aboveTrendMA = (close > g_Data[idx].maTrend);
   bool belowTrendMA = (close < g_Data[idx].maTrend);
   
   // === ADX TREND STRENGTH ===
   bool strongTrend = (g_Data[idx].adx > InpADXThreshold);
   bool bullishDI = (g_Data[idx].plusDI > g_Data[idx].minusDI);
   bool bearishDI = (g_Data[idx].minusDI > g_Data[idx].plusDI);
   
   // === RSI MOMENTUM ===
   bool rsiBullish = (g_Data[idx].rsi > 50);
   bool rsiBearish = (g_Data[idx].rsi < 50);
   bool rsiOverbought = (g_Data[idx].rsi > 70);
   bool rsiOversold = (g_Data[idx].rsi < 30);
   
   // === MACD MOMENTUM ===
   bool macdBullish = (g_Data[idx].macdMain > g_Data[idx].macdSignal);
   bool macdBearish = (g_Data[idx].macdMain < g_Data[idx].macdSignal);
   
   // === PARABOLIC SAR ===
   bool sarBullish = (g_Data[idx].psar < close);
   bool sarBearish = (g_Data[idx].psar > close);
   
   // === CALCULATE TREND SCORE (-100 to +100) ===
   int score = 0;
   
   // MA Alignment (+/- 25)
   if(maAlignedBull) score += 25;
   else if(maAlignedBear) score -= 25;
   
   // Price vs Trend MA (+/- 20)
   if(aboveTrendMA) score += 20;
   else if(belowTrendMA) score -= 20;
   
   // ADX Direction (+/- 15)
   if(strongTrend && bullishDI) score += 15;
   else if(strongTrend && bearishDI) score -= 15;
   
   // RSI (+/- 15)
   if(rsiBullish) score += 10;
   else if(rsiBearish) score -= 10;
   if(rsiOverbought) score -= 5;  // Exhaustion warning
   if(rsiOversold) score += 5;    // Bounce potential
   
   // MACD (+/- 15)
   if(macdBullish) score += 15;
   else if(macdBearish) score -= 15;
   
   // SAR (+/- 10)
   if(sarBullish) score += 10;
   else if(sarBearish) score -= 10;
   
   // === DETERMINE TREND ===
   g_Data[idx].trendStrength = MathAbs(score);
   
   if(score >= 60)
      g_Data[idx].trend = TREND_STRONG_BULL;
   else if(score >= 25)
      g_Data[idx].trend = TREND_BULL;
   else if(score <= -60)
      g_Data[idx].trend = TREND_STRONG_BEAR;
   else if(score <= -25)
      g_Data[idx].trend = TREND_BEAR;
   else
      g_Data[idx].trend = TREND_NEUTRAL;
   
   // === HIGHER TIMEFRAME CONFIRMATION ===
   if(InpUseMTF)
   {
      if(close > g_Data[idx].htfMA && g_Data[idx].htfRSI > 50)
         g_Data[idx].htfTrend = TREND_BULL;
      else if(close < g_Data[idx].htfMA && g_Data[idx].htfRSI < 50)
         g_Data[idx].htfTrend = TREND_BEAR;
      else
         g_Data[idx].htfTrend = TREND_NEUTRAL;
   }
   
   // === DETECT MOMENTUM STATE ===
   AnalyzeMomentum(idx);
   
   // === DETECT MARKET PHASE ===
   AnalyzeMarketPhase(idx);
   
   // === DETECT EXHAUSTION ===
   DetectExhaustion(idx);
   
   // === DETECT REVERSAL SIGNALS ===
   DetectReversalSignals(idx);
   
   // === CALCULATE PROJECTED TARGET ===
   CalculateProjectedTarget(idx);
}

//+------------------------------------------------------------------+
//| Analyze momentum state                                            |
//+------------------------------------------------------------------+
void AnalyzeMomentum(int idx)
{
   // Check for divergence
   string sym = g_Data[idx].name;
   double close0 = iClose(sym, PERIOD_CURRENT, 0);
   double close10 = iClose(sym, PERIOD_CURRENT, 10);
   
   double rsi0 = g_Data[idx].rsi;
   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   double rsi10 = 50;
   if(CopyBuffer(g_Data[idx].hRSI, 0, 10, 1, rsiBuf) > 0)
      rsi10 = rsiBuf[0];
   
   // Bearish divergence: Price higher high, RSI lower high
   bool bearishDiv = (close0 > close10 && rsi0 < rsi10 && rsi0 > 60);
   
   // Bullish divergence: Price lower low, RSI higher low
   bool bullishDiv = (close0 < close10 && rsi0 > rsi10 && rsi0 < 40);
   
   if(bearishDiv || bullishDiv)
      g_Data[idx].momentumState = MOMENTUM_DIVERGENCE;
   else if(g_Data[idx].adx > 40)
      g_Data[idx].momentumState = MOMENTUM_STRONG;
   else if(g_Data[idx].adx < 20)
      g_Data[idx].momentumState = MOMENTUM_WEAK;
   else
      g_Data[idx].momentumState = MOMENTUM_NORMAL;
}

//+------------------------------------------------------------------+
//| ART OF WAR: Analyze market phase (Wyckoff)                       |
//+------------------------------------------------------------------+
void AnalyzeMarketPhase(int idx)
{
   string sym = g_Data[idx].name;
   double close = iClose(sym, PERIOD_CURRENT, 0);
   
   // Volume analysis would go here (simplified version)
   double bbWidth = (g_Data[idx].bbUpper - g_Data[idx].bbLower) / g_Data[idx].bbMiddle;
   
   // Determine phase based on price action and volatility
   if(bbWidth < 0.02 && g_Data[idx].adx < 20)
   {
      // Tight range, low ADX = Accumulation or Distribution
      if(close > g_Data[idx].maMedium)
         g_Data[idx].phase = PHASE_ACCUMULATION;
      else
         g_Data[idx].phase = PHASE_DISTRIBUTION;
   }
   else if(g_Data[idx].trend == TREND_STRONG_BULL || g_Data[idx].trend == TREND_BULL)
   {
      g_Data[idx].phase = PHASE_MARKUP;
   }
   else if(g_Data[idx].trend == TREND_STRONG_BEAR || g_Data[idx].trend == TREND_BEAR)
   {
      g_Data[idx].phase = PHASE_MARKDOWN;
   }
   else
   {
      g_Data[idx].phase = PHASE_RANGING;
   }
}

//+------------------------------------------------------------------+
//| Detect trend exhaustion                                           |
//+------------------------------------------------------------------+
void DetectExhaustion(int idx)
{
   g_Data[idx].exhaustionDetected = false;
   
   // RSI extreme + divergence
   if(g_Data[idx].momentumState == MOMENTUM_DIVERGENCE)
   {
      g_Data[idx].exhaustionDetected = true;
      return;
   }
   
   // RSI extreme zones
   if(g_Data[idx].rsi > 80 || g_Data[idx].rsi < 20)
   {
      g_Data[idx].exhaustionDetected = true;
      return;
   }
   
   // Stochastic extreme
   if((g_Data[idx].stochK > 85 && g_Data[idx].stochD > 85) ||
      (g_Data[idx].stochK < 15 && g_Data[idx].stochD < 15))
   {
      g_Data[idx].exhaustionDetected = true;
      return;
   }
   
   // Price at Bollinger Band extreme
   string sym = g_Data[idx].name;
   double close = iClose(sym, PERIOD_CURRENT, 0);
   
   if(close > g_Data[idx].bbUpper || close < g_Data[idx].bbLower)
   {
      g_Data[idx].exhaustionDetected = true;
   }
}

//+------------------------------------------------------------------+
//| Detect reversal signals                                           |
//+------------------------------------------------------------------+
void DetectReversalSignals(int idx)
{
   g_Data[idx].reversalSignal = false;
   string sym = g_Data[idx].name;
   
   // Get recent candle data
   double close0 = iClose(sym, PERIOD_CURRENT, 0);
   double close1 = iClose(sym, PERIOD_CURRENT, 1);
   double close2 = iClose(sym, PERIOD_CURRENT, 2);
   double open1 = iOpen(sym, PERIOD_CURRENT, 1);
   double high1 = iHigh(sym, PERIOD_CURRENT, 1);
   double low1 = iLow(sym, PERIOD_CURRENT, 1);
   
   // Candlestick reversal patterns
   double body1 = MathAbs(close1 - open1);
   double range1 = high1 - low1;
   double upperWick = high1 - MathMax(close1, open1);
   double lowerWick = MathMin(close1, open1) - low1;
   
   // Hammer/Hanging Man (potential reversal)
   bool hammer = (lowerWick > body1 * 2 && upperWick < body1 * 0.5);
   bool shootingStar = (upperWick > body1 * 2 && lowerWick < body1 * 0.5);
   
   // Engulfing
   bool bullEngulf = (close1 > open1 && close2 < iOpen(sym, PERIOD_CURRENT, 2) &&
                      close1 > iOpen(sym, PERIOD_CURRENT, 2) && open1 < close2);
   bool bearEngulf = (close1 < open1 && close2 > iOpen(sym, PERIOD_CURRENT, 2) &&
                      close1 < iOpen(sym, PERIOD_CURRENT, 2) && open1 > close2);
   
   // MACD crossover
   double macdBuf[], signalBuf[];
   ArraySetAsSeries(macdBuf, true);
   ArraySetAsSeries(signalBuf, true);
   bool macdCross = false;
   
   if(CopyBuffer(g_Data[idx].hMACD, 0, 0, 3, macdBuf) >= 3 &&
      CopyBuffer(g_Data[idx].hMACD, 1, 0, 3, signalBuf) >= 3)
   {
      bool bullCross = (macdBuf[1] > signalBuf[1] && macdBuf[2] <= signalBuf[2]);
      bool bearCross = (macdBuf[1] < signalBuf[1] && macdBuf[2] >= signalBuf[2]);
      macdCross = bullCross || bearCross;
   }
   
   // SAR flip
   double psarBuf[];
   ArraySetAsSeries(psarBuf, true);
   bool sarFlip = false;
   
   if(CopyBuffer(g_Data[idx].hPSAR, 0, 0, 3, psarBuf) >= 3)
   {
      bool sarFlipBull = (psarBuf[1] < close1 && psarBuf[2] > close2);
      bool sarFlipBear = (psarBuf[1] > close1 && psarBuf[2] < close2);
      sarFlip = sarFlipBull || sarFlipBear;
   }
   
   // Combine signals
   if(hammer || shootingStar || bullEngulf || bearEngulf || macdCross || sarFlip)
   {
      if(g_Data[idx].exhaustionDetected)
         g_Data[idx].reversalSignal = true;
   }
}

//+------------------------------------------------------------------+
//| Calculate projected trend target                                  |
//+------------------------------------------------------------------+
void CalculateProjectedTarget(int idx)
{
   string sym = g_Data[idx].name;
   double close = iClose(sym, PERIOD_CURRENT, 0);
   double atr = g_Data[idx].atr;
   
   // Base projection on trend and structure
   double target = close;
   
   if(g_Data[idx].trend == TREND_STRONG_BULL || g_Data[idx].trend == TREND_BULL)
   {
      // Project to swing high + extension
      if(g_Data[idx].swingHigh > close)
         target = g_Data[idx].swingHigh;
      else
         target = close + atr * 2;
      
      // Fibonacci extension
      double range = g_Data[idx].swingHigh - g_Data[idx].swingLow;
      double fib161 = g_Data[idx].swingHigh + range * 0.618;
      if(fib161 > target)
         target = fib161;
   }
   else if(g_Data[idx].trend == TREND_STRONG_BEAR || g_Data[idx].trend == TREND_BEAR)
   {
      // Project to swing low - extension
      if(g_Data[idx].swingLow < close)
         target = g_Data[idx].swingLow;
      else
         target = close - atr * 2;
      
      // Fibonacci extension
      double range = g_Data[idx].swingHigh - g_Data[idx].swingLow;
      double fib161 = g_Data[idx].swingLow - range * 0.618;
      if(fib161 < target)
         target = fib161;
   }
   
   g_Data[idx].projectedTarget = target;
}

//+------------------------------------------------------------------+
//| Find swing high and low points                                    |
//+------------------------------------------------------------------+
void FindSwingPoints(int idx)
{
   string sym = g_Data[idx].name;
   int lookback = InpLookbackBars;
   
   double highestHigh = 0;
   double lowestLow = DBL_MAX;
   int highBar = 0;
   int lowBar = 0;
   
   for(int i = 1; i <= lookback; i++)
   {
      double h = iHigh(sym, PERIOD_CURRENT, i);
      double l = iLow(sym, PERIOD_CURRENT, i);
      
      if(h > highestHigh)
      {
         highestHigh = h;
         highBar = i;
      }
      if(l < lowestLow)
      {
         lowestLow = l;
         lowBar = i;
      }
   }
   
   g_Data[idx].swingHigh = highestHigh;
   g_Data[idx].swingLow = lowestLow;
   g_Data[idx].swingHighBar = highBar;
   g_Data[idx].swingLowBar = lowBar;
}

//+------------------------------------------------------------------+
//| SESSION INTELLIGENCE: Analyze current session                     |
//+------------------------------------------------------------------+
void AnalyzeSession(int idx)
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   
   // Determine current session
   bool inAsian = (hour >= InpAsianStart && hour < InpAsianEnd);
   bool inLondon = (hour >= InpLondonStart && hour < InpLondonEnd);
   bool inNY = (hour >= InpNYStart && hour < InpNYEnd);
   bool inOverlap = (hour >= InpNYStart && hour < InpLondonEnd);
   
   if(inOverlap)
      g_Data[idx].currentSession = SESSION_OVERLAP;
   else if(inLondon)
      g_Data[idx].currentSession = SESSION_LONDON;
   else if(inNY)
      g_Data[idx].currentSession = SESSION_NEWYORK;
   else if(inAsian)
      g_Data[idx].currentSession = SESSION_ASIAN;
   else
      g_Data[idx].currentSession = SESSION_DEAD;
   
   // Calculate session progress (how much of typical daily range used)
   string sym = g_Data[idx].name;
   double todayHigh = iHigh(sym, PERIOD_D1, 0);
   double todayLow = iLow(sym, PERIOD_D1, 0);
   double todayRange = todayHigh - todayLow;
   
   if(g_Data[idx].adr > 0)
      g_Data[idx].sessionProgress = (todayRange / g_Data[idx].adr) * 100;
   else
      g_Data[idx].sessionProgress = 50;
}

//+------------------------------------------------------------------+
//| QUANTUM: Calculate probability of trade success                   |
//+------------------------------------------------------------------+
void CalculateProbability(int idx)
{
   double prob = 0.5;  // Base probability
   
   // === TREND ALIGNMENT (+20%) ===
   if(g_Data[idx].trend != TREND_NEUTRAL)
   {
      // HTF confirmation bonus
      if(InpUseMTF && g_Data[idx].htfTrend == g_Data[idx].trend)
         prob += 0.15;
      else if(g_Data[idx].trend == TREND_STRONG_BULL || g_Data[idx].trend == TREND_STRONG_BEAR)
         prob += 0.10;
      else
         prob += 0.05;
   }
   
   // === SESSION QUALITY (+15%) ===
   switch(g_Data[idx].currentSession)
   {
      case SESSION_OVERLAP: prob += 0.15; break;  // Best session
      case SESSION_LONDON:  prob += 0.12; break;
      case SESSION_NEWYORK: prob += 0.10; break;
      case SESSION_ASIAN:   prob += 0.05; break;
      case SESSION_DEAD:    prob -= 0.10; break;  // Penalty
   }
   
   // === MOMENTUM (+10%) ===
   if(g_Data[idx].momentumState == MOMENTUM_STRONG)
      prob += 0.10;
   else if(g_Data[idx].momentumState == MOMENTUM_DIVERGENCE)
      prob -= 0.15;  // Warning
   
   // === VOLATILITY ADJUSTMENT ===
   if(g_Data[idx].volatility > 1.5)
      prob -= 0.05;  // High volatility = less predictable
   else if(g_Data[idx].volatility < 0.5)
      prob -= 0.05;  // Too quiet
   
   // === SESSION PROGRESS ===
   if(g_Data[idx].sessionProgress > InpSessionADRPercent)
      prob -= 0.10;  // ADR exhausted
   
   // === EXHAUSTION WARNING ===
   if(g_Data[idx].exhaustionDetected)
      prob -= 0.15;
   
   // === REVERSAL WARNING ===
   if(g_Data[idx].reversalSignal)
      prob -= 0.20;
   
   // Clamp probability
   prob = MathMax(0.1, MathMin(0.95, prob));
   g_Data[idx].probability = prob;
}

//+------------------------------------------------------------------+
//| Manage all positions for a symbol                                 |
//+------------------------------------------------------------------+
void ManagePositionsForSymbol(int idx)
{
   string sym = g_Data[idx].name;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_Position.SelectByIndex(i)) continue;
      if(g_Position.Symbol() != sym) continue;
      
      // Apply filter
      if(InpFilterByMagic && InpFilterMagic > 0 && g_Position.Magic() != InpFilterMagic)
         continue;
      
      // Get position details
      ulong ticket = g_Position.Ticket();
      double openPrice = g_Position.PriceOpen();
      double currentSL = g_Position.StopLoss();
      double currentTP = g_Position.TakeProfit();
      double posProfit = g_Position.Profit();
      double posLots = g_Position.Volume();
      ENUM_POSITION_TYPE posType = g_Position.PositionType();
      
      g_SymbolInfo.Name(sym);
      g_SymbolInfo.RefreshRates();
      double point = g_SymbolInfo.Point();
      int digits = g_SymbolInfo.Digits();
      
      double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                            g_SymbolInfo.Bid() : g_SymbolInfo.Ask();
      double profitPoints = (posType == POSITION_TYPE_BUY) ?
                            (currentPrice - openPrice) / point :
                            (openPrice - currentPrice) / point;
      
      // === APPLY SMART SL/TP IF MISSING ===
      if(currentSL == 0)
      {
         double newSL = CalculateQuantumSL(idx, posType, openPrice);
         double newTP = (currentTP == 0) ? 
                        CalculateQuantumTP(idx, posType, openPrice, newSL) : currentTP;
         
         if(newSL > 0)
         {
            if(g_Trade.PositionModify(ticket, newSL, newTP))
               Print("✓ QUANTUM SL/TP applied: ", sym, " #", ticket);
         }
         continue;  // Skip other management this tick
      }
      
      // === SMART CLOSE DECISION ===
      ENUM_CLOSE_DECISION decision = MakeCloseDecision(idx, posType, profitPoints, posProfit);
      
      if(decision == DECISION_CLOSE)
      {
         if(g_Trade.PositionClose(ticket))
         {
            Print("★ QUANTUM CLOSE: ", sym, " #", ticket, " Profit: $", posProfit);
            if(InpAlertOnAction)
               Alert("Quantum Close: ", sym, " $", DoubleToString(posProfit, 2));
         }
         continue;
      }
      else if(decision == DECISION_PARTIAL)
      {
         if(!IsPartiallyClosed(ticket))
         {
            double closeLots = NormalizeDouble(posLots * 0.5, 2);
            double minLot = g_SymbolInfo.LotsMin();
            if(closeLots >= minLot)
            {
               if(g_Trade.PositionClosePartial(ticket, closeLots))
               {
                  Print("★ PARTIAL CLOSE: ", sym, " #", ticket);
                  MarkPartiallyClosed(ticket);
               }
            }
         }
      }
      else if(decision == DECISION_HEDGE)
      {
         // Place hedge trade
         if(InpHedgeMode != HEDGE_DISABLED)
            PlaceHedgeTrade(idx, ticket, posType, posLots);
         continue;
      }
      
      // === BREAKEVEN ===
      if(InpUseBreakeven && profitPoints >= InpBETrigger)
      {
         double beSL;
         if(posType == POSITION_TYPE_BUY)
            beSL = openPrice + InpBEOffset * point;
         else
            beSL = openPrice - InpBEOffset * point;
         
         beSL = NormalizeDouble(beSL, digits);
         
         bool shouldBE = false;
         if(posType == POSITION_TYPE_BUY && currentSL < beSL)
            shouldBE = true;
         else if(posType == POSITION_TYPE_SELL && currentSL > beSL)
            shouldBE = true;
         
         if(shouldBE)
         {
            if(g_Trade.PositionModify(ticket, beSL, currentTP))
               Print("✓ BREAKEVEN: ", sym, " #", ticket);
         }
      }
      
      // === R-LEVEL PROTECTION ===
      if(currentSL != 0)
      {
         double slDist = MathAbs(openPrice - currentSL);
         double profitDist = (posType == POSITION_TYPE_BUY) ?
                             (currentPrice - openPrice) : (openPrice - currentPrice);
         
         double newSL = currentSL;
         bool modified = false;
         
         if(InpLockAt1R && profitDist >= slDist && profitDist < 2 * slDist)
         {
            double lockSL = (posType == POSITION_TYPE_BUY) ?
                            openPrice + InpBEOffset * point :
                            openPrice - InpBEOffset * point;
            if((posType == POSITION_TYPE_BUY && lockSL > currentSL) ||
               (posType == POSITION_TYPE_SELL && lockSL < currentSL))
            {
               newSL = lockSL;
               modified = true;
            }
         }
         
         if(InpLockAt2R && profitDist >= 2 * slDist && profitDist < 3 * slDist)
         {
            double lockSL = (posType == POSITION_TYPE_BUY) ?
                            openPrice + slDist :
                            openPrice - slDist;
            if((posType == POSITION_TYPE_BUY && lockSL > currentSL) ||
               (posType == POSITION_TYPE_SELL && lockSL < currentSL))
            {
               newSL = lockSL;
               modified = true;
            }
         }
         
         if(InpLockAt3R && profitDist >= 3 * slDist)
         {
            double lockSL = (posType == POSITION_TYPE_BUY) ?
                            openPrice + 2 * slDist :
                            openPrice - 2 * slDist;
            if((posType == POSITION_TYPE_BUY && lockSL > currentSL) ||
               (posType == POSITION_TYPE_SELL && lockSL < currentSL))
            {
               newSL = lockSL;
               modified = true;
            }
         }
         
         if(modified)
         {
            newSL = NormalizeDouble(newSL, digits);
            if(g_Trade.PositionModify(ticket, newSL, currentTP))
               Print("✓ R-LEVEL LOCK: ", sym, " #", ticket);
         }
      }
      
      // === QUANTUM TRAILING ===
      if(InpTrailMode != TRAIL_NONE && profitPoints >= InpTrailStart && currentSL != 0)
      {
         double newSL = CalculateQuantumTrail(idx, posType, openPrice, currentSL, currentPrice);
         
         if(newSL > 0)
         {
            newSL = NormalizeDouble(newSL, digits);
            
            bool shouldTrail = false;
            if(posType == POSITION_TYPE_BUY && newSL > currentSL)
               shouldTrail = true;
            else if(posType == POSITION_TYPE_SELL && newSL < currentSL)
               shouldTrail = true;
            
            if(shouldTrail)
            {
               if(g_Trade.PositionModify(ticket, newSL, currentTP))
                  Print("✓ QUANTUM TRAIL: ", sym, " #", ticket);
            }
         }
      }
      
      // === RATCHET PROFIT LOCK ===
      if(InpUseRatchet && profitPoints > 0 && currentSL != 0)
      {
         int ratchetLevel = (int)(profitPoints / InpRatchetStep);
         if(ratchetLevel >= 1)
         {
            double lockDist = (ratchetLevel - 1) * InpRatchetStep * point;
            double newSL;
            
            if(posType == POSITION_TYPE_BUY)
               newSL = openPrice + lockDist;
            else
               newSL = openPrice - lockDist;
            
            newSL = NormalizeDouble(newSL, digits);
            
            bool shouldLock = false;
            if(posType == POSITION_TYPE_BUY && newSL > currentSL)
               shouldLock = true;
            else if(posType == POSITION_TYPE_SELL && newSL < currentSL)
               shouldLock = true;
            
            if(shouldLock)
            {
               if(g_Trade.PositionModify(ticket, newSL, currentTP))
                  Print("✓ RATCHET LOCK: ", sym, " #", ticket, " Level:", ratchetLevel);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MASTER WISDOM: Make smart close decision                          |
//+------------------------------------------------------------------+
ENUM_CLOSE_DECISION MakeCloseDecision(int idx, ENUM_POSITION_TYPE posType, 
                                       double profitPoints, double profit)
{
   if(!InpUseSmartClose)
      return DECISION_HOLD;
   
   // === RULE 1: TREND REVERSAL (Art of War - Know when to retreat) ===
   if(InpCloseOnTrendReversal)
   {
      bool positionBullish = (posType == POSITION_TYPE_BUY);
      bool trendBullish = (g_Data[idx].trend == TREND_BULL || g_Data[idx].trend == TREND_STRONG_BULL);
      bool trendBearish = (g_Data[idx].trend == TREND_BEAR || g_Data[idx].trend == TREND_STRONG_BEAR);
      
      // Position against strong trend with profit
      if(positionBullish && trendBearish && g_Data[idx].trendStrength > 50 && profit > 0)
      {
         Print("! TREND REVERSAL DETECTED - Closing BUY in bearish trend");
         return DECISION_CLOSE;
      }
      if(!positionBullish && trendBullish && g_Data[idx].trendStrength > 50 && profit > 0)
      {
         Print("! TREND REVERSAL DETECTED - Closing SELL in bullish trend");
         return DECISION_CLOSE;
      }
   }
   
   // === RULE 2: MOMENTUM EXHAUSTION (Einstein - Energy conservation) ===
   if(InpCloseOnMomentumLoss && g_Data[idx].momentumState == MOMENTUM_DIVERGENCE)
   {
      if(profit > 0 && profitPoints >= InpBETrigger)
      {
         Print("! MOMENTUM DIVERGENCE - Taking profits");
         return DECISION_CLOSE;
      }
   }
   
   // === RULE 3: EXHAUSTION AT EXTREMES ===
   if(InpCloseOnExhaustion && g_Data[idx].exhaustionDetected)
   {
      bool positionBullish = (posType == POSITION_TYPE_BUY);
      
      // RSI extreme matching position direction
      if((positionBullish && g_Data[idx].rsi > 80) ||
         (!positionBullish && g_Data[idx].rsi < 20))
      {
         if(profit > 0)
         {
            Print("! EXHAUSTION DETECTED - Taking profits at extreme");
            return DECISION_CLOSE;
         }
      }
   }
   
   // === RULE 4: REVERSAL SIGNAL (50-year wisdom - Respect the market) ===
   if(g_Data[idx].reversalSignal && profit > 0)
   {
      bool positionBullish = (posType == POSITION_TYPE_BUY);
      bool trendBullish = (g_Data[idx].trend == TREND_BULL || g_Data[idx].trend == TREND_STRONG_BULL);
      
      // Reversal against our position
      if((positionBullish && !trendBullish) || (!positionBullish && trendBullish))
      {
         Print("! REVERSAL SIGNAL - Exiting with profit");
         return DECISION_CLOSE;
      }
   }
   
   // === RULE 5: SESSION ADR EXHAUSTED ===
   if(g_Data[idx].sessionProgress >= InpSessionADRPercent)
   {
      if(profit > 0 && profitPoints > InpBETrigger * 2)
      {
         Print("! SESSION ADR EXHAUSTED - Taking profits");
         return DECISION_PARTIAL;  // Partial close, let winner run
      }
   }
   
   // === RULE 6: SESSION END ===
   if(InpCloseOnSessionEnd && g_Data[idx].currentSession == SESSION_DEAD)
   {
      if(profit > 0)
      {
         Print("! SESSION ENDED - Closing profitable position");
         return DECISION_CLOSE;
      }
   }
   
   // === RULE 7: HEDGE TRIGGER ===
   if(InpHedgeMode != HEDGE_DISABLED)
   {
      // Check if we should hedge instead of close
      if(profit < 0 && MathAbs(profitPoints) > InpHedgeMinProfitPts)
      {
         if(InpHedgeOnReversal && g_Data[idx].reversalSignal)
         {
            if(!g_Data[idx].hedgeActive && g_Data[idx].hedgeCount < InpMaxHedges)
            {
               Print("! HEDGE TRIGGERED - Reversal against losing position");
               return DECISION_HEDGE;
            }
         }
      }
   }
   
   // === DEFAULT: HOLD ===
   return DECISION_HOLD;
}

//+------------------------------------------------------------------+
//| ART OF WAR: Place hedge trade                                     |
//+------------------------------------------------------------------+
void PlaceHedgeTrade(int idx, ulong originalTicket, ENUM_POSITION_TYPE originalType, double originalLots)
{
   if(g_Data[idx].hedgeActive || g_Data[idx].hedgeCount >= InpMaxHedges)
      return;
   
   string sym = g_Data[idx].name;
   g_SymbolInfo.Name(sym);
   g_SymbolInfo.RefreshRates();
   
   double hedgeLots = NormalizeDouble(originalLots * InpHedgeLotRatio, 2);
   double minLot = g_SymbolInfo.LotsMin();
   if(hedgeLots < minLot)
      hedgeLots = minLot;
   
   bool result = false;
   string comment = StringFormat("HEDGE_%d", originalTicket);
   
   // Open opposite position
   if(originalType == POSITION_TYPE_BUY)
   {
      // Hedge with SELL
      double sl = g_SymbolInfo.Bid() + g_Data[idx].atr * 2;
      double tp = g_SymbolInfo.Bid() - g_Data[idx].atr * 1.5;
      result = g_Trade.Sell(hedgeLots, sym, 0, sl, tp, comment);
   }
   else
   {
      // Hedge with BUY
      double sl = g_SymbolInfo.Ask() - g_Data[idx].atr * 2;
      double tp = g_SymbolInfo.Ask() + g_Data[idx].atr * 1.5;
      result = g_Trade.Buy(hedgeLots, sym, 0, sl, tp, comment);
   }
   
   if(result)
   {
      g_Data[idx].hedgeActive = true;
      g_Data[idx].hedgeCount++;
      Print("★ HEDGE PLACED: ", sym, " Lots: ", hedgeLots, " for ticket #", originalTicket);
      
      if(InpAlertOnAction)
         Alert("Hedge Trade Placed: ", sym);
   }
}

//+------------------------------------------------------------------+
//| Calculate Quantum SL                                              |
//+------------------------------------------------------------------+
double CalculateQuantumSL(int idx, ENUM_POSITION_TYPE posType, double entryPrice)
{
   string sym = g_Data[idx].name;
   g_SymbolInfo.Name(sym);
   
   double point = g_SymbolInfo.Point();
   int digits = g_SymbolInfo.Digits();
   double slPoints = InpFixedSL;
   
   switch(InpSLMode)
   {
      case SL_FIXED:
         slPoints = InpFixedSL;
         break;
         
      case SL_ATR:
         slPoints = g_Data[idx].atr / point * InpATRMultSL;
         break;
         
      case SL_STRUCTURE:
         if(posType == POSITION_TYPE_BUY)
            slPoints = (entryPrice - g_Data[idx].swingLow) / point + g_Data[idx].atr / point * 0.5;
         else
            slPoints = (g_Data[idx].swingHigh - entryPrice) / point + g_Data[idx].atr / point * 0.5;
         break;
         
      case SL_SESSION_ADR:
         slPoints = g_Data[idx].adr / point * 0.3;  // 30% of ADR
         break;
         
      case SL_QUANTUM:
         {
            // Adaptive based on multiple factors
            double baseSL = g_Data[idx].atr / point * InpATRMultSL;
            
            // Adjust for volatility
            if(g_Data[idx].volatility > 1.5)
               baseSL *= 1.3;
            else if(g_Data[idx].volatility < 0.7)
               baseSL *= 0.8;
            
            // Adjust for trend strength
            if(g_Data[idx].trendStrength > 60)
               baseSL *= 1.1;
            
            // Adjust for session
            if(g_Data[idx].currentSession == SESSION_OVERLAP)
               baseSL *= 1.2;
            else if(g_Data[idx].currentSession == SESSION_DEAD)
               baseSL *= 0.8;
            
            slPoints = baseSL;
         }
         break;
   }
   
   // Apply constraints
   slPoints = MathMax(slPoints, InpMinSL);
   slPoints = MathMin(slPoints, InpMaxSL);
   
   // Calculate price
   double sl;
   if(posType == POSITION_TYPE_BUY)
      sl = NormalizeDouble(entryPrice - slPoints * point, digits);
   else
      sl = NormalizeDouble(entryPrice + slPoints * point, digits);
   
   return sl;
}

//+------------------------------------------------------------------+
//| Calculate Quantum TP                                              |
//+------------------------------------------------------------------+
double CalculateQuantumTP(int idx, ENUM_POSITION_TYPE posType, double entryPrice, double slPrice)
{
   string sym = g_Data[idx].name;
   g_SymbolInfo.Name(sym);
   
   double point = g_SymbolInfo.Point();
   int digits = g_SymbolInfo.Digits();
   double slPoints = MathAbs(entryPrice - slPrice) / point;
   double tpPoints = InpFixedTP;
   
   switch(InpTPMode)
   {
      case TP_FIXED:
         tpPoints = InpFixedTP;
         break;
         
      case TP_RR_RATIO:
         tpPoints = slPoints * InpRRRatio;
         break;
         
      case TP_ATR:
         tpPoints = g_Data[idx].atr / point * InpATRMultTP;
         break;
         
      case TP_STRUCTURE:
         if(posType == POSITION_TYPE_BUY)
            tpPoints = (g_Data[idx].swingHigh - entryPrice) / point;
         else
            tpPoints = (entryPrice - g_Data[idx].swingLow) / point;
         if(tpPoints < slPoints)
            tpPoints = slPoints * InpRRRatio;
         break;
         
      case TP_TREND_PROJECT:
         {
            double projDist = MathAbs(g_Data[idx].projectedTarget - entryPrice) / point;
            tpPoints = (projDist > slPoints) ? projDist : slPoints * InpRRRatio;
         }
         break;
         
      case TP_QUANTUM:
         {
            // Base on R:R
            double baseTP = slPoints * InpRRRatio;
            
            // Adjust for trend alignment
            bool positionBullish = (posType == POSITION_TYPE_BUY);
            bool trendBullish = (g_Data[idx].trend == TREND_BULL || g_Data[idx].trend == TREND_STRONG_BULL);
            
            if((positionBullish && trendBullish) || (!positionBullish && !trendBullish))
               baseTP *= 1.3;  // Extend with trend
            
            // Adjust for probability
            if(g_Data[idx].probability > 0.7)
               baseTP *= 1.2;
            else if(g_Data[idx].probability < 0.5)
               baseTP *= 0.8;
            
            // Adjust for session
            if(g_Data[idx].currentSession == SESSION_DEAD && InpReduceInDeadZone)
               baseTP *= 0.7;
            
            // Check session ADR remaining
            double adrRemaining = g_Data[idx].adr * (1 - g_Data[idx].sessionProgress / 100);
            double adrRemainingPts = adrRemaining / point;
            if(baseTP > adrRemainingPts && adrRemainingPts > slPoints)
               baseTP = adrRemainingPts;
            
            tpPoints = baseTP;
         }
         break;
   }
   
   // Apply constraints
   tpPoints = MathMax(tpPoints, InpMinTP);
   tpPoints = MathMin(tpPoints, InpMaxTP);
   
   // Calculate price
   double tp;
   if(posType == POSITION_TYPE_BUY)
      tp = NormalizeDouble(entryPrice + tpPoints * point, digits);
   else
      tp = NormalizeDouble(entryPrice - tpPoints * point, digits);
   
   return tp;
}

//+------------------------------------------------------------------+
//| Calculate Quantum Trailing SL                                     |
//+------------------------------------------------------------------+
double CalculateQuantumTrail(int idx, ENUM_POSITION_TYPE posType,
                             double openPrice, double currentSL, double currentPrice)
{
   string sym = g_Data[idx].name;
   g_SymbolInfo.Name(sym);
   double point = g_SymbolInfo.Point();
   double newSL = currentSL;
   
   switch(InpTrailMode)
   {
      case TRAIL_FIXED:
         if(posType == POSITION_TYPE_BUY)
            newSL = currentPrice - InpTrailStep * point;
         else
            newSL = currentPrice + InpTrailStep * point;
         break;
         
      case TRAIL_ATR:
         {
            double trailDist = g_Data[idx].atr * InpTrailATRMult;
            if(posType == POSITION_TYPE_BUY)
               newSL = currentPrice - trailDist;
            else
               newSL = currentPrice + trailDist;
         }
         break;
         
      case TRAIL_PARABOLIC:
         if((posType == POSITION_TYPE_BUY && g_Data[idx].psar < currentPrice) ||
            (posType == POSITION_TYPE_SELL && g_Data[idx].psar > currentPrice))
            newSL = g_Data[idx].psar;
         break;
         
      case TRAIL_RATCHET:
         {
            double profitDist = (posType == POSITION_TYPE_BUY) ?
                                (currentPrice - openPrice) : (openPrice - currentPrice);
            int ratchetLevel = (int)(profitDist / (InpRatchetStep * point));
            if(ratchetLevel >= 1)
            {
               double lockDist = (ratchetLevel - 1) * InpRatchetStep * point;
               if(posType == POSITION_TYPE_BUY)
                  newSL = openPrice + lockDist;
               else
                  newSL = openPrice - lockDist;
            }
         }
         break;
         
      case TRAIL_TREND:
         {
            // Use MA as trailing stop
            double maSL = g_Data[idx].maFast;
            double buffer = g_Data[idx].atr * 0.5;
            
            if(posType == POSITION_TYPE_BUY)
               newSL = maSL - buffer;
            else
               newSL = maSL + buffer;
         }
         break;
         
      case TRAIL_QUANTUM:
         {
            // Adaptive trailing based on conditions
            double baseDist;
            
            // Strong trend = tighter trail (capture more)
            if(g_Data[idx].trendStrength > 60)
               baseDist = g_Data[idx].atr * 1.0;
            else
               baseDist = g_Data[idx].atr * InpTrailATRMult;
            
            // High volatility = wider trail
            if(g_Data[idx].volatility > 1.5)
               baseDist *= 1.3;
            
            // Exhaustion = tighter trail (protect profits)
            if(g_Data[idx].exhaustionDetected)
               baseDist *= 0.7;
            
            if(posType == POSITION_TYPE_BUY)
               newSL = currentPrice - baseDist;
            else
               newSL = currentPrice + baseDist;
         }
         break;
   }
   
   return newSL;
}

//+------------------------------------------------------------------+
//| Update drawdown tracking                                          |
//+------------------------------------------------------------------+
void UpdateDrawdownTracking()
{
   double equity = g_AccountInfo.Equity();
   
   if(equity > g_PeakEquity)
      g_PeakEquity = equity;
   
   double dd = (g_PeakEquity - equity) / g_PeakEquity * 100;
   if(dd > g_MaxDrawdown)
      g_MaxDrawdown = dd;
   
   // Check if drawdown hedge needed
   if(InpHedgeMode == HEDGE_DRAWDOWN && dd >= InpHedgeDrawdownPct)
   {
      // Hedge all losing positions
      for(int idx = 0; idx < g_SymbolCount; idx++)
      {
         if(g_Data[idx].hedgeActive) continue;
         
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(g_Position.SelectByIndex(i))
            {
               if(g_Position.Symbol() == g_Data[idx].name && g_Position.Profit() < 0)
               {
                  PlaceHedgeTrade(idx, g_Position.Ticket(), g_Position.PositionType(), g_Position.Volume());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            // Update statistics
            if(profit > 0)
            {
               g_TotalWins++;
               g_TotalProfit += profit;
               g_AvgWin = g_TotalProfit / g_TotalWins;
            }
            else if(profit < 0)
            {
               g_TotalLosses++;
               g_TotalLoss += MathAbs(profit);
               g_AvgLoss = g_TotalLoss / g_TotalLosses;
            }
            
            int total = g_TotalWins + g_TotalLosses;
            if(total > 0)
               g_WinRate = (double)g_TotalWins / total;
            
            if(g_AvgLoss > 0)
               g_RRRatioActual = g_AvgWin / g_AvgLoss;
            
            // Kelly Criterion
            if(total >= 10)
            {
               g_KellyPercent = g_WinRate - ((1 - g_WinRate) / g_RRRatioActual);
               g_KellyPercent = MathMax(0, g_KellyPercent * 0.25);  // Quarter Kelly
            }
            
            // Reset hedge tracking
            string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
            for(int i = 0; i < g_SymbolCount; i++)
            {
               if(g_Data[i].name == dealSymbol)
               {
                  g_Data[i].hedgeActive = false;
                  break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Display Quantum Dashboard                                         |
//+------------------------------------------------------------------+
void DisplayQuantumDashboard()
{
   string dash = "";
   dash += "╔═══════════════════════════════════════════════════════════════════╗\n";
   dash += "║     ★ QUANTUM INTELLIGENCE TRADING SYSTEM V3 ★                    ║\n";
   dash += "║     Einstein Analytics | Art of War | Master Wisdom               ║\n";
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   dash += StringFormat("║ Symbols: %d | Positions: %d | Equity: $%.2f\n",
                        g_SymbolCount, PositionsTotal(), g_AccountInfo.Equity());
   dash += StringFormat("║ Peak: $%.2f | Drawdown: %.2f%%\n", g_PeakEquity, g_MaxDrawdown);
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   
   // Display each symbol's analysis
   for(int i = 0; i < MathMin(g_SymbolCount, 5); i++)
   {
      string trendStr = "";
      color trendColor = InpNeutralColor;
      
      switch(g_Data[i].trend)
      {
         case TREND_STRONG_BULL: trendStr = "▲▲ STRONG BULL"; trendColor = InpBullColor; break;
         case TREND_BULL: trendStr = "▲ BULL"; trendColor = InpBullColor; break;
         case TREND_NEUTRAL: trendStr = "◆ NEUTRAL"; break;
         case TREND_BEAR: trendStr = "▼ BEAR"; trendColor = InpBearColor; break;
         case TREND_STRONG_BEAR: trendStr = "▼▼ STRONG BEAR"; trendColor = InpBearColor; break;
      }
      
      string sessionStr = "";
      switch(g_Data[i].currentSession)
      {
         case SESSION_ASIAN: sessionStr = "ASIAN"; break;
         case SESSION_LONDON: sessionStr = "LONDON"; break;
         case SESSION_NEWYORK: sessionStr = "NY"; break;
         case SESSION_OVERLAP: sessionStr = "OVERLAP★"; break;
         case SESSION_DEAD: sessionStr = "DEAD"; break;
      }
      
      dash += StringFormat("║ %s: %s | %s | Prob:%.0f%% | ADR:%.0f%%\n",
                           g_Data[i].name, trendStr, sessionStr,
                           g_Data[i].probability * 100, g_Data[i].sessionProgress);
      
      if(g_Data[i].exhaustionDetected)
         dash += "║   ⚠ EXHAUSTION DETECTED\n";
      if(g_Data[i].reversalSignal)
         dash += "║   ⚠ REVERSAL SIGNAL\n";
      if(g_Data[i].hedgeActive)
         dash += "║   🛡 HEDGE ACTIVE\n";
   }
   
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   dash += StringFormat("║ Stats: %dW/%dL | WR:%.1f%% | R:R:%.2f | Kelly:%.2f%%\n",
                        g_TotalWins, g_TotalLosses, g_WinRate * 100,
                        g_RRRatioActual, g_KellyPercent * 100);
   dash += StringFormat("║ P/L: $%.2f\n", g_TotalProfit - g_TotalLoss);
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   dash += "║ SL: " + EnumToString(InpSLMode) + " | TP: " + EnumToString(InpTPMode) + "\n";
   dash += "║ Trail: " + EnumToString(InpTrailMode) + " | Hedge: " + EnumToString(InpHedgeMode) + "\n";
   dash += "╚═══════════════════════════════════════════════════════════════════╝\n";
   
   Comment(dash);
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   DisplayQuantumDashboard();
}
//+------------------------------------------------------------------+
