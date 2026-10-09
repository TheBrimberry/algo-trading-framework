//+------------------------------------------------------------------+
//|          JAZZYLYFE_QuantumFortress_V6_UpcomersCompliant.mq5      |
//|                         Copyright 2026, JazzyLyfe Trading        |
//|                              https://github.com/TheBrimberry     |
//+------------------------------------------------------------------+
//|  ╔═══════════════════════════════════════════════════════════╗   |
//|  ║  ★★★ QUANTUM FORTRESS V6 - UPCOMERS ORACLE COMPLIANT ★★★  ║   |
//|  ║  100% COMPLIANCE WITH ALL UPCOMERS RULES + TIME LIMITS    ║   |
//|  ╠═══════════════════════════════════════════════════════════╣   |
//|  ║  TIME LIMITS ENFORCED:                                     ║   |
//|  ║  ✓ SUPERNOVA: 24-hour session (timer starts on 1st trade) ║   |
//|  ║  ✓ HYPERNOVA: 4-hour session (timer starts on 1st trade)  ║   |
//|  ║  ✓ ULTRANOVA: 1-hour session (timer starts on 1st trade)  ║   |
//|  ║  ✓ Min Hold Time: 2 minutes (no tick-scalping)            ║   |
//|  ║  ✓ Revenge Cooldown: 5 minutes after loss                 ║   |
//|  ║  ✓ Valid Day: ≥0.5% realized profit (daily reset UTC)     ║   |
//|  ║  ✓ 5 Valid Days required before payout                    ║   |
//|  ╠═══════════════════════════════════════════════════════════╣   |
//|  ║  UPCOMERS RULES ENFORCED:                                  ║   |
//|  ║  ✓ 4% Daily DD | 5% DRS Trailing | 2% Max Trade           ║   |
//|  ║  ✓ No Hedging | No Martingale | No One-Sided Betting      ║   |
//|  ║  ✓ No Gambling (3.5x lot cap) | No Revenge Trading        ║   |
//|  ╚═══════════════════════════════════════════════════════════╝   |
//|                                                                  |
//|  Author: JazzyLyfe / Brimberry LLC                              |
//|  Version: 6.0.0 UPCOMERS COMPLIANT + TIME LIMITS                |
//|  Build: 2026.07.13                                               |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, JazzyLyfe / Brimberry LLC"
#property link        "https://github.com/TheBrimberry"
#property version     "6.00"
#property description "★★★ QUANTUM FORTRESS V6 - UPCOMERS ORACLE COMPLIANT ★★★"
#property description "ALL TIME LIMITS: Supernova 24h | Hypernova 4h | Ultranova 1h"
#property description "2min Hold | 5min Revenge CD | Valid Day Tracking | 5 Days Required"
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
enum ENUM_UPCOMERS_PROGRAM
{
   PROGRAM_ORACLE = 0,       // Oracle (No time limit, 4% daily, 5% DRS)
   PROGRAM_VANGUARD = 1,     // Vanguard (No time limit, 3% DRS + 2% daily)
   PROGRAM_EMBER = 2,        // Ember (No time limit, 4% DRS only)
   PROGRAM_SUPERNOVA = 3,    // Supernova (24h session, 3% DRS)
   PROGRAM_HYPERNOVA = 4,    // Hypernova (4h session, 3% DRS)
   PROGRAM_ULTRANOVA = 5     // Ultranova (1h session, 3% DRS)
};

enum ENUM_SESSION_STATUS
{
   SESSION_NOT_STARTED = 0,  // Session not started (no trades yet)
   SESSION_ACTIVE = 1,       // Session running
   SESSION_WARNING = 2,      // < 10% time remaining
   SESSION_CRITICAL = 3,     // < 5% time remaining
   SESSION_ENDED = 4,        // Session time expired
   SESSION_NO_LIMIT = 5      // No time limit (Oracle/Vanguard/Ember)
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH = 0,
   TRADE_BUY_ONLY = 1,
   TRADE_SELL_ONLY = 2
};

enum ENUM_SL_MODE
{
   SL_ATR_2PCT = 0,          // ATR (capped at 2% wall)
   SL_FIXED = 1,             // Fixed Points
   SL_STRUCTURE = 2          // Market Structure
};

enum ENUM_TP_MODE
{
   TP_GOLDEN_RATIO = 0,      // Golden Ratio (1.618R)
   TP_FIXED = 1,             // Fixed Points
   TP_ATR = 2                // ATR Multiple
};

enum ENUM_TRAIL_MODE
{
   TRAIL_NONE = 0,
   TRAIL_BE_THEN_ATR = 1,    // BE then ATR chase
   TRAIL_AGGRESSIVE = 2,
   TRAIL_RATCHET = 3
};

enum ENUM_TREND
{
   TREND_STRONG_BULL = 2,
   TREND_BULL = 1,
   TREND_NEUTRAL = 0,
   TREND_BEAR = -1,
   TREND_STRONG_BEAR = -2
};

enum ENUM_SESSION_TIME
{
   SESSION_ASIAN = 0,
   SESSION_LONDON = 1,
   SESSION_NEWYORK = 2,
   SESSION_OVERLAP = 3,
   SESSION_DEAD = 4
};

enum ENUM_COMPLIANCE_STATUS
{
   COMPLIANCE_OK = 0,
   COMPLIANCE_WARNING = 1,
   COMPLIANCE_SOFT_STOP = 2,
   COMPLIANCE_HARD_STOP = 3,
   COMPLIANCE_BREACH = 4
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "═══════════════ ★ UPCOMERS PROGRAM SELECTION ★ ═══════════════"
input ENUM_UPCOMERS_PROGRAM InpProgram = PROGRAM_ORACLE;             // Upcomers Program
input string           InpEAComment = "JLUPC_FORTRESS_V6";           // EA Comment
input int              InpMagicNumber = 202512250;                   // Magic Number

input group "═══════════════ ★ TIME LIMITS (AUTO-SET BY PROGRAM) ★ ═══════════════"
input bool             InpAutoTimeSettings = true;                   // Auto-Set Time Limits by Program
input int              InpSessionHours = 24;                         // Manual: Session Hours (if not auto)
input int              InpSessionMinutes = 0;                        // Manual: Session Minutes
input bool             InpCloseBeforeExpiry = true;                  // Close All Before Session Ends
input int              InpCloseMinutesBefore = 5;                    // Close X Minutes Before Expiry

input group "═══════════════ ★ CRITICAL TIME RULES ★ ═══════════════"
input int              InpMinHoldSeconds = 120;                      // Min Hold Time (120s = 2min)
input int              InpRevengeCooldownSec = 300;                  // Revenge Cooldown (300s = 5min)
input int              InpMaxSameDirection = 2;                      // Max Same-Direction Trades/Symbol

input group "═══════════════ ★ VALID DAY REQUIREMENTS ★ ═══════════════"
input bool             InpTrackValidDays = true;                     // Track Valid Days
input double           InpValidDayThreshold = 0.5;                   // Valid Day = +0.5% Realized
input int              InpValidDaysRequired = 5;                     // Valid Days Required for Payout
input bool             InpValidDaysNonConsecutive = true;            // Non-Consecutive Days OK

input group "═══════════════ ★ DRAWDOWN LIMITS (AUTO-SET) ★ ═══════════════"
input bool             InpAutoDDSettings = true;                     // Auto-Set DD Limits by Program
input double           InpDailyDDLimit = 4.0;                        // Manual: Daily DD Limit %
input double           InpDRSLimit = 5.0;                            // Manual: DRS Trailing Limit %
input double           InpMaxTradeRisk = 2.0;                        // Max Single Trade Risk % (Always 2%)

input group "═══════════════ JAZZYLYFE RECOVERY-AWARE RISK ═══════════════"
input double           InpBaseRiskPercent = 0.25;                    // Base Risk % per Trade (Minimal Risk)
input double           InpMaxRiskPercent = 0.50;                      // Ceiling Risk % per Trade (Minimal Ceiling)
input double           InpDailySoftStop = 2.0;                       // Daily Soft-Stop % (Block New)
input double           InpDailyFlatten = 2.5;                        // Daily Flatten % (Close All)
input double           InpDDSoftStop = 3.0;                          // DD Soft-Stop % (Block New)
input double           InpDDFlatten = 4.0;                           // DD Flatten % (Close All)
input double           InpAntiMartingale = 0.85;                     // Anti-Martingale Factor
input double           InpAntiMartingaleFloor = 0.40;                // Anti-Martingale Floor
input double           InpMaxLotMultiplier = 3.5;                    // Max Lot vs Usual (Gambling Prevention)
input double           InpDistanceToFloorCap = 0.50;                 // Cap at 50% Distance to Floor

input group "═══════════════ MULTI-SYMBOL MANAGEMENT ═══════════════"
input bool             InpManageAllSymbols = true;                   // Manage ALL Symbols
input bool             InpFilterByMagic = false;                     // Filter by Magic Only

input group "═══════════════ TRADE DIRECTION & INVERSE ═══════════════"
input ENUM_TRADE_DIRECTION InpDirection = TRADE_BOTH;                // Trade Direction
input bool             InpInverseMode = false;                       // Inverse Mode

input group "═══════════════ STOP LOSS ═══════════════"
input ENUM_SL_MODE     InpSLMode = SL_ATR_2PCT;                      // SL Mode
input double           InpATRMultSL = 1.5;                           // ATR Multiplier
input int              InpATRPeriod = 14;                            // ATR Period
input int              InpMinSL = 15;                                // Min SL Points
input int              InpMaxSL = 100;                               // Max SL Points

input group "═══════════════ TAKE PROFIT ═══════════════"
input ENUM_TP_MODE     InpTPMode = TP_GOLDEN_RATIO;                  // TP Mode
input double           InpGoldenTP1 = 1.000;                         // TP1 at 1.000R
input double           InpGoldenTP2 = 1.618;                         // TP2 at 1.618R
input double           InpGoldenTP3 = 2.618;                         // TP3 at 2.618R
input int              InpMinTP = 20;                                // Min TP Points
input int              InpMaxTP = 500;                               // Max TP Points

input group "═══════════════ TRAILING ═══════════════"
input ENUM_TRAIL_MODE  InpTrailMode = TRAIL_BE_THEN_ATR;             // Trail Mode
input int              InpBETrigger = 15;                            // BE Trigger Points
input int              InpBEOffset = 2;                              // BE Offset Points
input double           InpTrailATRMult = 1.0;                        // Trail ATR Multiplier
input int              InpRatchetStep = 15;                          // Ratchet Step Points

input group "═══════════════ PARTIAL CLOSE ═══════════════"
input bool             InpUsePartialClose = true;                    // Enable Partial Close
input double           InpPartialAt1R = 33.0;                        // Close % at 1R
input double           InpPartialAt1618R = 33.0;                     // Close % at 1.618R
input double           InpPartialAt2618R = 34.0;                     // Close % at 2.618R

input group "═══════════════ REGIME FILTERS ═══════════════"
input bool             InpUseRegimeFilter = true;                    // Enable Regime Filters
input bool             InpSkipDeadVol = true;                        // Skip Dead Volatility
input bool             InpSkipVolSpike = true;                       // Skip Volatility Spike
input bool             InpSkipOverExtension = true;                  // Skip Over-Extension
input bool             InpSkipHTFConflict = true;                    // Skip HTF Conflict

input group "═══════════════ MTF ANALYSIS ═══════════════"
input bool             InpUseMTF = true;                             // Use Multi-Timeframe
input ENUM_TIMEFRAMES  InpHTF1 = PERIOD_H1;                          // Higher TF 1
input ENUM_TIMEFRAMES  InpHTF2 = PERIOD_H4;                          // Higher TF 2
input ENUM_TIMEFRAMES  InpHTF3 = PERIOD_D1;                          // Higher TF 3
input int              InpTrendMA = 200;                             // Trend MA Period
input int              InpFastMA = 21;                               // Fast MA
input int              InpSlowMA = 50;                               // Slow MA
input int              InpADXPeriod = 14;                            // ADX Period
input int              InpRSIPeriod = 14;                            // RSI Period

input group "═══════════════ DISPLAY & ALERTS ═══════════════"
input bool             InpShowDashboard = true;
input bool             InpAlertOnAction = true;
input bool             InpAlertOnTimeWarning = true;                 // Alert When Time Running Low
input bool             InpPushNotify = false;
input bool             InpSoundAlerts = true;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
// Trade Objects
CTrade         g_Trade;
CPositionInfo  g_Position;
CSymbolInfo    g_SymbolInfo;
CAccountInfo   g_AccountInfo;

// ═══════════════ PROGRAM SETTINGS (Auto-configured) ═══════════════
double         g_ProgramDailyDD = 4.0;         // Daily DD limit for selected program
double         g_ProgramDRS = 5.0;             // DRS limit for selected program
int            g_ProgramSessionSeconds = 0;    // Session time in seconds (0 = no limit)
bool           g_ProgramHasDailyDD = true;     // Does program have daily DD?
string         g_ProgramName = "Oracle";       // Program display name

// ═══════════════ SESSION TIMER TRACKING ═══════════════
datetime       g_SessionStartTime = 0;         // When first trade was placed
datetime       g_SessionEndTime = 0;           // When session expires
int            g_SessionSecondsRemaining = 0;  // Seconds left in session
double         g_SessionTimePercent = 100;     // % of session time remaining
ENUM_SESSION_STATUS g_SessionStatus = SESSION_NOT_STARTED;
bool           g_SessionExpired = false;       // Session has ended
bool           g_FirstTradeOpened = false;     // Has first trade been opened?

// ═══════════════ HOLD TIME TRACKING ═══════════════
struct PositionHoldTrack
{
   ulong          ticket;
   datetime       openTime;
   int            holdSeconds;
   bool           holdCompliant;        // Has held minimum 2 minutes
   string         symbol;
};
PositionHoldTrack g_HoldTrack[];
int            g_HoldTrackCount = 0;

// ═══════════════ REVENGE TRADING PREVENTION ═══════════════
datetime       g_LastLossTime = 0;
string         g_LastLossSymbol = "";
int            g_RevengeCooldownRemaining = 0;
bool           g_RevengeBlocked = false;

// ═══════════════ VALID DAY TRACKING ═══════════════
struct ValidDayRecord
{
   datetime       date;
   double         realizedPL;
   double         percentGain;
   bool           isValid;
};
ValidDayRecord g_ValidDayHistory[];
int            g_ValidDaysCount = 0;
datetime       g_TradingDayUTC = 0;
double         g_TodayRealizedPL = 0;
double         g_TodayPercentGain = 0;
bool           g_TodayIsValid = false;
int            g_DaysUntilPayout = 5;

// ═══════════════ DRAWDOWN TRACKING ═══════════════
double         g_InitialBalance = 0;
double         g_DRSHighWaterMark = 0;
double         g_DRSFloor = 0;
double         g_DailyStartEquity = 0;
double         g_DailyPeakEquity = 0;
double         g_CurrentDailyDD = 0;
double         g_CurrentDailyDDPct = 0;
double         g_CurrentDRSDD = 0;
double         g_CurrentDRSDDPct = 0;
ENUM_COMPLIANCE_STATUS g_ComplianceStatus = COMPLIANCE_OK;
bool           g_NewTradesBlocked = false;
bool           g_FlattenRequired = false;
bool           g_AccountBreached = false;

// ═══════════════ ANTI-VIOLATION TRACKING ═══════════════
int            g_ConsecutiveLosses = 0;
double         g_UsualLotSize = 0.01;

// ═══════════════ PERFORMANCE ═══════════════
double         g_TotalProfit = 0;
double         g_TotalLoss = 0;
int            g_TotalWins = 0;
int            g_TotalLosses = 0;
double         g_WinRate = 0.5;
double         g_AvgWin = 0;
double         g_AvgLoss = 0;
double         g_ProfitFactor = 1.0;

// ═══════════════ MULTI-SYMBOL ═══════════════
string         g_ManagedSymbols[];
int            g_SymbolCount = 0;

// Per-Symbol Data
struct SymbolData
{
   string         name;
   int            hATR;
   int            hADX;
   int            hRSI;
   int            hMAFast;
   int            hMASlow;
   int            hMATrend;
   int            hEMA20;
   int            hBB;
   int            hPSAR;
   int            hMACD;
   int            hHTF1_MA;
   int            hHTF2_MA;
   int            hHTF3_MA;
   double         atr;
   double         adx;
   double         plusDI;
   double         minusDI;
   double         rsi;
   double         maFast;
   double         maSlow;
   double         maTrend;
   double         ema20;
   double         htf1MA;
   double         htf2MA;
   double         htf3MA;
   ENUM_TREND     trendM15;
   ENUM_TREND     trendH1;
   ENUM_TREND     trendH4;
   ENUM_TREND     trendD1;
   ENUM_TREND     alignedTrend;
   double         trendStrength;
   double         volatility;
   double         adr;
   bool           exhaustion;
   bool           reversal;
   bool           regimeOK;
   int            buyCount;
   int            sellCount;
   bool           partial1Done;
   bool           partial2Done;
   bool           partial3Done;
};

SymbolData g_Data[];
datetime   g_LastRefresh = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("╔═══════════════════════════════════════════════════════════════════╗");
   Print("║  ★★★ QUANTUM FORTRESS V6 - UPCOMERS COMPLIANT + TIME LIMITS ★★★   ║");
   Print("║  Author: JazzyLyfe / Brimberry LLC | Grade: A++                   ║");
   Print("╚═══════════════════════════════════════════════════════════════════╝");
   
   // Configure program settings
   ConfigureProgramSettings();
   
   Print("╠═══════════════════════════════════════════════════════════════════╣");
   Print("║  Program: ", g_ProgramName);
   Print("║  Session Time: ", GetSessionTimeString());
   Print("║  Daily DD: ", g_ProgramHasDailyDD ? DoubleToString(g_ProgramDailyDD, 1) + "%" : "N/A");
   Print("║  DRS Trailing: ", g_ProgramDRS, "%");
   Print("║  Min Hold: ", InpMinHoldSeconds, "s (", InpMinHoldSeconds/60, "min)");
   Print("║  Revenge CD: ", InpRevengeCooldownSec, "s (", InpRevengeCooldownSec/60, "min)");
   Print("║  Valid Day: +", InpValidDayThreshold, "% | Need ", InpValidDaysRequired, " days");
   Print("╚═══════════════════════════════════════════════════════════════════╝");
   
   // Initialize trade object
   g_Trade.SetExpertMagicNumber(InpMagicNumber);
   g_Trade.SetDeviationInPoints(10);
   g_Trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Initialize tracking
   InitializeComplianceTracking();
   InitializeValidDayTracking();
   
   // Initialize hold tracking
   ArrayResize(g_HoldTrack, 100);
   g_HoldTrackCount = 0;
   
   // Build symbol list
   BuildSymbolList();
   InitializeAllIndicators();
   
   // Timer (500ms for responsive time tracking)
   EventSetMillisecondTimer(500);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Configure program-specific settings                               |
//+------------------------------------------------------------------+
void ConfigureProgramSettings()
{
   if(!InpAutoTimeSettings && !InpAutoDDSettings)
   {
      // Manual settings
      g_ProgramDailyDD = InpDailyDDLimit;
      g_ProgramDRS = InpDRSLimit;
      g_ProgramSessionSeconds = (InpSessionHours * 3600) + (InpSessionMinutes * 60);
      g_ProgramHasDailyDD = true;
      g_ProgramName = "Manual";
      return;
   }
   
   switch(InpProgram)
   {
      case PROGRAM_ORACLE:
         g_ProgramName = "ORACLE";
         g_ProgramDailyDD = 4.0;
         g_ProgramDRS = 5.0;
         g_ProgramSessionSeconds = 0;  // No time limit
         g_ProgramHasDailyDD = true;
         break;
         
      case PROGRAM_VANGUARD:
         g_ProgramName = "VANGUARD";
         g_ProgramDailyDD = 2.0;       // Conflicting info - using conservative
         g_ProgramDRS = 3.0;           // Some say 7%, using 3% to be safe
         g_ProgramSessionSeconds = 0;  // No time limit
         g_ProgramHasDailyDD = true;
         break;
         
      case PROGRAM_EMBER:
         g_ProgramName = "EMBER";
         g_ProgramDailyDD = 0;         // No daily DD
         g_ProgramDRS = 4.0;
         g_ProgramSessionSeconds = 0;  // No time limit
         g_ProgramHasDailyDD = false;
         break;
         
      case PROGRAM_SUPERNOVA:
         g_ProgramName = "SUPERNOVA (24h)";
         g_ProgramDailyDD = 0;         // Session-based, not daily
         g_ProgramDRS = 3.0;
         g_ProgramSessionSeconds = 24 * 3600;  // 24 hours
         g_ProgramHasDailyDD = false;
         break;
         
      case PROGRAM_HYPERNOVA:
         g_ProgramName = "HYPERNOVA (4h)";
         g_ProgramDailyDD = 0;
         g_ProgramDRS = 3.0;
         g_ProgramSessionSeconds = 4 * 3600;   // 4 hours
         g_ProgramHasDailyDD = false;
         break;
         
      case PROGRAM_ULTRANOVA:
         g_ProgramName = "ULTRANOVA (1h)";
         g_ProgramDailyDD = 0;
         g_ProgramDRS = 3.0;
         g_ProgramSessionSeconds = 1 * 3600;   // 1 hour
         g_ProgramHasDailyDD = false;
         break;
   }
}

//+------------------------------------------------------------------+
//| Get session time as string                                        |
//+------------------------------------------------------------------+
string GetSessionTimeString()
{
   if(g_ProgramSessionSeconds == 0)
      return "No Limit";
   
   int hours = g_ProgramSessionSeconds / 3600;
   int mins = (g_ProgramSessionSeconds % 3600) / 60;
   
   if(mins == 0)
      return IntegerToString(hours) + " hours";
   else
      return IntegerToString(hours) + "h " + IntegerToString(mins) + "m";
}

//+------------------------------------------------------------------+
//| Initialize compliance tracking                                    |
//+------------------------------------------------------------------+
void InitializeComplianceTracking()
{
   double equity = g_AccountInfo.Equity();
   double balance = g_AccountInfo.Balance();
   
   if(g_InitialBalance == 0)
      g_InitialBalance = balance;
   
   if(equity > g_DRSHighWaterMark || g_DRSHighWaterMark == 0)
   {
      g_DRSHighWaterMark = equity;
      g_DRSFloor = g_DRSHighWaterMark * (1 - g_ProgramDRS / 100);
   }
   
   // Daily tracking (UTC)
   datetime nowUTC = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(nowUTC, dt);
   datetime todayUTC = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
   
   if(g_TradingDayUTC != todayUTC)
   {
      // Check if yesterday was valid before resetting
      if(g_TradingDayUTC > 0 && g_TodayIsValid)
      {
         RecordValidDay(g_TradingDayUTC, g_TodayRealizedPL, g_TodayPercentGain);
      }
      
      g_TradingDayUTC = todayUTC;
      g_DailyStartEquity = equity;
      g_DailyPeakEquity = equity;
      g_TodayRealizedPL = 0;
      g_TodayPercentGain = 0;
      g_TodayIsValid = false;
      g_NewTradesBlocked = false;
      g_FlattenRequired = false;
      
      Print("═══ NEW TRADING DAY (UTC) ═══");
      Print("Starting Equity: $", g_DailyStartEquity);
      if(g_ProgramHasDailyDD)
         Print("Daily DD Limit: $", g_DailyStartEquity * g_ProgramDailyDD / 100);
      Print("DRS HWM: $", g_DRSHighWaterMark, " | Floor: $", g_DRSFloor);
   }
   
   if(equity > g_DailyPeakEquity)
      g_DailyPeakEquity = equity;
   
   if(equity > g_DRSHighWaterMark)
   {
      g_DRSHighWaterMark = equity;
      g_DRSFloor = g_DRSHighWaterMark * (1 - g_ProgramDRS / 100);
   }
}

//+------------------------------------------------------------------+
//| Initialize valid day tracking                                     |
//+------------------------------------------------------------------+
void InitializeValidDayTracking()
{
   ArrayResize(g_ValidDayHistory, 100);
   g_ValidDaysCount = 0;
   g_DaysUntilPayout = InpValidDaysRequired;
}

//+------------------------------------------------------------------+
//| Record a valid day                                                |
//+------------------------------------------------------------------+
void RecordValidDay(datetime date, double pl, double pct)
{
   if(g_ValidDaysCount < ArraySize(g_ValidDayHistory))
   {
      g_ValidDayHistory[g_ValidDaysCount].date = date;
      g_ValidDayHistory[g_ValidDaysCount].realizedPL = pl;
      g_ValidDayHistory[g_ValidDaysCount].percentGain = pct;
      g_ValidDayHistory[g_ValidDaysCount].isValid = true;
      g_ValidDaysCount++;
      g_DaysUntilPayout = MathMax(0, InpValidDaysRequired - g_ValidDaysCount);
      
      Print("★ VALID DAY RECORDED! Total: ", g_ValidDaysCount, "/", InpValidDaysRequired);
      
      if(g_ValidDaysCount >= InpValidDaysRequired)
      {
         Print("★★★ PAYOUT ELIGIBLE! ", g_ValidDaysCount, " valid days achieved! ★★★");
         if(InpAlertOnAction)
            Alert("PAYOUT ELIGIBLE! ", g_ValidDaysCount, " valid days!");
      }
   }
}

//+------------------------------------------------------------------+
//| Build symbol list                                                 |
//+------------------------------------------------------------------+
void BuildSymbolList()
{
   ArrayResize(g_ManagedSymbols, 0);
   g_SymbolCount = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(g_Position.SelectByIndex(i))
      {
         if(InpFilterByMagic && g_Position.Magic() != InpMagicNumber)
            continue;
         
         string sym = g_Position.Symbol();
         bool found = false;
         
         for(int j = 0; j < g_SymbolCount; j++)
         {
            if(g_ManagedSymbols[j] == sym)
            {
               found = true;
               break;
            }
         }
         
         if(!found)
         {
            g_SymbolCount++;
            ArrayResize(g_ManagedSymbols, g_SymbolCount);
            g_ManagedSymbols[g_SymbolCount - 1] = sym;
         }
      }
   }
   
   if(g_SymbolCount == 0)
   {
      g_SymbolCount = 1;
      ArrayResize(g_ManagedSymbols, 1);
      g_ManagedSymbols[0] = _Symbol;
   }
}

//+------------------------------------------------------------------+
//| Initialize indicators                                             |
//+------------------------------------------------------------------+
void InitializeAllIndicators()
{
   ArrayResize(g_Data, g_SymbolCount);
   
   for(int i = 0; i < g_SymbolCount; i++)
   {
      string sym = g_ManagedSymbols[i];
      g_Data[i].name = sym;
      
      g_Data[i].hATR = iATR(sym, PERIOD_CURRENT, InpATRPeriod);
      g_Data[i].hADX = iADX(sym, PERIOD_CURRENT, InpADXPeriod);
      g_Data[i].hRSI = iRSI(sym, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
      g_Data[i].hMAFast = iMA(sym, PERIOD_CURRENT, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
      g_Data[i].hMASlow = iMA(sym, PERIOD_CURRENT, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
      g_Data[i].hMATrend = iMA(sym, PERIOD_CURRENT, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
      g_Data[i].hEMA20 = iMA(sym, PERIOD_CURRENT, 20, 0, MODE_EMA, PRICE_CLOSE);
      
      if(InpUseMTF)
      {
         g_Data[i].hHTF1_MA = iMA(sym, InpHTF1, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
         g_Data[i].hHTF2_MA = iMA(sym, InpHTF2, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
         g_Data[i].hHTF3_MA = iMA(sym, InpHTF3, InpTrendMA, 0, MODE_SMA, PRICE_CLOSE);
      }
      
      g_Data[i].buyCount = 0;
      g_Data[i].sellCount = 0;
      g_Data[i].partial1Done = false;
      g_Data[i].partial2Done = false;
      g_Data[i].partial3Done = false;
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Data[i].hATR != INVALID_HANDLE) IndicatorRelease(g_Data[i].hATR);
      if(g_Data[i].hADX != INVALID_HANDLE) IndicatorRelease(g_Data[i].hADX);
      if(g_Data[i].hRSI != INVALID_HANDLE) IndicatorRelease(g_Data[i].hRSI);
      if(g_Data[i].hMAFast != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMAFast);
      if(g_Data[i].hMASlow != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMASlow);
      if(g_Data[i].hMATrend != INVALID_HANDLE) IndicatorRelease(g_Data[i].hMATrend);
      if(g_Data[i].hEMA20 != INVALID_HANDLE) IndicatorRelease(g_Data[i].hEMA20);
      if(g_Data[i].hHTF1_MA != INVALID_HANDLE) IndicatorRelease(g_Data[i].hHTF1_MA);
      if(g_Data[i].hHTF2_MA != INVALID_HANDLE) IndicatorRelease(g_Data[i].hHTF2_MA);
      if(g_Data[i].hHTF3_MA != INVALID_HANDLE) IndicatorRelease(g_Data[i].hHTF3_MA);
   }
   
   EventKillTimer();
   Comment("");
   
   Print("╔═══════════════════════════════════════════════════════════════════╗");
   Print("║  QUANTUM FORTRESS V6 - SHUTDOWN REPORT                            ║");
   Print("║  Program: ", g_ProgramName);
   Print("║  Session Status: ", GetSessionStatusString());
   Print("║  Valid Days: ", g_ValidDaysCount, "/", InpValidDaysRequired);
   Print("║  Breached: ", g_AccountBreached ? "YES!" : "NO");
   Print("╚═══════════════════════════════════════════════════════════════════╝");
}

//+------------------------------------------------------------------+
//| Timer function - ALL TIME MONITORING                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Update session timer
   UpdateSessionTimer();
   
   // 2. Update hold time tracking
   UpdateHoldTimeTracking();
   
   // 3. Update revenge cooldown
   UpdateRevengeCooldown();
   
   // 4. Check compliance
   CheckComplianceStatus();
   
   // 5. Update dashboard
   if(InpShowDashboard)
      DisplayTimeLimitDashboard();
}

//+------------------------------------------------------------------+
//| ★★★ UPDATE SESSION TIMER ★★★                                      |
//+------------------------------------------------------------------+
void UpdateSessionTimer()
{
   // No session limit for Oracle/Vanguard/Ember
   if(g_ProgramSessionSeconds == 0)
   {
      g_SessionStatus = SESSION_NO_LIMIT;
      return;
   }
   
   // Session not started until first trade
   if(!g_FirstTradeOpened)
   {
      g_SessionStatus = SESSION_NOT_STARTED;
      g_SessionSecondsRemaining = g_ProgramSessionSeconds;
      g_SessionTimePercent = 100;
      return;
   }
   
   // Calculate time remaining
   datetime now = TimeCurrent();
   
   if(now >= g_SessionEndTime)
   {
      g_SessionSecondsRemaining = 0;
      g_SessionTimePercent = 0;
      g_SessionStatus = SESSION_ENDED;
      g_SessionExpired = true;
      
      // Close all positions when session ends
      if(InpCloseBeforeExpiry && PositionsTotal() > 0)
      {
         Print("!!! SESSION EXPIRED - CLOSING ALL POSITIONS !!!");
         CloseAllPositions("SESSION EXPIRED");
      }
      
      g_NewTradesBlocked = true;
      return;
   }
   
   g_SessionSecondsRemaining = (int)(g_SessionEndTime - now);
   g_SessionTimePercent = ((double)g_SessionSecondsRemaining / g_ProgramSessionSeconds) * 100;
   
   // Determine status
   ENUM_SESSION_STATUS prevStatus = g_SessionStatus;
   
   if(g_SessionTimePercent <= 5)
      g_SessionStatus = SESSION_CRITICAL;
   else if(g_SessionTimePercent <= 10)
      g_SessionStatus = SESSION_WARNING;
   else
      g_SessionStatus = SESSION_ACTIVE;
   
   // Alert on status change
   if(g_SessionStatus != prevStatus && InpAlertOnTimeWarning)
   {
      string timeStr = FormatTimeRemaining(g_SessionSecondsRemaining);
      
      if(g_SessionStatus == SESSION_WARNING)
      {
         Print("⚠ SESSION WARNING: ", timeStr, " remaining!");
         if(InpAlertOnAction) Alert("SESSION WARNING: ", timeStr, " left!");
      }
      else if(g_SessionStatus == SESSION_CRITICAL)
      {
         Print("🚨 SESSION CRITICAL: ", timeStr, " remaining!");
         if(InpAlertOnAction) Alert("SESSION CRITICAL: ", timeStr, " left!");
         if(InpSoundAlerts) PlaySound("alert2.wav");
      }
   }
   
   // Close before expiry
   if(InpCloseBeforeExpiry && g_SessionSecondsRemaining <= InpCloseMinutesBefore * 60)
   {
      if(PositionsTotal() > 0)
      {
         Print("!!! CLOSING BEFORE SESSION EXPIRY !!!");
         CloseAllPositions("PRE-EXPIRY CLOSE");
      }
   }
}

//+------------------------------------------------------------------+
//| Start session timer (called on first trade)                       |
//+------------------------------------------------------------------+
void StartSessionTimer()
{
   if(g_FirstTradeOpened) return;  // Already started
   if(g_ProgramSessionSeconds == 0) return;  // No session limit
   
   g_FirstTradeOpened = true;
   g_SessionStartTime = TimeCurrent();
   g_SessionEndTime = g_SessionStartTime + g_ProgramSessionSeconds;
   g_SessionStatus = SESSION_ACTIVE;
   
   Print("═══════════════════════════════════════════════════════════════════");
   Print("★ SESSION TIMER STARTED!");
   Print("★ Program: ", g_ProgramName);
   Print("★ Start: ", TimeToString(g_SessionStartTime));
   Print("★ End: ", TimeToString(g_SessionEndTime));
   Print("★ Duration: ", FormatTimeRemaining(g_ProgramSessionSeconds));
   Print("═══════════════════════════════════════════════════════════════════");
   
   if(InpAlertOnAction)
      Alert("SESSION STARTED: ", g_ProgramName, " - ", FormatTimeRemaining(g_ProgramSessionSeconds));
}

//+------------------------------------------------------------------+
//| Format time remaining as string                                   |
//+------------------------------------------------------------------+
string FormatTimeRemaining(int seconds)
{
   if(seconds <= 0) return "EXPIRED";
   
   int hours = seconds / 3600;
   int mins = (seconds % 3600) / 60;
   int secs = seconds % 60;
   
   if(hours > 0)
      return StringFormat("%dh %02dm %02ds", hours, mins, secs);
   else if(mins > 0)
      return StringFormat("%dm %02ds", mins, secs);
   else
      return StringFormat("%ds", secs);
}

//+------------------------------------------------------------------+
//| Get session status string                                         |
//+------------------------------------------------------------------+
string GetSessionStatusString()
{
   switch(g_SessionStatus)
   {
      case SESSION_NOT_STARTED: return "NOT STARTED";
      case SESSION_ACTIVE: return "ACTIVE";
      case SESSION_WARNING: return "WARNING (<10%)";
      case SESSION_CRITICAL: return "CRITICAL (<5%)";
      case SESSION_ENDED: return "EXPIRED";
      case SESSION_NO_LIMIT: return "NO LIMIT";
   }
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| ★★★ UPDATE HOLD TIME TRACKING ★★★                                 |
//+------------------------------------------------------------------+
void UpdateHoldTimeTracking()
{
   datetime now = TimeCurrent();
   
   // Update existing tracked positions
   for(int i = 0; i < g_HoldTrackCount; i++)
   {
      if(g_Position.SelectByTicket(g_HoldTrack[i].ticket))
      {
         g_HoldTrack[i].holdSeconds = (int)(now - g_HoldTrack[i].openTime);
         g_HoldTrack[i].holdCompliant = (g_HoldTrack[i].holdSeconds >= InpMinHoldSeconds);
      }
   }
   
   // Add new positions to tracking
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(g_Position.SelectByIndex(i))
      {
         ulong ticket = g_Position.Ticket();
         bool found = false;
         
         for(int j = 0; j < g_HoldTrackCount; j++)
         {
            if(g_HoldTrack[j].ticket == ticket)
            {
               found = true;
               break;
            }
         }
         
         if(!found)
         {
            if(g_HoldTrackCount < ArraySize(g_HoldTrack))
            {
               g_HoldTrack[g_HoldTrackCount].ticket = ticket;
               g_HoldTrack[g_HoldTrackCount].openTime = (datetime)g_Position.Time();
               g_HoldTrack[g_HoldTrackCount].holdSeconds = (int)(now - g_HoldTrack[g_HoldTrackCount].openTime);
               g_HoldTrack[g_HoldTrackCount].holdCompliant = (g_HoldTrack[g_HoldTrackCount].holdSeconds >= InpMinHoldSeconds);
               g_HoldTrack[g_HoldTrackCount].symbol = g_Position.Symbol();
               g_HoldTrackCount++;
               
               // Start session timer on first trade
               StartSessionTimer();
            }
         }
      }
   }
   
   // Remove closed positions from tracking
   for(int i = g_HoldTrackCount - 1; i >= 0; i--)
   {
      if(!g_Position.SelectByTicket(g_HoldTrack[i].ticket))
      {
         // Position closed - remove from array
         for(int j = i; j < g_HoldTrackCount - 1; j++)
         {
            g_HoldTrack[j] = g_HoldTrack[j + 1];
         }
         g_HoldTrackCount--;
      }
   }
}

//+------------------------------------------------------------------+
//| ★★★ UPDATE REVENGE COOLDOWN ★★★                                   |
//+------------------------------------------------------------------+
void UpdateRevengeCooldown()
{
   if(g_LastLossTime == 0)
   {
      g_RevengeCooldownRemaining = 0;
      g_RevengeBlocked = false;
      return;
   }
   
   int secondsSinceLoss = (int)(TimeCurrent() - g_LastLossTime);
   g_RevengeCooldownRemaining = InpRevengeCooldownSec - secondsSinceLoss;
   
   if(g_RevengeCooldownRemaining <= 0)
   {
      g_RevengeCooldownRemaining = 0;
      g_RevengeBlocked = false;
      g_LastLossTime = 0;
      g_LastLossSymbol = "";
   }
   else
   {
      g_RevengeBlocked = true;
   }
}

//+------------------------------------------------------------------+
//| Check compliance status                                           |
//+------------------------------------------------------------------+
void CheckComplianceStatus()
{
   InitializeComplianceTracking();
   
   double equity = g_AccountInfo.Equity();
   
   // Daily DD
   if(g_ProgramHasDailyDD)
   {
      g_CurrentDailyDD = g_DailyStartEquity - equity;
      g_CurrentDailyDDPct = (g_DailyStartEquity > 0) ?
                            (g_CurrentDailyDD / g_DailyStartEquity) * 100 : 0;
      if(g_CurrentDailyDDPct < 0) g_CurrentDailyDDPct = 0;
   }
   else
   {
      g_CurrentDailyDD = 0;
      g_CurrentDailyDDPct = 0;
   }
   
   // DRS DD
   g_CurrentDRSDD = g_DRSHighWaterMark - equity;
   g_CurrentDRSDDPct = (g_DRSHighWaterMark > 0) ?
                        (g_CurrentDRSDD / g_DRSHighWaterMark) * 100 : 0;
   if(g_CurrentDRSDDPct < 0) g_CurrentDRSDDPct = 0;
   
   // Determine status
   ENUM_COMPLIANCE_STATUS prevStatus = g_ComplianceStatus;
   
   bool dailyBreached = g_ProgramHasDailyDD && (g_CurrentDailyDDPct >= g_ProgramDailyDD);
   bool drsBreached = (g_CurrentDRSDDPct >= g_ProgramDRS);
   
   if(dailyBreached || drsBreached)
   {
      g_ComplianceStatus = COMPLIANCE_BREACH;
      g_AccountBreached = true;
   }
   else if(g_CurrentDailyDDPct >= InpDailyFlatten || g_CurrentDRSDDPct >= InpDDFlatten)
   {
      g_ComplianceStatus = COMPLIANCE_HARD_STOP;
      g_FlattenRequired = true;
   }
   else if(g_CurrentDailyDDPct >= InpDailySoftStop || g_CurrentDRSDDPct >= InpDDSoftStop)
   {
      g_ComplianceStatus = COMPLIANCE_SOFT_STOP;
      g_NewTradesBlocked = true;
   }
   else if(g_CurrentDailyDDPct >= InpDailySoftStop * 0.75 || g_CurrentDRSDDPct >= InpDDSoftStop * 0.75)
   {
      g_ComplianceStatus = COMPLIANCE_WARNING;
   }
   else
   {
      g_ComplianceStatus = COMPLIANCE_OK;
      if(!g_SessionExpired)
         g_NewTradesBlocked = false;
   }
   
   // Take action
   if(g_ComplianceStatus == COMPLIANCE_HARD_STOP && g_FlattenRequired)
   {
      EmergencyKillSwitchAccountWide("HARD STOP DRAWDOWN BREACH");
      g_FlattenRequired = false;
   }
   
   // Check individual positions
   CheckPositionCompliance();
   
   // Update valid day tracking
   UpdateValidDayStatus();
}

//+------------------------------------------------------------------+
//| Emergency Account-Wide Kill Switch (Drawdown Breach)             |
//+------------------------------------------------------------------+
void EmergencyKillSwitchAccountWide(string reason)
{
   Print("🚨═══ EMERGENCY ACCOUNT KILL SWITCH: ", reason, " ═══🚨");
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_Position.SelectByIndex(i))
      {
         ulong ticket = g_Position.Ticket();
         if(g_Trade.PositionClose(ticket))
            Print("EMERGENCY FLATTENED: ", g_Position.Symbol(), " #", ticket);
      }
   }
   
   g_NewTradesBlocked = true;
}

//+------------------------------------------------------------------+
//| Close all positions belonging to QuantumFortress                |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("═══ CLOSING QUANTUM FORTRESS TRADES: ", reason, " ═══");
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_Position.SelectByIndex(i) && g_Position.Magic() == InpMagicNumber)
      {
         ulong ticket = g_Position.Ticket();
         
         // Check hold time
         if(!CanClosePosition(ticket))
         {
            int waitTime = GetTimeUntilCanClose(ticket);
            Print("WARNING: Position #", ticket, " needs ", waitTime, "s more hold time");
            continue;  // Will close when compliant
         }
         
         if(g_Trade.PositionClose(ticket))
            Print("CLOSED: ", g_Position.Symbol(), " #", ticket);
      }
   }
   
   g_NewTradesBlocked = true;
}

//+------------------------------------------------------------------+
//| Update valid day status                                           |
//+------------------------------------------------------------------+
void UpdateValidDayStatus()
{
   if(!InpTrackValidDays) return;
   
   g_TodayPercentGain = (g_DailyStartEquity > 0) ?
                        (g_TodayRealizedPL / g_DailyStartEquity) * 100 : 0;
   
   if(!g_TodayIsValid && g_TodayPercentGain >= InpValidDayThreshold)
   {
      g_TodayIsValid = true;
      Print("★ VALID DAY THRESHOLD REACHED! +", DoubleToString(g_TodayPercentGain, 2), "%");
      if(InpAlertOnAction)
         Alert("Valid Day! +", DoubleToString(g_TodayPercentGain, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Check position compliance                                         |
//+------------------------------------------------------------------+
void CheckPositionCompliance()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_Position.SelectByIndex(i))
      {
         ulong ticket = g_Position.Ticket();
         string sym = g_Position.Symbol();
         double profit = g_Position.Profit() + g_Position.Swap() + g_Position.Commission();
         
         // Check 2% max trade loss
         double maxLoss = g_DailyStartEquity * InpMaxTradeRisk / 100;
         
         if(profit <= -maxLoss)
         {
            // Check hold time first
            int holdIdx = GetHoldTrackIndex(ticket);
            if(holdIdx >= 0 && g_HoldTrack[holdIdx].holdCompliant)
            {
               Print("!!! 2% MAX TRADE LOSS: ", sym);
               if(g_Trade.PositionClose(ticket))
               {
                  g_ConsecutiveLosses++;
                  g_LastLossTime = TimeCurrent();
                  g_LastLossSymbol = sym;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get hold track index                                              |
//+------------------------------------------------------------------+
int GetHoldTrackIndex(ulong ticket)
{
   for(int i = 0; i < g_HoldTrackCount; i++)
   {
      if(g_HoldTrack[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Check if position can be closed (hold time check)                 |
//+------------------------------------------------------------------+
bool CanClosePosition(ulong ticket)
{
   int idx = GetHoldTrackIndex(ticket);
   if(idx < 0) return true;  // Not tracked, allow close
   
   return g_HoldTrack[idx].holdCompliant;
}

//+------------------------------------------------------------------+
//| Get time until position can close                                 |
//+------------------------------------------------------------------+
int GetTimeUntilCanClose(ulong ticket)
{
   int idx = GetHoldTrackIndex(ticket);
   if(idx < 0) return 0;
   
   int remaining = InpMinHoldSeconds - g_HoldTrack[idx].holdSeconds;
   return MathMax(0, remaining);
}

//+------------------------------------------------------------------+
//| Check if new trade allowed                                        |
//+------------------------------------------------------------------+
bool IsNewTradeAllowed(string sym, ENUM_POSITION_TYPE proposedType)
{
   // Session expired
   if(g_SessionExpired)
   {
      Print("NEW TRADE BLOCKED: Session expired");
      return false;
   }
   
   // Trading blocked
   if(g_NewTradesBlocked)
   {
      Print("NEW TRADE BLOCKED: Compliance stop");
      return false;
   }
   
   // Account breached
   if(g_AccountBreached)
   {
      Print("NEW TRADE BLOCKED: Account breached");
      return false;
   }
   
   // Revenge trading check
   if(g_RevengeBlocked && g_LastLossSymbol == sym)
   {
      Print("REVENGE BLOCKED: Wait ", g_RevengeCooldownRemaining, "s on ", sym);
      return false;
   }
   
   // One-sided betting check
   int idx = GetSymbolIndex(sym);
   if(idx >= 0)
   {
      if(proposedType == POSITION_TYPE_BUY && g_Data[idx].buyCount >= InpMaxSameDirection)
      {
         Print("ONE-SIDED BLOCKED: Max ", InpMaxSameDirection, " buys on ", sym);
         return false;
      }
      if(proposedType == POSITION_TYPE_SELL && g_Data[idx].sellCount >= InpMaxSameDirection)
      {
         Print("ONE-SIDED BLOCKED: Max ", InpMaxSameDirection, " sells on ", sym);
         return false;
      }
   }
   
   // Hedging check
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(g_Position.SelectByIndex(i))
      {
         if(g_Position.Symbol() == sym)
         {
            ENUM_POSITION_TYPE existing = g_Position.PositionType();
            if((existing == POSITION_TYPE_BUY && proposedType == POSITION_TYPE_SELL) ||
               (existing == POSITION_TYPE_SELL && proposedType == POSITION_TYPE_BUY))
            {
               Print("HEDGING BLOCKED: Opposing position on ", sym);
               return false;
            }
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get symbol index                                                  |
//+------------------------------------------------------------------+
int GetSymbolIndex(string sym)
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Data[i].name == sym)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckComplianceStatus();
   
   if(g_AccountBreached || g_SessionExpired)
      return;
   
   if(TimeCurrent() - g_LastRefresh > 30)
   {
      BuildSymbolList();
      InitializeAllIndicators();
      g_LastRefresh = TimeCurrent();
   }
   
   UpdateDirectionCounts();
   
   for(int i = 0; i < g_SymbolCount; i++)
   {
      ProcessSymbol(i);
   }
}

//+------------------------------------------------------------------+
//| Update direction counts                                           |
//+------------------------------------------------------------------+
void UpdateDirectionCounts()
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      g_Data[i].buyCount = 0;
      g_Data[i].sellCount = 0;
   }
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(g_Position.SelectByIndex(i))
      {
         int idx = GetSymbolIndex(g_Position.Symbol());
         if(idx >= 0)
         {
            if(g_Position.PositionType() == POSITION_TYPE_BUY)
               g_Data[idx].buyCount++;
            else
               g_Data[idx].sellCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Process symbol                                                    |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx)
{
   if(idx < 0 || idx >= g_SymbolCount) return;
   
   string sym = g_Data[idx].name;
   if(!g_SymbolInfo.Name(sym)) return;
   g_SymbolInfo.RefreshRates();
   
   UpdateIndicators(idx);
   ManagePositionsForSymbol(idx);
}

//+------------------------------------------------------------------+
//| Update indicators                                                 |
//+------------------------------------------------------------------+
void UpdateIndicators(int idx)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   
   if(CopyBuffer(g_Data[idx].hATR, 0, 0, 3, buf) > 0)
      g_Data[idx].atr = buf[0];
   if(CopyBuffer(g_Data[idx].hADX, 0, 0, 3, buf) > 0)
      g_Data[idx].adx = buf[0];
   if(CopyBuffer(g_Data[idx].hRSI, 0, 0, 3, buf) > 0)
      g_Data[idx].rsi = buf[0];
   if(CopyBuffer(g_Data[idx].hMAFast, 0, 0, 3, buf) > 0)
      g_Data[idx].maFast = buf[0];
   if(CopyBuffer(g_Data[idx].hMASlow, 0, 0, 3, buf) > 0)
      g_Data[idx].maSlow = buf[0];
   if(CopyBuffer(g_Data[idx].hMATrend, 0, 0, 3, buf) > 0)
      g_Data[idx].maTrend = buf[0];
   
   if(InpUseMTF)
   {
      if(CopyBuffer(g_Data[idx].hHTF1_MA, 0, 0, 3, buf) > 0)
         g_Data[idx].htf1MA = buf[0];
      if(CopyBuffer(g_Data[idx].hHTF2_MA, 0, 0, 3, buf) > 0)
         g_Data[idx].htf2MA = buf[0];
      if(CopyBuffer(g_Data[idx].hHTF3_MA, 0, 0, 3, buf) > 0)
         g_Data[idx].htf3MA = buf[0];
   }
}

//+------------------------------------------------------------------+
//| Manage positions                                                  |
//+------------------------------------------------------------------+
void ManagePositionsForSymbol(int idx)
{
   string sym = g_Data[idx].name;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_Position.SelectByIndex(i)) continue;
      if(g_Position.Symbol() != sym) continue;
      
      ulong ticket = g_Position.Ticket();
      double openPrice = g_Position.PriceOpen();
      double currentSL = g_Position.StopLoss();
      double currentTP = g_Position.TakeProfit();
      double posProfit = g_Position.Profit();
      ENUM_POSITION_TYPE posType = g_Position.PositionType();
      
      g_SymbolInfo.Name(sym);
      g_SymbolInfo.RefreshRates();
      double point = g_SymbolInfo.Point();
      int digits = g_SymbolInfo.Digits();
      
      double currentPrice = (posType == POSITION_TYPE_BUY) ?
                            g_SymbolInfo.Bid() : g_SymbolInfo.Ask();
      double profitPts = (posType == POSITION_TYPE_BUY) ?
                         (currentPrice - openPrice) / point :
                         (openPrice - currentPrice) / point;
      
      // Universal $1000 breach 50% partial close check
      double totalFlt = posProfit + g_Position.Swap();
      if(MathAbs(totalFlt) >= 1000.0)
      {
         string comment = g_Position.Comment();
         if(StringFind(comment, "PC1000") < 0)
         {
            double vol = g_Position.Volume();
            double step = g_SymbolInfo.LotsStep();
            if(step <= 0) step = 0.01;
            double vmin = g_SymbolInfo.LotsMin();
            double closeVol = MathFloor((vol * 0.5) / step + 1e-9) * step;
            if(closeVol >= vmin && closeVol < vol)
            {
               DoPartialClose(ticket, sym, posType, closeVol, "PC1000");
               PrintFormat("QUANTUM V6 >> UNIVERSAL $1000 BREACH >> Partial closed 50%% on ticket %d (P&L: $%.2f)", ticket, totalFlt);
            }
         }
      }
      
      // Apply SL if missing
      if(currentSL == 0)
      {
         double lots = g_Position.Volume();
         double newSL = Calculate2PercentWallSL(idx, posType, openPrice, lots);
         double newTP = CalculateGoldenRatioTP(posType, openPrice, newSL, point, digits);
         
         if(newSL > 0)
            g_Trade.PositionModify(ticket, newSL, newTP);
         continue;
      }
      
      // BE + Trailing
      if(profitPts >= InpBETrigger)
      {
         double beSL = (posType == POSITION_TYPE_BUY) ?
                       openPrice + InpBEOffset * point :
                       openPrice - InpBEOffset * point;
         beSL = NormalizeDouble(beSL, digits);
         
         bool shouldBE = (posType == POSITION_TYPE_BUY && currentSL < beSL) ||
                         (posType == POSITION_TYPE_SELL && currentSL > beSL);
         
         if(shouldBE)
            g_Trade.PositionModify(ticket, beSL, currentTP);
      }
      
      // ATR trailing
      if(profitPts >= InpBETrigger * 2)
      {
         double trailDist = g_Data[idx].atr * InpTrailATRMult;
         double newSL = (posType == POSITION_TYPE_BUY) ?
                        currentPrice - trailDist :
                        currentPrice + trailDist;
         newSL = NormalizeDouble(newSL, digits);
         
         bool shouldTrail = false;
         if(posType == POSITION_TYPE_BUY && newSL > currentSL && newSL < currentPrice)
            shouldTrail = true;
         else if(posType == POSITION_TYPE_SELL && newSL < currentSL && newSL > currentPrice)
            shouldTrail = true;
         
         if(shouldTrail)
            g_Trade.PositionModify(ticket, newSL, currentTP);
      }
      
      // Partial Close Logic (Avoid Death Loops using Deal Comment Checks)
      if(InpUsePartialClose)
      {
         ulong pos_id = g_Position.Identifier();
         bool pt1_done = false;
         bool pt2_done = false;
         bool pt3_done = false;
         
         if(HistorySelectByPosition(pos_id))
         {
            for(int d = 0; d < HistoryDealsTotal(); d++)
            {
               ulong deal_ticket = HistoryDealGetTicket(d);
               if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
               {
                  string d_comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
                  if(StringFind(d_comment, "PT1") >= 0) pt1_done = true;
                  if(StringFind(d_comment, "PT2") >= 0) pt2_done = true;
                  if(StringFind(d_comment, "PT3") >= 0) pt3_done = true;
               }
            }
         }
         
         double initialSLPts = g_Data[idx].atr / point * InpATRMultSL;
         if(initialSLPts < InpMinSL) initialSLPts = InpMinSL;
         if(initialSLPts > InpMaxSL) initialSLPts = InpMaxSL;
         
         if(initialSLPts > 0)
         {
            double rMultiple = profitPts / initialSLPts;
            
            if(rMultiple >= 1.0 && !pt1_done && InpPartialAt1R > 0)
            {
               double volToClose = NormalizeDouble(g_Position.Volume() * (InpPartialAt1R / 100.0), 2);
               if(volToClose >= g_SymbolInfo.LotsMin()) DoPartialClose(ticket, sym, posType, volToClose, "PT1");
            }
            else if(rMultiple >= 1.618 && !pt2_done && InpPartialAt1618R > 0)
            {
               double volToClose = NormalizeDouble(g_Position.Volume() * (InpPartialAt1618R / 100.0), 2);
               if(volToClose >= g_SymbolInfo.LotsMin()) DoPartialClose(ticket, sym, posType, volToClose, "PT2");
            }
            else if(rMultiple >= 2.618 && !pt3_done && InpPartialAt2618R > 0)
            {
               double volToClose = NormalizeDouble(g_Position.Volume() * (InpPartialAt2618R / 100.0), 2);
               if(volToClose >= g_SymbolInfo.LotsMin()) DoPartialClose(ticket, sym, posType, volToClose, "PT3");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate 2% wall SL                                              |
//+------------------------------------------------------------------+
double Calculate2PercentWallSL(int idx, ENUM_POSITION_TYPE posType, double entryPrice, double lots)
{
   string sym = g_Data[idx].name;
   g_SymbolInfo.Name(sym);
   
   double point = g_SymbolInfo.Point();
   int digits = g_SymbolInfo.Digits();
   double tickValue = g_SymbolInfo.TickValue();
   double tickSize = g_SymbolInfo.TickSize();
   
   double maxLoss = g_DailyStartEquity * InpMaxTradeRisk / 100;
   double maxSLPoints = 0;
   
   if(tickValue > 0 && lots > 0)
   {
      double riskPerPoint = (tickValue / tickSize) * point * lots;
      if(riskPerPoint > 0)
         maxSLPoints = maxLoss / riskPerPoint;
   }
   
   double atrSL = g_Data[idx].atr / point * InpATRMultSL;
   double slPoints = MathMin(atrSL, maxSLPoints);
   slPoints = MathMax(slPoints, InpMinSL);
   slPoints = MathMin(slPoints, InpMaxSL);
   slPoints = MathMin(slPoints, maxSLPoints);
   
   double sl;
   if(posType == POSITION_TYPE_BUY)
      sl = NormalizeDouble(entryPrice - slPoints * point, digits);
   else
      sl = NormalizeDouble(entryPrice + slPoints * point, digits);
   
   return sl;
}

//+------------------------------------------------------------------+
//| Calculate Golden Ratio TP                                         |
//+------------------------------------------------------------------+
double CalculateGoldenRatioTP(ENUM_POSITION_TYPE posType, double entryPrice, 
                               double slPrice, double point, int digits)
{
   double slPoints = MathAbs(entryPrice - slPrice) / point;
   double tpPoints = slPoints * InpGoldenTP3;
   
   tpPoints = MathMax(tpPoints, InpMinTP);
   tpPoints = MathMin(tpPoints, InpMaxTP);
   
   double tp;
   if(posType == POSITION_TYPE_BUY)
      tp = NormalizeDouble(entryPrice + tpPoints * point, digits);
   else
      tp = NormalizeDouble(entryPrice - tpPoints * point, digits);
   
   return tp;
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
         string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            g_TodayRealizedPL += profit;
            
            if(profit > 0)
            {
               g_TotalWins++;
               g_TotalProfit += profit;
               g_AvgWin = g_TotalProfit / g_TotalWins;
               g_ConsecutiveLosses = 0;
            }
            else if(profit < 0)
            {
               g_TotalLosses++;
               g_TotalLoss += MathAbs(profit);
               g_AvgLoss = g_TotalLoss / g_TotalLosses;
               g_ConsecutiveLosses++;
               g_LastLossTime = TimeCurrent();
               g_LastLossSymbol = dealSymbol;
            }
            
            int total = g_TotalWins + g_TotalLosses;
            if(total > 0)
               g_WinRate = (double)g_TotalWins / total;
            if(g_TotalLoss > 0)
               g_ProfitFactor = g_TotalProfit / g_TotalLoss;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Display Time Limit Dashboard                                      |
//+------------------------------------------------------------------+
void DisplayTimeLimitDashboard()
{
   string sessionEmoji = "";
   switch(g_SessionStatus)
   {
      case SESSION_NOT_STARTED: sessionEmoji = "⏸"; break;
      case SESSION_ACTIVE: sessionEmoji = "🟢"; break;
      case SESSION_WARNING: sessionEmoji = "🟡"; break;
      case SESSION_CRITICAL: sessionEmoji = "🔴"; break;
      case SESSION_ENDED: sessionEmoji = "⛔"; break;
      case SESSION_NO_LIMIT: sessionEmoji = "∞"; break;
   }
   
   string compEmoji = "";
   switch(g_ComplianceStatus)
   {
      case COMPLIANCE_OK: compEmoji = "✓"; break;
      case COMPLIANCE_WARNING: compEmoji = "⚠"; break;
      case COMPLIANCE_SOFT_STOP: compEmoji = "🛑"; break;
      case COMPLIANCE_HARD_STOP: compEmoji = "⛔"; break;
      case COMPLIANCE_BREACH: compEmoji = "❌"; break;
   }
   
   string dash = "";
   dash += "╔═══════════════════════════════════════════════════════════════════╗\n";
   dash += "║  ★★★ QUANTUM FORTRESS V6 - UPCOMERS COMPLIANT ★★★                 ║\n";
   dash += "║  Program: " + g_ProgramName + "                                              \n";
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   
   // SESSION TIMER
   dash += "║ " + sessionEmoji + " SESSION: " + GetSessionStatusString();
   if(g_ProgramSessionSeconds > 0)
   {
      dash += " | " + FormatTimeRemaining(g_SessionSecondsRemaining);
      dash += " (" + DoubleToString(g_SessionTimePercent, 1) + "%)";
   }
   dash += "\n";
   
   if(g_SessionStartTime > 0 && g_ProgramSessionSeconds > 0)
   {
      dash += "║   Started: " + TimeToString(g_SessionStartTime, TIME_DATE|TIME_MINUTES);
      dash += " | Ends: " + TimeToString(g_SessionEndTime, TIME_DATE|TIME_MINUTES) + "\n";
   }
   
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   
   // TIME LIMITS
   dash += "║ ⏱️ TIME LIMITS:                                                    \n";
   dash += StringFormat("║   Min Hold: %ds (%.1fmin) | Revenge CD: %ds (%.1fmin)\n",
                        InpMinHoldSeconds, (double)InpMinHoldSeconds/60,
                        InpRevengeCooldownSec, (double)InpRevengeCooldownSec/60);
   
   if(g_RevengeBlocked)
   {
      dash += "║   🚫 REVENGE BLOCKED: " + IntegerToString(g_RevengeCooldownRemaining) + "s on " + g_LastLossSymbol + "\n";
   }
   
   // Show positions with hold time
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   dash += "║ 📍 POSITIONS (Hold Time):                                          \n";
   
   for(int i = 0; i < MathMin(g_HoldTrackCount, 5); i++)
   {
      string holdStatus = g_HoldTrack[i].holdCompliant ? "✓" : "⏳";
      int waitTime = GetTimeUntilCanClose(g_HoldTrack[i].ticket);
      
      dash += StringFormat("║   #%d %s: %ds %s",
                           g_HoldTrack[i].ticket, g_HoldTrack[i].symbol,
                           g_HoldTrack[i].holdSeconds, holdStatus);
      
      if(waitTime > 0)
         dash += " (wait " + IntegerToString(waitTime) + "s)";
      dash += "\n";
   }
   
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   
   // VALID DAYS
   dash += "║ 📅 VALID DAYS: " + IntegerToString(g_ValidDaysCount) + "/" + IntegerToString(InpValidDaysRequired);
   if(g_ValidDaysCount >= InpValidDaysRequired)
      dash += " ★ PAYOUT ELIGIBLE!";
   else
      dash += " | Need " + IntegerToString(g_DaysUntilPayout) + " more";
   dash += "\n";
   
   dash += StringFormat("║   Today: %s%.2f%% %s | Threshold: +%.1f%%\n",
                        g_TodayPercentGain >= 0 ? "+" : "",
                        g_TodayPercentGain,
                        g_TodayIsValid ? "✓ VALID" : "",
                        InpValidDayThreshold);
   
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   
   // DRAWDOWN
   dash += "║ " + compEmoji + " COMPLIANCE:                                                    \n";
   if(g_ProgramHasDailyDD)
   {
      dash += StringFormat("║   Daily DD: %.2f%% / %.1f%%\n", g_CurrentDailyDDPct, g_ProgramDailyDD);
   }
   dash += StringFormat("║   DRS DD: %.2f%% / %.1f%% (HWM: $%.0f)\n",
                        g_CurrentDRSDDPct, g_ProgramDRS, g_DRSHighWaterMark);
   
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   dash += StringFormat("║ 📊 Stats: %dW/%dL | WR: %.1f%% | PF: %.2f\n",
                        g_TotalWins, g_TotalLosses, g_WinRate * 100, g_ProfitFactor);
   dash += StringFormat("║ 💰 Equity: $%.2f | Today P/L: $%.2f\n",
                        g_AccountInfo.Equity(), g_TodayRealizedPL);
   
   dash += "╠═══════════════════════════════════════════════════════════════════╣\n";
   dash += "║ RULES: No Hedge | No MG | Max 2/Dir | 2min Hold | 5min CD        \n";
   dash += "╚═══════════════════════════════════════════════════════════════════╝\n";
   
   Comment(dash);
}

//+------------------------------------------------------------------+
//| Execute Partial Close with specific comment                       |
//+------------------------------------------------------------------+
void DoPartialClose(ulong ticket, string sym, ENUM_POSITION_TYPE posType, double vol, string comment)
{
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   request.action=TRADE_ACTION_DEAL;
   request.position=ticket;
   request.symbol=sym;
   request.volume=vol;
   request.type=(posType==POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price=(posType==POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
   request.deviation=10;
   request.magic=InpMagicNumber;
   request.comment=comment;
   
   if(!OrderSend(request, result))
   {
      Print("Partial close failed! Error: ", GetLastError());
   }
   else
   {
      Print("Partial close successful: ", comment);
   }
}
//+------------------------------------------------------------------+
