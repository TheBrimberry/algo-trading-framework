//+------------------------------------------------------------------+
//|          JazzyLyfe_UltProfit_v8.mq5                             |
//|          Ultimate Profit EA — FTMO Edition                       |
//|          Author  : JazzyLyfe Trading Systems                     |
//|          Version : 8.0 | Magic: 777000 | Grade A++              |
//|          Fixes   : SL enforcement, MTF filter, signal quality,  |
//|                    position sizing, over-trading prevention       |
//+------------------------------------------------------------------+
#property copyright "JazzyLyfe Trading Systems"
#property version   "8.00"
#property description "UltProfit v8 — FTMO-compliant multi-signal EA with MTF bias"

#include "JazzyLyfe_FTMO_Safeguard.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- EA Identity
input group "=== JAZZYLYFE ULTPROFIT v8 ==="
input int      EA_Magic           = 777000;    // Magic Number
input string   EA_Comment         = "UltProfit v8 - JazzyLyfe";

//--- Trade Direction
input group "=== TRADE DIRECTION ==="
input bool     Allow_Buy          = true;      // Allow BUY trades
input bool     Allow_Sell         = true;      // Allow SELL trades
input bool     InverseMode        = false;     // Inverse Mode (flip all signals)

//--- Risk Management
input group "=== RISK MANAGEMENT ==="
input double   RiskPerTrade_Pct   = 0.8;      // Risk per trade % (FTMO safe = 0.8%)
input double   ATR_SL_Multiplier  = 2.5;      // ATR multiplier for stop loss
input double   ATR_TP_Multiplier  = 4.0;      // ATR multiplier for take profit
input double   MaxLotSize         = 2.0;      // Hard max lot size cap
input int      MaxOpenTrades      = 3;        // Max concurrent positions

//--- Signal Parameters
input group "=== SIGNAL ENGINE ==="
input int      EMA_Fast           = 21;       // Fast EMA period
input int      EMA_Slow           = 50;       // Slow EMA period
input int      EMA_Trend          = 200;      // Trend EMA period
input int      RSI_Period         = 14;       // RSI period
input double   RSI_Oversold       = 35.0;     // RSI oversold level
input double   RSI_Overbought     = 65.0;     // RSI overbought level
input int      MACD_Fast          = 12;       // MACD fast
input int      MACD_Slow          = 26;       // MACD slow
input int      MACD_Signal        = 9;        // MACD signal
input int      ATR_Period         = 14;       // ATR period
input int      MinSignals         = 4;        // Minimum signals required (out of 6)

//--- Multi-Timeframe Filter
input group "=== MULTI-TIMEFRAME ==="
input ENUM_TIMEFRAMES TF_Entry    = PERIOD_M15;  // Entry timeframe
input ENUM_TIMEFRAMES TF_Filter   = PERIOD_H1;   // Filter timeframe
input ENUM_TIMEFRAMES TF_Bias     = PERIOD_H4;   // Bias timeframe
input bool     RequireMTFAlign    = true;         // Require all 3 TFs aligned

//--- ICT Killzone Filter
input group "=== ICT KILLZONES ==="
input bool     UseKillzones       = true;     // Only trade in killzones
input bool     KZ_London          = true;     // London Open (07:00-10:00 GMT)
input bool     KZ_NewYork         = true;     // New York Open (13:00-16:00 GMT)
input bool     KZ_LondonClose     = true;     // London Close (15:00-17:00 GMT)
input bool     KZ_Asian           = false;    // Asian Session (22:00-01:00 GMT)

//--- Trade Cooldown
input group "=== EXECUTION ==="
input int      CooldownMinutes    = 10;       // Minimum minutes between trades
input int      MaxHoldMinutes     = 480;      // Max position hold time (minutes)
input bool     CloseAtSessionEnd  = true;     // Close positions at session end

//--- Objects
CTrade         trade;
CPositionInfo  posInfo;

//--- Indicator handles
int h_EMA_Fast, h_EMA_Slow, h_EMA_Trend;
int h_RSI, h_MACD;
int h_ATR_Entry, h_ATR_Filter, h_ATR_Bias;
int h_RSI_Filter, h_RSI_Bias;
int h_EMA_Fast_Filter, h_EMA_Slow_Filter;
int h_EMA_Fast_Bias, h_EMA_Slow_Bias;

datetime g_LastTradeTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(EA_Magic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Entry TF indicators
   h_EMA_Fast   = iMA(_Symbol, TF_Entry,  EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Slow   = iMA(_Symbol, TF_Entry,  EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Trend  = iMA(_Symbol, TF_Entry,  EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI        = iRSI(_Symbol, TF_Entry, RSI_Period, PRICE_CLOSE);
   h_MACD       = iMACD(_Symbol, TF_Entry, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   h_ATR_Entry  = iATR(_Symbol, TF_Entry, ATR_Period);

   // Filter TF indicators
   h_EMA_Fast_Filter = iMA(_Symbol, TF_Filter, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Slow_Filter = iMA(_Symbol, TF_Filter, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI_Filter      = iRSI(_Symbol, TF_Filter, RSI_Period, PRICE_CLOSE);
   h_ATR_Filter      = iATR(_Symbol, TF_Filter, ATR_Period);

   // Bias TF indicators
   h_EMA_Fast_Bias  = iMA(_Symbol, TF_Bias, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Slow_Bias  = iMA(_Symbol, TF_Bias, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI_Bias       = iRSI(_Symbol, TF_Bias, RSI_Period, PRICE_CLOSE);
   h_ATR_Bias       = iATR(_Symbol, TF_Bias, ATR_Period);

   if(h_EMA_Fast == INVALID_HANDLE || h_RSI == INVALID_HANDLE || h_MACD == INVALID_HANDLE)
   { Alert("UltProfit v8: Indicator init failed!"); return INIT_FAILED; }

   FG_Init();
   Print("⚡ UltProfit v8 initialized | Symbol: ", _Symbol, " | Magic: ", EA_Magic);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int handles[] = {h_EMA_Fast, h_EMA_Slow, h_EMA_Trend, h_RSI, h_MACD,
                    h_ATR_Entry, h_ATR_Filter, h_ATR_Bias,
                    h_RSI_Filter, h_RSI_Bias,
                    h_EMA_Fast_Filter, h_EMA_Slow_Filter,
                    h_EMA_Fast_Bias, h_EMA_Slow_Bias};
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Safeguard check first
   if(!FG_IsSafeToTrade()) return;

   // Manage open positions (trailing, time-based exits)
   ManageOpenPositions();

   // Weekend close
   if(FG_WeekendClose && IsWeekendClose()) { FG_CloseAllPositions("Weekend Close"); return; }

   // Check new bar on entry TF
   static datetime lastBar = 0;
   datetime currBar = iTime(_Symbol, TF_Entry, 0);
   if(currBar == lastBar) return;
   lastBar = currBar;

   // Cooldown check
   if(TimeCurrent() - g_LastTradeTime < CooldownMinutes * 60) return;

   // Max open trades check
   if(CountOpenTrades() >= MaxOpenTrades) return;

   // Killzone check
   if(UseKillzones && !IsInKillzone()) return;

   // Get multi-timeframe signals
   int entrySignal = GetEntrySignal();
   if(entrySignal == 0) return;

   // Apply inverse mode
   if(InverseMode) entrySignal = -entrySignal;

   // Direction filter
   if(entrySignal > 0 && !Allow_Buy) return;
   if(entrySignal < 0 && !Allow_Sell) return;

   // MTF alignment check
   if(RequireMTFAlign && !IsMTFAligned(entrySignal)) return;

   // Execute trade
   ExecuteTrade(entrySignal);
}

//+------------------------------------------------------------------+
//| Count signals and return direction (+1 buy, -1 sell, 0 none)    |
//+------------------------------------------------------------------+
int GetEntrySignal()
{
   double emaFast[3], emaSlow[3], emaTrend[3];
   double rsi[3], macd[3], macdSig[3];
   double atr[1];

   if(CopyBuffer(h_EMA_Fast,  0, 0, 3, emaFast)  < 3) return 0;
   if(CopyBuffer(h_EMA_Slow,  0, 0, 3, emaSlow)  < 3) return 0;
   if(CopyBuffer(h_EMA_Trend, 0, 0, 3, emaTrend) < 3) return 0;
   if(CopyBuffer(h_RSI,       0, 0, 3, rsi)       < 3) return 0;
   if(CopyBuffer(h_MACD,      0, 0, 3, macd)      < 3) return 0;
   if(CopyBuffer(h_MACD,      1, 0, 3, macdSig)   < 3) return 0;
   if(CopyBuffer(h_ATR_Entry, 0, 0, 1, atr)       < 1) return 0;

   // Skip if ATR too low (low volatility = no edge)
   double minATR = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 50;
   if(atr[0] < minATR) return 0;

   int buyScore = 0, sellScore = 0;

   // Signal 1: EMA Cross
   if(emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2]) buyScore++;
   if(emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2]) sellScore++;

   // Signal 2: EMA Trend alignment
   if(emaFast[1] > emaTrend[1] && emaSlow[1] > emaTrend[1]) buyScore++;
   if(emaFast[1] < emaTrend[1] && emaSlow[1] < emaTrend[1]) sellScore++;

   // Signal 3: RSI momentum
   if(rsi[2] < RSI_Oversold  && rsi[1] >= RSI_Oversold)  buyScore++;
   if(rsi[2] > RSI_Overbought && rsi[1] <= RSI_Overbought) sellScore++;

   // Signal 4: MACD histogram direction
   double macdHist1 = macd[1] - macdSig[1];
   double macdHist2 = macd[2] - macdSig[2];
   if(macdHist1 > 0 && macdHist2 <= 0) buyScore++;
   if(macdHist1 < 0 && macdHist2 >= 0) sellScore++;

   // Signal 5: MACD above zero
   if(macd[1] > 0 && macd[1] > macdSig[1]) buyScore++;
   if(macd[1] < 0 && macd[1] < macdSig[1]) sellScore++;

   // Signal 6: Price above/below fast EMA
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > emaFast[1] && bid > emaSlow[1]) buyScore++;
   if(bid < emaFast[1] && bid < emaSlow[1]) sellScore++;

   if(buyScore  >= MinSignals) return  1;
   if(sellScore >= MinSignals) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Multi-timeframe alignment check                                   |
//+------------------------------------------------------------------+
bool IsMTFAligned(int direction)
{
   // Filter TF check
   double emaFF[1], emaFS[1], rsiF[1];
   if(CopyBuffer(h_EMA_Fast_Filter, 0, 0, 1, emaFF) < 1) return false;
   if(CopyBuffer(h_EMA_Slow_Filter, 0, 0, 1, emaFS) < 1) return false;
   if(CopyBuffer(h_RSI_Filter,      0, 0, 1, rsiF)  < 1) return false;

   bool filterOK = (direction > 0) ? (emaFF[0] > emaFS[0] && rsiF[0] > 50)
                                   : (emaFF[0] < emaFS[0] && rsiF[0] < 50);

   // Bias TF check
   double emaFB[1], emaSB[1], rsiB[1];
   if(CopyBuffer(h_EMA_Fast_Bias, 0, 0, 1, emaFB) < 1) return false;
   if(CopyBuffer(h_EMA_Slow_Bias, 0, 0, 1, emaSB) < 1) return false;
   if(CopyBuffer(h_RSI_Bias,      0, 0, 1, rsiB)  < 1) return false;

   bool biasOK = (direction > 0) ? (emaFB[0] > emaSB[0])
                                 : (emaFB[0] < emaSB[0]);

   return filterOK && biasOK;
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                         |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   double atr[1];
   if(CopyBuffer(h_ATR_Entry, 0, 0, 1, atr) < 1) return;

   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point= SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = (ask - bid) / point;

   double slDist = atr[0] * ATR_SL_Multiplier;
   double tpDist = atr[0] * ATR_TP_Multiplier;

   // Don't trade if spread is > 30% of ATR
   if(spread * point > atr[0] * 0.3) { Print("⚠️ Spread too wide, skipping trade"); return; }

   double sl, tp, entry;
   if(direction > 0)
   {
      entry = ask;
      sl    = NormalizeDouble(entry - slDist, _Digits);
      tp    = NormalizeDouble(entry + tpDist, _Digits);
   }
   else
   {
      entry = bid;
      sl    = NormalizeDouble(entry + slDist, _Digits);
      tp    = NormalizeDouble(entry - tpDist, _Digits);
   }

   double slPips = slDist / point;
   double lots   = FG_CalcLotSize(_Symbol, slPips, RiskPerTrade_Pct);
   lots = MathMin(lots, MaxLotSize);  // Hard cap

   if(lots <= 0) return;

   bool result = false;
   if(direction > 0)
      result = trade.Buy(lots, _Symbol, entry, sl, tp, EA_Comment);
   else
      result = trade.Sell(lots, _Symbol, entry, sl, tp, EA_Comment);

   if(result)
   {
      g_LastTradeTime = TimeCurrent();
      FG_RegisterTrade();
      PrintFormat("✅ UltProfit v8 %s | Lots=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | Risk=$%.2f | %s",
                  direction > 0 ? "BUY" : "SELL", lots, entry, sl, tp,
                  AccountInfoDouble(ACCOUNT_BALANCE) * RiskPerTrade_Pct / 100.0,
                  FG_StatusString());
   }
   else
      Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Manage open positions — trailing stop, time exit                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double atr[1];
   if(CopyBuffer(h_ATR_Entry, 0, 0, 1, atr) < 1) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != EA_Magic) continue;

      // Time-based exit
      if(MaxHoldMinutes > 0)
      {
         int heldMinutes = (int)((TimeCurrent() - posInfo.Time()) / 60);
         if(heldMinutes >= MaxHoldMinutes)
         {
            trade.PositionClose(posInfo.Ticket());
            Print("⏰ Time exit: position held ", heldMinutes, " minutes");
            continue;
         }
      }

      // Trail stop at 2x ATR profit
      double trailDist = atr[0] * 2.0;
      double currentSL = posInfo.StopLoss();
      double price     = (posInfo.PositionType() == POSITION_TYPE_BUY)
                         ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                         : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(price - trailDist, _Digits);
         if(newSL > currentSL + SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10)
            trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
      }
      else
      {
         double newSL = NormalizeDouble(price + trailDist, _Digits);
         if(newSL < currentSL - SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10 || currentSL == 0)
            trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == EA_Magic) count++;
   return count;
}

//+------------------------------------------------------------------+
bool IsInKillzone()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(KZ_London     && h >= 7  && h < 10) return true;
   if(KZ_NewYork    && h >= 13 && h < 16) return true;
   if(KZ_LondonClose && h >= 15 && h < 17) return true;
   if(KZ_Asian      && (h >= 22 || h < 1)) return true;
   return false;
}

//+------------------------------------------------------------------+
bool IsWeekendClose()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= 21);
}
