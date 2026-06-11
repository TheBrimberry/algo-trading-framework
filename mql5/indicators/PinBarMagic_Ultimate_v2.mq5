//+------------------------------------------------------------------+
//|                                       PinBarMagic_Ultimate_v2.mq5 |
//|                                              Author: JazzyLyfe    |
//|                                   https://github.com/jazzylyfe    |
//|                                         Grade: A++ Professional   |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2025, JazzyLyfe Trading Systems"
#property link        "https://github.com/jazzylyfe"
#property version     "2.00"
#property description "═══════════════════════════════════════════════"
#property description "   PINBAR MAGIC ULTIMATE v2.0 - Grade A++      "
#property description "═══════════════════════════════════════════════"
#property description "Advanced PinBar Detection with SMC Integration"
#property description "ICT Kill Zones • MTF Confirmation • Dashboard  "
#property description "═══════════════════════════════════════════════"
#property indicator_chart_window
#property indicator_buffers 16
#property indicator_plots   8

//--- Plot 1: Bullish PinBar (Strong)
#property indicator_label1  "Strong Bullish PinBar"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  4

//--- Plot 2: Bearish PinBar (Strong)
#property indicator_label2  "Strong Bearish PinBar"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

//--- Plot 3: Bullish PinBar (Weak)
#property indicator_label3  "Weak Bullish PinBar"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- Plot 4: Bearish PinBar (Weak)
#property indicator_label4  "Weak Bearish PinBar"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrOrange
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

//--- Plot 5: Buy Signal (Entry Point)
#property indicator_label5  "BUY Signal"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrGold
#property indicator_style5  STYLE_SOLID
#property indicator_width5  5

//--- Plot 6: Sell Signal (Entry Point)
#property indicator_label6  "SELL Signal"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrMagenta
#property indicator_style6  STYLE_SOLID
#property indicator_width6  5

//--- Plot 7: Stop Loss Level
#property indicator_label7  "Stop Loss"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrCrimson
#property indicator_style7  STYLE_SOLID
#property indicator_width7  1

//--- Plot 8: Take Profit Level
#property indicator_label8  "Take Profit"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrSpringGreen
#property indicator_style8  STYLE_SOLID
#property indicator_width8  1

//+------------------------------------------------------------------+
//| INCLUDES                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                      |
//+------------------------------------------------------------------+
enum ENUM_PINBAR_STRENGTH
{
   PINBAR_NONE = 0,       // No PinBar
   PINBAR_WEAK = 1,       // Weak PinBar
   PINBAR_MODERATE = 2,   // Moderate PinBar
   PINBAR_STRONG = 3      // Strong PinBar (A+ Setup)
};

enum ENUM_TREND_DIRECTION
{
   TREND_NONE = 0,        // No Clear Trend
   TREND_BULLISH = 1,     // Bullish Trend
   TREND_BEARISH = -1     // Bearish Trend
};

enum ENUM_MARKET_SESSION
{
   SESSION_ASIAN = 0,     // Asian Session
   SESSION_LONDON = 1,    // London Session
   SESSION_NEWYORK = 2,   // New York Session
   SESSION_OVERLAP = 3,   // London/NY Overlap
   SESSION_NONE = 4       // No Active Session
};

enum ENUM_SMC_ZONE
{
   SMC_NONE = 0,          // No SMC Zone
   SMC_ORDER_BLOCK = 1,   // Order Block
   SMC_FVG = 2,           // Fair Value Gap
   SMC_LIQUIDITY = 3,     // Liquidity Zone
   SMC_BREAKER = 4        // Breaker Block
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "═══════════ PINBAR DETECTION SETTINGS ═══════════"
input double   InpNoseRatio        = 0.33;        // Max Nose/Body Ratio
input double   InpWickRatio        = 2.0;         // Min Wick/Body Ratio
input double   InpBodyRatio        = 0.35;        // Max Body/Candle Ratio
input double   InpMinWickPips      = 10.0;        // Min Wick Size (Pips)
input bool     InpRequireEngulf    = false;       // Require Body Engulfment
input bool     InpCloseBeyondMid   = true;        // Close Beyond Midpoint

input group "═══════════ TREND FILTER SETTINGS ═══════════"
input bool     InpUseTrendFilter   = true;        // Enable Trend Filter
input int      InpFastMAPeriod     = 21;          // Fast MA Period
input int      InpSlowMAPeriod     = 50;          // Slow MA Period
input int      InpTrendMAPeriod    = 200;         // Trend MA Period
input ENUM_MA_METHOD InpMAMethod   = MODE_EMA;    // MA Method

input group "═══════════ SMC (SMART MONEY CONCEPTS) ═══════════"
input bool     InpUseSMC           = true;        // Enable SMC Analysis
input int      InpOrderBlockLook   = 20;          // Order Block Lookback
input int      InpFVGLookback      = 10;          // FVG Lookback
input double   InpFVGMinSize       = 5.0;         // Min FVG Size (Pips)
input bool     InpShowOrderBlocks  = true;        // Show Order Blocks
input bool     InpShowFVG          = true;        // Show Fair Value Gaps
input bool     InpShowLiquidity    = true;        // Show Liquidity Zones
input color    InpBullishOBColor   = clrDodgerBlue; // Bullish OB Color
input color    InpBearishOBColor   = clrOrangeRed;  // Bearish OB Color
input color    InpFVGColor         = clrGold;       // FVG Color

input group "═══════════ ICT KILL ZONES ═══════════"
input bool     InpUseKillZones     = true;        // Enable Kill Zone Filter
input int      InpAsianStart       = 0;           // Asian Start (Server Hour)
input int      InpAsianEnd         = 8;           // Asian End (Server Hour)
input int      InpLondonStart      = 7;           // London Start (Server Hour)
input int      InpLondonEnd        = 16;          // London End (Server Hour)
input int      InpNYStart          = 12;          // NY Start (Server Hour)
input int      InpNYEnd            = 21;          // NY End (Server Hour)
input bool     InpLondonKillZone   = true;        // Trade London Kill Zone (7-9)
input bool     InpNYKillZone       = true;        // Trade NY Kill Zone (12-14)
input bool     InpOverlapKillZone  = true;        // Trade Overlap (12-16)

input group "═══════════ MULTI-TIMEFRAME CONFIRMATION ═══════════"
input bool     InpUseMTF           = true;        // Enable MTF Confirmation
input ENUM_TIMEFRAMES InpHTF1      = PERIOD_H4;   // Higher TF 1
input ENUM_TIMEFRAMES InpHTF2      = PERIOD_D1;   // Higher TF 2
input bool     InpRequireHTFAlign  = true;        // Require HTF Trend Alignment

input group "═══════════ SIGNAL QUALITY FILTERS ═══════════"
input int      InpMinPinBarsConf   = 1;           // Min Confirmation Bars
input double   InpMinRiskReward    = 2.0;         // Min Risk:Reward Ratio
input bool     InpFilterByATR      = true;        // Filter by ATR Volatility
input int      InpATRPeriod        = 14;          // ATR Period
input double   InpATRMultiplier    = 1.5;         // ATR Multiplier for SL

input group "═══════════ DASHBOARD SETTINGS ═══════════"
input bool     InpShowDashboard    = true;        // Show Dashboard
input int      InpDashboardX       = 20;          // Dashboard X Position
input int      InpDashboardY       = 50;          // Dashboard Y Position
input color    InpDashBGColor      = C'25,25,35'; // Dashboard BG Color
input color    InpDashTextColor    = clrWhite;    // Dashboard Text Color
input int      InpDashFontSize     = 9;           // Dashboard Font Size

input group "═══════════ ALERT SETTINGS ═══════════"
input bool     InpEnableAlerts     = true;        // Enable Alerts
input bool     InpAlertPopup       = true;        // Popup Alert
input bool     InpAlertSound       = true;        // Sound Alert
input bool     InpAlertPush        = false;       // Push Notification
input bool     InpAlertEmail       = false;       // Email Alert
input string   InpAlertSound_Buy   = "alert.wav"; // Buy Alert Sound
input string   InpAlertSound_Sell  = "alert2.wav";// Sell Alert Sound

input group "═══════════ VISUAL SETTINGS ═══════════"
input int      InpArrowOffset      = 10;          // Arrow Offset (Points)
input bool     InpShowSLTP         = true;        // Show SL/TP Levels
input bool     InpShowEntryZone    = true;        // Show Entry Zone
input color    InpEntryZoneColor   = clrYellow;   // Entry Zone Color

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
//--- Indicator Buffers
double BullStrongBuffer[];
double BearStrongBuffer[];
double BullWeakBuffer[];
double BearWeakBuffer[];
double BuySignalBuffer[];
double SellSignalBuffer[];
double StopLossBuffer[];
double TakeProfitBuffer[];

//--- Internal Buffers
double TrendBuffer[];
double ATRBuffer[];
double FastMABuffer[];
double SlowMABuffer[];
double TrendMABuffer[];
double StrengthBuffer[];
double HTF1TrendBuffer[];
double HTF2TrendBuffer[];

//--- Handles
int HandleFastMA;
int HandleSlowMA;
int HandleTrendMA;
int HandleATR;
int HandleHTF1MA;
int HandleHTF2MA;

//--- Dashboard Objects
string DashboardPrefix = "PBM_DASH_";

//--- Statistics
int TotalBullish = 0;
int TotalBearish = 0;
int StrongSignals = 0;
datetime LastAlertTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set indicator buffers
   SetIndexBuffer(0, BullStrongBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BearStrongBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, BullWeakBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, BearWeakBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, SellSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, StopLossBuffer, INDICATOR_DATA);
   SetIndexBuffer(7, TakeProfitBuffer, INDICATOR_DATA);
   
   SetIndexBuffer(8, TrendBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, ATRBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, FastMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, SlowMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, TrendMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, StrengthBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, HTF1TrendBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, HTF2TrendBuffer, INDICATOR_CALCULATIONS);
   
   //--- Set arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // Up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // Down arrow
   PlotIndexSetInteger(2, PLOT_ARROW, 241);  // Small up
   PlotIndexSetInteger(3, PLOT_ARROW, 242);  // Small down
   PlotIndexSetInteger(4, PLOT_ARROW, 225);  // Buy signal
   PlotIndexSetInteger(5, PLOT_ARROW, 226);  // Sell signal
   PlotIndexSetInteger(6, PLOT_ARROW, 251);  // SL marker
   PlotIndexSetInteger(7, PLOT_ARROW, 252);  // TP marker
   
   //--- Set empty values
   for(int i = 0; i < 8; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   //--- Create indicator handles
   HandleFastMA = iMA(_Symbol, PERIOD_CURRENT, InpFastMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   HandleSlowMA = iMA(_Symbol, PERIOD_CURRENT, InpSlowMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   HandleTrendMA = iMA(_Symbol, PERIOD_CURRENT, InpTrendMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   HandleATR = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   
   if(InpUseMTF)
   {
      HandleHTF1MA = iMA(_Symbol, InpHTF1, InpTrendMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
      HandleHTF2MA = iMA(_Symbol, InpHTF2, InpTrendMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   }
   
   //--- Validate handles
   if(HandleFastMA == INVALID_HANDLE || HandleSlowMA == INVALID_HANDLE ||
      HandleTrendMA == INVALID_HANDLE || HandleATR == INVALID_HANDLE)
   {
      Print("❌ Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   //--- Create dashboard
   if(InpShowDashboard)
      CreateDashboard();
   
   //--- Set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, "🎯 PinBar Magic Ultimate v2.0");
   
   Print("═══════════════════════════════════════════════════");
   Print("   🎯 PINBAR MAGIC ULTIMATE v2.0 INITIALIZED       ");
   Print("   Author: JazzyLyfe | Grade: A++ Professional     ");
   Print("═══════════════════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release handles
   if(HandleFastMA != INVALID_HANDLE) IndicatorRelease(HandleFastMA);
   if(HandleSlowMA != INVALID_HANDLE) IndicatorRelease(HandleSlowMA);
   if(HandleTrendMA != INVALID_HANDLE) IndicatorRelease(HandleTrendMA);
   if(HandleATR != INVALID_HANDLE) IndicatorRelease(HandleATR);
   if(HandleHTF1MA != INVALID_HANDLE) IndicatorRelease(HandleHTF1MA);
   if(HandleHTF2MA != INVALID_HANDLE) IndicatorRelease(HandleHTF2MA);
   
   //--- Delete dashboard objects
   DeleteDashboard();
   
   //--- Delete SMC objects
   DeleteSMCObjects();
   
   Print("🎯 PinBar Magic Ultimate v2.0 Removed");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Check for minimum bars
   if(rates_total < InpTrendMAPeriod + 10)
      return(0);
   
   //--- Copy indicator data
   int copyBars = rates_total - prev_calculated + 1;
   if(prev_calculated == 0) copyBars = rates_total;
   
   if(CopyBuffer(HandleFastMA, 0, 0, copyBars, FastMABuffer) <= 0) return(0);
   if(CopyBuffer(HandleSlowMA, 0, 0, copyBars, SlowMABuffer) <= 0) return(0);
   if(CopyBuffer(HandleTrendMA, 0, 0, copyBars, TrendMABuffer) <= 0) return(0);
   if(CopyBuffer(HandleATR, 0, 0, copyBars, ATRBuffer) <= 0) return(0);
   
   //--- Copy HTF data if enabled
   if(InpUseMTF)
   {
      CopyBuffer(HandleHTF1MA, 0, 0, copyBars, HTF1TrendBuffer);
      CopyBuffer(HandleHTF2MA, 0, 0, copyBars, HTF2TrendBuffer);
   }
   
   //--- Reset statistics on full recalculation
   if(prev_calculated == 0)
   {
      TotalBullish = 0;
      TotalBearish = 0;
      StrongSignals = 0;
   }

   //--- Calculate start position
   int start = prev_calculated > 0 ? prev_calculated - 1 : InpTrendMAPeriod;
   
   //--- Main calculation loop
   for(int i = start; i < rates_total - 1 && !IsStopped(); i++)
   {
      //--- Initialize buffers
      BullStrongBuffer[i] = EMPTY_VALUE;
      BearStrongBuffer[i] = EMPTY_VALUE;
      BullWeakBuffer[i] = EMPTY_VALUE;
      BearWeakBuffer[i] = EMPTY_VALUE;
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      StopLossBuffer[i] = EMPTY_VALUE;
      TakeProfitBuffer[i] = EMPTY_VALUE;
      
      //--- Get candle data
      double candleOpen = open[i];
      double candleHigh = high[i];
      double candleLow = low[i];
      double candleClose = close[i];
      
      //--- Check Kill Zone if enabled
      if(InpUseKillZones && !IsInKillZone(time[i]))
         continue;
      
      //--- Detect PinBar
      ENUM_PINBAR_STRENGTH bullStrength = DetectBullishPinBar(candleOpen, candleHigh, candleLow, candleClose);
      ENUM_PINBAR_STRENGTH bearStrength = DetectBearishPinBar(candleOpen, candleHigh, candleLow, candleClose);
      
      //--- Get trend direction
      ENUM_TREND_DIRECTION trend = GetTrendDirection(i, close);
      
      //--- Check MTF alignment
      bool mtfAligned = true;
      if(InpUseMTF && InpRequireHTFAlign)
      {
         mtfAligned = CheckMTFAlignment(i, trend);
      }
      
      //--- Check SMC zones
      ENUM_SMC_ZONE smcZone = SMC_NONE;
      if(InpUseSMC)
      {
         smcZone = CheckSMCZone(i, open, high, low, close, time);
      }
      
      //--- Calculate signal quality score
      double qualityScore = CalculateQualityScore(bullStrength > PINBAR_NONE ? bullStrength : bearStrength, 
                                                   trend, mtfAligned, smcZone, i);
      
      //--- Plot signals based on strength and filters
      double offset = InpArrowOffset * _Point;
      
      //--- Bullish PinBar
      if(bullStrength > PINBAR_NONE)
      {
         //--- Check trend filter
         if(!(InpUseTrendFilter && trend == TREND_BEARISH))
         {
         if(bullStrength >= PINBAR_STRONG && mtfAligned)
         {
            BullStrongBuffer[i] = candleLow - offset;
            
            //--- Strong signal - show entry
            if(qualityScore >= 70)
            {
               BuySignalBuffer[i] = candleLow - offset * 2;
               
               //--- Calculate SL/TP
               if(InpShowSLTP)
               {
                  double sl = candleLow - ATRBuffer[i] * InpATRMultiplier;
                  double tp = candleClose + (candleClose - sl) * InpMinRiskReward;
                  StopLossBuffer[i] = sl;
                  TakeProfitBuffer[i] = tp;
               }
               
               //--- Send alert
               if(InpEnableAlerts && i == rates_total - 2)
                  SendAlert("🟢 STRONG BUY SIGNAL", candleClose, time[i], qualityScore);
               
               StrongSignals++;
            }
            TotalBullish++;
         }
         else if(bullStrength >= PINBAR_WEAK)
         {
            BullWeakBuffer[i] = candleLow - offset;
            TotalBullish++;
         }
         }
      }

      //--- Bearish PinBar
      if(bearStrength > PINBAR_NONE)
      {
         //--- Check trend filter
         if(!(InpUseTrendFilter && trend == TREND_BULLISH))
         {
         if(bearStrength >= PINBAR_STRONG && mtfAligned)
         {
            BearStrongBuffer[i] = candleHigh + offset;
            
            //--- Strong signal - show entry
            if(qualityScore >= 70)
            {
               SellSignalBuffer[i] = candleHigh + offset * 2;
               
               //--- Calculate SL/TP
               if(InpShowSLTP)
               {
                  double sl = candleHigh + ATRBuffer[i] * InpATRMultiplier;
                  double tp = candleClose - (sl - candleClose) * InpMinRiskReward;
                  StopLossBuffer[i] = sl;
                  TakeProfitBuffer[i] = tp;
               }
               
               //--- Send alert
               if(InpEnableAlerts && i == rates_total - 2)
                  SendAlert("🔴 STRONG SELL SIGNAL", candleClose, time[i], qualityScore);
               
               StrongSignals++;
            }
            TotalBearish++;
         }
         else if(bearStrength >= PINBAR_WEAK)
         {
            BearWeakBuffer[i] = candleHigh + offset;
            TotalBearish++;
         }
         }
      }
      
      //--- Store strength for later use
      StrengthBuffer[i] = MathMax((int)bullStrength, (int)bearStrength);
   }
   
   //--- Update dashboard
   if(InpShowDashboard)
      UpdateDashboard(rates_total, time, close);
   
   //--- Draw SMC objects
   if(InpUseSMC)
      DrawSMCObjects(rates_total, time, open, high, low, close);
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Detect Bullish PinBar (Hammer)                                    |
//+------------------------------------------------------------------+
ENUM_PINBAR_STRENGTH DetectBullishPinBar(double open, double high, double low, double close)
{
   double candleRange = high - low;
   if(candleRange <= 0) return PINBAR_NONE;
   
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   //--- Check minimum wick size
   double minWick = InpMinWickPips * _Point * 10;
   if(lowerWick < minWick) return PINBAR_NONE;
   
   //--- Check body/candle ratio
   double bodyRatio = body / candleRange;
   if(bodyRatio > InpBodyRatio) return PINBAR_NONE;
   
   //--- Check wick/body ratio
   double wickBodyRatio = body > 0 ? lowerWick / body : 999;
   if(wickBodyRatio < InpWickRatio) return PINBAR_NONE;
   
   //--- Check nose (upper wick) ratio
   if(body > 0)
   {
      double noseRatio = upperWick / body;
      if(noseRatio > InpNoseRatio * candleRange / body) return PINBAR_NONE;
   }
   else
   {
      if(upperWick > candleRange * InpNoseRatio) return PINBAR_NONE;
   }

   //--- Check close beyond midpoint
   if(InpCloseBeyondMid)
   {
      double midpoint = (high + low) / 2;
      if(close < midpoint) return PINBAR_NONE;
   }
   
   //--- Determine strength
   int strengthScore = 0;
   
   //--- Score: Wick/Body ratio
   if(wickBodyRatio >= 3.0) strengthScore += 3;
   else if(wickBodyRatio >= 2.5) strengthScore += 2;
   else strengthScore += 1;
   
   //--- Score: Body size (smaller is better)
   if(bodyRatio <= 0.15) strengthScore += 2;
   else if(bodyRatio <= 0.25) strengthScore += 1;
   
   //--- Score: Nose size (smaller is better)
   if(upperWick / candleRange <= 0.1) strengthScore += 2;
   else if(upperWick / candleRange <= 0.2) strengthScore += 1;
   
   //--- Score: Close position
   if(close > open && close >= high - candleRange * 0.1) strengthScore += 1;
   
   //--- Classify strength
   if(strengthScore >= 6) return PINBAR_STRONG;
   if(strengthScore >= 4) return PINBAR_MODERATE;
   if(strengthScore >= 2) return PINBAR_WEAK;
   
   return PINBAR_NONE;
}

//+------------------------------------------------------------------+
//| Detect Bearish PinBar (Shooting Star)                             |
//+------------------------------------------------------------------+
ENUM_PINBAR_STRENGTH DetectBearishPinBar(double open, double high, double low, double close)
{
   double candleRange = high - low;
   if(candleRange <= 0) return PINBAR_NONE;
   
   double body = MathAbs(close - open);
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   //--- Check minimum wick size
   double minWick = InpMinWickPips * _Point * 10;
   if(upperWick < minWick) return PINBAR_NONE;
   
   //--- Check body/candle ratio
   double bodyRatio = body / candleRange;
   if(bodyRatio > InpBodyRatio) return PINBAR_NONE;
   
   //--- Check wick/body ratio
   double wickBodyRatio = body > 0 ? upperWick / body : 999;
   if(wickBodyRatio < InpWickRatio) return PINBAR_NONE;
   
   //--- Check nose (lower wick) ratio
   if(body > 0)
   {
      double noseRatio = lowerWick / body;
      if(noseRatio > InpNoseRatio * candleRange / body) return PINBAR_NONE;
   }
   else
   {
      if(lowerWick > candleRange * InpNoseRatio) return PINBAR_NONE;
   }

   //--- Check close beyond midpoint
   if(InpCloseBeyondMid)
   {
      double midpoint = (high + low) / 2;
      if(close > midpoint) return PINBAR_NONE;
   }
   
   //--- Determine strength
   int strengthScore = 0;
   
   //--- Score: Wick/Body ratio
   if(wickBodyRatio >= 3.0) strengthScore += 3;
   else if(wickBodyRatio >= 2.5) strengthScore += 2;
   else strengthScore += 1;
   
   //--- Score: Body size
   if(bodyRatio <= 0.15) strengthScore += 2;
   else if(bodyRatio <= 0.25) strengthScore += 1;
   
   //--- Score: Nose size
   if(lowerWick / candleRange <= 0.1) strengthScore += 2;
   else if(lowerWick / candleRange <= 0.2) strengthScore += 1;
   
   //--- Score: Close position
   if(close < open && close <= low + candleRange * 0.1) strengthScore += 1;
   
   //--- Classify strength
   if(strengthScore >= 6) return PINBAR_STRONG;
   if(strengthScore >= 4) return PINBAR_MODERATE;
   if(strengthScore >= 2) return PINBAR_WEAK;
   
   return PINBAR_NONE;
}

//+------------------------------------------------------------------+
//| Get trend direction from MAs                                      |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetTrendDirection(int shift, const double &close[])
{
   if(shift < InpTrendMAPeriod) return TREND_NONE;
   
   double fast = FastMABuffer[shift];
   double slow = SlowMABuffer[shift];
   double trend = TrendMABuffer[shift];
   double price = close[shift];
   
   //--- Strong bullish trend
   if(fast > slow && price > trend && fast > trend)
      return TREND_BULLISH;
   
   //--- Strong bearish trend
   if(fast < slow && price < trend && fast < trend)
      return TREND_BEARISH;
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Check if in ICT Kill Zone                                         |
//+------------------------------------------------------------------+
bool IsInKillZone(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   int hour = dt.hour;
   
   //--- London Kill Zone (7-9)
   if(InpLondonKillZone && hour >= 7 && hour < 9)
      return true;
   
   //--- NY Kill Zone (12-14)
   if(InpNYKillZone && hour >= 12 && hour < 14)
      return true;
   
   //--- London/NY Overlap (12-16)
   if(InpOverlapKillZone && hour >= 12 && hour < 16)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Get current market session                                        |
//+------------------------------------------------------------------+
ENUM_MARKET_SESSION GetCurrentSession(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   int hour = dt.hour;
   
   //--- Check overlap first
   if(hour >= 12 && hour < 16)
      return SESSION_OVERLAP;
   
   //--- London
   if(hour >= InpLondonStart && hour < InpLondonEnd)
      return SESSION_LONDON;
   
   //--- New York
   if(hour >= InpNYStart && hour < InpNYEnd)
      return SESSION_NEWYORK;
   
   //--- Asian
   if(hour >= InpAsianStart && hour < InpAsianEnd)
      return SESSION_ASIAN;
   
   return SESSION_NONE;
}

//+------------------------------------------------------------------+
//| Check MTF alignment                                               |
//+------------------------------------------------------------------+
bool CheckMTFAlignment(int shift, ENUM_TREND_DIRECTION currentTrend)
{
   if(currentTrend == TREND_NONE) return false;
   
   //--- Get HTF data
   double htf1Price = iClose(_Symbol, InpHTF1, 0);
   double htf2Price = iClose(_Symbol, InpHTF2, 0);
   
   double htf1MA = HTF1TrendBuffer[shift];
   double htf2MA = HTF2TrendBuffer[shift];
   
   if(htf1MA == 0 || htf2MA == 0) return false;
   
   //--- Check alignment
   if(currentTrend == TREND_BULLISH)
   {
      if(htf1Price > htf1MA && htf2Price > htf2MA)
         return true;
   }
   else if(currentTrend == TREND_BEARISH)
   {
      if(htf1Price < htf1MA && htf2Price < htf2MA)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check SMC Zone                                                    |
//+------------------------------------------------------------------+
ENUM_SMC_ZONE CheckSMCZone(int shift, const double &open[], const double &high[], 
                           const double &low[], const double &close[], const datetime &time[])
{
   //--- Check for Order Block
   for(int i = 1; i <= InpOrderBlockLook && shift - i >= 0; i++)
   {
      //--- Bullish Order Block (last down candle before up move)
      if(close[shift-i] < open[shift-i])  // Down candle
      {
         bool upMove = true;
         for(int j = 1; j <= 3 && shift - i + j < shift; j++)
         {
            if(close[shift-i+j] < close[shift-i+j-1]) upMove = false;
         }
         if(upMove && low[shift] <= high[shift-i] && low[shift] >= low[shift-i])
            return SMC_ORDER_BLOCK;
      }
      
      //--- Bearish Order Block (last up candle before down move)
      if(close[shift-i] > open[shift-i])  // Up candle
      {
         bool downMove = true;
         for(int j = 1; j <= 3 && shift - i + j < shift; j++)
         {
            if(close[shift-i+j] > close[shift-i+j-1]) downMove = false;
         }
         if(downMove && high[shift] >= low[shift-i] && high[shift] <= high[shift-i])
            return SMC_ORDER_BLOCK;
      }
   }
   
   //--- Check for FVG
   for(int i = 1; i <= InpFVGLookback && shift - i - 1 >= 0; i++)
   {
      //--- Bullish FVG: Gap between candle 1 high and candle 3 low
      double bullFVG = low[shift-i+1] - high[shift-i-1];
      if(bullFVG > InpFVGMinSize * _Point * 10)
      {
         if(close[shift] >= high[shift-i-1] && close[shift] <= low[shift-i+1])
            return SMC_FVG;
      }
      
      //--- Bearish FVG
      double bearFVG = low[shift-i-1] - high[shift-i+1];
      if(bearFVG > InpFVGMinSize * _Point * 10)
      {
         if(close[shift] <= low[shift-i-1] && close[shift] >= high[shift-i+1])
            return SMC_FVG;
      }
   }
   
   return SMC_NONE;
}

//+------------------------------------------------------------------+
//| Calculate signal quality score (0-100)                            |
//+------------------------------------------------------------------+
double CalculateQualityScore(ENUM_PINBAR_STRENGTH strength, ENUM_TREND_DIRECTION trend,
                              bool mtfAligned, ENUM_SMC_ZONE smcZone, int shift)
{
   double score = 0;
   
   //--- Base score from pinbar strength (0-40)
   switch(strength)
   {
      case PINBAR_STRONG: score += 40; break;
      case PINBAR_MODERATE: score += 30; break;
      case PINBAR_WEAK: score += 15; break;
      default: return 0;
   }
   
   //--- Trend alignment (0-20)
   if(trend != TREND_NONE) score += 20;
   
   //--- MTF alignment (0-15)
   if(mtfAligned) score += 15;
   
   //--- SMC zone (0-15)
   switch(smcZone)
   {
      case SMC_ORDER_BLOCK: score += 15; break;
      case SMC_FVG: score += 12; break;
      case SMC_LIQUIDITY: score += 10; break;
      case SMC_BREAKER: score += 13; break;
   }
   
   //--- Kill zone bonus (0-10)
   if(InpUseKillZones && IsInKillZone(iTime(_Symbol, PERIOD_CURRENT, shift)))
      score += 10;
   
   return MathMin(score, 100);
}

//+------------------------------------------------------------------+
//| Send alert                                                        |
//+------------------------------------------------------------------+
void SendAlert(string message, double price, datetime time, double quality)
{
   //--- Prevent duplicate alerts
   if(time <= LastAlertTime) return;
   LastAlertTime = time;
   
   string fullMessage = StringFormat("%s\n%s @ %.5f\nQuality: %.0f%%\nTime: %s",
                                      message, _Symbol, price, quality, TimeToString(time));
   
   //--- Popup
   if(InpAlertPopup)
      Alert(fullMessage);
   
   //--- Sound
   if(InpAlertSound)
   {
      if(StringFind(message, "BUY") >= 0)
         PlaySound(InpAlertSound_Buy);
      else
         PlaySound(InpAlertSound_Sell);
   }
   
   //--- Push notification
   if(InpAlertPush)
      SendNotification(fullMessage);
   
   //--- Email
   if(InpAlertEmail)
      SendMail("PinBar Magic Signal - " + _Symbol, fullMessage);
}

//+------------------------------------------------------------------+
//| Create Dashboard                                                  |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int width = 280;
   int height = 320;
   
   //--- Background
   CreateRectangle(DashboardPrefix + "BG", x, y, width, height, InpDashBGColor);
   
   //--- Title
   CreateLabel(DashboardPrefix + "Title", x + 10, y + 5, 
               "🎯 PINBAR MAGIC ULTIMATE v2.0", clrGold, 11, true);
   CreateLabel(DashboardPrefix + "Author", x + 10, y + 25, 
               "by JazzyLyfe | Grade A++", clrSilver, 8, false);
   
   //--- Separator
   CreateLabel(DashboardPrefix + "Sep1", x + 10, y + 45, 
               "═══════════════════════════", clrDimGray, 8, false);
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(int rates_total, const datetime &time[], const double &close[])
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   
   //--- Symbol & Timeframe
   string tf = GetTimeframeString(Period());
   CreateLabel(DashboardPrefix + "Symbol", x + 10, y + 60,
               StringFormat("Symbol: %s | %s", _Symbol, tf), clrWhite, InpDashFontSize, false);
   
   //--- Current Price
   CreateLabel(DashboardPrefix + "Price", x + 10, y + 78,
               StringFormat("Price: %.5f", close[rates_total-1]), clrAqua, InpDashFontSize, false);
   
   //--- Trend Status
   ENUM_TREND_DIRECTION trend = GetTrendDirection(rates_total-2, close);
   string trendStr = trend == TREND_BULLISH ? "🟢 BULLISH" : 
                     trend == TREND_BEARISH ? "🔴 BEARISH" : "⚪ NEUTRAL";
   CreateLabel(DashboardPrefix + "Trend", x + 10, y + 96,
               "Trend: " + trendStr, clrWhite, InpDashFontSize, false);
   
   //--- Session
   ENUM_MARKET_SESSION session = GetCurrentSession(TimeCurrent());
   string sessionStr = GetSessionString(session);
   CreateLabel(DashboardPrefix + "Session", x + 10, y + 114,
               "Session: " + sessionStr, clrWhite, InpDashFontSize, false);
   
   //--- Kill Zone Status
   bool inKZ = IsInKillZone(TimeCurrent());
   string kzStr = inKZ ? "🟢 ACTIVE" : "⚪ INACTIVE";
   CreateLabel(DashboardPrefix + "KillZone", x + 10, y + 132,
               "Kill Zone: " + kzStr, clrWhite, InpDashFontSize, false);
   
   //--- Separator
   CreateLabel(DashboardPrefix + "Sep2", x + 10, y + 150,
               "═══════════════════════════", clrDimGray, 8, false);
   
   //--- Statistics
   CreateLabel(DashboardPrefix + "Stats", x + 10, y + 165,
               "📊 STATISTICS", clrGold, InpDashFontSize, true);
   
   CreateLabel(DashboardPrefix + "BullCount", x + 10, y + 183,
               StringFormat("Bullish Signals: %d", TotalBullish), clrLime, InpDashFontSize, false);
   
   CreateLabel(DashboardPrefix + "BearCount", x + 10, y + 201,
               StringFormat("Bearish Signals: %d", TotalBearish), clrRed, InpDashFontSize, false);
   
   CreateLabel(DashboardPrefix + "StrongCount", x + 10, y + 219,
               StringFormat("Strong Signals: %d", StrongSignals), clrGold, InpDashFontSize, false);
   
   //--- Separator
   CreateLabel(DashboardPrefix + "Sep3", x + 10, y + 237,
               "═══════════════════════════", clrDimGray, 8, false);
   
   //--- Settings Status
   CreateLabel(DashboardPrefix + "Settings", x + 10, y + 252,
               "⚙️ ACTIVE FILTERS", clrGold, InpDashFontSize, true);
   
   string filters = "";
   if(InpUseTrendFilter) filters += "Trend ";
   if(InpUseSMC) filters += "SMC ";
   if(InpUseKillZones) filters += "KZ ";
   if(InpUseMTF) filters += "MTF ";
   if(filters == "") filters = "None";
   
   CreateLabel(DashboardPrefix + "Filters", x + 10, y + 270,
               "Filters: " + filters, clrWhite, InpDashFontSize, false);
   
   CreateLabel(DashboardPrefix + "RR", x + 10, y + 288,
               StringFormat("Min R:R = %.1f:1", InpMinRiskReward), clrWhite, InpDashFontSize, false);
}

//+------------------------------------------------------------------+
//| Delete Dashboard                                                  |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   ObjectsDeleteAll(0, DashboardPrefix);
}

//+------------------------------------------------------------------+
//| Draw SMC Objects                                                  |
//+------------------------------------------------------------------+
void DrawSMCObjects(int rates_total, const datetime &time[], const double &open[], 
                    const double &high[], const double &low[], const double &close[])
{
   if(!InpShowOrderBlocks && !InpShowFVG && !InpShowLiquidity)
      return;
   
   //--- Limit drawing to recent bars
   int lookback = MathMin(200, rates_total - 1);
   
   for(int i = 1; i < lookback; i++)
   {
      int idx = rates_total - 1 - i;
      
      //--- Draw Order Blocks
      if(InpShowOrderBlocks)
      {
         //--- Bullish OB
         if(close[idx] < open[idx] && idx + 3 < rates_total)
         {
            bool isBullOB = true;
            for(int j = 1; j <= 3 && idx + j < rates_total; j++)
            {
               if(close[idx+j] < close[idx+j-1]) isBullOB = false;
            }
            if(isBullOB)
            {
               string name = "PBM_OB_Bull_" + IntegerToString(idx);
               if(ObjectFind(0, name) < 0)
               {
                  ObjectCreate(0, name, OBJ_RECTANGLE, 0, time[idx], high[idx], time[rates_total-1], low[idx]);
                  ObjectSetInteger(0, name, OBJPROP_COLOR, InpBullishOBColor);
                  ObjectSetInteger(0, name, OBJPROP_FILL, true);
                  ObjectSetInteger(0, name, OBJPROP_BACK, true);
                  ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               }
            }
         }
         
         //--- Bearish OB
         if(close[idx] > open[idx] && idx + 3 < rates_total)
         {
            bool isBearOB = true;
            for(int j = 1; j <= 3 && idx + j < rates_total; j++)
            {
               if(close[idx+j] > close[idx+j-1]) isBearOB = false;
            }
            if(isBearOB)
            {
               string name = "PBM_OB_Bear_" + IntegerToString(idx);
               if(ObjectFind(0, name) < 0)
               {
                  ObjectCreate(0, name, OBJ_RECTANGLE, 0, time[idx], high[idx], time[rates_total-1], low[idx]);
                  ObjectSetInteger(0, name, OBJPROP_COLOR, InpBearishOBColor);
                  ObjectSetInteger(0, name, OBJPROP_FILL, true);
                  ObjectSetInteger(0, name, OBJPROP_BACK, true);
                  ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               }
            }
         }
      }
      
      //--- Draw FVG
      if(InpShowFVG && idx >= 2)
      {
         //--- Bullish FVG
         double bullGap = low[idx] - high[idx-2];
         if(bullGap > InpFVGMinSize * _Point * 10)
         {
            string name = "PBM_FVG_Bull_" + IntegerToString(idx);
            if(ObjectFind(0, name) < 0)
            {
               ObjectCreate(0, name, OBJ_RECTANGLE, 0, time[idx-1], high[idx-2], time[rates_total-1], low[idx]);
               ObjectSetInteger(0, name, OBJPROP_COLOR, InpFVGColor);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
            }
         }
         
         //--- Bearish FVG
         double bearGap = low[idx-2] - high[idx];
         if(bearGap > InpFVGMinSize * _Point * 10)
         {
            string name = "PBM_FVG_Bear_" + IntegerToString(idx);
            if(ObjectFind(0, name) < 0)
            {
               ObjectCreate(0, name, OBJ_RECTANGLE, 0, time[idx-1], low[idx-2], time[rates_total-1], high[idx]);
               ObjectSetInteger(0, name, OBJPROP_COLOR, InpFVGColor);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete SMC Objects                                                |
//+------------------------------------------------------------------+
void DeleteSMCObjects()
{
   ObjectsDeleteAll(0, "PBM_OB_");
   ObjectsDeleteAll(0, "PBM_FVG_");
   ObjectsDeleteAll(0, "PBM_LIQ_");
}

//+------------------------------------------------------------------+
//| Create Label helper                                               |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

//+------------------------------------------------------------------+
//| Create Rectangle helper                                           |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color bgColor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
}

//+------------------------------------------------------------------+
//| Get timeframe string                                              |
//+------------------------------------------------------------------+
string GetTimeframeString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "?";
   }
}

//+------------------------------------------------------------------+
//| Get session string                                                |
//+------------------------------------------------------------------+
string GetSessionString(ENUM_MARKET_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN:   return "🌏 ASIAN";
      case SESSION_LONDON:  return "🇬🇧 LONDON";
      case SESSION_NEWYORK: return "🇺🇸 NEW YORK";
      case SESSION_OVERLAP: return "🔥 OVERLAP";
      default:              return "💤 CLOSED";
   }
}
//+------------------------------------------------------------------+
