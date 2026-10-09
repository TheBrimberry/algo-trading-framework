//+------------------------------------------------------------------+
//|                                   JAZZYLYFE_AutoTrader_AI.mq5    |
//|                     Copyright 2026, JAZZYLYFE / Brimberry LLC    |
//|                          https://github.com/TheBrimberry         |
//+------------------------------------------------------------------+
//|  Author   : JAZZYLYFE (Jason Brimberry) / Brimberry LLC          |
//|  Version  : 2.00  — research-driven rebuild                      |
//|  Build    : MetaEditor 0 errors / 0 warnings                     |
//|                                                                  |
//|  WHAT IT IS                                                      |
//|  A self-learning, prop-firm-safe auto trader for trending        |
//|  markets (gold, silver, US500, US100 by default).                |
//|                                                                  |
//|  CASCADE  D1 -> H4 -> H1 -> M15                                  |
//|   D1  : 55-day Donchian breakout + trend/TSMOM bias (exit on flip)|
//|   H4  : EMA20/EMA50 alignment required                           |
//|   H1  : volatility yardstick for execution + chandelier updates  |
//|   M15 : clean execution — no rollover spread, breakout must hold |
//|                                                                  |
//|  AI   : online meta-labeling model (logistic SGD, triple-barrier |
//|         labels, zero look-ahead) that SELF-VALIDATES: it only    |
//|         gates or sizes trades after its own out-of-sample AUC    |
//|         proves it can discriminate. Until then it observes.      |
//|  EXITS: golden ladder 1.000R / 1.618R partials, runner trailed   |
//|         by a 2.5 x ATR(D1) chandelier (the 2.618R leg runs free) |
//|  SHIELD: FTMO 2-Step / 1-Step (Standard or Swing), Upcomers,     |
//|         custom. Clamp-last sizing, hard-stop flatten loop.       |
//|                                                                  |
//|  HONEST NOTE: see JAZZYLYFE_AutoTrader_AI_Validation report.     |
//|  Backtests on real Dukascopy data are evidence, not guarantees.  |
//|  Forward-test on demo before any paid challenge.                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "2.00"
#property description "JAZZYLYFE AutoTrader AI v2 — MTF trend-breakout engine, self-validating AI, FTMO shield."
#property description "Author: JAZZYLYFE / Brimberry LLC. Golden-ratio exits, clamp-last sizing, zero look-ahead learning."

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_JZ_PROGRAM
  {
   JZ_FTMO_2STEP_CHALLENGE    = 0, // FTMO 2-Step: Challenge (10% / 5% daily / 10% static)
   JZ_FTMO_2STEP_VERIFICATION = 1, // FTMO 2-Step: Verification (5% / 5% / 10%)
   JZ_FTMO_2STEP_FUNDED       = 2, // FTMO 2-Step: FTMO Account (5% / 10%)
   JZ_FTMO_1STEP_CHALLENGE    = 3, // FTMO 1-Step: Challenge (10% / 3% daily / 10% trailing)
   JZ_FTMO_1STEP_FUNDED       = 4, // FTMO 1-Step: FTMO Account (3% / 10% trailing)
   JZ_UPCOMERS_ORACLE         = 5, // Upcomers Oracle (4% intraday-peak / 5% trailing / 2% cap)
   JZ_CUSTOM                  = 6  // Custom (use the Custom inputs)
  };

enum ENUM_JZ_FTMO_TYPE
  {
   JZ_FTMO_SWING    = 0, // Swing (weekend + news holding allowed)
   JZ_FTMO_STANDARD = 1  // Standard (funded: flatten before weekend, 2-min news rule)
  };

enum ENUM_JZ_DAILY_BASIS
  {
   JZ_DAILY_DAYSTART_BALANCE = 0, // Day-start balance minus % of initial capital (FTMO)
   JZ_DAILY_INTRADAY_PEAK    = 1  // % below intraday equity peak (Upcomers)
  };

enum ENUM_JZ_TOTAL_BASIS
  {
   JZ_TOTAL_STATIC         = 0, // Static floor below initial capital (FTMO 2-Step)
   JZ_TOTAL_TRAIL_BALANCE  = 1, // Trails highest balance (FTMO 1-Step)
   JZ_TOTAL_TRAIL_EQUITY   = 2  // Trails equity high-water mark (Upcomers)
  };

enum ENUM_JZ_DAY_CLOCK
  {
   JZ_CLOCK_CEST = 0, // Midnight CE(S)T (FTMO)
   JZ_CLOCK_UTC  = 1  // Midnight UTC (Upcomers)
  };

enum ENUM_JZ_DIRECTION
  {
   JZ_DIR_BOTH      = 0, // Both
   JZ_DIR_BUY_ONLY  = 1, // Buy only
   JZ_DIR_SELL_ONLY = 2  // Sell only
  };

enum ENUM_JZ_SIZING
  {
   JZ_SIZE_FIXED_RISK = 0, // Fixed % risk (AI half-Kelly only once AI is validated)
   JZ_SIZE_FIXED_LOTS = 1  // Fixed lots (panel editable)
  };

enum ENUM_JZ_AI_MODE
  {
   JZ_AI_OFF             = 0, // Off
   JZ_AI_OBSERVE         = 1, // Observe only (learn + report, never gate)
   JZ_AI_SELF_VALIDATING = 2, // Self-validating (gate/size only when live AUC proves skill)
   JZ_AI_ALWAYS          = 3  // Always gate (not recommended)
  };

enum ENUM_JZ_STATE
  {
   JZ_ST_ACTIVE = 0,
   JZ_ST_PAUSED,
   JZ_ST_SOFT_HALT,
   JZ_ST_HARD_HALT_DAY,
   JZ_ST_HARD_HALT_TOTAL,
   JZ_ST_TARGET_LOCK,
   JZ_ST_DAY_LOCK,
   JZ_ST_EXPOSURE
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== JAZZYLYFE AutoTrader AI — Identity ==="
input long              InpMagic              = 26091020;          // Magic number (unique across fleet)
input string            InpComment            = "JZ-AI";           // Order comment prefix
input string            InpBannedSymbols      = "BCHUSD";          // Banned symbols (comma separated)

input group "=== Prop-Firm Shield ==="
input ENUM_JZ_PROGRAM   InpProgram            = JZ_FTMO_2STEP_CHALLENGE; // Program ruleset
input ENUM_JZ_FTMO_TYPE InpFTMOType           = JZ_FTMO_SWING;     // FTMO account type
input double            InpInitialCapital     = 0.0;               // Initial capital (0 = first deposit / first balance)
input double            InpSoftFrac           = 0.60;              // Soft stop: block entries at this fraction of a limit
input double            InpHardFrac           = 0.80;              // Hard stop: flatten at this fraction of a limit
input bool              InpFlattenWholeAccount= true;              // Hard stop flattens ALL account positions
input bool              InpStopAtTarget       = true;              // Lock new entries once profit target is banked
input bool              InpDayKeeper          = true;              // After target: min-lot trade per day until min days met
input double            InpDailyProfitLockPct = 0.0;               // Block entries after day P/L >= % (0 = off)
input bool              InpBlockIfNakedPos    = true;              // Block entries while any account position has no SL
input bool              InpResetTotalHalt     = false;             // Clear a persisted total-drawdown halt on init
input int               InpTesterGMTOffset    = 2;                 // Tester only: server GMT offset (hours, winter)
input bool              InpServerUSDST        = true;              // Server clock follows US DST (GMT+2/+3 brokers)

input group "=== Custom Program (when Program = Custom) ==="
input double            InpCustomDailyPct     = 5.0;               // Daily loss limit %
input double            InpCustomTotalPct     = 10.0;              // Max loss limit %
input double            InpCustomTargetPct    = 10.0;              // Profit target % (0 = none)
input ENUM_JZ_DAILY_BASIS InpCustomDailyBasis = JZ_DAILY_DAYSTART_BALANCE; // Daily basis
input ENUM_JZ_TOTAL_BASIS InpCustomTotalBasis = JZ_TOTAL_STATIC;   // Max loss basis
input ENUM_JZ_DAY_CLOCK InpCustomClock        = JZ_CLOCK_CEST;     // Day reset clock
input double            InpCustomTradeCapPct  = 0.0;               // Per-trade risk cap % (0 = none)
input int               InpCustomMinDays      = 4;                 // Minimum trading days

input group "=== Risk & Sizing ==="
input ENUM_JZ_SIZING    InpSizing             = JZ_SIZE_FIXED_RISK; // Sizing mode
input double            InpBaseRiskPct        = 0.50;              // Risk % per trade
input double            InpMaxRiskPct         = 1.00;              // Hard ceiling risk % per trade
input double            InpKellyRef           = 0.05;              // Half-Kelly fraction mapping to base risk (validated AI only)
input double            InpPayoffB            = 1.20;              // Prior payoff ratio b (avg win R / avg loss R)
input double            InpFixedLots          = 0.10;              // Fixed lots (Fixed-lots mode)
input double            InpStreakDamp         = 0.85;              // Anti-martingale damping per losing trade
input double            InpStreakFloor        = 0.40;              // Damping floor
input bool              InpNoSizeUpAfterLoss  = true;              // Never increase lots right after a loss
input double            InpCommissionPerLot   = 6.0;               // Round-turn commission per lot (acct ccy)
input int               InpMaxOpenPositions   = 4;                 // Max open positions (this magic, all symbols)
input int               InpRevengeCooldownSec = 300;               // No entry within N sec of a losing close
input int               InpMinHoldSec         = 120;               // EA-driven closes wait at least N sec
input int               InpSlippagePoints     = 30;                // Max slippage (points)

input group "=== Strategy: D1 -> H4 -> H1 -> M15 Trend Breakout ==="
input int               InpDonchianDays       = 55;                // D1 breakout lookback (days)
input int               InpMomDays            = 63;                // D1 time-series momentum lookback (days)
input int               InpATRDays            = 20;                // D1 ATR period (risk unit)
input bool              InpRequireH4          = true;              // Require H4 EMA20/EMA50 alignment
input int               InpExecWindowHours    = 12;                // Hours to find a clean M15 execution
input double            InpExecSpreadATR      = 0.10;              // Max spread at execution (x H1 ATR14)
input string            InpNoEntryHoursUTC    = "20,21,22,23";     // No-entry hours (UTC; rollover)
input bool              InpInverseMode        = false;             // Inverse mode (flip all signals)
input ENUM_JZ_DIRECTION InpDirection          = JZ_DIR_BOTH;       // Trade direction filter

input group "=== Exits: Golden Ratio Ladder + Chandelier ==="
input double            InpSL_ATR             = 1.0;               // Initial stop (x ATR D1)
input double            InpTrail_ATR          = 2.5;               // Chandelier trail after TP1 (x ATR D1)
input double            InpTP1_R              = 1.000;             // TP1 (R)
input double            InpTP2_R              = 1.618;             // TP2 (R)
input double            InpTP1_Frac           = 0.30;              // TP1 close fraction
input double            InpTP2_Frac           = 0.30;              // TP2 close fraction
input double            InpLock2_R            = 0.618;             // Stop after TP2 (R)
input double            InpBEBufferR          = 0.05;              // Breakeven buffer after TP1 (R)
input int               InpMaxHoldDays        = 40;                // Time stop (trading days)
input bool              InpBiasExit           = true;              // Exit when the D1 trend bias no longer agrees
input bool              InpFridayFlat         = false;             // Flatten before the weekend (forced on FTMO Standard funded)
input int               InpFridayFlatHourUTC  = 20;                // Friday flatten hour (UTC)

input group "=== AI Meta-Model (self-validating) ==="
input ENUM_JZ_AI_MODE   InpAIMode             = JZ_AI_SELF_VALIDATING; // AI mode
input double            InpMinProb            = 0.50;              // Min P(reach 1R before stop) when AI gates
input int               InpAIMinSamples       = 200;               // Resolved samples before AI may gate
input double            InpAIMinAUC           = 0.55;              // Rolling out-of-sample AUC required to gate
input int               InpAIWindow           = 200;               // Rolling AUC window (samples)
input int               InpBootstrapDays      = 2500;              // D1 history to pre-train on (days)
input int               InpLabelDays          = 10;                // Triple-barrier horizon (days)
input double            InpAILearnRate        = 0.10;              // SGD base learning rate
input double            InpAIL2               = 0.001;             // L2 regularisation
input bool              InpPersistModel       = true;              // Save/load model weights

input group "=== News Filter (MQL5 Economic Calendar) ==="
input bool              InpUseNews            = true;              // Block entries around high-impact news
input int               InpNewsMinsBefore     = 5;                 // Minutes before event
input int               InpNewsMinsAfter      = 5;                 // Minutes after event

input group "=== OpenAI Second Opinion (live only, optional) ==="
input bool              InpUseOpenAI          = false;             // Enable OpenAI veto (add api.openai.com to WebRequest list)
input string            InpOpenAIKey          = "";                // OpenAI API key
input string            InpOpenAIModel        = "gpt-5-mini";      // Model name
input int               InpOpenAITimeoutMs    = 8000;              // Timeout (ms)
input bool              InpOpenAIFailOpen     = true;              // Allow trade if the call fails

input group "=== Dashboard ==="
input bool              InpShowPanel          = true;              // Show dashboard
input int               InpPanelX             = 12;                // Panel X
input int               InpPanelY             = 24;                // Panel Y
input int               InpLogLevel           = 1;                 // Log level 0=errors 1=trades 2=debug

//+------------------------------------------------------------------+
//| Constants & structures                                           |
//+------------------------------------------------------------------+
#define JZ_NFEAT        12
#define JZ_MAX_PENDING  4000
#define JZ_AUC_MAX      1000
#define JZ_PANEL_ROWS   22
#define JZ_PFX_OBJ      "JZAI_"
#define JZ_BARS_PER_DAY 96

struct JzRules
  {
   double            dailyPct;
   double            totalPct;
   double            targetPct;
   double            tradeCapPct;
   int               minDays;
   ENUM_JZ_DAILY_BASIS dailyBasis;
   ENUM_JZ_TOTAL_BASIS totalBasis;
   ENUM_JZ_DAY_CLOCK clock;
   string            name;
  };

// higher-timeframe context at one moment (all values from CLOSED bars)
struct JzCtx
  {
   bool              ok;
   datetime          d1Time;                            // open time of the closed D1 bar used
   double            d1Close, d1Ema50, d1Ema200, d1Atr, d1Mom, d1Hh, d1Ll, d1Er, d1Adx, d1AtrPct;
   int               bias;                              // +1 / -1 / 0
   double            h4Ema20, h4Ema50, h4Adx;
   double            h1Rsi, h1Atr;
  };

struct JzSample
  {
   double            x[JZ_NFEAT];
   int               dir;
   double            entry;
   double            slDist;
   datetime          entryBar;      // M15 bar time from which barriers are checked
   int               barsSeen;
   double            pAtCreation;   // causal prediction, used for the rolling AUC
  };

struct JzArmed
  {
   bool              on;
   int               dir;
   double            level;
   datetime          expiry;
   bool              sampled;       // learner sample already created for this arm
  };

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade         g_trade;
JzRules        g_rules;
bool           g_isTester      = false;
bool           g_isVisual      = false;
string         g_acctPfx       = "";
string         g_symPfx        = "";
double         g_point         = 0.0;
int            g_digits        = 0;

int            hD1_EMA50 = INVALID_HANDLE, hD1_EMA200 = INVALID_HANDLE, hD1_ATR = INVALID_HANDLE, hD1_ADX = INVALID_HANDLE;
int            hH4_EMA20 = INVALID_HANDLE, hH4_EMA50 = INVALID_HANDLE, hH4_ADX = INVALID_HANDLE;
int            hH1_RSI = INVALID_HANDLE, hH1_ATR = INVALID_HANDLE;

// shield state (account level, persisted)
double         g_initCap       = 0.0;
int            g_dayKey        = 0;
double         g_dayStartBal   = 0.0;
double         g_dayPeakEq     = 0.0;
double         g_hwmBal        = 0.0;
double         g_hwmEq         = 0.0;
int            g_haltDayKey    = 0;
bool           g_haltTotal     = false;
datetime       g_firstSeen     = 0;
int            g_tradingDays   = 0;
int            g_lastCountedDay= 0;

// shield outputs
ENUM_JZ_STATE  g_state         = JZ_ST_ACTIVE;
double         g_dailyUsed     = 0.0;
double         g_totalUsed     = 0.0;
double         g_budgetMoney   = 0.0;
double         g_openRiskMoney = 0.0;
bool           g_nakedPos      = false;
bool           g_paused        = false;

// symbol / strategy state (persisted per symbol+magic)
int            g_lossStreak    = 0;
double         g_lastLots      = 0.0;
bool           g_lastWasLoss   = false;
datetime       g_lastLossClose = 0;
datetime       g_lastEntryBar  = 0;
int            g_tradesToday   = 0;
int            g_tradesDayKey  = 0;
int            g_closedTrades  = 0;
int            g_wins          = 0;
double         g_sumR          = 0.0;
double         g_sumWinR       = 0.0;
double         g_sumLossR      = 0.0;
double         g_dayKeeperKey  = 0;
JzArmed        g_armed;
datetime       g_armD1Done     = 0;       // D1 bar whose breakout was already armed / consumed (persisted)
bool           g_flipPending   = false;   // bias-flip close still owed
int            g_flipBias      = 0;
datetime       g_flipBefore    = 0;       // only positions opened before this D1 close are flipped
bool           g_execRetry     = false;   // arm evaluation deferred within the current M15 bar
bool           g_modelReady    = false;   // model is loaded or bootstrapped: safe to persist
datetime       g_bootFrom      = 0;       // saved training watermark at init (bootstrap replays after it)
datetime       g_eaStart       = 0;       // samples executing after this belong to the live learner

// AI model
double         g_w[JZ_NFEAT];
long           g_modelN        = 0;
double         g_brier         = 0.25;
bool           g_bootstrapped  = false;
datetime       g_lastTrainedBar= 0;
JzSample       g_pending[];
int            g_pendingCount  = 0;
long           g_updatesSinceSave = 0;
double         g_aucP[JZ_AUC_MAX];
int            g_aucY[JZ_AUC_MAX];
int            g_aucCount      = 0;
int            g_aucHead       = 0;
double         g_lastAUC       = 0.5;
bool           g_aiActive      = false;

// events & telemetry
datetime       g_lastM15Bar    = 0;
datetime       g_lastH1Bar     = 0;
datetime       g_lastD1Bar     = 0;
double         g_lastProb      = -1.0;
int            g_lastBias      = 0;
string         g_lastSignal    = "-";
string         g_lastBlock     = "-";
double         g_manualLots    = 0.0;

// news cache
datetime       g_newsTimes[];
datetime       g_newsLoaded    = 0;
bool           g_newsFailed    = false;
bool           g_newsForced    = false;   // FTMO Standard funded: 2-minute news rule enforced

// hours filter
bool           g_noEntryHour[24];

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
void JzLog(const int level, const string msg)
  {
   if(level <= InpLogLevel)
      PrintFormat("[JZ-AI %s] %s", _Symbol, msg);
  }

//+------------------------------------------------------------------+
//| Time helpers                                                     |
//+------------------------------------------------------------------+
datetime JzNthSunday(const int year, const int month, const int nth)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year = year;
   s.mon  = month;
   s.day  = 1;
   datetime first = StructToTime(s);
   MqlDateTime t;
   TimeToStruct(first, t);
   return (datetime)((long)first + (long)(((7 - t.day_of_week) % 7) + 7 * (nth - 1)) * 86400);
  }

bool JzIsUSDST(const datetime gmt)
  {
   MqlDateTime t;
   TimeToStruct(gmt, t);
   long start = (long)JzNthSunday(t.year, 3, 2) + 7 * 3600;   // 02:00 EST
   long end   = (long)JzNthSunday(t.year, 11, 1) + 6 * 3600;  // 02:00 EDT
   return ((long)gmt >= start && (long)gmt < end);
  }

// server-GMT offset in force at server time srv (history-safe; live offset alone is wrong for half the year)
long JzServerOffsetAt(const datetime srv)
  {
   long base;
   if(g_isTester)
      base = (long)InpTesterGMTOffset * 3600;                 // tester input = WINTER offset
   else
     {
      long off = (long)MathRound(((double)((long)TimeTradeServer() - (long)TimeGMT())) / 1800.0) * 1800;
      base = off - ((InpServerUSDST && JzIsUSDST(TimeGMT())) ? 3600 : 0);
     }
   if(!InpServerUSDST)
      return base;
   return base + (JzIsUSDST((datetime)((long)srv - base)) ? 3600 : 0);
  }

long JzServerOffsetSec()
  {
   return JzServerOffsetAt(g_isTester ? TimeCurrent() : TimeTradeServer());
  }

datetime JzGMT()
  {
   if(g_isTester)
      return (datetime)((long)TimeCurrent() - JzServerOffsetSec());
   return TimeGMT();
  }

datetime JzLastSunday(const int year, const int month)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year = (month == 12) ? year + 1 : year;
   s.mon  = (month == 12) ? 1 : month + 1;
   s.day  = 1;
   datetime firstNext = StructToTime(s);
   datetime lastDay   = (datetime)((long)firstNext - 86400);
   MqlDateTime t;
   TimeToStruct(lastDay, t);
   return (datetime)((long)lastDay - (long)t.day_of_week * 86400);
  }

bool JzIsEUDST(const datetime gmt)
  {
   MqlDateTime t;
   TimeToStruct(gmt, t);
   long start = (long)JzLastSunday(t.year, 3) + 3600;
   long end   = (long)JzLastSunday(t.year, 10) + 3600;
   return ((long)gmt >= start && (long)gmt < end);
  }

int JzDayKey(const datetime gmt)
  {
   long local = (long)gmt;
   if(g_rules.clock == JZ_CLOCK_CEST)
      local += JzIsEUDST(gmt) ? 7200 : 3600;
   MqlDateTime t;
   TimeToStruct((datetime)local, t);
   return t.year * 10000 + t.mon * 100 + t.day;
  }

//+------------------------------------------------------------------+
//| Persistence (GlobalVariables)                                    |
//+------------------------------------------------------------------+
double GVGet(const string name, const double def)
  {
   if(GlobalVariableCheck(name))
      return GlobalVariableGet(name);
   return def;
  }

void GVSet(const string name, const double value)
  {
   GlobalVariableSet(name, value);
  }

void SaveShieldState()
  {
   GVSet(g_acctPfx + "INIT", g_initCap);
   GVSet(g_acctPfx + "DAYKEY", (double)g_dayKey);
   GVSet(g_acctPfx + "DAYBAL", g_dayStartBal);
   GVSet(g_acctPfx + "DAYPEAK", g_dayPeakEq);
   GVSet(g_acctPfx + "HWMBAL", g_hwmBal);
   GVSet(g_acctPfx + "HWMEQ", g_hwmEq);
   GVSet(g_acctPfx + "HALTDAY", (double)g_haltDayKey);
   GVSet(g_acctPfx + "HALTTOT", g_haltTotal ? 1.0 : 0.0);
   GVSet(g_acctPfx + "FIRST", (double)g_firstSeen);
   GVSet(g_acctPfx + "TDAYS", (double)g_tradingDays);
   GVSet(g_acctPfx + "TDLAST", (double)g_lastCountedDay);
   GlobalVariablesFlush();
  }

double JzFirstDeposit()
  {
   if(!HistorySelect(0, (datetime)((long)TimeCurrent() + 86400)))
      return 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d > 0 && HistoryDealGetInteger(d, DEAL_TYPE) == DEAL_TYPE_BALANCE && HistoryDealGetDouble(d, DEAL_PROFIT) > 0.0)
         return HistoryDealGetDouble(d, DEAL_PROFIT);
     }
   return 0.0;
  }

void LoadShieldState()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpInitialCapital > 0.0)
      g_initCap = InpInitialCapital;
   else
     {
      double dep = JzFirstDeposit();
      g_initCap = GVGet(g_acctPfx + "INIT", dep > 0.0 ? dep : bal);
     }
   g_dayKey        = (int)GVGet(g_acctPfx + "DAYKEY", 0.0);
   g_dayStartBal   = GVGet(g_acctPfx + "DAYBAL", MathMax(bal, eq));
   g_dayPeakEq     = GVGet(g_acctPfx + "DAYPEAK", eq);
   g_hwmBal        = MathMax(GVGet(g_acctPfx + "HWMBAL", bal), MathMax(bal, g_initCap));
   g_hwmEq         = MathMax(GVGet(g_acctPfx + "HWMEQ", eq), MathMax(eq, g_initCap));
   g_haltDayKey    = (int)GVGet(g_acctPfx + "HALTDAY", 0.0);
   g_haltTotal     = GVGet(g_acctPfx + "HALTTOT", 0.0) > 0.5;
   g_firstSeen     = (datetime)(long)GVGet(g_acctPfx + "FIRST", (double)(long)TimeCurrent());
   g_tradingDays   = (int)GVGet(g_acctPfx + "TDAYS", 0.0);
   g_lastCountedDay= (int)GVGet(g_acctPfx + "TDLAST", 0.0);
   if(InpResetTotalHalt)
      g_haltTotal = false;
  }

void SaveSymbolState()
  {
   GVSet(g_symPfx + "STREAK", (double)g_lossStreak);
   GVSet(g_symPfx + "LASTLOTS", g_lastLots);
   GVSet(g_symPfx + "LASTLOSS", g_lastWasLoss ? 1.0 : 0.0);
   GVSet(g_symPfx + "LOSSTIME", (double)(long)g_lastLossClose);
   GVSet(g_symPfx + "NTR", (double)g_closedTrades);
   GVSet(g_symPfx + "NWIN", (double)g_wins);
   GVSet(g_symPfx + "SUMR", g_sumR);
   GVSet(g_symPfx + "SUMWR", g_sumWinR);
   GVSet(g_symPfx + "SUMLR", g_sumLossR);
   GVSet(g_symPfx + "TTODAY", (double)g_tradesToday);
   GVSet(g_symPfx + "TTKEY", (double)g_tradesDayKey);
   GVSet(g_symPfx + "DKKEY", g_dayKeeperKey);
   GVSet(g_symPfx + "LASTBAR", (double)(long)g_lastEntryBar);
   GVSet(g_symPfx + "ARMDIR", g_armed.on ? (double)g_armed.dir : 0.0);
   GVSet(g_symPfx + "ARMLVL", g_armed.level);
   GVSet(g_symPfx + "ARMEXP", (double)(long)g_armed.expiry);
   GVSet(g_symPfx + "ARMSMP", g_armed.sampled ? 1.0 : 0.0);
   GVSet(g_symPfx + "ARMD1", (double)(long)g_armD1Done);
   GlobalVariablesFlush();
  }

void LoadSymbolState()
  {
   g_lossStreak    = (int)GVGet(g_symPfx + "STREAK", 0.0);
   g_lastLots      = GVGet(g_symPfx + "LASTLOTS", 0.0);
   g_lastWasLoss   = GVGet(g_symPfx + "LASTLOSS", 0.0) > 0.5;
   g_lastLossClose = (datetime)(long)GVGet(g_symPfx + "LOSSTIME", 0.0);
   g_closedTrades  = (int)GVGet(g_symPfx + "NTR", 0.0);
   g_wins          = (int)GVGet(g_symPfx + "NWIN", 0.0);
   g_sumR          = GVGet(g_symPfx + "SUMR", 0.0);
   g_sumWinR       = GVGet(g_symPfx + "SUMWR", 0.0);
   g_sumLossR      = GVGet(g_symPfx + "SUMLR", 0.0);
   g_tradesToday   = (int)GVGet(g_symPfx + "TTODAY", 0.0);
   g_tradesDayKey  = (int)GVGet(g_symPfx + "TTKEY", 0.0);
   g_dayKeeperKey  = GVGet(g_symPfx + "DKKEY", 0.0);
   g_lastEntryBar  = (datetime)(long)GVGet(g_symPfx + "LASTBAR", 0.0);
   g_armed.dir     = (int)GVGet(g_symPfx + "ARMDIR", 0.0);
   g_armed.level   = GVGet(g_symPfx + "ARMLVL", 0.0);
   g_armed.expiry  = (datetime)(long)GVGet(g_symPfx + "ARMEXP", 0.0);
   g_armed.sampled = GVGet(g_symPfx + "ARMSMP", 0.0) > 0.5;
   g_armD1Done     = (datetime)(long)GVGet(g_symPfx + "ARMD1", 0.0);
   g_armed.on      = (g_armed.dir != 0 && (long)g_armed.expiry > (long)TimeCurrent());
  }

string PosKey(const ulong posId, const string field)
  {
   return "JZP_" + IntegerToString((long)InpMagic) + "_" + IntegerToString((long)posId) + "_" + field;
  }

void PosCleanup(const ulong posId)
  {
   string f[6] = {"R", "V", "L", "RM", "P", "E"};
   for(int i = 0; i < 6; i++)
     {
      string n = PosKey(posId, f[i]);
      if(GlobalVariableCheck(n))
         GlobalVariableDel(n);
     }
  }

//+------------------------------------------------------------------+
//| Rules                                                            |
//+------------------------------------------------------------------+
void ResolveRules()
  {
   g_rules.tradeCapPct = 0.0;
   switch(InpProgram)
     {
      case JZ_FTMO_2STEP_CHALLENGE:
         g_rules.name = "FTMO 2-Step Challenge";
         g_rules.dailyPct = 5.0;
         g_rules.totalPct = 10.0;
         g_rules.targetPct = 10.0;
         g_rules.minDays = 4;
         g_rules.dailyBasis = JZ_DAILY_DAYSTART_BALANCE;
         g_rules.totalBasis = JZ_TOTAL_STATIC;
         g_rules.clock = JZ_CLOCK_CEST;
         break;
      case JZ_FTMO_2STEP_VERIFICATION:
         g_rules.name = "FTMO 2-Step Verification";
         g_rules.dailyPct = 5.0;
         g_rules.totalPct = 10.0;
         g_rules.targetPct = 5.0;
         g_rules.minDays = 4;
         g_rules.dailyBasis = JZ_DAILY_DAYSTART_BALANCE;
         g_rules.totalBasis = JZ_TOTAL_STATIC;
         g_rules.clock = JZ_CLOCK_CEST;
         break;
      case JZ_FTMO_2STEP_FUNDED:
         g_rules.name = "FTMO 2-Step Account";
         g_rules.dailyPct = 5.0;
         g_rules.totalPct = 10.0;
         g_rules.targetPct = 0.0;
         g_rules.minDays = 0;
         g_rules.dailyBasis = JZ_DAILY_DAYSTART_BALANCE;
         g_rules.totalBasis = JZ_TOTAL_STATIC;
         g_rules.clock = JZ_CLOCK_CEST;
         break;
      case JZ_FTMO_1STEP_CHALLENGE:
         g_rules.name = "FTMO 1-Step Challenge";
         g_rules.dailyPct = 3.0;
         g_rules.totalPct = 10.0;
         g_rules.targetPct = 10.0;
         g_rules.minDays = 0;
         g_rules.dailyBasis = JZ_DAILY_DAYSTART_BALANCE;
         g_rules.totalBasis = JZ_TOTAL_TRAIL_BALANCE;
         g_rules.clock = JZ_CLOCK_CEST;
         break;
      case JZ_FTMO_1STEP_FUNDED:
         g_rules.name = "FTMO 1-Step Account";
         g_rules.dailyPct = 3.0;
         g_rules.totalPct = 10.0;
         g_rules.targetPct = 0.0;
         g_rules.minDays = 0;
         g_rules.dailyBasis = JZ_DAILY_DAYSTART_BALANCE;
         g_rules.totalBasis = JZ_TOTAL_TRAIL_BALANCE;
         g_rules.clock = JZ_CLOCK_CEST;
         break;
      case JZ_UPCOMERS_ORACLE:
         g_rules.name = "Upcomers Oracle";
         g_rules.dailyPct = 4.0;
         g_rules.totalPct = 5.0;
         g_rules.targetPct = 0.0;
         g_rules.tradeCapPct = 2.0;
         g_rules.minDays = 5;
         g_rules.dailyBasis = JZ_DAILY_INTRADAY_PEAK;
         g_rules.totalBasis = JZ_TOTAL_TRAIL_EQUITY;
         g_rules.clock = JZ_CLOCK_UTC;
         break;
      default:
         g_rules.name = "Custom";
         g_rules.dailyPct = InpCustomDailyPct;
         g_rules.totalPct = InpCustomTotalPct;
         g_rules.targetPct = InpCustomTargetPct;
         g_rules.tradeCapPct = InpCustomTradeCapPct;
         g_rules.minDays = InpCustomMinDays;
         g_rules.dailyBasis = InpCustomDailyBasis;
         g_rules.totalBasis = InpCustomTotalBasis;
         g_rules.clock = InpCustomClock;
         break;
     }
  }

//+------------------------------------------------------------------+
//| Symbol / volume helpers                                          |
//+------------------------------------------------------------------+
double NormPrice(const double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      return NormalizeDouble(price, g_digits);
   return NormalizeDouble(MathRound(price / tick) * tick, g_digits);
  }

double NormLotsDown(const double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(lots / step + 1e-9) * step;
   v = MathMin(v, vmax);
   int stepDigits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(v, stepDigits);
  }

bool IsBannedSymbol()
  {
   string list = InpBannedSymbols;
   StringToUpper(list);
   string sym = _Symbol;
   StringToUpper(sym);
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) > 0 && StringFind(sym, p) >= 0)
         return true;
     }
   return false;
  }

void ParseNoEntryHours()
  {
   for(int h = 0; h < 24; h++)
      g_noEntryHour[h] = false;
   string parts[];
   int n = StringSplit(InpNoEntryHoursUTC, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(StringLen(p) == 0)
         continue;
      int h = (int)StringToInteger(p);
      if(h >= 0 && h < 24)
         g_noEntryHour[h] = true;
     }
  }

// money lost per 1.0 lot if price travels entry -> sl (positive number)
double LossPerLot(const int dir, const double entry, const double sl)
  {
   double profit = 0.0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcProfit(t, _Symbol, 1.0, entry, sl, profit))
      return MathAbs(profit) + InpCommissionPerLot;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0.0 || ts <= 0.0)
      return 0.0;
   return MathAbs(entry - sl) / ts * tv + InpCommissionPerLot;
  }

//+------------------------------------------------------------------+
//| Prop-firm shield                                                 |
//+------------------------------------------------------------------+
void RecountTradingDays()
  {
   if(!HistorySelect(g_firstSeen, (datetime)((long)TimeCurrent() + 86400)))
      return;
   int total = HistoryDealsTotal();
   int count = 0, lastKey = 0;
   for(int i = 0; i < total; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      datetime srv = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      int k = JzDayKey((datetime)((long)srv - JzServerOffsetAt(srv)));
      if(k != lastKey)
        {
         count++;
         lastKey = k;
        }
     }
   g_tradingDays = MathMax(g_tradingDays, count);
   if(lastKey > 0)
      g_lastCountedDay = MathMax(g_lastCountedDay, lastKey);
  }

void ScanOpenRisk()
  {
   g_openRiskMoney = 0.0;
   g_nakedPos = false;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double sl  = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
      long type  = PositionGetInteger(POSITION_TYPE);
      if(sl <= 0.0)
        {
         g_nakedPos = true;
         continue;
        }
      double profit = 0.0;
      ENUM_ORDER_TYPE ot = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, sym, vol, cur, sl, profit) && profit < 0.0)
         g_openRiskMoney += -profit;
     }
  }

bool FlattenAll(const bool wholeAccount, const string why)
  {
   bool allOk = true;
   for(int pass = 0; pass < 3; pass++)
     {
      allOk = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!wholeAccount)
           {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
           }
         if(!g_trade.PositionClose(ticket, (ulong)InpSlippagePoints))
            allOk = false;
        }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ot = OrderGetTicket(i);
         if(ot == 0)
            continue;
         if(!wholeAccount && (OrderGetInteger(ORDER_MAGIC) != InpMagic || OrderGetString(ORDER_SYMBOL) != _Symbol))
            continue;
         if(!g_trade.OrderDelete(ot))
            allOk = false;
        }
      if(allOk)
         break;
     }
   JzLog(0, StringFormat("FLATTEN (%s) whole=%s ok=%s", why, wholeAccount ? "yes" : "no", allOk ? "yes" : "no"));
   return allOk;
  }

bool ExposureRemains(const bool wholeAccount)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(wholeAccount || (PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol))
         return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(wholeAccount || (OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol))
         return true;
     }
   return false;
  }

// balance at the start of the current shield day, rebuilt from deal history (EA offline at midnight / first attach)
double JzBalanceAtDayStart(const double bal)
  {
   long gmtNow = (long)JzGMT();
   long shift = 0;
   if(g_rules.clock == JZ_CLOCK_CEST)
      shift = JzIsEUDST((datetime)gmtNow) ? 7200 : 3600;
   long localNow = gmtNow + shift;
   long localMid = localNow - localNow % 86400;
   if(g_rules.clock == JZ_CLOCK_CEST)
      shift = JzIsEUDST((datetime)(localMid - 3600)) ? 7200 : 3600;   // regime in force at local midnight
   datetime srvMid = (datetime)(localMid - shift + JzServerOffsetSec());
   if(!HistorySelect(srvMid, (datetime)((long)TimeCurrent() + 86400)))
      return bal;
   double sinceMid = 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      sinceMid += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                  HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
     }
   return bal - sinceMid;
  }

void ShieldUpdate()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime gmt = JzGMT();
   int dk = JzDayKey(gmt);
   bool dirty = false;

   if(dk != g_dayKey)
     {
      // Conservative anchor: max(balance, equity) is never below FTMO's balance reference.
      double midBal = JzBalanceAtDayStart(bal);
      g_dayKey      = dk;
      g_dayStartBal = MathMax(MathMax(bal, eq), midBal);
      g_dayPeakEq   = MathMax(eq, midBal);
      dirty = true;
      JzLog(1, StringFormat("New trading day %d  start=%.2f", dk, g_dayStartBal));
     }
   if(eq > g_dayPeakEq) { g_dayPeakEq = eq; dirty = true; }
   if(bal > g_hwmBal)   { g_hwmBal = bal;   dirty = true; }
   if(eq > g_hwmEq)     { g_hwmEq = eq;     dirty = true; }

   double init = MathMax(g_initCap, 1.0);
   double dailyLimit = 0.0, floorDaily = -DBL_MAX;
   if(g_rules.dailyPct > 0.0)
     {
      if(g_rules.dailyBasis == JZ_DAILY_DAYSTART_BALANCE)
        {
         dailyLimit = g_rules.dailyPct / 100.0 * init;
         floorDaily = g_dayStartBal - dailyLimit;
        }
      else
        {
         dailyLimit = g_rules.dailyPct / 100.0 * g_dayPeakEq;
         floorDaily = g_dayPeakEq - dailyLimit;
        }
     }
   double totalLimit = 0.0, floorTotal = -DBL_MAX;
   if(g_rules.totalPct > 0.0)
     {
      if(g_rules.totalBasis == JZ_TOTAL_STATIC)
        {
         totalLimit = g_rules.totalPct / 100.0 * init;
         floorTotal = init - totalLimit;
        }
      else
         if(g_rules.totalBasis == JZ_TOTAL_TRAIL_BALANCE)
           {
            totalLimit = g_rules.totalPct / 100.0 * init;
            floorTotal = MathMax(init, g_hwmBal) - totalLimit;
           }
         else
           {
            totalLimit = g_rules.totalPct / 100.0 * g_hwmEq;
            floorTotal = g_hwmEq - totalLimit;
           }
     }

   g_dailyUsed = (dailyLimit > 0.0) ? (dailyLimit - (eq - floorDaily)) / dailyLimit : 0.0;
   g_totalUsed = (totalLimit > 0.0) ? (totalLimit - (eq - floorTotal)) / totalLimit : 0.0;
   g_dailyUsed = MathMax(0.0, g_dailyUsed);
   g_totalUsed = MathMax(0.0, g_totalUsed);

   ScanOpenRisk();
   double hardRoomD = (dailyLimit > 0.0) ? (eq - floorDaily) - (1.0 - InpHardFrac) * dailyLimit : DBL_MAX;
   double hardRoomT = (totalLimit > 0.0) ? (eq - floorTotal) - (1.0 - InpHardFrac) * totalLimit : DBL_MAX;
   double room = MathMin(hardRoomD, hardRoomT);
   if(room == DBL_MAX)
      room = eq * InpMaxRiskPct / 100.0 * 2.0;
   g_budgetMoney = MathMax(0.0, room - g_openRiskMoney);

   // ---- hard stops: flatten ----
   if(g_rules.dailyPct > 0.0 && g_dailyUsed >= InpHardFrac && g_haltDayKey != dk)
     {
      g_haltDayKey = dk;
      dirty = true;
      JzLog(0, StringFormat("daily hard stop %.0f%% of limit", g_dailyUsed * 100.0));
     }
   if(g_rules.totalPct > 0.0 && g_totalUsed >= InpHardFrac && !g_haltTotal)
     {
      g_haltTotal = true;
      dirty = true;
      JzLog(0, StringFormat("total hard stop %.0f%% of limit", g_totalUsed * 100.0));
     }
   // keep flattening while halted: a failed close or a position opened later must not survive the halt
   if((g_haltTotal || g_haltDayKey == dk) && ExposureRemains(InpFlattenWholeAccount))
     {
      static datetime lastFlat = 0;
      if(TimeCurrent() != lastFlat)
        {
         lastFlat = TimeCurrent();
         FlattenAll(InpFlattenWholeAccount, g_haltTotal ? "total halt" : "daily halt");
        }
     }

   // ---- state machine ----
   bool targetHit = (g_rules.targetPct > 0.0 && bal >= init * (1.0 + g_rules.targetPct / 100.0));
   if(g_haltTotal)
      g_state = JZ_ST_HARD_HALT_TOTAL;
   else
      if(g_haltDayKey == dk)
         g_state = JZ_ST_HARD_HALT_DAY;
      else
         if(g_paused)
            g_state = JZ_ST_PAUSED;
         else
            if(InpStopAtTarget && targetHit)
               g_state = JZ_ST_TARGET_LOCK;
            else
               if(g_dailyUsed >= InpSoftFrac || g_totalUsed >= InpSoftFrac)
                  g_state = JZ_ST_SOFT_HALT;
               else
                  if(InpDailyProfitLockPct > 0.0 && (eq - g_dayStartBal) / init * 100.0 >= InpDailyProfitLockPct)
                     g_state = JZ_ST_DAY_LOCK;
                  else
                     if(InpBlockIfNakedPos && g_nakedPos)
                        g_state = JZ_ST_EXPOSURE;
                     else
                        g_state = JZ_ST_ACTIVE;

   if(dirty)
      SaveShieldState();
  }

string StateName(const ENUM_JZ_STATE s)
  {
   switch(s)
     {
      case JZ_ST_ACTIVE:          return "ACTIVE";
      case JZ_ST_PAUSED:          return "PAUSED";
      case JZ_ST_SOFT_HALT:       return "SOFT HALT (managing only)";
      case JZ_ST_HARD_HALT_DAY:   return "HARD HALT - DAY";
      case JZ_ST_HARD_HALT_TOTAL: return "HARD HALT - TOTAL";
      case JZ_ST_TARGET_LOCK:     return "TARGET BANKED";
      case JZ_ST_DAY_LOCK:        return "DAY PROFIT LOCK";
      case JZ_ST_EXPOSURE:        return "BLOCKED: POSITION WITHOUT SL";
     }
   return "?";
  }

//+------------------------------------------------------------------+
//| Historical series container (series-ordered: index 0 = newest)   |
//+------------------------------------------------------------------+
struct JzHist
  {
   MqlRates          d1[];
   double            d1e50[], d1e200[], d1atr[], d1adx[];
   datetime          h4t[];
   double            h4e20[], h4e50[], h4adx[];
   MqlRates          h1[];
   double            h1rsi[], h1atr[];
  };

bool CopyBuf(const int handle, const int buffer, const int count, double &arr[])
  {
   ArraySetAsSeries(arr, true);
   int got = CopyBuffer(handle, buffer, 0, count, arr);
   return (got == count);
  }

int ReadyCount(const ENUM_TIMEFRAMES tf, const int &handles[], const int want)
  {
   int n = Bars(_Symbol, tf);
   if(n <= 0)
      return 0;
   n = MathMin(n, want);
   for(int i = 0; i < ArraySize(handles); i++)
     {
      int c = BarsCalculated(handles[i]);
      if(c <= 0)
         return 0;
      n = MathMin(n, c);
     }
   return n;
  }

bool HandlesCurrent(const ENUM_TIMEFRAMES tf, const int &handles[])
  {
   int n = Bars(_Symbol, tf);
   for(int i = 0; i < ArraySize(handles); i++)
      if(BarsCalculated(handles[i]) < n)
         return false;
   return true;
  }

bool LoadHist(JzHist &h, const int d1Want, const int h4Want, const int h1Want)
  {
   int hd[4];
   hd[0] = hD1_EMA50;
   hd[1] = hD1_EMA200;
   hd[2] = hD1_ATR;
   hd[3] = hD1_ADX;
   int h4h[3];
   h4h[0] = hH4_EMA20;
   h4h[1] = hH4_EMA50;
   h4h[2] = hH4_ADX;
   int h1h[2];
   h1h[0] = hH1_RSI;
   h1h[1] = hH1_ATR;
   int nD1 = ReadyCount(PERIOD_D1, hd, d1Want);
   int nH4 = ReadyCount(PERIOD_H4, h4h, h4Want);
   int nH1 = ReadyCount(PERIOD_H1, h1h, h1Want);
   int needD1 = MathMax(InpDonchianDays, InpMomDays) + 25;
   if(nD1 < needD1 || nH4 < 5 || nH1 < 30)
      return false;
   ArraySetAsSeries(h.d1, true);
   if(CopyRates(_Symbol, PERIOD_D1, 0, nD1, h.d1) != nD1)
      return false;
   if(!CopyBuf(hD1_EMA50, 0, nD1, h.d1e50) || !CopyBuf(hD1_EMA200, 0, nD1, h.d1e200) ||
      !CopyBuf(hD1_ATR, 0, nD1, h.d1atr) || !CopyBuf(hD1_ADX, 0, nD1, h.d1adx))
      return false;
   ArraySetAsSeries(h.h4t, true);
   if(CopyTime(_Symbol, PERIOD_H4, 0, nH4, h.h4t) != nH4)
      return false;
   if(!CopyBuf(hH4_EMA20, 0, nH4, h.h4e20) || !CopyBuf(hH4_EMA50, 0, nH4, h.h4e50) || !CopyBuf(hH4_ADX, 0, nH4, h.h4adx))
      return false;
   ArraySetAsSeries(h.h1, true);
   if(CopyRates(_Symbol, PERIOD_H1, 0, nH1, h.h1) != nH1)
      return false;
   if(!CopyBuf(hH1_RSI, 0, nH1, h.h1rsi) || !CopyBuf(hH1_ATR, 0, nH1, h.h1atr))
      return false;
   // a buffer that lags its series by a bar would silently shift every indicator one bar vs the rates
   if(!HandlesCurrent(PERIOD_D1, hd) || !HandlesCurrent(PERIOD_H4, h4h) || !HandlesCurrent(PERIOD_H1, h1h))
      return false;
   return true;
  }

// index of the most recent bar (series array of open times) that had CLOSED by time t
int ClosedIndexT(const datetime &times[], const datetime t, const int periodSec)
  {
   int n = ArraySize(times);
   int lo = 0, hi = n - 1, ans = -1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if((long)times[mid] + periodSec <= (long)t)
        {
         ans = mid;
         hi = mid - 1;
        }
      else
         lo = mid + 1;
     }
   return ans;
  }

int ClosedIndexR(const MqlRates &rates[], const datetime t, const int periodSec)
  {
   int n = ArraySize(rates);
   int lo = 0, hi = n - 1, ans = -1;
   while(lo <= hi)
     {
      int mid = (lo + hi) / 2;
      if((long)rates[mid].time + periodSec <= (long)t)
        {
         ans = mid;
         hi = mid - 1;
        }
      else
         lo = mid + 1;
     }
   return ans;
  }

// Full MTF context as of time t. c = D1 index, b = H4 index, a = H1 index (all closed by t)
bool BuildCtx(const JzHist &h, const datetime t, JzCtx &x)
  {
   x.ok = false;
   int c = ClosedIndexR(h.d1, t, 86400);
   int b = ClosedIndexT(h.h4t, t, 14400);
   int a = ClosedIndexR(h.h1, t, 3600);
   int nD1 = ArraySize(h.d1);
   if(c < 0 || b < 0 || a < 0)
      return false;
   if(c + MathMax(InpDonchianDays, InpMomDays) + 1 >= nD1 || c + 21 >= nD1)
      return false;
   x.d1Time   = h.d1[c].time;
   x.d1Close  = h.d1[c].close;
   x.d1Ema50  = h.d1e50[c];
   x.d1Ema200 = h.d1e200[c];
   x.d1Atr    = h.d1atr[c];
   x.d1Adx    = h.d1adx[c];
   x.d1Mom    = h.d1[c].close - h.d1[c + InpMomDays].close;
   x.d1Hh = -DBL_MAX;
   x.d1Ll = DBL_MAX;
   for(int j = c + 1; j <= c + InpDonchianDays; j++)
     {
      x.d1Hh = MathMax(x.d1Hh, h.d1[j].high);
      x.d1Ll = MathMin(x.d1Ll, h.d1[j].low);
     }
   double change = MathAbs(h.d1[c].close - h.d1[c + 20].close);
   double vol = 0.0;
   for(int j = c; j < c + 20; j++)
      vol += MathAbs(h.d1[j].close - h.d1[j + 1].close);
   x.d1Er = (vol > 0.0) ? change / vol : 0.0;
   // ATR percentile over up to 250 closed D1 bars (min 60), pandas "average" rank
   int win = MathMin(250, nD1 - c);
   if(win < 60)
      return false;
   int less = 0, equal = 0;
   for(int j = c; j < c + win; j++)
     {
      if(h.d1atr[j] < x.d1Atr)
         less++;
      else
         if(h.d1atr[j] == x.d1Atr)
            equal++;
     }
   x.d1AtrPct = ((double)less + ((double)equal + 1.0) / 2.0) / (double)win;
   x.bias = 0;
   if(x.d1Close > x.d1Ema200 && x.d1Ema50 > x.d1Ema200 && x.d1Mom > 0.0)
      x.bias = 1;
   else
      if(x.d1Close < x.d1Ema200 && x.d1Ema50 < x.d1Ema200 && x.d1Mom < 0.0)
         x.bias = -1;
   x.h4Ema20 = h.h4e20[b];
   x.h4Ema50 = h.h4e50[b];
   x.h4Adx   = h.h4adx[b];
   x.h1Rsi   = h.h1rsi[a];
   x.h1Atr   = h.h1atr[a];
   if(x.d1Atr <= 0.0 || x.h1Atr <= 0.0)
      return false;
   x.ok = true;
   return true;
  }

// D1 breakout signal on the D1 bar that closed by ctx time. +1 / -1 / 0 (inverse applied)
int BreakoutSignal(const JzCtx &x)
  {
   int d = 0;
   bool h4l = !InpRequireH4 || (x.h4Ema20 > x.h4Ema50);
   bool h4s = !InpRequireH4 || (x.h4Ema20 < x.h4Ema50);
   if(x.d1Close > x.d1Hh && h4l)
      d = 1;
   else
      if(x.d1Close < x.d1Ll && h4s)
         d = -1;
   if(InpInverseMode)
      d = -d;
   return d;
  }

int EffectiveBias(const JzCtx &x)
  {
   return InpInverseMode ? -x.bias : x.bias;
  }

//+------------------------------------------------------------------+
//| AI meta-model                                                    |
//+------------------------------------------------------------------+
void Features(const JzCtx &c, const int d, const double close, const int hourUTC, const double spread, double &x[])
  {
   double dd = (double)d;
   x[0]  = 1.0;
   x[1]  = MathMin(3.0, MathAbs(c.d1Mom) / c.d1Atr / 5.0);
   x[2]  = c.d1Er;
   x[3]  = c.d1Adx / 50.0;
   x[4]  = c.d1AtrPct;
   x[5]  = dd * MathMax(-3.0, MathMin(3.0, (close - c.d1Ema50) / c.d1Atr)) / 3.0;
   x[6]  = c.h4Adx / 50.0;
   x[7]  = dd * (c.h1Rsi - 50.0) / 50.0;
   x[8]  = c.h1Atr / c.d1Atr;
   x[9]  = MathSin(2.0 * M_PI * hourUTC / 24.0);
   x[10] = MathCos(2.0 * M_PI * hourUTC / 24.0);
   x[11] = MathMin(1.0, spread / c.h1Atr);
  }

double ModelProb(const double &x[])
  {
   double z = 0.0;
   for(int i = 0; i < JZ_NFEAT; i++)
      z += g_w[i] * x[i];
   z = MathMax(-30.0, MathMin(30.0, z));
   return 1.0 / (1.0 + MathExp(-z));
  }

void AucPush(const double p, const int y)
  {
   int cap = MathMax(20, MathMin(InpAIWindow, JZ_AUC_MAX));
   g_aucP[g_aucHead] = p;
   g_aucY[g_aucHead] = y;
   g_aucHead = (g_aucHead + 1) % cap;
   if(g_aucCount < cap)
      g_aucCount++;
  }

// re-pack the ring chronologically into slots 0..keep-1 for the CURRENT window (window input may have changed)
void AucNormalize()
  {
   int cap = MathMax(20, MathMin(InpAIWindow, JZ_AUC_MAX));
   int cnt = g_aucCount;
   if(cnt <= 0)
     {
      g_aucCount = 0;
      g_aucHead = 0;
      return;
     }
   int start = (g_aucHead < cnt) ? g_aucHead : 0;      // oldest slot
   int keep = MathMin(cnt, cap);
   double tp[];
   int ty[];
   ArrayResize(tp, keep);
   ArrayResize(ty, keep);
   for(int k = 0; k < keep; k++)
     {
      int idx = (start + (cnt - keep) + k) % cnt;         // newest `keep` samples, oldest first
      tp[k] = g_aucP[idx];
      ty[k] = g_aucY[idx];
     }
   for(int k = 0; k < keep; k++)
     {
      g_aucP[k] = tp[k];
      g_aucY[k] = ty[k];
     }
   g_aucCount = keep;
   g_aucHead = keep % cap;
  }

double ComputeAUC()
  {
   double pos = 0.0, neg = 0.0, score = 0.0;
   for(int i = 0; i < g_aucCount; i++)
     {
      if(g_aucY[i] == 1)
         pos++;
      else
         neg++;
     }
   if(pos < 5 || neg < 5)
      return 0.5;
   for(int i = 0; i < g_aucCount; i++)
     {
      if(g_aucY[i] != 1)
         continue;
      for(int j = 0; j < g_aucCount; j++)
        {
         if(g_aucY[j] == 1)
            continue;
         if(g_aucP[i] > g_aucP[j])
            score += 1.0;
         else
            if(g_aucP[i] == g_aucP[j])
               score += 0.5;
        }
     }
   return score / (pos * neg);
  }

void RefreshAIStatus()
  {
   g_lastAUC = ComputeAUC();
   if(InpAIMode == JZ_AI_ALWAYS)
      g_aiActive = true;
   else
      if(InpAIMode == JZ_AI_SELF_VALIDATING)
         g_aiActive = (g_modelN >= InpAIMinSamples && g_aucCount >= MathMin(InpAIWindow, InpAIMinSamples) && g_lastAUC >= InpAIMinAUC);
      else
         g_aiActive = false;
  }

void ModelUpdate(const double &x[], const int y, const double pCausal)
  {
   double p = ModelProb(x);
   g_brier = 0.98 * g_brier + 0.02 * (p - y) * (p - y);
   double lr = MathMax(0.005, InpAILearnRate / MathSqrt(1.0 + (double)g_modelN / 100.0));
   double gr = (double)y - p;
   for(int i = 0; i < JZ_NFEAT; i++)
     {
      double reg = (i == 0) ? 0.0 : InpAIL2 * g_w[i];
      g_w[i] += lr * (gr * x[i] - reg);
     }
   g_modelN++;
   g_updatesSinceSave++;
   AucPush(pCausal, y);
  }

string ModelFile()
  {
   string sym = _Symbol;
   StringReplace(sym, ".", "_");
   return "JZ_AI\\" + sym + "_" + IntegerToString((long)InpMagic) + "_v2.model";
  }

void SaveModel()
  {
   if(!InpPersistModel || g_isTester || InpAIMode == JZ_AI_OFF || !g_modelReady)
      return;                                   // never overwrite a good file with an un-bootstrapped zero model
   int h = FileOpen(ModelFile(), FILE_WRITE | FILE_BIN);
   if(h == INVALID_HANDLE)
      return;
   FileWriteInteger(h, 0x4A5A4132);            // 'JZA2'
   FileWriteInteger(h, JZ_NFEAT);
   FileWriteArray(h, g_w, 0, JZ_NFEAT);
   FileWriteLong(h, g_modelN);
   FileWriteDouble(h, g_brier);
   FileWriteLong(h, (long)g_lastTrainedBar);
   FileWriteInteger(h, g_aucCount);
   FileWriteInteger(h, g_aucHead);
   FileWriteArray(h, g_aucP, 0, JZ_AUC_MAX);
   FileWriteArray(h, g_aucY, 0, JZ_AUC_MAX);
   FileClose(h);
   g_updatesSinceSave = 0;
  }

bool LoadModel()
  {
   if(!InpPersistModel || g_isTester || InpAIMode == JZ_AI_OFF)
      return false;
   if(!FileIsExist(ModelFile()))
      return false;
   int h = FileOpen(ModelFile(), FILE_READ | FILE_BIN);
   if(h == INVALID_HANDLE)
      return false;
   bool ok = false;
   if(FileReadInteger(h) == 0x4A5A4132 && FileReadInteger(h) == JZ_NFEAT)
     {
      if(FileReadArray(h, g_w, 0, JZ_NFEAT) == JZ_NFEAT)
        {
         g_modelN = FileReadLong(h);
         g_brier = FileReadDouble(h);
         g_lastTrainedBar = (datetime)FileReadLong(h);
         g_aucCount = FileReadInteger(h);
         g_aucHead = FileReadInteger(h);
         ok = (FileReadArray(h, g_aucP, 0, JZ_AUC_MAX) == JZ_AUC_MAX && FileReadArray(h, g_aucY, 0, JZ_AUC_MAX) == JZ_AUC_MAX);
         if(g_aucCount < 0 || g_aucCount > JZ_AUC_MAX || g_aucHead < 0 || g_aucHead >= JZ_AUC_MAX)
            ok = false;
         else
            AucNormalize();
        }
     }
   FileClose(h);
   if(!ok)
     {
      ArrayInitialize(g_w, 0.0);
      g_modelN = 0;
      g_lastTrainedBar = 0;
      g_aucCount = 0;
      g_aucHead = 0;
     }
   return ok;
  }

void PendingPush(const JzSample &smp)
  {
   if(g_pendingCount >= JZ_MAX_PENDING)
     {
      for(int i = 1; i < g_pendingCount; i++)
         g_pending[i - 1] = g_pending[i];
      g_pendingCount--;
     }
   if(ArraySize(g_pending) <= g_pendingCount)
      ArrayResize(g_pending, g_pendingCount + 64);
   g_pending[g_pendingCount] = smp;
   g_pendingCount++;
  }

// -1 unresolved, 0 stop first (or ambiguous bar), 1 target first
int BarrierCheck(const JzSample &smp, const MqlRates &bar)
  {
   double up = smp.entry + smp.slDist * InpTP1_R * smp.dir;
   double dn = smp.entry - smp.slDist * smp.dir;
   double spr = (double)bar.spread * g_point;
   bool hitSl, hitTp;
   if(smp.dir > 0)
     {
      hitSl = (bar.low <= dn);
      hitTp = (bar.high >= up);
     }
   else
     {
      hitSl = (bar.high + spr >= dn);
      hitTp = (bar.low + spr <= up);
     }
   if(hitSl)
      return 0;
   if(hitTp)
      return 1;
   return -1;
  }

void ResolvePending(const MqlRates &bar, const int horizonBars)
  {
   int w = 0;
   for(int i = 0; i < g_pendingCount; i++)
     {
      if(bar.time < g_pending[i].entryBar)
        {
         g_pending[w++] = g_pending[i];
         continue;
        }
      int lab = BarrierCheck(g_pending[i], bar);
      g_pending[i].barsSeen++;
      if(lab < 0 && g_pending[i].barsSeen >= horizonBars + 1)
         lab = 0;
      if(lab >= 0)
         ModelUpdate(g_pending[i].x, lab, g_pending[i].pAtCreation);
      else
         g_pending[w++] = g_pending[i];
     }
   g_pendingCount = w;
   g_lastTrainedBar = bar.time;
   if(g_updatesSinceSave >= 5)
      SaveModel();
  }

//+------------------------------------------------------------------+
//| Bootstrap: replay the SAME signal on D1/H4/H1 history, learn     |
//| causally (a label trains only after it resolved in time order)   |
//+------------------------------------------------------------------+
// Open time of the first M15 bar that closes at/after a D1 close (= backtest d1_event bar):
// the last M15 bar of the day on 24h feeds (FX, gold), the first bar of the next session on
// instruments with a daily break (indices) - which is also why Friday index signals execute Monday.
datetime D1EventBarOpen(const datetime d1Close)
  {
   datetime t[];
   ArraySetAsSeries(t, false);
   int n = CopyTime(_Symbol, PERIOD_M15, (datetime)((long)d1Close - 900), (datetime)((long)d1Close + 4 * 86400), t);
   if(n > 0 && (long)t[0] >= (long)d1Close - 900)
      return t[0];
   return (datetime)((long)d1Close - 900);
  }

struct JzBootSample
  {
   double            x[JZ_NFEAT];
   int               y;
   datetime          created;
   datetime          resolved;
   double            p;
   bool              done;
  };

bool Bootstrap()
  {
   if(g_bootstrapped)
      return true;
   if(InpAIMode == JZ_AI_OFF)
     {
      g_bootstrapped = true;
      return true;
     }
   int days = MathMax(InpBootstrapDays, 300);
   JzHist h;
   if(!LoadHist(h, days + 320, days * 6 + 400, days * 24 + 600))
      return false;
   ulong t0 = GetTickCount64();
   int nD1 = ArraySize(h.d1);
   int nH1 = ArraySize(h.h1);
   JzBootSample bs[];
   int nb = 0;
   int horizonH1 = InpLabelDays * 24;
   int armedDir = 0;
   long srvOffNow = JzServerOffsetSec();

   // walk D1 closes from oldest to newest (series index descending)
   for(int c = nD1 - 2; c >= 1; c--)
     {
      datetime tD1Close = (datetime)((long)h.d1[c].time + 86400);
      if((long)tD1Close > (long)TimeCurrent())
         break;
      if(g_bootFrom > 0 && tD1Close <= g_bootFrom)          // NOT g_lastTrainedBar: OnNewM15 advances it before bootstrap succeeds
         continue;
      JzCtx ctx;
      if(!BuildCtx(h, tD1Close, ctx))
         continue;
      int d = BreakoutSignal(ctx);
      if(d == 0)
         continue;
      int orig = InpInverseMode ? -d : d;               // side of the actual breakout
      double level = (orig > 0) ? ctx.d1Hh : ctx.d1Ll;
      armedDir = orig;
      // search a clean H1 execution inside the window
      int a0 = ClosedIndexR(h.h1, tD1Close, 3600);          // last H1 closed at D1 close
      if(a0 < 1)
         continue;
      int execA = -1;
      long expLimit = (long)D1EventBarOpen(tD1Close) + (long)InpExecWindowHours * 3600;
      for(int a = a0 - 1; a >= 1; a--)
        {
         datetime barClose = (datetime)((long)h.h1[a].time + 3600);
         if((long)barClose - 900 > expLimit)                // last M15 bar of this H1 opened after expiry
            break;
         MqlDateTime g;
         TimeToStruct((datetime)((long)barClose - JzServerOffsetAt(h.h1[a].time)), g);
         if(g_noEntryHour[g.hour])
            continue;
         if((double)h.h1[a].spread * g_point > InpExecSpreadATR * h.h1atr[a])
            continue;
         bool beyond = (armedDir > 0) ? (h.h1[a].close > level) : (h.h1[a].close < level);
         if(!beyond)
            continue;
         execA = a;
         break;
        }
      if(execA < 1)
         continue;
      datetime tExec = (datetime)((long)h.h1[execA].time + 3600);
      if((long)tExec >= (long)g_eaStart)
         continue;                                  // live arm/sample path owns executions after attach (no double count)
      JzCtx cx;
      if(!BuildCtx(h, tExec, cx))
         continue;
      double entry = (d > 0) ? h.h1[execA - 1].open + (double)h.h1[execA - 1].spread * g_point : h.h1[execA - 1].open;
      double R = InpSL_ATR * cx.d1Atr;
      if(R <= 0.0)
         continue;
      MqlDateTime go;
      TimeToStruct((datetime)((long)h.h1[execA].time - JzServerOffsetAt(h.h1[execA].time)), go);
      if(ArraySize(bs) <= nb)
         ArrayResize(bs, nb + 256);
      Features(cx, d, h.h1[execA].close, go.hour, (double)h.h1[execA].spread * g_point, bs[nb].x);
      bs[nb].created = tExec;
      bs[nb].done = false;
      // triple barrier on H1 bars (stop first on ambiguous bars)
      double up = entry + d * InpTP1_R * R, dn = entry - d * R;
      int y = -1;
      datetime res = 0;
      int last = MathMax(0, execA - 1 - horizonH1);
      for(int j = execA - 1; j >= 1 && j >= last; j--)
        {
         double spr = (double)h.h1[j].spread * g_point;
         bool sl = (d > 0) ? (h.h1[j].low <= dn) : (h.h1[j].high + spr >= dn);
         bool tp = (d > 0) ? (h.h1[j].high >= up) : (h.h1[j].low + spr <= up);
         if(sl) { y = 0; res = (datetime)((long)h.h1[j].time + 3600); break; }
         if(tp) { y = 1; res = (datetime)((long)h.h1[j].time + 3600); break; }
         if(j == last) { y = 0; res = (datetime)((long)h.h1[j].time + 3600); }
        }
      if(y < 0)
         continue;                                  // horizon not complete yet: live learner will not see it (acceptable)
      bs[nb].y = y;
      bs[nb].resolved = res;
      nb++;
     }

   // causal replay: before predicting sample k, learn every sample resolved by its creation time
   int trained = 0;
   for(int k = 0; k < nb; k++)
     {
      for(int m = 0; m < k; m++)
        {
         if(!bs[m].done && bs[m].resolved <= bs[k].created)
           {
            ModelUpdate(bs[m].x, bs[m].y, bs[m].p);
            bs[m].done = true;
            trained++;
           }
        }
      bs[k].p = ModelProb(bs[k].x);
     }
   for(int m = 0; m < nb; m++)
     {
      if(!bs[m].done && bs[m].resolved <= TimeCurrent())
        {
         ModelUpdate(bs[m].x, bs[m].y, bs[m].p);
         bs[m].done = true;
         trained++;
        }
     }
   g_lastTrainedBar = MathMax(g_lastTrainedBar, iTime(_Symbol, PERIOD_M15, 1));
   g_bootstrapped = true;
   g_modelReady = true;
   RefreshAIStatus();
   SaveModel();
   JzLog(1, StringFormat("AI bootstrap: %d D1 bars, %d H1 bars, %d samples, %d trained, AUC %.3f, active=%s, %I64u ms (srv offset %I64d)",
                         nD1, nH1, nb, trained, g_lastAUC, g_aiActive ? "YES" : "no", GetTickCount64() - t0, srvOffNow));
   return true;
  }

//+------------------------------------------------------------------+
//| News filter                                                      |
//+------------------------------------------------------------------+
void LoadNews()
  {
   ArrayResize(g_newsTimes, 0);
   datetime now = TimeTradeServer();
   string curs[2];
   curs[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   curs[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   for(int c = 0; c < 2; c++)
     {
      if(c == 1 && curs[1] == curs[0])
         continue;
      MqlCalendarValue vals[];
      ResetLastError();
      int n = CalendarValueHistory(vals, (datetime)((long)now - 3600), (datetime)((long)now + 2 * 86400), NULL, curs[c]);
      if(n < 0 || (n == 0 && GetLastError() != 0))
        {
         JzLog(0, StringFormat("calendar load failed err=%d - retry in 60s", GetLastError()));
         g_newsLoaded = (datetime)((long)now - 840);     // retry soon instead of silently disabling for 15 min
         g_newsFailed = true;
         return;
        }
      for(int i = 0; i < n; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev))
            continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;
         int sz = ArraySize(g_newsTimes);
         ArrayResize(g_newsTimes, sz + 1);
         g_newsTimes[sz] = vals[i].time;
        }
     }
   g_newsLoaded = now;
   g_newsFailed = false;
  }

bool NewsBlocked()
  {
   if(!(InpUseNews || g_newsForced) || g_isTester)
      return false;
   datetime now = TimeTradeServer();
   if((long)now - (long)g_newsLoaded > 900)
      LoadNews();
   if(g_newsFailed)
      return true;                                   // fail closed: unknown calendar = no new entries
   for(int i = 0; i < ArraySize(g_newsTimes); i++)
     {
      long dt = (long)g_newsTimes[i] - (long)now;
      long before = (long)MathMax(InpNewsMinsBefore, g_newsForced ? 2 : 0) * 60;
      long after  = (long)MathMax(InpNewsMinsAfter, g_newsForced ? 2 : 0) * 60;
      if(dt <= before && dt >= -after)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| OpenAI second opinion (optional, live only)                      |
//+------------------------------------------------------------------+
string JsonEscape(const string s)
  {
   string o = s;
   StringReplace(o, "\\", "\\\\");
   StringReplace(o, "\"", "\\\"");
   StringReplace(o, "\n", "\\n");
   StringReplace(o, "\r", "");
   return o;
  }

double PayoffB()
  {
   int losses = g_closedTrades - g_wins;
   if(g_closedTrades >= 30 && g_wins > 0 && losses > 0 && g_sumLossR < 0.0)
     {
      double b = (g_sumWinR / g_wins) / (-g_sumLossR / losses);
      return MathMax(0.5, MathMin(3.0, b));
     }
   return InpPayoffB;
  }
bool JzEntryLock()
  {
   string n = g_acctPfx + "ENTRYLOCK";
   if(!GlobalVariableCheck(n))
      GlobalVariableTemp(n);                        // value 0 = free
   double now = (double)(long)TimeLocal();
   for(int i = 0; i < 20; i++)
     {
      if(GlobalVariableSetOnCondition(n, now, 0.0))
         return true;
      double held = GlobalVariableGet(n);
      if(now - held > 30.0 && GlobalVariableSetOnCondition(n, now, held))   // stale lock from a crashed instance
         return true;
      Sleep(50);
     }
   return false;
  }

void JzEntryUnlock()
  {
   GlobalVariableSet(g_acctPfx + "ENTRYLOCK", 0.0);
  }

bool HasOwnPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
     }
   return false;
  }

bool HasAnySymbolPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
     }
   return false;
  }

bool SendMarket(const int dir, const double lots, const double slDist, const string cmt, ulong &posId, double &fillPrice)
  {
   posId = 0;
   fillPrice = 0.0;
   long stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(slDist < (double)stopsLvl * g_point * 1.5)
     {
      JzLog(1, "refuse: stop inside broker stops level");
      return false;
     }
   for(int attempt = 0; attempt < 3; attempt++)
     {
      MqlTick tk;
      if(!SymbolInfoTick(_Symbol, tk))
         return false;
      double price = (dir > 0) ? tk.ask : tk.bid;
      double sl = NormPrice(price - dir * slDist);
      double tp = 0.0;                                // runner rides the chandelier; stop is always server-side
      bool ok = (dir > 0) ? g_trade.Buy(lots, _Symbol, price, sl, tp, cmt) : g_trade.Sell(lots, _Symbol, price, sl, tp, cmt);
      uint rc = g_trade.ResultRetcode();
      if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL))
        {
         fillPrice = g_trade.ResultPrice() > 0.0 ? g_trade.ResultPrice() : price;
         ulong deal = g_trade.ResultDeal();
         if(deal > 0 && HistoryDealSelect(deal))
            posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(posId == 0)
           {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
              {
               ulong t = PositionGetTicket(i);
               if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
                 {
                  posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
                  break;
                 }
              }
           }
         return true;
        }
      JzLog(0, StringFormat("order failed rc=%u %s (attempt %d)", rc, g_trade.ResultRetcodeDescription(), attempt + 1));
      if(rc == TRADE_RETCODE_TIMEOUT || rc == TRADE_RETCODE_CONNECTION || rc == 0)
        {
         // outcome unknown: the order may have filled server-side. Never blind-retry.
         Sleep(1000);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong t = PositionGetTicket(i);
            if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
              {
               posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
               fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               return true;
              }
           }
         break;
        }
      if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_PRICE_OFF)
        {
         Sleep(250 * (attempt + 1));
         continue;
        }
      break;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Position management — runs on EVERY tick, halted or not          |
//+------------------------------------------------------------------+
bool ClosePartialAny(const ulong ticket, const int dir, const double q)
  {
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return g_trade.PositionClosePartial(ticket, q, (ulong)InpSlippagePoints);
   // netting: CTrade::PositionClosePartial() is hedging-only and always returns false
   return (dir > 0) ? g_trade.Sell(q, _Symbol, 0.0, 0.0, 0.0, InpComment + "|PC")
          : g_trade.Buy(q, _Symbol, 0.0, 0.0, 0.0, InpComment + "|PC");
  }

bool SafeModifySL(const ulong ticket, const int dir, const double newSL, const double tp)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   double curSL = PositionGetDouble(POSITION_SL);
   double nsl = NormPrice(newSL);
   if(dir > 0 && curSL > 0.0 && nsl <= curSL)
      return true;                                  // tighten only
   if(dir < 0 && curSL > 0.0 && nsl >= curSL)
      return true;
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return false;
   double minDist = (double)MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                    SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * g_point;
   if(dir > 0 && tk.bid - nsl <= minDist)
      return false;
   if(dir < 0 && nsl - tk.ask <= minDist)
      return false;
   return g_trade.PositionModify(ticket, nsl, tp);
  }

void PanelLabel(const string name, const int x, const int y, const string text, const color clr, const int size)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void PanelButton(const string name, const int x, const int y, const int w, const int h, const string text, const color bg)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Extra globals for v2 flow                                        |
//+------------------------------------------------------------------+
bool           g_forceFridayFlat = false;

//+------------------------------------------------------------------+
//| OpenAI second opinion (optional, live only)                      |
//+------------------------------------------------------------------+
// returns 1 approve, 0 veto, -1 failure
int OpenAIVerdict(const JzCtx &c, const int d, const double p)
  {
   if(!InpUseOpenAI || g_isTester || StringLen(InpOpenAIKey) < 10)
      return 1;
   string user = StringFormat(
                    "Symbol %s. Proposed %s on a D1 55-day breakout. D1 bias %d, momentum %.2f ATR, efficiency ratio %.2f, "
                    "D1 ADX %.1f, ATR percentile %.2f, H4 ADX %.1f, H1 RSI %.1f. On-board model P(reach 1R before stop) = %.3f "
                    "(AUC %.3f, active %s). Reply ONLY with JSON {\"approve\":true|false,\"confidence\":0..1,\"reason\":\"<15 words\"}.",
                    _Symbol, (d > 0 ? "BUY" : "SELL"), c.bias, c.d1Mom / c.d1Atr, c.d1Er, c.d1Adx, c.d1AtrPct, c.h4Adx, c.h1Rsi, p,
                    g_lastAUC, g_aiActive ? "yes" : "no");
   string sys = "You are a risk officer for a prop-firm trading desk. Veto only trades with clear structural or event risk.";
   string body = "{\"model\":\"" + JsonEscape(InpOpenAIModel) + "\",\"messages\":[{\"role\":\"system\",\"content\":\"" +
                 JsonEscape(sys) + "\"},{\"role\":\"user\",\"content\":\"" + JsonEscape(user) + "\"}]}";
   char data[], result[];
   string resHeaders;
   int len = StringToCharArray(body, data, 0, StringLen(body), CP_UTF8);
   ArrayResize(data, len);
   string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + InpOpenAIKey + "\r\n";
   ResetLastError();
   int code = WebRequest("POST", "https://api.openai.com/v1/chat/completions", headers, InpOpenAITimeoutMs, data, result, resHeaders);
   if(code != 200)
     {
      int err = GetLastError();
      JzLog(0, StringFormat("OpenAI call failed http=%d err=%d%s", code, err,
                            err == 4014 ? " (add https://api.openai.com to Tools > Options > Expert Advisors > WebRequest)" : ""));
      return -1;
     }
   string txt = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   int cpos = StringFind(txt, "\"content\"");
   if(cpos < 0)
      return -1;
   string content = StringSubstr(txt, cpos, 600);
   int apos = StringFind(content, "approve");
   if(apos < 0)
      return -1;
   string tail = StringSubstr(content, apos, 24);
   int tpos = StringFind(tail, "true");
   int fpos = StringFind(tail, "false");
   bool approve;
   if(tpos >= 0 && (fpos < 0 || tpos < fpos))
      approve = true;
   else
      if(fpos >= 0)
         approve = false;
      else
         return -1;
   double conf = 0.5;
   int kpos = StringFind(content, "confidence");
   if(kpos >= 0)
     {
      string num = "";
      string seg = StringSubstr(content, kpos + 10, 16);
      for(int i = 0; i < StringLen(seg); i++)
        {
         ushort ch = StringGetCharacter(seg, i);
         if((ch >= '0' && ch <= '9') || ch == '.')
            num += ShortToString(ch);
         else
            if(StringLen(num) > 0)
               break;
        }
      if(StringLen(num) > 0)
         conf = StringToDouble(num);
     }
   JzLog(1, StringFormat("OpenAI verdict: %s (confidence %.2f)", approve ? "APPROVE" : "VETO", conf));
   if(!approve && conf >= 0.60)
      return 0;
   return 1;
  }

//+------------------------------------------------------------------+
//| Sizing — clamp to compliance budget LAST                          |
//+------------------------------------------------------------------+
double RiskPercent(const double p)
  {
   double riskPct = InpBaseRiskPct;
   if(g_aiActive && p > 0.0)
     {
      double b = PayoffB();
      double f = (p * b - (1.0 - p)) / b;
      if(f <= 0.0)
         return 0.0;
      riskPct = InpBaseRiskPct * ((0.5 * f) / MathMax(InpKellyRef, 1e-6));
      riskPct = MathMax(InpBaseRiskPct * 0.5, MathMin(InpMaxRiskPct, riskPct));
     }
   double damp = MathMax(InpStreakFloor, MathPow(InpStreakDamp, g_lossStreak));
   return MathMin(riskPct * damp, InpMaxRiskPct);
  }

double SizeLots(const int dir, const double entry, const double sl, const double p, double &riskMoney)
  {
   riskMoney = 0.0;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double basis = MathMin(bal, eq);
   double lossLot = LossPerLot(dir, entry, sl);
   if(lossLot <= 0.0)
      return 0.0;
   double lots;
   if(InpSizing == JZ_SIZE_FIXED_LOTS)
     {
      lots = (g_manualLots > 0.0) ? g_manualLots : InpFixedLots;
      riskMoney = lots * lossLot;
     }
   else
     {
      double pct = RiskPercent(p);
      if(pct <= 0.0)
         return 0.0;
      riskMoney = basis * pct / 100.0;
     }
   double cap = 0.5 * g_budgetMoney;
   if(g_rules.tradeCapPct > 0.0)
      cap = MathMin(cap, basis * g_rules.tradeCapPct / 100.0);
   cap = MathMin(cap, basis * InpMaxRiskPct / 100.0);
   riskMoney = MathMin(riskMoney, cap);                   // <- compliance clamp, applied last
   lots = NormLotsDown(riskMoney / lossLot);
   if(InpNoSizeUpAfterLoss && g_lastWasLoss && g_lastLots > 0.0 && lots > g_lastLots)
      lots = NormLotsDown(g_lastLots);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lots < vmin)
      return 0.0;                                         // refuse, never round up
   double margin = 0.0;
   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(t, _Symbol, lots, entry, margin))
      return 0.0;
   double freeM = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > 0.9 * freeM)
     {
      lots = NormLotsDown(lots * 0.9 * freeM / margin);
      if(lots < vmin)
         return 0.0;
     }
   riskMoney = lots * lossLot;
   return lots;
  }

int CountMagicPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic && StringFind(PositionGetString(POSITION_COMMENT), "|DK") < 0)
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Live context (last CLOSED bars right now)                        |
//+------------------------------------------------------------------+
bool LiveCtx(JzCtx &c)
  {
   JzHist h;
   int d1 = MathMax(InpDonchianDays, InpMomDays) + 270;
   if(!LoadHist(h, d1, 60, 60))
      return false;
   return BuildCtx(h, TimeCurrent(), c);
  }

//+------------------------------------------------------------------+
//| Position management — EVERY tick, in every shield state          |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   datetime gmt = JzGMT();
   MqlDateTime g;
   TimeToStruct(gmt, g);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   bool fridayRule = (InpFridayFlat || g_forceFridayFlat) && g.day_of_week == 5 && g.hour >= InpFridayFlatHourUTC;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      long held = (long)TimeCurrent() - (long)opened;
      string comment = PositionGetString(POSITION_COMMENT);

      if(StringFind(comment, "|DK") >= 0)
        {
         if(held >= (long)MathMax(InpMinHoldSec, 300))
            g_trade.PositionClose(ticket, (ulong)InpSlippagePoints);
         continue;
        }

      // time stop (trading-day bars) & weekend rule — before the R lookup so nothing is orphaned
      int barsHeld = iBarShift(_Symbol, PERIOD_M15, opened, false);
      bool timeUp = (barsHeld >= InpMaxHoldDays * JZ_BARS_PER_DAY);
      if((timeUp || fridayRule) && held >= InpMinHoldSec)
        {
         if(g_trade.PositionClose(ticket, (ulong)InpSlippagePoints))
            JzLog(1, StringFormat("close #%I64u %s", ticket, timeUp ? "time stop" : "weekend flatten"));
         continue;
        }

      double R = GVGet(PosKey(posId, "R"), 0.0);
      if(R <= 0.0)
        {
         int rp = StringFind(comment, "R=");
         if(rp >= 0)
            R = StringToDouble(StringSubstr(comment, rp + 2)) * g_point;
        }
      if(R <= 0.0 && sl > 0.0 && dir * (open - sl) > 0.0)
         R = MathAbs(open - sl);
      if(R <= 0.0)
         continue;
      double initVol = GVGet(PosKey(posId, "V"), vol);
      int legs = (int)GVGet(PosKey(posId, "L"), 0.0);

      MqlTick tk;
      if(!SymbolInfoTick(_Symbol, tk))
         continue;
      double px = (dir > 0) ? tk.bid : tk.ask;
      double progR = dir * (px - open) / R;
      if(held < InpMinHoldSec)
         continue;

      if(legs == 0 && progR >= InpTP1_R)
        {
         double q = NormLotsDown(initVol * InpTP1_Frac);
         bool partialOk = true;
         if(q >= vmin && vol - q >= vmin)
            partialOk = ClosePartialAny(ticket, dir, q);
         if(partialOk)
           {
            SafeModifySL(ticket, dir, open + dir * InpBEBufferR * R, tp);
            GVSet(PosKey(posId, "L"), 1.0);
            JzLog(1, StringFormat("#%I64u TP1 %.3fR: closed %.2f, stop -> breakeven", ticket, InpTP1_R, q));
           }
         continue;
        }
      if(legs == 1 && progR >= InpTP2_R)
        {
         double q = NormLotsDown(initVol * InpTP2_Frac);
         bool partialOk = true;
         if(PositionSelectByTicket(ticket))
            vol = PositionGetDouble(POSITION_VOLUME);
         if(q >= vmin && vol - q >= vmin)
            partialOk = ClosePartialAny(ticket, dir, q);
         if(partialOk)
           {
            SafeModifySL(ticket, dir, open + dir * InpLock2_R * R, tp);
            GVSet(PosKey(posId, "L"), 2.0);
            JzLog(1, StringFormat("#%I64u TP2 %.3fR: closed %.2f, stop -> +%.3fR, runner on chandelier", ticket, InpTP2_R, q, InpLock2_R));
           }
         continue;
        }
      // re-assert the ladder stop if a modify was rejected earlier
      double want = (legs == 0) ? open - dir * R : ((legs == 1) ? open + dir * InpBEBufferR * R : open + dir * InpLock2_R * R);
      bool slBehind = (legs == 0) ? (sl <= 0.0) : (sl <= 0.0 || dir * (want - sl) > g_point);
      if(slBehind)
        {
         if(dir * (px - want) <= 0.0)
           {
            if(g_trade.PositionClose(ticket, (ulong)InpSlippagePoints))
               JzLog(1, StringFormat("#%I64u virtual stop (legs=%d) at %.2fR", ticket, legs, progR));
           }
         else
            SafeModifySL(ticket, dir, want, tp);
        }
     }
  }

// H1 close: extend the extreme, trail the runner with the chandelier (tighten only)
bool OnNewH1()
  {
   double hi = iHigh(_Symbol, PERIOD_H1, 1);
   double lo = iLow(_Symbol, PERIOD_H1, 1);
   datetime h1Close = iTime(_Symbol, PERIOD_H1, 0);
   double atrD1[];
   ArraySetAsSeries(atrD1, true);
   if(CopyBuffer(hD1_ATR, 0, 1, 1, atrD1) != 1 || atrD1[0] <= 0.0 || hi <= 0.0 || lo <= 0.0 || h1Close == 0)
      return false;                                        // retried: a lost H1 update is a lost extreme
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "|DK") >= 0)
         continue;
      if((long)PositionGetInteger(POSITION_TIME) >= (long)h1Close)
         continue;                                         // that H1 bar ended before this position existed
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double ext = GVGet(PosKey(posId, "E"), open);
      ext = (dir > 0) ? MathMax(ext, hi) : MathMin(ext, lo);
      GVSet(PosKey(posId, "E"), ext);
      int legs = (int)GVGet(PosKey(posId, "L"), 0.0);
      if(legs < 1)
         continue;
      double ch = ext - dir * InpTrail_ATR * atrD1[0];
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0 || dir * (ch - sl) > g_point)
        {
         MqlTick tk;
         if(SymbolInfoTick(_Symbol, tk) && dir * (((dir > 0) ? tk.bid : tk.ask) - ch) <= 0.0)
           {
            // chandelier already through price: a server-side modify is impossible, exit at market
            if(g_trade.PositionClose(ticket, (ulong)InpSlippagePoints))
               JzLog(1, StringFormat("#%I64u chandelier crossed price: closed", ticket));
            continue;
           }
         SafeModifySL(ticket, dir, ch, PositionGetDouble(POSITION_TP));
        }
     }
   return true;
  }

// bias-flip exits owed since the last D1 close; retried until every such position is gone
void DoBiasExits()
  {
   bool remaining = false;
   // execution realism: never exit into the rollover spread unless the 12h grace has run out
   bool graceOver = ((long)TimeCurrent() - (long)g_flipBefore) > (long)InpExecWindowHours * 3600;
   bool clean = true;
   if(!graceOver)
     {
      MqlDateTime gn;
      TimeToStruct(JzGMT(), gn);
      MqlTick tkc;
      double atrH1[];
      ArraySetAsSeries(atrH1, true);
      if(g_noEntryHour[gn.hour] || !SymbolInfoTick(_Symbol, tkc) || CopyBuffer(hH1_ATR, 0, 1, 1, atrH1) != 1 ||
         (tkc.ask - tkc.bid) > InpExecSpreadATR * atrH1[0])
         clean = false;
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "|DK") >= 0)
         continue;
      if((long)PositionGetInteger(POSITION_TIME) >= (long)g_flipBefore)
         continue;                                          // opened after that D1 close: not subject to it
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(g_flipBias == dir)
         continue;
      long held = (long)TimeCurrent() - (long)PositionGetInteger(POSITION_TIME);
      if(held < InpMinHoldSec || !clean)
        {
         remaining = true;
         continue;
        }
      if(g_trade.PositionClose(ticket, (ulong)InpSlippagePoints))
         JzLog(1, StringFormat("close #%I64u: D1 bias no longer %s", ticket, dir > 0 ? "long" : "short"));
      else
         remaining = true;
     }
   g_flipPending = remaining;
  }

// replay closed M15 bars of an arm window through the execution gate (bar spread as proxy):
// true = the backtest would already have consumed this arm (EA was offline / freshly attached)
bool ArmAlreadyExecuted(const JzHist &h, const int origDir, const double level, const datetime evtBar, const datetime expiry)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   datetime cur = iTime(_Symbol, PERIOD_M15, 0);
   int n = CopyRates(_Symbol, PERIOD_M15, evtBar, expiry, r);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
     {
      if((long)r[i].time >= (long)cur)
         break;
      datetime cl = (datetime)((long)r[i].time + 900);
      MqlDateTime g;
      TimeToStruct((datetime)((long)cl - JzServerOffsetAt(r[i].time)), g);
      if(g_noEntryHour[g.hour])
         continue;
      int a = ClosedIndexR(h.h1, cl, 3600);
      if(a < 0)
         continue;
      if((double)r[i].spread * g_point > InpExecSpreadATR * h.h1atr[a])
         continue;
      if((origDir > 0) ? (r[i].close > level) : (r[i].close < level))
         return true;
     }
   return false;
  }

// D1 close: bias-flip exits, then arm a fresh breakout. false = context not ready, caller retries
bool OnNewD1(const bool firstRun)
  {
   JzHist h;
   JzCtx c;
   int d1Want = MathMax(InpDonchianDays, InpMomDays) + 270;
   if(!LoadHist(h, d1Want, 60, MathMax(60, InpExecWindowHours + 48)) || !BuildCtx(h, TimeCurrent(), c))
     {
      g_lastBlock = "D1 context not ready";
      return false;
     }
   int bias = EffectiveBias(c);
   g_lastBias = bias;
   datetime d1Close = (datetime)((long)c.d1Time + 86400);
   if(InpBiasExit)
     {
      // also on first run: a position that existed at this D1 close is owed the flip even if the EA was offline
      g_flipBias = bias;
      g_flipBefore = d1Close;
      DoBiasExits();
     }
   if(g_armed.on && (long)TimeCurrent() <= (long)g_armed.expiry)
     {
      if(firstRun && !g_armed.sampled)                     // a sampled arm was kept after a transient failure: keep it
        {
         int o = InpInverseMode ? -g_armed.dir : g_armed.dir;
         if(ArmAlreadyExecuted(h, o, g_armed.level, (datetime)((long)g_armed.expiry - (long)InpExecWindowHours * 3600), g_armed.expiry))
           {
            g_armed.on = false;
            g_lastBlock = "persisted arm already executable while offline - dropped";
            SaveSymbolState();
           }
        }
      return true;                                           // a live arm is never replaced (same as backtest)
     }
   if(c.d1Time == g_armD1Done)
      return true;                                           // this D1 breakout was already armed/consumed (restart / re-init)
   int d = BreakoutSignal(c);
   if(d == 0)
     {
      g_armed.on = false;
      g_lastSignal = "-";
      SaveSymbolState();
      return true;
     }
   datetime evtBar = D1EventBarOpen(d1Close);
   datetime expiry = (datetime)((long)evtBar + (long)InpExecWindowHours * 3600);
   int orig = InpInverseMode ? -d : d;
   double level = (orig > 0) ? c.d1Hh : c.d1Ll;
   g_armD1Done = c.d1Time;
   if((long)TimeCurrent() > (long)expiry)
     {
      g_armed.on = false;
      SaveSymbolState();
      return true;
     }
   if(firstRun && ArmAlreadyExecuted(h, orig, level, evtBar, expiry))
     {
      g_armed.on = false;
      g_lastSignal = "breakout already executable before attach - skipped";
      SaveSymbolState();
      return true;
     }
   g_armed.on = true;
   g_armed.dir = d;
   g_armed.level = level;
   g_armed.expiry = expiry;
   g_armed.sampled = false;
   g_lastSignal = StringFormat("%s breakout armed (lvl %s)", d > 0 ? "BUY" : "SELL", DoubleToString(g_armed.level, g_digits));
   SaveSymbolState();
   JzLog(1, "D1 " + g_lastSignal + " until " + TimeToString(expiry));
   return true;
  }

//+------------------------------------------------------------------+
//| Day keeper (min trading days after target is banked)             |
//+------------------------------------------------------------------+
void DayKeeper()
  {
   if(!InpDayKeeper || g_state != JZ_ST_TARGET_LOCK || g_rules.minDays <= 0)
      return;
   if(g_tradingDays >= g_rules.minDays)
      return;
   if((int)g_dayKeeperKey == g_dayKey || g_lastCountedDay == g_dayKey)
      return;
   if(HasAnySymbolPosition() || g_nakedPos || g_dailyUsed >= InpSoftFrac)
      return;
   MqlDateTime g;
   TimeToStruct(JzGMT(), g);
   if(g_noEntryHour[g.hour] || NewsBlocked() || (g.day_of_week == 5 && g.hour >= InpFridayFlatHourUTC - 1))
      return;
   if(!JzEntryLock())
      return;
   double atrH1[];
   ArraySetAsSeries(atrH1, true);
   if(CopyBuffer(hH1_ATR, 0, 1, 1, atrH1) != 1)
     {
      JzEntryUnlock();
      return;
     }
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   int dir = (g_lastBias >= 0) ? 1 : -1;
   double slDist = MathMax(atrH1[0], (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point * 2.0);
   ulong posId;
   double fill;
   bool ok = SendMarket(dir, vmin, slDist, InpComment + "|DK", posId, fill);
   JzEntryUnlock();
   if(ok)
     {
      g_dayKeeperKey = g_dayKey;
      SaveSymbolState();
      JzLog(1, StringFormat("Day keeper trade opened (trading days %d/%d)", g_tradingDays, g_rules.minDays));
     }
  }

// transient failure after the gate passed: keep the arm for the next M15 close (sample is not re-created)
void ArmKeep(const string why)
  {
   g_armed.on = true;
   g_lastBlock = why + " (arm kept)";
   SaveSymbolState();
  }

//+------------------------------------------------------------------+
//| M15 close: learn, then try to execute an armed breakout          |
//+------------------------------------------------------------------+
void OnNewM15()
  {
   int horizon = InpLabelDays * JZ_BARS_PER_DAY;
   if(InpAIMode != JZ_AI_OFF && g_pendingCount > 0)
     {
      MqlRates m[];
      ArraySetAsSeries(m, true);
      int got = CopyRates(_Symbol, PERIOD_M15, 1, 200, m);
      for(int k = got - 1; k >= 0; k--)
         if(m[k].time > g_lastTrainedBar)
            ResolvePending(m[k], horizon);
      RefreshAIStatus();
     }
   else
      g_lastTrainedBar = iTime(_Symbol, PERIOD_M15, 1);

   DayKeeper();
   g_execRetry = !TryExecuteArm();
  }

// false = data not ready yet: OnTick retries within the SAME M15 bar (no state was changed)
bool TryExecuteArm()
  {
   if(!g_armed.on)
      return true;
   datetime barOpen = iTime(_Symbol, PERIOD_M15, 1);
   double barClose = iClose(_Symbol, PERIOD_M15, 1);
   if(barOpen == 0 || barClose <= 0.0)
      return false;
   if((long)barOpen > (long)g_armed.expiry)
     {
      g_armed.on = false;
      g_lastBlock = "arm expired (no clean execution)";
      SaveSymbolState();
      return true;
     }
   MqlDateTime gNow, gBar;
   TimeToStruct((datetime)((long)iTime(_Symbol, PERIOD_M15, 0) - JzServerOffsetAt(iTime(_Symbol, PERIOD_M15, 0))), gNow);
   TimeToStruct((datetime)((long)barOpen - JzServerOffsetAt(barOpen)), gBar);
   if(g_noEntryHour[gNow.hour])
     { g_lastBlock = "rollover hours"; return true; }
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk) || tk.bid <= 0.0 || tk.ask <= 0.0)
     { g_lastBlock = "no tick"; return false; }
   JzCtx c;
   if(!LiveCtx(c))
     { g_lastBlock = "context not ready"; return false; }
   double spread = tk.ask - tk.bid;
   if(spread > InpExecSpreadATR * c.h1Atr)
     { g_lastBlock = "spread too wide for execution"; return true; }
   int orig = InpInverseMode ? -g_armed.dir : g_armed.dir;
   bool beyond = (orig > 0) ? (barClose > g_armed.level) : (barClose < g_armed.level);
   if(!beyond)
     { g_lastBlock = "breakout not holding"; return true; }

   // ---- clean execution point reached: learner sample (traded or not) ----
   int d = g_armed.dir;
   bool newSample = !g_armed.sampled;
   g_armed.on = false;
   g_armed.sampled = true;
   SaveSymbolState();
   double entryRef = (d > 0) ? tk.ask : tk.bid;
   double R = InpSL_ATR * c.d1Atr;
   JzSample smp;
   smp.dir = d;
   smp.entry = entryRef;
   smp.slDist = R;
   Features(c, d, barClose, gBar.hour, spread, smp.x);
   smp.entryBar = iTime(_Symbol, PERIOD_M15, 0);
   smp.barsSeen = 0;
   double p = ModelProb(smp.x);
   smp.pAtCreation = p;
   g_lastProb = p;
   if(InpAIMode != JZ_AI_OFF && newSample)
      PendingPush(smp);

   // ---- gates ----
   if(g_tradesDayKey != g_dayKey)
     {
      g_tradesDayKey = g_dayKey;
      g_tradesToday = 0;
     }
   if(g_state != JZ_ST_ACTIVE)
     { g_lastBlock = StateName(g_state); return true; }
   if(InpDirection == JZ_DIR_BUY_ONLY && d < 0)
     { g_lastBlock = "direction filter"; return true; }
   if(InpDirection == JZ_DIR_SELL_ONLY && d > 0)
     { g_lastBlock = "direction filter"; return true; }
   if(HasAnySymbolPosition())
     { g_lastBlock = "position open (no hedge/grid)"; return true; }
   if(CountMagicPositions() >= InpMaxOpenPositions)
     { g_lastBlock = "max open positions"; return true; }
   if(g_lastLossClose > 0 && (long)TimeCurrent() - (long)g_lastLossClose < InpRevengeCooldownSec)
     { g_lastBlock = "revenge cooldown"; return true; }
   if(NewsBlocked())
     { ArmKeep("news blackout"); return true; }
   if(g_aiActive && p < InpMinProb)
     { g_lastBlock = StringFormat("AI veto p=%.3f (AUC %.3f)", p, g_lastAUC); return true; }
   int verdict = OpenAIVerdict(c, d, p);
   if(verdict == 0)
     { g_lastBlock = "OpenAI veto"; return true; }
   if(verdict < 0 && !InpOpenAIFailOpen)
     { ArmKeep("OpenAI unavailable"); return true; }

   if(!JzEntryLock())
     { ArmKeep("entry lock busy"); return true; }
   ShieldUpdate();
   if(g_state != JZ_ST_ACTIVE || HasAnySymbolPosition() || CountMagicPositions() >= InpMaxOpenPositions)
     { JzEntryUnlock(); g_lastBlock = StateName(g_state); return true; }
   double riskMoney;
   double lots = SizeLots(d, entryRef, entryRef - d * R, p, riskMoney);
   if(lots <= 0.0)
     { JzEntryUnlock(); g_lastBlock = "size below min / no budget"; return true; }
   string cmt = StringFormat("%s|D1BO|R=%d", InpComment, (int)MathRound(R / g_point));
   ulong posId;
   double fill;
   bool sent = SendMarket(d, lots, R, cmt, posId, fill);
   JzEntryUnlock();
   if(!sent)
     { ArmKeep("order rejected"); return true; }
   if(posId > 0)
     {
      GVSet(PosKey(posId, "R"), R);
      GVSet(PosKey(posId, "V"), lots);
      GVSet(PosKey(posId, "L"), 0.0);
      GVSet(PosKey(posId, "RM"), riskMoney);
      GVSet(PosKey(posId, "P"), p);
      GVSet(PosKey(posId, "E"), fill);
     }
   g_lastEntryBar = barOpen;
   g_tradesToday++;
   g_lastLots = lots;
   SaveSymbolState();
   g_lastBlock = "TRADED";
   JzLog(1, StringFormat("OPEN %s D1 breakout %.2f lots @%s  stop %.1f pts (%.2f x ATR D1)  risk %.2f  p=%.3f  AI %s  state=%s",
                         d > 0 ? "BUY" : "SELL", lots, DoubleToString(fill, g_digits), R / g_point, InpSL_ATR, riskMoney, p,
                         g_aiActive ? "ACTIVE" : "observing", StateName(g_state)));
   return true;
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   if(!InpShowPanel || (g_isTester && !g_isVisual))
      return;
   int x = InpPanelX, y = InpPanelY, lh = 15, w = 340;
   string bg = JZ_PFX_OBJ + "BG";
   if(ObjectFind(0, bg) < 0)
     {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'12,16,28');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, C'255,196,0');
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x - 6);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y - 6);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, lh * JZ_PANEL_ROWS + 58);

   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double init = MathMax(g_initCap, 1.0);
   color gold = C'255,196,0', txt = C'220,226,240', dim = C'140,150,170';
   color stc = (g_state == JZ_ST_ACTIVE) ? clrLime : ((g_state == JZ_ST_HARD_HALT_DAY || g_state == JZ_ST_HARD_HALT_TOTAL) ? clrRed : clrOrange);
   double winRate = (g_closedTrades > 0) ? 100.0 * g_wins / g_closedTrades : 0.0;
   double expR = (g_closedTrades > 0) ? g_sumR / g_closedTrades : 0.0;
   string aiMode = (InpAIMode == JZ_AI_OFF) ? "OFF" : (InpAIMode == JZ_AI_OBSERVE ? "OBSERVE" : (InpAIMode == JZ_AI_ALWAYS ? "ALWAYS" : "SELF-VALIDATING"));

   string rows[JZ_PANEL_ROWS];
   color cols[JZ_PANEL_ROWS];
   int i = 0;
   rows[i] = "JAZZYLYFE  AUTOTRADER  AI   v2.00";                                                 cols[i++] = gold;
   rows[i] = "by JAZZYLYFE / Brimberry LLC";                                                      cols[i++] = dim;
   rows[i] = "State      " + StateName(g_state);                                                   cols[i++] = stc;
   rows[i] = "Program    " + g_rules.name + (InpFTMOType == JZ_FTMO_SWING ? " (Swing)" : " (Standard)"); cols[i++] = txt;
   rows[i] = StringFormat("Equity     %.2f   Bal %.2f", eq, bal);                                  cols[i++] = txt;
   rows[i] = StringFormat("P/L        %+.2f%% of initial %.0f", (eq - init) / init * 100.0, init);   cols[i++] = txt;
   rows[i] = StringFormat("Daily used %.0f%% of %.1f%% limit", g_dailyUsed * 100.0, g_rules.dailyPct); cols[i++] = (g_dailyUsed >= InpSoftFrac) ? clrOrange : txt;
   rows[i] = StringFormat("Total used %.0f%% of %.1f%% limit", g_totalUsed * 100.0, g_rules.totalPct); cols[i++] = (g_totalUsed >= InpSoftFrac) ? clrOrange : txt;
   rows[i] = StringFormat("Risk budget %.2f  open risk %.2f", g_budgetMoney, g_openRiskMoney);     cols[i++] = txt;
   rows[i] = StringFormat("Target %.1f%%   Trading days %d/%d", g_rules.targetPct, g_tradingDays, g_rules.minDays); cols[i++] = txt;
   rows[i] = "------------------- ENGINE --------------------";                                    cols[i++] = dim;
   rows[i] = StringFormat("D1 bias    %s", g_lastBias > 0 ? "LONG" : (g_lastBias < 0 ? "SHORT" : "FLAT"));  cols[i++] = txt;
   rows[i] = "Signal     " + g_lastSignal;                                                         cols[i++] = txt;
   rows[i] = "Last gate  " + g_lastBlock;                                                          cols[i++] = dim;
   rows[i] = StringFormat("AI %s  %s  n=%I64d", aiMode, g_aiActive ? "ACTIVE" : "observing", g_modelN); cols[i++] = g_aiActive ? clrLime : txt;
   rows[i] = StringFormat("AUC %.3f (need %.2f)  last p %s", g_lastAUC, InpAIMinAUC, g_lastProb < 0 ? "-" : DoubleToString(g_lastProb, 3)); cols[i++] = txt;
   rows[i] = "------------------- RESULTS -------------------";                                    cols[i++] = dim;
   rows[i] = StringFormat("Trades %d  Win %.0f%%  Exp %+.2fR", g_closedTrades, winRate, expR);     cols[i++] = txt;
   rows[i] = StringFormat("Loss streak %d  damp x%.2f", g_lossStreak, MathMax(InpStreakFloor, MathPow(InpStreakDamp, g_lossStreak))); cols[i++] = txt;
   rows[i] = StringFormat("Inverse %s  Dir %s  Weekend flat %s", InpInverseMode ? "ON" : "off",
                          InpDirection == JZ_DIR_BOTH ? "BOTH" : (InpDirection == JZ_DIR_BUY_ONLY ? "BUY" : "SELL"),
                          (InpFridayFlat || g_forceFridayFlat) ? "ON" : "off");                   cols[i++] = txt;
   rows[i] = "Lots (fixed mode):";                                                                 cols[i++] = dim;
   rows[i] = "";                                                                                   cols[i++] = dim;
   for(int k = 0; k < JZ_PANEL_ROWS; k++)
      PanelLabel(JZ_PFX_OBJ + "L" + IntegerToString(k), x, y + k * lh, rows[k], cols[k], (k == 0) ? 10 : 8);

   int by = y + (JZ_PANEL_ROWS - 2) * lh - 2;
   string ed = JZ_PFX_OBJ + "LOTS";
   if(ObjectFind(0, ed) < 0)
     {
      ObjectCreate(0, ed, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, ed, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, ed, OBJPROP_XSIZE, 70);
      ObjectSetInteger(0, ed, OBJPROP_YSIZE, 18);
      ObjectSetInteger(0, ed, OBJPROP_HIDDEN, true);
      ObjectSetString(0, ed, OBJPROP_TEXT, DoubleToString(InpFixedLots, 2));
      ObjectSetInteger(0, ed, OBJPROP_BGCOLOR, C'30,36,52');
      ObjectSetInteger(0, ed, OBJPROP_COLOR, clrWhite);
     }
   ObjectSetInteger(0, ed, OBJPROP_XDISTANCE, x + 140);
   ObjectSetInteger(0, ed, OBJPROP_YDISTANCE, by);
   PanelButton(JZ_PFX_OBJ + "PAUSE", x, by + 24, 155, 22, g_paused ? "RESUME TRADING" : "PAUSE NEW ENTRIES", g_paused ? C'0,110,60' : C'120,90,0');
   PanelButton(JZ_PFX_OBJ + "FLAT", x + 167, by + 24, 155, 22, "FLATTEN THIS EA", C'150,20,30');
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);
   g_isVisual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(IsBannedSymbol())
     {
      Alert("JAZZYLYFE AutoTrader AI: ", _Symbol, " is a banned symbol. EA will not run.");
      return INIT_FAILED;
     }
   if(InpSoftFrac <= 0.0 || InpHardFrac <= InpSoftFrac || InpHardFrac >= 1.0)
     {
      Alert("JAZZYLYFE AutoTrader AI: require 0 < SoftFrac < HardFrac < 1.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxRiskPct <= 0.0 || InpMaxRiskPct > 2.0 || InpBaseRiskPct <= 0.0 || InpBaseRiskPct > InpMaxRiskPct)
     {
      Alert("JAZZYLYFE AutoTrader AI: risk inputs out of bounds (0 < base <= max <= 2%).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTP1_R <= 0.0 || InpTP2_R <= InpTP1_R || InpTP1_Frac + InpTP2_Frac >= 1.0 || InpLock2_R < 0.0 || InpLock2_R >= InpTP2_R ||
      InpSL_ATR <= 0.0 || InpTrail_ATR <= 0.0 || InpMaxHoldDays < 1 || InpDonchianDays < 5 || InpMomDays < 5 ||
      InpATRDays < 2 || InpExecWindowHours < 1 || InpMinProb <= 0.0 || InpMinProb >= 1.0 || InpAIWindow < 20 || InpAIWindow > JZ_AUC_MAX)
     {
      Alert("JAZZYLYFE AutoTrader AI: strategy / exit / AI inputs out of bounds.");
      return INIT_PARAMETERS_INCORRECT;
     }

   ResolveRules();
   ParseNoEntryHours();
   bool funded = (InpProgram == JZ_FTMO_2STEP_FUNDED || InpProgram == JZ_FTMO_1STEP_FUNDED);
   g_forceFridayFlat = (InpFTMOType == JZ_FTMO_STANDARD && funded);
   g_newsForced = (InpFTMOType == JZ_FTMO_STANDARD && funded);
   g_acctPfx = "JZA_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_";
   string sym = _Symbol;
   StringReplace(sym, ".", "_");
   g_symPfx = "JZS2_" + IntegerToString((long)InpMagic) + "_" + sym + "_";
   LoadShieldState();
   LoadSymbolState();
   RecountTradingDays();
   SaveShieldState();

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   hD1_EMA50  = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_EMA, PRICE_CLOSE);
   hD1_EMA200 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hD1_ATR    = iATR(_Symbol, PERIOD_D1, InpATRDays);
   hD1_ADX    = iADXWilder(_Symbol, PERIOD_D1, 14);
   hH4_EMA20  = iMA(_Symbol, PERIOD_H4, 20, 0, MODE_EMA, PRICE_CLOSE);
   hH4_EMA50  = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   hH4_ADX    = iADXWilder(_Symbol, PERIOD_H4, 14);
   hH1_RSI    = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);
   hH1_ATR    = iATR(_Symbol, PERIOD_H1, 14);
   if(hD1_EMA50 == INVALID_HANDLE || hD1_EMA200 == INVALID_HANDLE || hD1_ATR == INVALID_HANDLE || hD1_ADX == INVALID_HANDLE ||
      hH4_EMA20 == INVALID_HANDLE || hH4_EMA50 == INVALID_HANDLE || hH4_ADX == INVALID_HANDLE ||
      hH1_RSI == INVALID_HANDLE || hH1_ATR == INVALID_HANDLE)
     {
      Print("JZ-AI: failed to create indicator handles, error ", GetLastError());
      return INIT_FAILED;
     }

   // EA globals survive parameter/chart re-init: reset learner + event state explicitly
   ArrayInitialize(g_w, 0.0);
   ArrayInitialize(g_aucP, 0.5);
   ArrayInitialize(g_aucY, 0);
   g_modelN = 0;
   g_brier = 0.25;
   g_lastTrainedBar = 0;
   g_bootstrapped = false;
   g_updatesSinceSave = 0;
   g_aucCount = 0;
   g_aucHead = 0;
   g_aiActive = false;
   g_lastM15Bar = 0;
   g_lastH1Bar = 0;
   g_lastD1Bar = 0;
   ArrayResize(g_pending, 256);
   g_pendingCount = 0;
   g_modelReady = false;
   g_flipPending = false;
   g_bootFrom = 0;
   g_eaStart = TimeCurrent();
   if(LoadModel())
     {
      g_modelReady = true;         // bootstrap still runs: it only replays D1 closes after the saved lastTrainedBar
      RefreshAIStatus();
      g_bootFrom = g_lastTrainedBar;
      JzLog(1, StringFormat("Model loaded: n=%I64d AUC=%.3f active=%s", g_modelN, g_lastAUC, g_aiActive ? "yes" : "no"));
     }

   if(!g_isTester)
      EventSetTimer(1);
   ShieldUpdate();
   JzLog(1, StringFormat("INIT v2.00 %s | initial %.2f | daily %.1f%% total %.1f%% target %.1f%% | magic %I64d | author JAZZYLYFE",
                         g_rules.name, g_initCap, g_rules.dailyPct, g_rules.totalPct, g_rules.targetPct, InpMagic));
   if(InpInitialCapital <= 0.0)
      JzLog(0, "WARNING: initial capital auto-detected. Set InpInitialCapital to your challenge size for exact limits.");
   if(g_forceFridayFlat)
      JzLog(0, "FTMO Standard funded account: weekend flatten and 2-minute news blackout are ENFORCED.");
   DrawPanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   SaveModel();
   SaveShieldState();
   SaveSymbolState();
   int handles[9];
   handles[0] = hD1_EMA50;
   handles[1] = hD1_EMA200;
   handles[2] = hD1_ATR;
   handles[3] = hD1_ADX;
   handles[4] = hH4_EMA20;
   handles[5] = hH4_EMA50;
   handles[6] = hH4_ADX;
   handles[7] = hH1_RSI;
   handles[8] = hH1_ATR;
   for(int i = 0; i < 9; i++)
      if(handles[i] != INVALID_HANDLE)
         IndicatorRelease(handles[i]);
   ObjectsDeleteAll(0, JZ_PFX_OBJ);
   ChartRedraw(0);
  }

void OnTick()
  {
   ShieldUpdate();                  // 1. compliance first, always
   ManagePositions();               // 2. open risk managed in EVERY state

   if(!g_bootstrapped)
      Bootstrap();                  // AI never blocks trading: the rule engine runs regardless

   datetime d1 = iTime(_Symbol, PERIOD_D1, 0);
   datetime h1 = iTime(_Symbol, PERIOD_H1, 0);
   datetime m15 = iTime(_Symbol, PERIOD_M15, 0);
   if(d1 == 0 || h1 == 0 || m15 == 0)
      return;
   static datetime lastD1Try = 0, lastH1Try = 0, lastFlipTry = 0;
   if(d1 != g_lastD1Bar && TimeCurrent() != lastD1Try)
     {
      lastD1Try = TimeCurrent();
      if(OnNewD1(g_lastD1Bar == 0))
         g_lastD1Bar = d1;                                  // only a processed D1 close is marked done
     }
   if(g_flipPending && (long)TimeCurrent() - (long)lastFlipTry >= 5)
     {
      lastFlipTry = TimeCurrent();
      DoBiasExits();
     }
   if(h1 != g_lastH1Bar && TimeCurrent() != lastH1Try)
     {
      lastH1Try = TimeCurrent();
      if(OnNewH1())                                         // idempotent: safe on the first tick too
         g_lastH1Bar = h1;
     }
   static datetime lastExecTry = 0;
   if(m15 != g_lastM15Bar)
     {
      bool firstM15 = (g_lastM15Bar == 0);
      g_lastM15Bar = m15;
      g_execRetry = false;
      if(!firstM15)
        {
         ShieldUpdate();
         lastExecTry = TimeCurrent();
         OnNewM15();
        }
     }
   else
      if(g_execRetry && TimeCurrent() != lastExecTry)
        {
         lastExecTry = TimeCurrent();
         g_execRetry = !TryExecuteArm();
        }
   if(g_isTester && !g_isVisual)
      return;
   DrawPanel();
  }

void OnTimer()
  {
   ShieldUpdate();
   ManagePositions();
   DrawPanel();
  }

//+------------------------------------------------------------------+
//| Trade transactions: R per trade, streaks, trading days           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long dtype = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
      return;

   if(entry == DEAL_ENTRY_IN)
     {
      datetime srv = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      int k = JzDayKey((datetime)((long)srv - JzServerOffsetSec()));
      if(k != g_lastCountedDay)
        {
         g_lastCountedDay = k;
         g_tradingDays++;
         SaveShieldState();
        }
      return;
     }
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   ulong posId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(!HistorySelectByPosition((long)posId))
      return;
   double pnl = 0.0, vin = 0.0, vout = 0.0;
   bool dayKeeper = false, ours = false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong dl = HistoryDealGetTicket(i);
      if(dl == 0)
         continue;
      double v = HistoryDealGetDouble(dl, DEAL_VOLUME);
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dl, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         vin += v;
         if(HistoryDealGetInteger(dl, DEAL_MAGIC) == InpMagic)   // ownership from the OPENING deal
            ours = true;
        }
      else
         vout += v;
      pnl += HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) +
             HistoryDealGetDouble(dl, DEAL_COMMISSION) + HistoryDealGetDouble(dl, DEAL_FEE);
      if(StringFind(HistoryDealGetString(dl, DEAL_COMMENT), "|DK") >= 0)
         dayKeeper = true;
     }
   if(!ours || vout + 1e-8 < vin)
      return;                                        // not ours, or partial close: one R per trade
   double rm = GVGet(PosKey(posId, "RM"), 0.0);
   PosCleanup(posId);
   if(dayKeeper || rm <= 0.0)
      return;
   double R = pnl / rm;
   g_closedTrades++;
   g_sumR += R;
   if(pnl > 0.0)
     {
      g_wins++;
      g_sumWinR += R;
      g_lossStreak = 0;
      g_lastWasLoss = false;
     }
   else
     {
      g_sumLossR += R;
      g_lossStreak++;
      g_lastWasLoss = true;
      g_lastLossClose = TimeCurrent();
     }
   SaveSymbolState();
   JzLog(1, StringFormat("CLOSED position %I64u  P/L %.2f  R %+.2f  streak %d  trades %d", posId, pnl, R, g_lossStreak, g_closedTrades));
  }

//+------------------------------------------------------------------+
//| Chart events: panel controls                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == JZ_PFX_OBJ + "PAUSE")
        {
         g_paused = !g_paused;
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         JzLog(1, g_paused ? "Paused by user (positions still managed)" : "Resumed by user");
         ShieldUpdate();
         DrawPanel();
        }
      else
         if(sparam == JZ_PFX_OBJ + "FLAT")
           {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            FlattenAll(false, "user button");
           }
     }
   else
      if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == JZ_PFX_OBJ + "LOTS")
        {
         double v = StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT));
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         g_manualLots = (v >= vmin) ? NormLotsDown(v) : 0.0;
         ObjectSetString(0, sparam, OBJPROP_TEXT, DoubleToString(g_manualLots > 0.0 ? g_manualLots : InpFixedLots, 2));
         JzLog(1, StringFormat("Fixed lots set to %.2f", g_manualLots));
        }
  }

//+------------------------------------------------------------------+
//| Tester criterion: expectancy x sqrt(trades), penalised by DD     |
//+------------------------------------------------------------------+
double OnTester()
  {
   double ddPct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(g_closedTrades < 30)
      return 0.0;
   double expR = g_sumR / g_closedTrades;
   return expR * MathSqrt((double)g_closedTrades) / (1.0 + ddPct / 10.0);
  }
//+------------------------------------------------------------------+
//| END — JAZZYLYFE / Brimberry LLC                                  |
//+------------------------------------------------------------------+
