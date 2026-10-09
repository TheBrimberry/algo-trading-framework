//+------------------------------------------------------------------+
//|                                    JazzyLyfe_Claude_AI_EA.mq5    |
//|                        Copyright 2026, JazzyLyfe Trading Systems  |
//|                                    Author: JazzyLyfe | Grade A++ |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, JazzyLyfe Trading Systems"
#property link        "https://jazzylyfe.com"
#property version     "3.00"
#property description "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#property description "⚡ JAZZYLYFE CLAUDE AI TRADING ENGINE ⚡"
#property description "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#property description "Connects to Claude API for AI-Powered Trade Decisions"
#property description "Features: Live Market Analysis, SMC Detection,"
#property description "Multi-TF Confluence, Adaptive Risk, ICT Killzones"
#property strict

//+------------------------------------------------------------------+
//| INCLUDES                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIR
  {
   TRADE_BOTH    = 0,  // Both Directions
   TRADE_BUY     = 1,  // Buy Only
   TRADE_SELL    = 2,  // Sell Only
  };

enum ENUM_RISK_MODE
  {
   RISK_FIXED    = 0,  // Fixed Lot Size
   RISK_PERCENT  = 1,  // Percent of Balance
   RISK_KELLY    = 2,  // Kelly Criterion
   RISK_ATR      = 3,  // ATR-Based Dynamic
  };

enum ENUM_AI_MODEL
  {
   MODEL_SONNET  = 0,  // Claude Sonnet 4.5 (Fast)
   MODEL_OPUS    = 1,  // Claude Opus 4.6 (Deep Analysis)
   MODEL_HAIKU   = 2,  // Claude Haiku 4.5 (Ultra Fast)
  };

enum ENUM_AI_AGGRESSION
  {
   AI_CONSERVATIVE = 0, // Conservative (High Confidence Only)
   AI_MODERATE     = 1, // Moderate (Balanced)
   AI_AGGRESSIVE   = 2, // Aggressive (More Trades)
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
//--- Claude AI Settings
input group           "═══ 🤖 CLAUDE AI ENGINE ═══"
input string          InpApiKey         = "";                    // Claude API Key (sk-ant-...) — SET AT LOAD TIME. DO NOT EMBED.
input ENUM_AI_MODEL   InpModel          = MODEL_SONNET;         // AI Model
input ENUM_AI_AGGRESSION InpAggression  = AI_MODERATE;          // AI Aggression Level
input int             InpAnalysisInterval = 300;                // Analysis Interval (seconds)
input int             InpCandlesForAI   = 50;                   // Candles to Send to AI
input bool            InpSendIndicators = true;                 // Send Indicator Data to AI
input bool            InpSendSMC        = true;                 // Send SMC Data to AI
input int             InpMaxTokens      = 1024;                 // Max AI Response Tokens
input int             InpRequestTimeout = 30000;                // Request Timeout (ms)
input int             InpHistoryDays    = 90;                   // Trade History Days to Analyze

//--- Trade Settings
input group           "═══ 📊 TRADE SETTINGS ═══"
input ENUM_TRADE_DIR  InpTradeDir       = TRADE_BOTH;           // Trade Direction
input bool            InpInverseMode    = false;                // Inverse Mode (Flip Signals)
input int             InpMagicNumber    = 777777;               // Magic Number
input int             InpMaxTrades      = 3;                    // Max Concurrent Trades
input int             InpMaxSpread      = 30;                   // Max Spread (points)
input bool            InpCloseOpposite  = true;                 // Close Opposite on New Signal

//--- Risk Management
input group           "═══ 💰 RISK MANAGEMENT ═══"
input ENUM_RISK_MODE  InpRiskMode       = RISK_PERCENT;         // Risk Mode
input double          InpFixedLots      = 0.01;                 // Fixed Lot Size
input double          InpRiskPercent    = 2.0;                  // Risk Percent per Trade
input double          InpMaxDrawdown    = 10.0;                 // Max Drawdown % (FTMO: 10%)
input double          InpDailyLossLimit = 5.0;                  // Daily Loss Limit % (FTMO: 5%)
input bool            InpFridayCloseEnabled = true;             // FTMO: flatten at Friday 20:00 server
input int             InpFridayCloseHour    = 20;               // Friday hour (server tz)
input int             InpATRPeriod      = 14;                   // ATR Period
input double          InpATRSLMulti     = 2.0;                  // ATR SL Multiplier
input double          InpATRTPMulti     = 3.0;                  // ATR TP Multiplier
input double          InpMinRR          = 1.5;                  // Minimum Risk:Reward Ratio

//--- Session Filters
input group           "═══ ⏰ SESSION FILTERS ═══"
input bool            InpUseSessions    = true;                 // Enable Session Filter
input bool            InpLondonSession  = true;                 // Trade London (02:00-11:00 EST)
input bool            InpNYSession      = true;                 // Trade New York (07:00-16:00 EST)
input bool            InpAsiaSession    = false;                // Trade Asia (19:00-04:00 EST)
input bool            InpAvoidNews      = true;                 // Avoid 30min Before/After News

//--- Trailing & BE
input group           "═══ 🎯 TRAILING & BREAKEVEN ═══"
input bool            InpUseTrailing    = true;                 // Enable Trailing Stop
input int             InpTrailingStart  = 200;                  // Trailing Start (points)
input int             InpTrailingStep   = 50;                   // Trailing Step (points)
input bool            InpUseBreakeven   = true;                 // Enable Breakeven
input int             InpBEActivation   = 150;                  // BE Activation (points profit)
input int             InpBEOffset       = 10;                   // BE Offset (points above entry)

//--- Dashboard
input group           "═══ 📋 DASHBOARD ═══"
input bool            InpShowDashboard  = true;                 // Show On-Chart Dashboard
input int             InpDashX          = 20;                   // Dashboard X Position
input int             InpDashY          = 30;                   // Dashboard Y Position
input color           InpDashBg         = clrBlack;             // Dashboard Background
input color           InpDashText       = clrWhite;             // Dashboard Text Color
input color           InpDashAccent     = clrLime;              // Dashboard Accent Color

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;
CAccountInfo   accInfo;

//--- AI State
datetime       g_lastAnalysis   = 0;
string         g_lastSignal     = "NONE";
string         g_lastReason     = "Waiting for first analysis...";
double         g_aiConfidence   = 0.0;
double         g_aiSL           = 0.0;
double         g_aiTP           = 0.0;
int            g_aiCalls        = 0;
int            g_aiFails        = 0;
int            g_signalBuy      = 0;
int            g_signalSell     = 0;
int            g_signalHold     = 0;

//--- Trading State
double         g_dayStartBalance = 0;
double         g_maxEquity       = 0;
int            g_totalTrades     = 0;
int            g_winTrades       = 0;
int            g_lossTrades      = 0;
double         g_totalProfit     = 0;
bool           g_tradingPaused   = false;
string         g_pauseReason     = "";

//--- Indicator Handles
int            h_RSI, h_MACD, h_BB, h_ATR, h_EMA21, h_EMA50, h_EMA200;
int            h_Stoch, h_ADX, h_SAR, h_Ichimoku, h_Volume;

//+------------------------------------------------------------------+
//| Expert Initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Validate API Key
   if(InpApiKey == "" || StringFind(InpApiKey, "sk-ant-") < 0)
     {
      Print("⚠️ WARNING: No valid Claude API key provided!");
      Print("   Get your key at: https://console.anthropic.com/");
      Print("   Format: sk-ant-api03-...");
      Print("   EA will run in DEMO/ANALYSIS mode without trading");
     }
   
   //--- Allow WebRequest URL
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("⚡ JAZZYLYFE CLAUDE AI TRADING ENGINE v3.00 ⚡");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("📌 IMPORTANT: Add this URL to MT5 allowed list:");
   Print("   Tools > Options > Expert Advisors > Allow WebRequest");
   Print("   URL: https://api.anthropic.com");
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   
   //--- Initialize Trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   //--- Initialize Symbol
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   //--- Create Indicator Handles
   h_RSI      = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   h_MACD     = iMACD(_Symbol, PERIOD_CURRENT, 3, 10, 16, PRICE_CLOSE);
   h_BB       = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   h_ATR      = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   h_EMA21    = iMA(_Symbol, PERIOD_CURRENT, 21, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA50    = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA200   = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_EMA, PRICE_CLOSE);
   h_Stoch    = iStochastic(_Symbol, PERIOD_CURRENT, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   h_ADX      = iADX(_Symbol, PERIOD_CURRENT, 14);
   h_SAR      = iSAR(_Symbol, PERIOD_CURRENT, 0.02, 0.2);
   h_Ichimoku = iIchimoku(_Symbol, PERIOD_CURRENT, 9, 26, 52);
   h_Volume   = iVolumes(_Symbol, PERIOD_CURRENT, VOLUME_TICK);
   
   //--- Validate handles
   if(h_RSI==INVALID_HANDLE || h_MACD==INVALID_HANDLE || h_BB==INVALID_HANDLE ||
      h_ATR==INVALID_HANDLE || h_EMA21==INVALID_HANDLE || h_EMA50==INVALID_HANDLE ||
      h_EMA200==INVALID_HANDLE || h_Stoch==INVALID_HANDLE || h_ADX==INVALID_HANDLE)
     {
      Print("❌ Failed to create indicator handles!");
      return INIT_FAILED;
     }
   
   //--- Initialize state
   g_dayStartBalance = accInfo.Balance();
   g_maxEquity       = accInfo.Equity();
   
   //--- Create dashboard
   if(InpShowDashboard)
      CreateDashboard();
   
   Print("✅ JazzyLyfe Claude AI EA initialized successfully");
   Print("   Symbol: ", _Symbol, " | TF: ", EnumToString(Period()));
   Print("   Model: ", GetModelName());
   Print("   Risk: ", EnumToString(InpRiskMode), " | ", InpRiskPercent, "%");
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Release indicator handles
   IndicatorRelease(h_RSI);
   IndicatorRelease(h_MACD);
   IndicatorRelease(h_BB);
   IndicatorRelease(h_ATR);
   IndicatorRelease(h_EMA21);
   IndicatorRelease(h_EMA50);
   IndicatorRelease(h_EMA200);
   IndicatorRelease(h_Stoch);
   IndicatorRelease(h_ADX);
   IndicatorRelease(h_SAR);
   IndicatorRelease(h_Ichimoku);
   IndicatorRelease(h_Volume);
   
   //--- Remove dashboard
   ObjectsDeleteAll(0, "JZAI_");
   
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("📊 SESSION STATS:");
   Print("   Total AI Calls: ", g_aiCalls, " | Failed: ", g_aiFails);
   Print("   Signals - Buy: ", g_signalBuy, " | Sell: ", g_signalSell, " | Hold: ", g_signalHold);
   Print("   Trades: ", g_totalTrades, " | W: ", g_winTrades, " | L: ", g_lossTrades);
   Print("   Win Rate: ", g_totalTrades > 0 ? DoubleToString((double)g_winTrades/g_totalTrades*100, 1) + "%" : "N/A");
   Print("   Total P/L: ", DoubleToString(g_totalProfit, 2));
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                              |
//+------------------------------------------------------------------+
bool IsFridayFlattenAI()
{
   if(!InpFridayCloseEnabled) return false;
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   return (d.day_of_week==5 && d.hour>=InpFridayCloseHour);
}

void FlattenOurPositions(const string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      trade.PositionClose(tk);
      Print("[CLAUDE-AI] Flatten (", reason, ") ticket=", tk);
   }
}

void OnTick()
  {
   symInfo.Refresh();

   //--- Friday weekend-flat (FTMO rule)
   if(IsFridayFlattenAI())
     {
      FlattenOurPositions("Fri 20:00 FTMO flat");
      g_tradingPaused = true;
      g_pauseReason   = "Weekend flat";
      return;
     }

   //--- Daily reset
   MqlDateTime dt;
   TimeCurrent(dt);
   static int lastDay = -1;
   if(dt.day != lastDay)
     {
      lastDay = dt.day;
      g_dayStartBalance = accInfo.Balance();
      g_tradingPaused = false;
      g_pauseReason = "";
     }

   //--- Check safety limits
   CheckSafetyLimits();

   //--- Universal $1000 breach 50% partial close check
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         double flt = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(MathAbs(flt) >= 1000.0)
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "PC1000") < 0)
            {
               double vol = PositionGetDouble(POSITION_VOLUME);
               double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               if(step <= 0) step = 0.01;
               double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double closeVol = MathFloor((vol * 0.5) / step + 1e-9) * step;
               if(closeVol >= vmin && closeVol < vol)
               {
                  if(trade.PositionClosePartial(ticket, closeVol))
                  {
                     PrintFormat("CLAUDE AI EA >> UNIVERSAL $1000 BREACH >> Partial closed 50%% (%.2f lots) on ticket #%I64u (P&L: $%.2f)", closeVol, ticket, flt);
                  }
               }
            }
         }
      }
   }
   
   //--- Manage existing positions (trailing, BE)
   ManagePositions();
   
   //--- Check if it's time for AI analysis
   if(TimeCurrent() - g_lastAnalysis >= InpAnalysisInterval)
     {
      g_lastAnalysis = TimeCurrent();
      
      //--- Gather market data
      string marketData = GatherMarketData();
      
      //--- Send to Claude AI
      string aiResponse = CallClaudeAPI(marketData);
      
      //--- Parse AI response
      if(aiResponse != "")
        {
         ParseAIResponse(aiResponse);
         
         //--- Execute trade if signal received
         if(!g_tradingPaused)
            ExecuteAISignal();
        }
     }
   
   //--- Update dashboard
   if(InpShowDashboard)
      UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Gather Comprehensive Market Data                                  |
//+------------------------------------------------------------------+
string GatherMarketData()
  {
   string data = "";
   
   //--- Account Info
   data += "ACCOUNT: Balance=" + DoubleToString(accInfo.Balance(), 2);
   data += " Equity=" + DoubleToString(accInfo.Equity(), 2);
   data += " FreeMargin=" + DoubleToString(accInfo.FreeMargin(), 2);
   data += " OpenPositions=" + IntegerToString(CountPositions());
   data += "\n";
   
   //--- Symbol Info
   data += "SYMBOL: " + _Symbol;
   data += " Bid=" + DoubleToString(symInfo.Bid(), _Digits);
   data += " Ask=" + DoubleToString(symInfo.Ask(), _Digits);
   data += " Spread=" + IntegerToString(symInfo.Spread());
   data += " TF=" + EnumToString(Period());
   data += "\n";
   
   //--- OHLC Candles
   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, InpCandlesForAI, rates);
   if(copied > 0)
     {
      data += "CANDLES (last " + IntegerToString(MathMin(copied, 20)) + "):\n";
      int start = MathMax(0, copied - 20);
      for(int i = start; i < copied; i++)
        {
         data += "  [" + IntegerToString(i) + "] ";
         data += TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES);
         data += " O=" + DoubleToString(rates[i].open, _Digits);
         data += " H=" + DoubleToString(rates[i].high, _Digits);
         data += " L=" + DoubleToString(rates[i].low, _Digits);
         data += " C=" + DoubleToString(rates[i].close, _Digits);
         data += " V=" + IntegerToString(rates[i].tick_volume);
         data += "\n";
        }
     }
   
   //--- Indicator Data
   if(InpSendIndicators)
     {
      double rsi[], macdMain[], macdSignal[], bbUpper[], bbMiddle[], bbLower[];
      double ema21[], ema50[], ema200[], atr[], stochK[], stochD[];
      double adxMain[], adxPlus[], adxMinus[], sar[];
      
      CopyBuffer(h_RSI, 0, 0, 5, rsi);
      CopyBuffer(h_MACD, 0, 0, 5, macdMain);
      CopyBuffer(h_MACD, 1, 0, 5, macdSignal);
      CopyBuffer(h_BB, 0, 0, 5, bbMiddle);
      CopyBuffer(h_BB, 1, 0, 5, bbUpper);
      CopyBuffer(h_BB, 2, 0, 5, bbLower);
      CopyBuffer(h_EMA21, 0, 0, 5, ema21);
      CopyBuffer(h_EMA50, 0, 0, 5, ema50);
      CopyBuffer(h_EMA200, 0, 0, 5, ema200);
      CopyBuffer(h_ATR, 0, 0, 5, atr);
      CopyBuffer(h_Stoch, 0, 0, 5, stochK);
      CopyBuffer(h_Stoch, 1, 0, 5, stochD);
      CopyBuffer(h_ADX, 0, 0, 5, adxMain);
      CopyBuffer(h_ADX, 1, 0, 5, adxPlus);
      CopyBuffer(h_ADX, 2, 0, 5, adxMinus);
      CopyBuffer(h_SAR, 0, 0, 5, sar);
      
      if(ArraySize(rsi) >= 3)
        {
         data += "INDICATORS (current | prev | prev2):\n";
         data += "  RSI: " + Arr3(rsi) + "\n";
         data += "  MACD_Main: " + Arr3(macdMain) + " Signal: " + Arr3(macdSignal) + "\n";
         data += "  BB_Upper: " + Arr3(bbUpper) + " Mid: " + Arr3(bbMiddle) + " Lower: " + Arr3(bbLower) + "\n";
         data += "  EMA21: " + Arr3(ema21) + " EMA50: " + Arr3(ema50) + " EMA200: " + Arr3(ema200) + "\n";
         data += "  ATR: " + Arr3(atr) + "\n";
         data += "  Stoch_K: " + Arr3(stochK) + " D: " + Arr3(stochD) + "\n";
         data += "  ADX: " + Arr3(adxMain) + " +DI: " + Arr3(adxPlus) + " -DI: " + Arr3(adxMinus) + "\n";
         data += "  ParabolicSAR: " + Arr3(sar) + "\n";
         
         //--- Price relative to EMAs
         double bid = symInfo.Bid();
         data += "  Price_vs_EMA21: " + (bid > ema21[0] ? "ABOVE" : "BELOW") + "\n";
         data += "  Price_vs_EMA50: " + (bid > ema50[0] ? "ABOVE" : "BELOW") + "\n";
         data += "  Price_vs_EMA200: " + (bid > ema200[0] ? "ABOVE" : "BELOW") + "\n";
         data += "  EMA_Alignment: " + (ema21[0] > ema50[0] && ema50[0] > ema200[0] ? "BULLISH" : 
                   (ema21[0] < ema50[0] && ema50[0] < ema200[0] ? "BEARISH" : "MIXED")) + "\n";
        }
     }
   
   //--- Smart Money Concepts Data
   if(InpSendSMC)
     {
      data += "SMC_ANALYSIS:\n";
      data += DetectSMCPatterns();
     }
   
   //--- Multi-Timeframe Context
   data += "MTF_CONTEXT:\n";
   data += GetMTFContext();
   
   //--- Session Info
   data += "SESSION: " + GetCurrentSession() + "\n";
   
   //--- Comprehensive Trade History Analysis
   data += "TRADE_HISTORY_ANALYSIS:\n";
   data += AnalyzeTradeHistory();
   
   return data;
  }

//+------------------------------------------------------------------+
//| Helper: Format 3 values from array                                |
//+------------------------------------------------------------------+
string Arr3(double &arr[])
  {
   if(ArraySize(arr) < 3) return "N/A";
   return DoubleToString(arr[0], _Digits) + " | " + 
          DoubleToString(arr[1], _Digits) + " | " + 
          DoubleToString(arr[2], _Digits);
  }

//+------------------------------------------------------------------+
//| Detect Smart Money Concept Patterns                               |
//+------------------------------------------------------------------+
string DetectSMCPatterns()
  {
   string smc = "";
   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates);
   if(copied < 20) return "  Insufficient data\n";
   
   //--- Order Block Detection (last bullish/bearish OB)
   string lastBullOB = "NONE", lastBearOB = "NONE";
   for(int i = copied - 3; i >= 2; i--)
     {
      //--- Bullish OB: last bearish candle before a strong bullish move
      if(rates[i].close < rates[i].open &&    // Bearish candle
         rates[i+1].close > rates[i+1].open && // Followed by bullish
         rates[i+1].close > rates[i].high &&   // Broke above
         lastBullOB == "NONE")
        {
         lastBullOB = DoubleToString(rates[i].low, _Digits) + "-" + DoubleToString(rates[i].high, _Digits);
        }
      //--- Bearish OB: last bullish candle before a strong bearish move  
      if(rates[i].close > rates[i].open &&    // Bullish candle
         rates[i+1].close < rates[i+1].open && // Followed by bearish
         rates[i+1].close < rates[i].low &&    // Broke below
         lastBearOB == "NONE")
        {
         lastBearOB = DoubleToString(rates[i].low, _Digits) + "-" + DoubleToString(rates[i].high, _Digits);
        }
      if(lastBullOB != "NONE" && lastBearOB != "NONE") break;
     }
   smc += "  BullishOB: " + lastBullOB + "\n";
   smc += "  BearishOB: " + lastBearOB + "\n";
   
   //--- Fair Value Gap Detection
   string fvgUp = "NONE", fvgDown = "NONE";
   for(int i = copied - 3; i >= 1; i--)
     {
      //--- Bullish FVG: gap between candle[i-1].high and candle[i+1].low
      if(rates[i+1].low > rates[i-1].high && fvgUp == "NONE")
        {
         fvgUp = DoubleToString(rates[i-1].high, _Digits) + "-" + DoubleToString(rates[i+1].low, _Digits);
        }
      //--- Bearish FVG
      if(rates[i-1].low > rates[i+1].high && fvgDown == "NONE")
        {
         fvgDown = DoubleToString(rates[i+1].high, _Digits) + "-" + DoubleToString(rates[i-1].low, _Digits);
        }
      if(fvgUp != "NONE" && fvgDown != "NONE") break;
     }
   smc += "  BullishFVG: " + fvgUp + "\n";
   smc += "  BearishFVG: " + fvgDown + "\n";
   
   //--- Liquidity Levels (swing highs/lows)
   double swingHigh = 0, swingLow = 999999;
   for(int i = 2; i < copied - 2 && i < 50; i++)
     {
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
         rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
        {
         if(rates[i].high > swingHigh) swingHigh = rates[i].high;
        }
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
         rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
        {
         if(rates[i].low < swingLow) swingLow = rates[i].low;
        }
     }
   smc += "  SwingHigh_Liquidity: " + DoubleToString(swingHigh, _Digits) + "\n";
   smc += "  SwingLow_Liquidity: " + DoubleToString(swingLow, _Digits) + "\n";
   
   //--- Market Structure (HH, HL, LH, LL)
   string structure = DetectMarketStructure(rates, copied);
   smc += "  MarketStructure: " + structure + "\n";
   
   //--- Break of Structure
   double lastHigh = rates[copied-2].high;
   double lastLow  = rates[copied-2].low;
   double curClose = rates[copied-1].close;
   if(curClose > swingHigh) smc += "  BOS: BULLISH (broke swing high)\n";
   else if(curClose < swingLow) smc += "  BOS: BEARISH (broke swing low)\n";
   else smc += "  BOS: NONE\n";
   
   return smc;
  }

//+------------------------------------------------------------------+
//| Detect Market Structure                                           |
//+------------------------------------------------------------------+
string DetectMarketStructure(MqlRates &rates[], int count)
  {
   if(count < 20) return "UNKNOWN";
   
   double highs[], lows[];
   ArrayResize(highs, 0);
   ArrayResize(lows, 0);
   
   for(int i = 2; i < count - 2 && i < 50; i++)
     {
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
        {
         int size = ArraySize(highs);
         ArrayResize(highs, size + 1);
         highs[size] = rates[i].high;
        }
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
        {
         int size = ArraySize(lows);
         ArrayResize(lows, size + 1);
         lows[size] = rates[i].low;
        }
     }
   
   int hSize = ArraySize(highs);
   int lSize = ArraySize(lows);
   
   if(hSize >= 2 && lSize >= 2)
     {
      bool HH = highs[hSize-1] > highs[hSize-2];
      bool HL = lows[lSize-1] > lows[lSize-2];
      bool LH = highs[hSize-1] < highs[hSize-2];
      bool LL = lows[lSize-1] < lows[lSize-2];
      
      if(HH && HL) return "UPTREND (HH+HL)";
      if(LH && LL) return "DOWNTREND (LH+LL)";
      if(HH && LL) return "EXPANSION";
      if(LH && HL) return "CONTRACTION/RANGE";
     }
   
   return "FORMING";
  }

//+------------------------------------------------------------------+
//| Get Multi-Timeframe Context                                       |
//+------------------------------------------------------------------+
string GetMTFContext()
  {
   string mtf = "";
   ENUM_TIMEFRAMES tfs[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   string tfNames[]      = {"M15", "H1", "H4", "D1"};
   
   for(int t = 0; t < ArraySize(tfs); t++)
     {
      int handle = iMA(_Symbol, tfs[t], 21, 0, MODE_EMA, PRICE_CLOSE);
      if(handle == INVALID_HANDLE) continue;
      
      double ema[];
      MqlRates r[];
      CopyBuffer(handle, 0, 0, 3, ema);
      CopyRates(_Symbol, tfs[t], 0, 3, r);
      IndicatorRelease(handle);
      
      if(ArraySize(ema) >= 1 && ArraySize(r) >= 2)
        {
         string bias = r[1].close > ema[0] ? "BULLISH" : "BEARISH";
         string candle = r[1].close > r[1].open ? "GREEN" : "RED";
         mtf += "  " + tfNames[t] + ": " + bias + " (" + candle + ")\n";
        }
     }
   
   return mtf;
  }

//+------------------------------------------------------------------+
//| Get Current Trading Session                                       |
//+------------------------------------------------------------------+
string GetCurrentSession()
  {
   MqlDateTime dt;
   TimeGMT(dt);
   int hour = dt.hour;
   
   //--- Convert to EST (GMT-5)
   int est = (hour - 5 + 24) % 24;
   
   if(est >= 2 && est < 7)  return "LONDON_OPEN (Killzone)";
   if(est >= 7 && est < 11) return "LONDON_NY_OVERLAP (Prime)";
   if(est >= 11 && est < 16) return "NEW_YORK";
   if(est >= 19 || est < 4)  return "ASIA";
   return "TRANSITION";
  }

//+------------------------------------------------------------------+
//| Check if Current Session is Allowed                               |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
  {
   if(!InpUseSessions) return true;
   
   MqlDateTime dt;
   TimeGMT(dt);
   int est = (dt.hour - 5 + 24) % 24;
   
   if(InpLondonSession && est >= 2 && est < 11) return true;
   if(InpNYSession && est >= 7 && est < 16) return true;
   if(InpAsiaSession && (est >= 19 || est < 4)) return true;
   
   return false;
  }

//+------------------------------------------------------------------+
//| Analyze Complete Trade History                                    |
//+------------------------------------------------------------------+
string AnalyzeTradeHistory()
  {
   string report = "";
   
   //--- Select history (last 90 days)
   datetime fromDate = TimeCurrent() - InpHistoryDays * 24 * 3600;
   datetime toDate   = TimeCurrent();
   HistorySelect(fromDate, toDate);
   
   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0)
     {
      report += "  No trade history found (last 90 days)\n";
      return report;
     }
   
   //--- Accumulators
   int    wins = 0, losses = 0, breakevens = 0;
   double totalProfitH = 0, totalLossH = 0;
   double grossProfit = 0, grossLoss = 0;
   double largestWin = 0, largestLoss = 0;
   double maxConsecWinAmt = 0, maxConsecLossAmt = 0;
   int    consecWins = 0, consecLosses = 0;
   int    maxConsecWins = 0, maxConsecLosses = 0;
   double peakBalance = 0, maxDrawdownAmt = 0, maxDrawdownPct = 0;
   double runningBalance = accInfo.Balance();
   
   //--- Per-symbol tracking
   string symbols[];
   double symbolPL[];
   int    symbolCount[];
   int    symbolWins[];
   int    symArrSize = 0;
   
   //--- Per-hour tracking
   double hourPL[24];
   int    hourCount[24];
   int    hourWins[24];
   ArrayInitialize(hourPL, 0);
   ArrayInitialize(hourCount, 0);
   ArrayInitialize(hourWins, 0);
   
   //--- Per-day tracking
   double dayPL[7];
   int    dayCount[7];
   int    dayWins[7];
   ArrayInitialize(dayPL, 0);
   ArrayInitialize(dayCount, 0);
   ArrayInitialize(dayWins, 0);
   
   //--- Duration tracking
   double totalDurationSec = 0;
   double avgWinDuration = 0, avgLossDuration = 0;
   double winDurationTotal = 0, lossDurationTotal = 0;
   
   //--- Buy vs Sell tracking
   int    buyTrades = 0, sellTrades = 0;
   int    buyWins = 0, sellWins = 0;
   double buyPL = 0, sellPL = 0;
   
   //--- Lot size tracking
   double totalLots = 0;
   double minLot = 99999, maxLot = 0;
   
   //--- Recent trades for AI context (last 20)
   string recentTrades = "";
   int    recentCount = 0;
   
   //--- Process all deals
   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      
      //--- Get deal properties
      double profit     = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double swap       = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double commission  = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double volume     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double priceOpen  = HistoryDealGetDouble(ticket, DEAL_PRICE);
      string symbol     = HistoryDealGetString(ticket, DEAL_SYMBOL);
      long   dealType   = HistoryDealGetInteger(ticket, DEAL_TYPE);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      long   magic      = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      
      double netPL = profit + swap + commission;
      
      //--- Time analysis
      MqlDateTime mdt;
      TimeToStruct(dealTime, mdt);
      int hour = mdt.hour;
      int dow  = mdt.day_of_week; // 0=Sun, 1=Mon...6=Sat
      
      //--- Classify win/loss
      if(netPL > 0.01)
        {
         wins++;
         grossProfit += netPL;
         if(netPL > largestWin) largestWin = netPL;
         consecWins++;
         consecLosses = 0;
         if(consecWins > maxConsecWins) maxConsecWins = consecWins;
         hourWins[hour]++;
         dayWins[dow]++;
         if(dealType == DEAL_TYPE_BUY) { sellWins++; } // Closing a sell = was a sell trade
         else { buyWins++; }
        }
      else if(netPL < -0.01)
        {
         losses++;
         grossLoss += MathAbs(netPL);
         if(netPL < largestLoss) largestLoss = netPL;
         consecLosses++;
         consecWins = 0;
         if(consecLosses > maxConsecLosses) maxConsecLosses = consecLosses;
        }
      else
        {
         breakevens++;
        }
      
      //--- Running balance for drawdown calc
      runningBalance += netPL;
      if(runningBalance > peakBalance) peakBalance = runningBalance;
      double dd = peakBalance - runningBalance;
      if(dd > maxDrawdownAmt) maxDrawdownAmt = dd;
      if(peakBalance > 0)
        {
         double ddPct = dd / peakBalance * 100.0;
         if(ddPct > maxDrawdownPct) maxDrawdownPct = ddPct;
        }
      
      //--- Hour/Day tracking
      hourPL[hour] += netPL;
      hourCount[hour]++;
      dayPL[dow] += netPL;
      dayCount[dow]++;
      
      //--- Buy vs Sell
      if(dealType == DEAL_TYPE_SELL) // Closing buy = was a buy trade
        { buyTrades++; buyPL += netPL; }
      else
        { sellTrades++; sellPL += netPL; }
      
      //--- Lot tracking
      totalLots += volume;
      if(volume < minLot) minLot = volume;
      if(volume > maxLot) maxLot = volume;
      
      //--- Symbol tracking
      bool found = false;
      for(int s = 0; s < symArrSize; s++)
        {
         if(symbols[s] == symbol)
           {
            symbolPL[s] += netPL;
            symbolCount[s]++;
            if(netPL > 0) symbolWins[s]++;
            found = true;
            break;
           }
        }
      if(!found)
        {
         symArrSize++;
         ArrayResize(symbols, symArrSize);
         ArrayResize(symbolPL, symArrSize);
         ArrayResize(symbolCount, symArrSize);
         ArrayResize(symbolWins, symArrSize);
         symbols[symArrSize-1] = symbol;
         symbolPL[symArrSize-1] = netPL;
         symbolCount[symArrSize-1] = 1;
         symbolWins[symArrSize-1] = netPL > 0 ? 1 : 0;
        }
      
      //--- Recent trades (last 20)
      if(totalDeals - i <= 20)
        {
         recentTrades += "  " + TimeToString(dealTime, TIME_DATE|TIME_MINUTES);
         recentTrades += " " + symbol;
         recentTrades += " " + (dealType == DEAL_TYPE_SELL ? "BUY" : "SELL");
         recentTrades += " " + DoubleToString(volume, 2) + "lot";
         recentTrades += " PL=" + DoubleToString(netPL, 2);
         recentTrades += (netPL > 0 ? " ✅" : (netPL < 0 ? " ❌" : " ➖"));
         recentTrades += "\n";
         recentCount++;
        }
     }
   
   //--- Calculate derived metrics
   int totalClosed = wins + losses + breakevens;
   double winRate = totalClosed > 0 ? (double)wins / totalClosed * 100.0 : 0;
   double avgWin = wins > 0 ? grossProfit / wins : 0;
   double avgLoss = losses > 0 ? grossLoss / losses : 0;
   double profitFactor = grossLoss > 0 ? grossProfit / grossLoss : 999;
   double expectancy = totalClosed > 0 ? (grossProfit - grossLoss) / totalClosed : 0;
   double payoffRatio = avgLoss > 0 ? avgWin / avgLoss : 0;
   double avgLotSize = totalClosed > 0 ? totalLots / totalClosed : 0;
   double netProfit = grossProfit - grossLoss;
   
   //--- Sharpe-like ratio (simplified)
   double returnPct = accInfo.Balance() > 0 ? netProfit / accInfo.Balance() * 100.0 : 0;
   
   //--- Build report
   report += "  ── OVERALL PERFORMANCE (" + IntegerToString(InpHistoryDays) + " days) ──\n";
   report += "  Total Trades: " + IntegerToString(totalClosed) + "\n";
   report += "  Wins: " + IntegerToString(wins) + " | Losses: " + IntegerToString(losses) + " | BE: " + IntegerToString(breakevens) + "\n";
   report += "  Win Rate: " + DoubleToString(winRate, 1) + "%\n";
   report += "  Net Profit: " + DoubleToString(netProfit, 2) + "\n";
   report += "  Gross Profit: " + DoubleToString(grossProfit, 2) + " | Gross Loss: " + DoubleToString(grossLoss, 2) + "\n";
   report += "  Profit Factor: " + DoubleToString(profitFactor, 2) + "\n";
   report += "  Expectancy: " + DoubleToString(expectancy, 2) + " per trade\n";
   report += "  Payoff Ratio: " + DoubleToString(payoffRatio, 2) + " (avg win/avg loss)\n";
   report += "  Avg Win: " + DoubleToString(avgWin, 2) + " | Avg Loss: " + DoubleToString(avgLoss, 2) + "\n";
   report += "  Largest Win: " + DoubleToString(largestWin, 2) + " | Largest Loss: " + DoubleToString(largestLoss, 2) + "\n";
   report += "  Max Consec Wins: " + IntegerToString(maxConsecWins) + " | Max Consec Losses: " + IntegerToString(maxConsecLosses) + "\n";
   report += "  Max Drawdown: " + DoubleToString(maxDrawdownAmt, 2) + " (" + DoubleToString(maxDrawdownPct, 1) + "%)\n";
   
   //--- Buy vs Sell breakdown
   report += "\n  ── BUY vs SELL PERFORMANCE ──\n";
   double buyWR = buyTrades > 0 ? (double)buyWins / buyTrades * 100.0 : 0;
   double sellWR = sellTrades > 0 ? (double)sellWins / sellTrades * 100.0 : 0;
   report += "  Buy Trades: " + IntegerToString(buyTrades) + " | WR: " + DoubleToString(buyWR, 1) + "% | PL: " + DoubleToString(buyPL, 2) + "\n";
   report += "  Sell Trades: " + IntegerToString(sellTrades) + " | WR: " + DoubleToString(sellWR, 1) + "% | PL: " + DoubleToString(sellPL, 2) + "\n";
   report += "  Better Direction: " + (buyPL > sellPL ? "BUY" : "SELL") + "\n";
   
   //--- Per-Symbol Performance
   report += "\n  ── SYMBOL PERFORMANCE ──\n";
   for(int s = 0; s < symArrSize; s++)
     {
      double sWR = symbolCount[s] > 0 ? (double)symbolWins[s] / symbolCount[s] * 100.0 : 0;
      report += "  " + symbols[s] + ": " + IntegerToString(symbolCount[s]) + " trades";
      report += " | WR: " + DoubleToString(sWR, 1) + "%";
      report += " | PL: " + DoubleToString(symbolPL[s], 2);
      report += (symbolPL[s] >= 0 ? " ✅" : " ❌");
      report += "\n";
     }
   
   //--- Best/Worst Trading Hours (EST)
   report += "\n  ── HOURLY PERFORMANCE (Server Time) ──\n";
   int bestHour = 0, worstHour = 0;
   double bestHourPL = -99999, worstHourPL = 99999;
   for(int h = 0; h < 24; h++)
     {
      if(hourCount[h] > 0)
        {
         if(hourPL[h] > bestHourPL) { bestHourPL = hourPL[h]; bestHour = h; }
         if(hourPL[h] < worstHourPL) { worstHourPL = hourPL[h]; worstHour = h; }
         
         double hWR = (double)hourWins[h] / hourCount[h] * 100.0;
         report += "  " + StringFormat("%02d:00", h) + " - " + IntegerToString(hourCount[h]) + " trades";
         report += " | WR: " + DoubleToString(hWR, 0) + "%";
         report += " | PL: " + DoubleToString(hourPL[h], 2) + "\n";
        }
     }
   report += "  ★ Best Hour: " + StringFormat("%02d:00", bestHour) + " (+" + DoubleToString(bestHourPL, 2) + ")\n";
   report += "  ✗ Worst Hour: " + StringFormat("%02d:00", worstHour) + " (" + DoubleToString(worstHourPL, 2) + ")\n";
   
   //--- Day of Week Performance
   report += "\n  ── DAY OF WEEK PERFORMANCE ──\n";
   string dayNames[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   int bestDay = 0, worstDay = 0;
   double bestDayPL = -99999, worstDayPL = 99999;
   for(int d = 0; d < 7; d++)
     {
      if(dayCount[d] > 0)
        {
         if(dayPL[d] > bestDayPL) { bestDayPL = dayPL[d]; bestDay = d; }
         if(dayPL[d] < worstDayPL) { worstDayPL = dayPL[d]; worstDay = d; }
         
         double dWR = (double)dayWins[d] / dayCount[d] * 100.0;
         report += "  " + dayNames[d] + ": " + IntegerToString(dayCount[d]) + " trades";
         report += " | WR: " + DoubleToString(dWR, 0) + "%";
         report += " | PL: " + DoubleToString(dayPL[d], 2) + "\n";
        }
     }
   report += "  ★ Best Day: " + dayNames[bestDay] + " (+" + DoubleToString(bestDayPL, 2) + ")\n";
   report += "  ✗ Worst Day: " + dayNames[worstDay] + " (" + DoubleToString(worstDayPL, 2) + ")\n";
   
   //--- Lot Size Analysis
   report += "\n  ── POSITION SIZING ──\n";
   report += "  Avg Lot: " + DoubleToString(avgLotSize, 3) + "\n";
   report += "  Min Lot: " + DoubleToString(minLot, 3) + " | Max Lot: " + DoubleToString(maxLot, 3) + "\n";
   
   //--- AI Recommendations based on data
   report += "\n  ── AI RECOMMENDATIONS ──\n";
   if(winRate < 45) report += "  ⚠️ Low win rate - tighten entry criteria\n";
   if(profitFactor < 1.0) report += "  ⚠️ Profit factor < 1 - system is losing money\n";
   if(profitFactor >= 1.5) report += "  ✅ Strong profit factor\n";
   if(payoffRatio < 1.0) report += "  ⚠️ Avg win < avg loss - need better R:R\n";
   if(maxConsecLosses > 5) report += "  ⚠️ " + IntegerToString(maxConsecLosses) + " consec losses detected - add streak protection\n";
   if(maxDrawdownPct > 20) report += "  🛑 Max DD > 20% - reduce risk per trade\n";
   if(buyPL > sellPL * 2 && sellPL < 0) report += "  💡 Sells are losing - consider BUY ONLY mode\n";
   if(sellPL > buyPL * 2 && buyPL < 0) report += "  💡 Buys are losing - consider SELL ONLY mode\n";
   report += "  💡 Best trading window: " + dayNames[bestDay] + " at " + StringFormat("%02d:00", bestHour) + "\n";
   report += "  💡 Avoid: " + dayNames[worstDay] + " at " + StringFormat("%02d:00", worstHour) + "\n";
   
   //--- Recent Trades
   if(recentCount > 0)
     {
      report += "\n  ── LAST " + IntegerToString(recentCount) + " TRADES ──\n";
      report += recentTrades;
     }
   
   return report;
  }

//+------------------------------------------------------------------+
//| Call Claude API via WebRequest                                    |
//+------------------------------------------------------------------+
string CallClaudeAPI(string marketData)
  {
   if(InpApiKey == "" || StringFind(InpApiKey, "sk-ant-") < 0)
     {
      //--- Demo mode: generate local signal
      return GenerateLocalSignal(marketData);
     }
   
   g_aiCalls++;
   
   //--- Build the AI prompt
   string confidenceLevel = "70";
   if(InpAggression == AI_CONSERVATIVE) confidenceLevel = "85";
   if(InpAggression == AI_AGGRESSIVE) confidenceLevel = "55";
   
   string systemPrompt = 
      "You are JazzyLyfe AI Trading Engine, an expert algorithmic trader. "
      "Analyze the market data AND the trader's complete history to make informed decisions. "
      "You must respond in EXACTLY this format with no other text:\\n"
      "SIGNAL: BUY or SELL or HOLD\\n"
      "CONFIDENCE: 0-100\\n"
      "SL_PIPS: number (stop loss in pips from entry)\\n"
      "TP_PIPS: number (take profit in pips from entry)\\n"
      "REASON: one line explanation\\n\\n"
      "Rules:\\n"
      "- Only signal BUY/SELL if confidence >= " + confidenceLevel + "\\n"
      "- STUDY the TRADE_HISTORY_ANALYSIS section carefully\\n"
      "- Avoid trading during hours/days that historically lose money\\n"
      "- If buys historically outperform sells (or vice versa), bias toward the winning direction\\n"
      "- If the worst performing symbol is current symbol, require higher confidence\\n"
      "- Factor in recent consecutive wins/losses (reduce size after losing streaks)\\n"
      "- If drawdown is high, signal HOLD until conditions improve\\n"
      "- If profit factor < 1.0, be extra selective and only take A+ setups\\n"
      "- Consider trend alignment across timeframes\\n"
      "- Respect Smart Money Concepts (order blocks, FVG, liquidity)\\n"
      "- Minimum 1.5:1 reward-to-risk ratio\\n"
      "- Be conservative in ranging/choppy markets\\n"
      "- Factor in current session and volatility\\n"
      "- Learn from past mistakes in the trade history";
   
   string userMessage = "Analyze this live market data and provide your trading decision:\\n\\n" + marketData;
   
   //--- Build JSON request body
   string model = GetModelString();
   string body = 
      "{\"model\":\"" + model + "\","
      "\"max_tokens\":" + IntegerToString(InpMaxTokens) + ","
      "\"system\":\"" + EscapeJSON(systemPrompt) + "\","
      "\"messages\":[{\"role\":\"user\",\"content\":\"" + EscapeJSON(userMessage) + "\"}]}";
   
   //--- Prepare request
   string url = "https://api.anthropic.com/v1/messages";
   string headers = 
      "Content-Type: application/json\r\n"
      "x-api-key: " + InpApiKey + "\r\n"
      "anthropic-version: 2023-06-01\r\n";
   
   char postData[];
   StringToCharArray(body, postData, 0, WHOLE_ARRAY, CP_UTF8);
   // Remove null terminator
   ArrayResize(postData, ArraySize(postData) - 1);
   
   char result[];
   string responseHeaders;
   
   //--- Send request
   int timeout = InpRequestTimeout;
   int res = WebRequest("POST", url, headers, timeout, postData, result, responseHeaders);
   
   if(res == -1)
     {
      int err = GetLastError();
      Print("❌ WebRequest failed! Error: ", err);
      if(err == 4014)
        {
         Print("   → Add https://api.anthropic.com to allowed URLs in MT5");
         Print("   → Tools > Options > Expert Advisors > Allow WebRequest");
        }
      g_aiFails++;
      return "";
     }
   
   string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   
   if(res != 200)
     {
      Print("❌ API Error (HTTP ", res, "): ", StringSubstr(response, 0, 200));
      g_aiFails++;
      return "";
     }
   
   //--- Extract text content from Claude response
   string content = ExtractJSONContent(response);
   
   if(content == "")
     {
      Print("⚠️ Empty AI response");
      g_aiFails++;
      return "";
     }
   
   Print("🤖 Claude Response: ", StringSubstr(content, 0, 200));
   return content;
  }

//+------------------------------------------------------------------+
//| Generate Local Signal (Demo Mode - No API Key)                    |
//+------------------------------------------------------------------+
string GenerateLocalSignal(string marketData)
  {
   //--- Use technical indicators to generate signal locally
   double rsi[], macdMain[], macdSignal[], ema21[], ema50[], ema200[], atr[];
   double stochK[], stochD[], adxMain[], adxPlus[], adxMinus[], sar[];
   
   CopyBuffer(h_RSI, 0, 0, 3, rsi);
   CopyBuffer(h_MACD, 0, 0, 3, macdMain);
   CopyBuffer(h_MACD, 1, 0, 3, macdSignal);
   CopyBuffer(h_EMA21, 0, 0, 3, ema21);
   CopyBuffer(h_EMA50, 0, 0, 3, ema50);
   CopyBuffer(h_EMA200, 0, 0, 3, ema200);
   CopyBuffer(h_ATR, 0, 0, 3, atr);
   CopyBuffer(h_Stoch, 0, 0, 3, stochK);
   CopyBuffer(h_Stoch, 1, 0, 3, stochD);
   CopyBuffer(h_ADX, 0, 0, 3, adxMain);
   CopyBuffer(h_ADX, 1, 0, 3, adxPlus);
   CopyBuffer(h_ADX, 2, 0, 3, adxMinus);
   CopyBuffer(h_SAR, 0, 0, 3, sar);
   
   if(ArraySize(rsi) < 2) return "";
   
   double bid = symInfo.Bid();
   int buyScore = 0, sellScore = 0;
   string reasons = "";
   
   //--- RSI
   if(rsi[0] < 30) { buyScore += 2; reasons += "RSI_oversold "; }
   else if(rsi[0] > 70) { sellScore += 2; reasons += "RSI_overbought "; }
   else if(rsi[0] < 45) { buyScore += 1; }
   else if(rsi[0] > 55) { sellScore += 1; }
   
   //--- MACD
   if(macdMain[0] > macdSignal[0] && macdMain[1] <= macdSignal[1]) { buyScore += 2; reasons += "MACD_cross_up "; }
   else if(macdMain[0] < macdSignal[0] && macdMain[1] >= macdSignal[1]) { sellScore += 2; reasons += "MACD_cross_down "; }
   else if(macdMain[0] > macdSignal[0]) buyScore += 1;
   else sellScore += 1;
   
   //--- EMA Alignment
   if(ema21[0] > ema50[0] && ema50[0] > ema200[0]) { buyScore += 2; reasons += "EMA_bullish "; }
   else if(ema21[0] < ema50[0] && ema50[0] < ema200[0]) { sellScore += 2; reasons += "EMA_bearish "; }
   
   //--- Price vs EMAs
   if(bid > ema21[0] && bid > ema50[0]) buyScore += 1;
   else if(bid < ema21[0] && bid < ema50[0]) sellScore += 1;
   
   //--- Stochastic
   if(stochK[0] < 20 && stochK[0] > stochD[0]) { buyScore += 1; reasons += "Stoch_oversold "; }
   else if(stochK[0] > 80 && stochK[0] < stochD[0]) { sellScore += 1; reasons += "Stoch_overbought "; }
   
   //--- ADX Trend Strength
   if(adxMain[0] > 25 && adxPlus[0] > adxMinus[0]) { buyScore += 1; reasons += "ADX_trend_up "; }
   else if(adxMain[0] > 25 && adxMinus[0] > adxPlus[0]) { sellScore += 1; reasons += "ADX_trend_down "; }
   
   //--- Parabolic SAR
   if(sar[0] < bid) { buyScore += 1; reasons += "SAR_below "; }
   else { sellScore += 1; reasons += "SAR_above "; }
   
   //--- Generate signal
   int totalScore = buyScore + sellScore;
   if(totalScore == 0) totalScore = 1;
   
   double atrVal = atr[0];
   double slPips = (atrVal * InpATRSLMulti) / symInfo.Point() / 10.0;
   double tpPips = (atrVal * InpATRTPMulti) / symInfo.Point() / 10.0;
   
   string signal = "HOLD";
   double confidence = 0;
   
   if(buyScore > sellScore + 2)
     {
      signal = "BUY";
      confidence = MathMin(95, 50.0 + (buyScore - sellScore) * 7);
     }
   else if(sellScore > buyScore + 2)
     {
      signal = "SELL";
      confidence = MathMin(95, 50.0 + (sellScore - buyScore) * 7);
     }
   else
     {
      confidence = 30;
     }
   
   string result = "SIGNAL: " + signal + "\n";
   result += "CONFIDENCE: " + DoubleToString(confidence, 0) + "\n";
   result += "SL_PIPS: " + DoubleToString(slPips, 1) + "\n";
   result += "TP_PIPS: " + DoubleToString(tpPips, 1) + "\n";
   result += "REASON: LOCAL_ENGINE " + reasons + "(B:" + IntegerToString(buyScore) + " S:" + IntegerToString(sellScore) + ")";
   
   Print("🧠 Local Engine: ", signal, " | Conf: ", DoubleToString(confidence, 0), "% | ", reasons);
   return result;
  }

//+------------------------------------------------------------------+
//| Parse AI Response                                                 |
//+------------------------------------------------------------------+
void ParseAIResponse(string response)
  {
   //--- Extract SIGNAL
   g_lastSignal = ExtractField(response, "SIGNAL:");
   StringTrimLeft(g_lastSignal);
   StringTrimRight(g_lastSignal);
   
   //--- Extract CONFIDENCE
   string confStr = ExtractField(response, "CONFIDENCE:");
   g_aiConfidence = StringToDouble(confStr);
   
   //--- Extract SL_PIPS
   string slStr = ExtractField(response, "SL_PIPS:");
   g_aiSL = StringToDouble(slStr);
   
   //--- Extract TP_PIPS
   string tpStr = ExtractField(response, "TP_PIPS:");
   g_aiTP = StringToDouble(tpStr);
   
   //--- Extract REASON
   g_lastReason = ExtractField(response, "REASON:");
   StringTrimLeft(g_lastReason);
   StringTrimRight(g_lastReason);
   
   //--- Count signals
   if(g_lastSignal == "BUY") g_signalBuy++;
   else if(g_lastSignal == "SELL") g_signalSell++;
   else g_signalHold++;
   
   Print("📊 AI Signal: ", g_lastSignal, " | Conf: ", g_aiConfidence, 
         "% | SL: ", g_aiSL, " | TP: ", g_aiTP, " | ", g_lastReason);
  }

//+------------------------------------------------------------------+
//| Extract a field value from response text                          |
//+------------------------------------------------------------------+
string ExtractField(string text, string field)
  {
   int pos = StringFind(text, field);
   if(pos < 0) return "";
   
   int start = pos + StringLen(field);
   int end = StringFind(text, "\n", start);
   if(end < 0) end = StringLen(text);
   
   string value = StringSubstr(text, start, end - start);
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

//+------------------------------------------------------------------+
//| Execute AI Signal                                                 |
//+------------------------------------------------------------------+
void ExecuteAISignal()
  {
   //--- Validate signal
   if(g_lastSignal != "BUY" && g_lastSignal != "SELL") return;
   
   //--- Apply Inverse Mode
   string signal = g_lastSignal;
   if(InpInverseMode)
     {
      signal = (signal == "BUY") ? "SELL" : "BUY";
      Print("🔄 Inverse Mode: Flipped to ", signal);
     }
   
   //--- Check Trade Direction Filter
   if(InpTradeDir == TRADE_BUY && signal == "SELL") { Print("⛔ Sell blocked by direction filter"); return; }
   if(InpTradeDir == TRADE_SELL && signal == "BUY") { Print("⛔ Buy blocked by direction filter"); return; }
   
   //--- Check confidence threshold
   double minConf = 70;
   if(InpAggression == AI_CONSERVATIVE) minConf = 85;
   if(InpAggression == AI_AGGRESSIVE) minConf = 55;
   if(g_aiConfidence < minConf) { Print("⏸ Confidence too low: ", g_aiConfidence, "% < ", minConf, "%"); return; }
   
   //--- Check session
   if(!IsSessionAllowed()) { Print("⏸ Outside allowed session"); return; }
   
   //--- Check spread
   if(symInfo.Spread() > InpMaxSpread) { Print("⏸ Spread too high: ", symInfo.Spread()); return; }
   
   //--- Check max trades
   if(CountPositions() >= InpMaxTrades) { Print("⏸ Max trades reached: ", CountPositions()); return; }
   
   //--- Close opposite positions
   if(InpCloseOpposite)
      CloseOppositePositions(signal == "BUY" ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
   
   //--- Calculate lot size
   double atr[];
   CopyBuffer(h_ATR, 0, 0, 1, atr);
   double atrVal = (ArraySize(atr) > 0) ? atr[0] : 0.001;
   
   double slDistance = g_aiSL * 10 * symInfo.Point();  // Convert pips to price
   if(slDistance <= 0) slDistance = atrVal * InpATRSLMulti;
   
   double tpDistance = g_aiTP * 10 * symInfo.Point();
   if(tpDistance <= 0) tpDistance = atrVal * InpATRTPMulti;
   
   //--- Check min R:R
   if(tpDistance / slDistance < InpMinRR)
     {
      tpDistance = slDistance * InpMinRR;
      Print("📐 Adjusted TP for minimum R:R of ", InpMinRR);
     }
   
   double lots = CalculateLotSize(slDistance);
   
   //--- Execute trade
   double price, sl, tp;
   
   if(signal == "BUY")
     {
      price = symInfo.Ask();
      sl    = NormalizeDouble(price - slDistance, _Digits);
      tp    = NormalizeDouble(price + tpDistance, _Digits);
      
      if(trade.Buy(lots, _Symbol, price, sl, tp, "JZAI|" + g_lastSignal + "|" + DoubleToString(g_aiConfidence, 0) + "%"))
        {
         g_totalTrades++;
         Print("✅ BUY ", lots, " @ ", price, " SL:", sl, " TP:", tp, " | AI Conf: ", g_aiConfidence, "%");
        }
      else
         Print("❌ Buy failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }
   else if(signal == "SELL")
     {
      price = symInfo.Bid();
      sl    = NormalizeDouble(price + slDistance, _Digits);
      tp    = NormalizeDouble(price - tpDistance, _Digits);
      
      if(trade.Sell(lots, _Symbol, price, sl, tp, "JZAI|" + g_lastSignal + "|" + DoubleToString(g_aiConfidence, 0) + "%"))
        {
         g_totalTrades++;
         Print("✅ SELL ", lots, " @ ", price, " SL:", sl, " TP:", tp, " | AI Conf: ", g_aiConfidence, "%");
        }
      else
         Print("❌ Sell failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
  {
   double lots = InpFixedLots;
   
   if(InpRiskMode == RISK_PERCENT || InpRiskMode == RISK_ATR)
     {
      double riskAmount = accInfo.Balance() * InpRiskPercent / 100.0;
      double tickValue  = symInfo.TickValue();
      double tickSize   = symInfo.TickSize();
      
      if(tickValue > 0 && tickSize > 0 && slDistance > 0)
        {
         double slTicks = slDistance / tickSize;
         lots = riskAmount / (slTicks * tickValue);
        }
     }
   else if(InpRiskMode == RISK_KELLY)
     {
      //--- Kelly Criterion: f* = (bp - q) / b
      double winRate = g_totalTrades > 0 ? (double)g_winTrades / g_totalTrades : 0.5;
      double avgWin = 1.5, avgLoss = 1.0;  // Default R:R
      double b = avgWin / avgLoss;
      double p = winRate;
      double q = 1.0 - p;
      double kelly = (b * p - q) / b;
      kelly = MathMax(0.01, MathMin(kelly, 0.25));  // Cap at 25%
      
      double riskAmount = accInfo.Balance() * kelly;
      double tickValue = symInfo.TickValue();
      double tickSize  = symInfo.TickSize();
      
      if(tickValue > 0 && tickSize > 0 && slDistance > 0)
        {
         double slTicks = slDistance / tickSize;
         lots = riskAmount / (slTicks * tickValue);
        }
     }
   
   //--- Normalize lots
   double minLot  = symInfo.LotsMin();
   double maxLot  = symInfo.LotsMax();
   double lotStep = symInfo.LotsStep();
   
   lots = MathMax(minLot, lots);
   lots = MathMin(maxLot, lots);
   lots = NormalizeDouble(MathFloor(lots / lotStep) * lotStep, 2);
   
   return lots;
  }

//+------------------------------------------------------------------+
//| Count My Positions                                                |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Close Opposite Positions                                          |
//+------------------------------------------------------------------+
void CloseOppositePositions(ENUM_POSITION_TYPE type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Magic() == InpMagicNumber && posInfo.Symbol() == _Symbol && 
            posInfo.PositionType() == type)
           {
            for(int r = 0; r < 5; r++) {
               if(trade.PositionClose(posInfo.Ticket())) break;
               Sleep(200);
            }
            
            //--- Track P&L
            double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            g_totalProfit += profit;
            if(profit >= 0) g_winTrades++;
            else g_lossTrades++;
            
            Print("🔄 Closed opposite ", EnumToString(type), " | P/L: ", DoubleToString(profit, 2));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage Open Positions (Trailing, Breakeven)                       |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != InpMagicNumber || posInfo.Symbol() != _Symbol) continue;
      
      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      double curTP     = posInfo.TakeProfit();
      double bid       = symInfo.Bid();
      double ask       = symInfo.Ask();
      double point     = symInfo.Point();
      
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double profitPoints = (bid - openPrice) / point;
         
         //--- Breakeven
         if(InpUseBreakeven && profitPoints >= InpBEActivation && curSL < openPrice)
           {
            double newSL = NormalizeDouble(openPrice + InpBEOffset * point, _Digits);
            if(newSL > curSL)
              {
               trade.PositionModify(posInfo.Ticket(), newSL, curTP);
               Print("🎯 BE activated for BUY #", posInfo.Ticket());
              }
           }
         
         //--- Trailing Stop
         if(InpUseTrailing && profitPoints >= InpTrailingStart)
           {
            double newSL = NormalizeDouble(bid - InpTrailingStep * point, _Digits);
            if(newSL > curSL + point)
              {
               trade.PositionModify(posInfo.Ticket(), newSL, curTP);
              }
           }
        }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double profitPoints = (openPrice - ask) / point;
         
         //--- Breakeven
         if(InpUseBreakeven && profitPoints >= InpBEActivation && (curSL > openPrice || curSL == 0))
           {
            double newSL = NormalizeDouble(openPrice - InpBEOffset * point, _Digits);
            if(newSL < curSL || curSL == 0)
              {
               trade.PositionModify(posInfo.Ticket(), newSL, curTP);
               Print("🎯 BE activated for SELL #", posInfo.Ticket());
              }
           }
         
         //--- Trailing Stop
         if(InpUseTrailing && profitPoints >= InpTrailingStart)
           {
            double newSL = NormalizeDouble(ask + InpTrailingStep * point, _Digits);
            if(newSL < curSL - point || curSL == 0)
              {
               trade.PositionModify(posInfo.Ticket(), newSL, curTP);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Safety Limits                                               |
//+------------------------------------------------------------------+
void CheckSafetyLimits()
  {
   //--- Max Drawdown Check
   double equity = accInfo.Equity();
   if(equity > g_maxEquity) g_maxEquity = equity;
   
   double drawdown = (g_maxEquity - equity) / g_maxEquity * 100.0;
   if(drawdown >= InpMaxDrawdown && !g_tradingPaused)
     {
      g_tradingPaused = true;
      g_pauseReason = "Max DD " + DoubleToString(drawdown, 1) + "% reached!";
      Print("🛑 TRADING PAUSED: ", g_pauseReason);
     }
   
   //--- Daily Loss Limit
   double dayPL = equity - g_dayStartBalance;
   double dayLossPct = -dayPL / g_dayStartBalance * 100.0;
   if(dayPL < 0 && dayLossPct >= InpDailyLossLimit && !g_tradingPaused)
     {
      g_tradingPaused = true;
      g_pauseReason = "Daily loss limit " + DoubleToString(dayLossPct, 1) + "% reached!";
      Print("🛑 TRADING PAUSED: ", g_pauseReason);
     }
  }

//+------------------------------------------------------------------+
//| JSON Helpers                                                      |
//+------------------------------------------------------------------+
string EscapeJSON(string text)
  {
   string result = text;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
  }

string ExtractJSONContent(string json)
  {
   //--- Find "text":" in the response
   int pos = StringFind(json, "\"text\":\"");
   if(pos < 0)
     {
      pos = StringFind(json, "\"text\": \"");
      if(pos < 0) return "";
      pos += 9;
     }
   else
      pos += 8;
   
   //--- Find the closing quote (handle escaped quotes)
   string content = "";
   bool escaped = false;
   for(int i = pos; i < StringLen(json); i++)
     {
      ushort ch = StringGetCharacter(json, i);
      if(escaped)
        {
         if(ch == 'n') content += "\n";
         else if(ch == 'r') content += "\r";
         else if(ch == 't') content += "\t";
         else if(ch == '"') content += "\"";
         else if(ch == '\\') content += "\\";
         else { content += "\\"; content += ShortToString(ch); }
         escaped = false;
        }
      else
        {
         if(ch == '\\') escaped = true;
         else if(ch == '"') break;
         else content += ShortToString(ch);
        }
     }
   
   return content;
  }

//+------------------------------------------------------------------+
//| Get Model Name for Display                                        |
//+------------------------------------------------------------------+
string GetModelName()
  {
   switch(InpModel)
     {
      case MODEL_SONNET: return "Claude Sonnet 4.5";
      case MODEL_OPUS:   return "Claude Opus 4.6";
      case MODEL_HAIKU:  return "Claude Haiku 4.5";
      default:           return "Claude Sonnet 4.5";
     }
  }

//+------------------------------------------------------------------+
//| Get Model API String                                              |
//+------------------------------------------------------------------+
string GetModelString()
  {
   switch(InpModel)
     {
      case MODEL_SONNET: return "claude-sonnet-4-5-20250929";
      case MODEL_OPUS:   return "claude-opus-4-6";
      case MODEL_HAIKU:  return "claude-haiku-4-5-20251001";
      default:           return "claude-sonnet-4-5-20250929";
     }
  }

//+------------------------------------------------------------------+
//| DASHBOARD                                                         |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   ObjectsDeleteAll(0, "JZAI_");
  }

void UpdateDashboard()
  {
   int x = InpDashX, y = InpDashY;
   int w = 320;
   int lineH = 16;
   int row = 0;
   
   //--- Background
   CreateRect("JZAI_BG", x-5, y-5, w+10, lineH * 24 + 15, InpDashBg);
   
   //--- Header
   CreateLabel("JZAI_H1", x, y + lineH * row++, "⚡ JAZZYLYFE CLAUDE AI ENGINE ⚡", InpDashAccent, 10, true);
   CreateLabel("JZAI_H2", x, y + lineH * row++, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", InpDashAccent, 8);
   
   //--- Connection Status
   string apiStatus = (InpApiKey != "" && StringFind(InpApiKey, "sk-ant-") >= 0) ? "🟢 CLAUDE API CONNECTED" : "🟡 LOCAL ENGINE (No API Key)";
   CreateLabel("JZAI_API", x, y + lineH * row++, apiStatus, clrYellow, 8);
   CreateLabel("JZAI_MDL", x, y + lineH * row++, "Model: " + GetModelName(), InpDashText, 8);
   
   //--- Account
   CreateLabel("JZAI_S1", x, y + lineH * row++, "── Account ──", clrDarkGray, 8);
   CreateLabel("JZAI_BAL", x, y + lineH * row++, "Balance: " + DoubleToString(accInfo.Balance(), 2) + " " + accInfo.Currency(), InpDashText, 8);
   CreateLabel("JZAI_EQ",  x, y + lineH * row++, "Equity:  " + DoubleToString(accInfo.Equity(), 2), InpDashText, 8);
   
   double dd = g_maxEquity > 0 ? (g_maxEquity - accInfo.Equity()) / g_maxEquity * 100.0 : 0;
   color ddColor = dd > 10 ? clrRed : (dd > 5 ? clrOrange : clrLime);
   CreateLabel("JZAI_DD",  x, y + lineH * row++, "Drawdown: " + DoubleToString(dd, 1) + "%", ddColor, 8);
   
   //--- AI Signal
   CreateLabel("JZAI_S2", x, y + lineH * row++, "── AI Signal ──", clrDarkGray, 8);
   color sigColor = g_lastSignal == "BUY" ? clrLime : (g_lastSignal == "SELL" ? clrRed : clrGray);
   CreateLabel("JZAI_SIG", x, y + lineH * row++, "Signal: " + g_lastSignal + " | Conf: " + DoubleToString(g_aiConfidence, 0) + "%", sigColor, 9, true);
   CreateLabel("JZAI_RSN", x, y + lineH * row++, StringSubstr(g_lastReason, 0, 45), InpDashText, 7);
   CreateLabel("JZAI_STP", x, y + lineH * row++, "SL: " + DoubleToString(g_aiSL, 1) + " pips | TP: " + DoubleToString(g_aiTP, 1) + " pips", InpDashText, 8);
   
   //--- Mode
   string modeStr = "";
   if(InpInverseMode) modeStr += "🔄INVERSE ";
   if(InpTradeDir == TRADE_BUY) modeStr += "⬆️BUY_ONLY ";
   else if(InpTradeDir == TRADE_SELL) modeStr += "⬇️SELL_ONLY ";
   if(modeStr == "") modeStr = "NORMAL";
   CreateLabel("JZAI_MOD", x, y + lineH * row++, "Mode: " + modeStr, clrCyan, 8);
   
   //--- Stats
   CreateLabel("JZAI_S3", x, y + lineH * row++, "── Statistics ──", clrDarkGray, 8);
   CreateLabel("JZAI_TR",  x, y + lineH * row++, "Trades: " + IntegerToString(g_totalTrades) + " | W: " + IntegerToString(g_winTrades) + " L: " + IntegerToString(g_lossTrades), InpDashText, 8);
   
   double wr = g_totalTrades > 0 ? (double)g_winTrades / g_totalTrades * 100.0 : 0;
   CreateLabel("JZAI_WR",  x, y + lineH * row++, "Win Rate: " + DoubleToString(wr, 1) + "%", wr >= 60 ? clrLime : (wr >= 45 ? clrYellow : clrRed), 8);
   
   color plColor = g_totalProfit >= 0 ? clrLime : clrRed;
   CreateLabel("JZAI_PL",  x, y + lineH * row++, "Total P/L: " + DoubleToString(g_totalProfit, 2), plColor, 8);
   
   CreateLabel("JZAI_AI",  x, y + lineH * row++, "AI Calls: " + IntegerToString(g_aiCalls) + " | Fails: " + IntegerToString(g_aiFails), InpDashText, 8);
   CreateLabel("JZAI_SG",  x, y + lineH * row++, "Signals B:" + IntegerToString(g_signalBuy) + " S:" + IntegerToString(g_signalSell) + " H:" + IntegerToString(g_signalHold), InpDashText, 8);
   
   //--- Status
   CreateLabel("JZAI_S4", x, y + lineH * row++, "── Status ──", clrDarkGray, 8);
   string sessStr = GetCurrentSession();
   bool sessOK = IsSessionAllowed();
   CreateLabel("JZAI_SESS", x, y + lineH * row++, "Session: " + sessStr, sessOK ? clrLime : clrGray, 8);
   
   if(g_tradingPaused)
      CreateLabel("JZAI_PAUS", x, y + lineH * row++, "🛑 PAUSED: " + g_pauseReason, clrRed, 8, true);
   else
      CreateLabel("JZAI_PAUS", x, y + lineH * row++, "🟢 ACTIVE | Spread: " + IntegerToString(symInfo.Spread()), clrLime, 8);
   
   //--- Next analysis
   int nextIn = (int)(InpAnalysisInterval - (TimeCurrent() - g_lastAnalysis));
   if(nextIn < 0) nextIn = 0;
   CreateLabel("JZAI_NXT", x, y + lineH * row++, "Next AI scan in: " + IntegerToString(nextIn) + "s", clrSilver, 8);
   
   //--- Trade History Summary
   CreateLabel("JZAI_S5", x, y + lineH * row++, "── History Analysis ──", clrDarkGray, 8);
   
   //--- Quick history scan for dashboard
   datetime hFrom = TimeCurrent() - InpHistoryDays * 24 * 3600;
   HistorySelect(hFrom, TimeCurrent());
   int hDeals = HistoryDealsTotal();
   int hWins = 0, hLosses = 0;
   double hGrossP = 0, hGrossL = 0, hNet = 0;
   
   for(int hi = 0; hi < hDeals; hi++)
     {
      ulong ht = HistoryDealGetTicket(hi);
      if(ht == 0) continue;
      long hEntry = HistoryDealGetInteger(ht, DEAL_ENTRY);
      if(hEntry != DEAL_ENTRY_OUT && hEntry != DEAL_ENTRY_OUT_BY) continue;
      double hpl = HistoryDealGetDouble(ht, DEAL_PROFIT) + HistoryDealGetDouble(ht, DEAL_SWAP) + HistoryDealGetDouble(ht, DEAL_COMMISSION);
      hNet += hpl;
      if(hpl > 0.01) { hWins++; hGrossP += hpl; }
      else if(hpl < -0.01) { hLosses++; hGrossL += MathAbs(hpl); }
     }
   
   int hTotal = hWins + hLosses;
   double hWR = hTotal > 0 ? (double)hWins / hTotal * 100.0 : 0;
   double hPF = hGrossL > 0 ? hGrossP / hGrossL : 0;
   
   CreateLabel("JZAI_HT", x, y + lineH * row++, "" + IntegerToString(InpHistoryDays) + "d: " + IntegerToString(hTotal) + " trades | WR: " + DoubleToString(hWR, 1) + "%", hWR >= 50 ? clrLime : clrOrange, 8);
   color hNetClr = hNet >= 0 ? clrLime : clrRed;
   CreateLabel("JZAI_HN", x, y + lineH * row++, "Net: " + DoubleToString(hNet, 2) + " | PF: " + DoubleToString(hPF, 2), hNetClr, 8);
   
   //--- Resize background
   CreateRect("JZAI_BG", InpDashX-5, InpDashY-5, w+10, lineH * (row+1) + 10, InpDashBg);
   
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Dashboard Helper: Create Label                                    |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize=8, bool bold=false)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Consolas");
  }

//+------------------------------------------------------------------+
//| Dashboard Helper: Create Rectangle                                |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDarkSlateGray);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

//+------------------------------------------------------------------+
//| Trade Event Handler                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      CDealInfo deal;
      if(deal.SelectByIndex(HistoryDealsTotal() - 1))
        {
         if(deal.Magic() == InpMagicNumber && deal.Symbol() == _Symbol)
           {
            if(deal.Entry() == DEAL_ENTRY_OUT || deal.Entry() == DEAL_ENTRY_OUT_BY)
              {
               double profit = deal.Profit() + deal.Swap() + deal.Commission();
               g_totalProfit += profit;
               if(profit >= 0) g_winTrades++;
               else g_lossTrades++;
               
               Print("📊 Trade closed: P/L = ", DoubleToString(profit, 2), 
                     " | Total: ", DoubleToString(g_totalProfit, 2),
                     " | WR: ", g_totalTrades > 0 ? DoubleToString((double)g_winTrades/g_totalTrades*100, 1) + "%" : "N/A");
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
