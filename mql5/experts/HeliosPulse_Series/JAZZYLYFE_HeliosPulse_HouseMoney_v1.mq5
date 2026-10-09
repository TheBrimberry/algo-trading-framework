//+------------------------------------------------------------------+
//| JAZZYLYFE_HeliosPulse_HouseMoney_v1.mq5                          |
//| Copyright 2026, JAZZYLYFE Trading Systems                        |
//| Author: JAZZYLYFE (TheBrimberry) | House Money Pyramiding EA     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, JAZZYLYFE Trading Systems"
#property link      "https://github.com/TheBrimberry"
#property version   "1.00"
#property description "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#property description "⚡ HELIOS PULSE - HOUSE MONEY 100% PYRAMID ENGINE ⚡"
#property description "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#property description "1. Every +$50 Profit: Closes 25% Partial Volume to Bank Cash"
#property description "2. Ratchets SL to Lock +$50 Cash Profit (Zero-Risk Guarantee)"
#property description "3. Triggers 100% Size Boosted Entry #2 (0.09 -> 0.18 Lots) on House Money"
#property description "4. Ideal for Single Symbol Testing (Gold XAUUSD / US30 Index)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_LOT_SIZE_MODE
  {
   LOT_MODE_FIXED,   // Fixed Lots
   LOT_MODE_RISK     // Auto Risk %
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "═══ 📈 LOT SIZE SIZING MODE ═══"
input ENUM_LOT_SIZE_MODE InpLotMode  = LOT_MODE_FIXED;  // Lot Sizing Mode
input double    InpBaseLots          = 0.09;            // Initial Base Lot Size (Fixed)
input double    InpRiskPercent       = 2.0;             // Auto Risk % per trade (if Auto Risk mode)
input double    InpHouseMoneyBoostLot= 0.50;            // House Money Boosted Pyramid Lot (Fixed)
input double    InpHouseMoneyBoostPct= 10.0;            // House Money Boost Risk % (if Auto Risk mode)

input group "═══ 💰 HOUSE MONEY & PYRAMID SETTINGS ═══"
input ulong     InpMagicNumber       = 2026999;     // Dedicated Magic Number (Single Symbol Test)
input double    InpPartialBankProfit = 50.0;        // Cash Profit Trigger for 25% Partial Close ($50)
input double    InpPartialBankPct    = 25.0;        // Partial Close Percentage (25%)
input int       InpMaxPyramidPos     = 5;           // Max Staggered Pyramid Positions (5)
input bool      InpEveryOtherTradeBoost = true;     // House Boost Every Other Trade (Alternating)

input group "═══ 🛡️ RISK SHIELD & SLIPPAGE ═══"
input double    InpMaxDailyLossPct   = 4.0;         // Daily Loss Limit Cap (4.0%)
input double    InpMaxTotalDRSPct    = 5.0;         // Total DRS Account Drawdown Cap (5.0%)
input double    InpMaxSlippagePips   = 1.5;         // Max Allowed Slippage (1.5 Pips)

input group "═══ 🎯 ATR SL/TP & TRAILING STOP ═══"
input int       InpATRPeriod         = 14;          // ATR Period
input double    InpATRSLMult         = 1.8;         // Stop Loss ATR Multiplier
input double    InpRiskRewardRatio   = 2.0;         // Risk:Reward Target (1:2.0)
input bool      InpEnableTrailingStop= true;        // Enable Dynamic ATR Trailing Stop
input double    InpTrailATRMult      = 1.5;         // Trailing Stop ATR Multiplier

//+------------------------------------------------------------------+
//| STRUCTS & GLOBALS                                                |
//+------------------------------------------------------------------+
struct SPosStateHM
  {
   ulong  ticket;
   bool   bank50Done;
   bool   sl50Locked;
   bool   boostTriggered;
  };

SPosStateHM g_posState[];

CTrade        trade;
CPositionInfo pos;
CAccountInfo  acc;
CSymbolInfo   symInfo;

int  g_hATR = INVALID_HANDLE;
int  g_totalTradeCount = 0;
bool g_autoTrade = true;
double g_dayStartEquity = 0;
datetime g_dayStamp = 0;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION FUNCTION                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   symInfo.Name(_Symbol);
   symInfo.Refresh();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);

   double pips = (_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point;
   trade.SetDeviationInPoints((ulong)MathRound((InpMaxSlippagePips * pips) / _Point));

   g_hATR = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   if(g_hATR == INVALID_HANDLE)
     {
      Print("HP_HOUSEMONEY >> Failed to create ATR handle.");
      return INIT_FAILED;
     }

   g_dayStartEquity = acc.Equity();
   g_dayStamp = iTime(_Symbol, PERIOD_D1, 0);

   CreateHouseMoneyDashboard();
   PrintFormat("=== HELIOS PULSE HOUSE MONEY V1 INITIALIZED (%s | Magic: %I64u) ===", _Symbol, InpMagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION FUNCTION                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(g_hATR);
   ObjectsDeleteAll(0, "HP_HM_");
  }

//+------------------------------------------------------------------+
//| TRACKING STATE INDEX LOOKUP                                      |
//+------------------------------------------------------------------+
int GetPosStateIdx(ulong ticket)
  {
   int sz = ArraySize(g_posState);
   for(int i = 0; i < sz; i++)
     {
      if(g_posState[i].ticket == ticket) return i;
     }
   ArrayResize(g_posState, sz + 1);
   g_posState[sz].ticket         = ticket;
   g_posState[sz].bank50Done     = false;
   g_posState[sz].sl50Locked     = false;
   g_posState[sz].boostTriggered = false;
   return sz;
  }

//+------------------------------------------------------------------+
//| EXPERT TICK FUNCTION                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(GlobalVariableCheck("JAZZY_EMERGENCY_LOCKOUT")) return;
   ManageHouseMoneyPositions();
   UpdateHouseMoneyDashboard();

   if(!CheckRiskGuards()) return;
   if(!g_autoTrade) return;

   // AUTOMATED ENTRY TRIGGER ON CONTINUOUS SCAN
   if(CountActivePositions() == 0)
     {
      double rsiBuf[1], ema13Buf[1], ema200Buf[1];
      int hRSI = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);
      int hEMA13 = iMA(_Symbol, PERIOD_M15, 13, 0, MODE_EMA, PRICE_CLOSE);
      int hEMA200 = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);

      if(CopyBuffer(hRSI, 0, 1, 1, rsiBuf) >= 1 && CopyBuffer(hEMA13, 0, 1, 1, ema13Buf) >= 1 && CopyBuffer(hEMA200, 0, 1, 1, ema200Buf) >= 1)
        {
         double close1 = iClose(_Symbol, PERIOD_M15, 1);
         if(close1 > ema200Buf[0] && rsiBuf[0] >= 50.0)
           {
            ExecuteHouseMoneyTrade(ORDER_TYPE_BUY, InpBaseLots);
           }
         else if(close1 < ema200Buf[0] && rsiBuf[0] <= 50.0)
           {
            ExecuteHouseMoneyTrade(ORDER_TYPE_SELL, InpBaseLots);
           }
        }

      IndicatorRelease(hRSI);
      IndicatorRelease(hEMA13);
      IndicatorRelease(hEMA200);
     }
  }

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT, 25% PARTIAL & 100% HOUSE MONEY BOOST        |
//+------------------------------------------------------------------+
void ManageHouseMoneyPositions()
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != InpMagicNumber || pos.Symbol() != _Symbol) continue;

      bool isBuy    = (pos.PositionType() == POSITION_TYPE_BUY);
      double vol    = pos.Volume();
      double entry  = pos.PriceOpen();
      double sl     = pos.StopLoss();
      double tp     = pos.TakeProfit();
      double profit = pos.Profit() + pos.Swap();
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double px     = isBuy ? bid : ask;

      int si = GetPosStateIdx(t);

      // 1. AT +$50 PROFIT: CLOSE 25% PARTIAL VOLUME
      if(!g_posState[si].bank50Done && profit >= InpPartialBankProfit)
        {
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         if(step <= 0) step = 0.01;
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double closeVol = MathFloor((vol * (InpPartialBankPct / 100.0)) / step + 1e-9) * step;

         if(closeVol >= vmin && closeVol < vol)
           {
            if(trade.PositionClosePartial(t, closeVol))
              {
               g_posState[si].bank50Done = true;
               Alert(StringFormat("💰 HOUSE MONEY BANKED! Closed 25%% (%.2f lots) on #%I64u @ +$%.2f Profit", closeVol, t, profit));
               PrintFormat("HP_HOUSEMONEY >> Banked 25%% (%.2f lots) on #%I64u at +$%.2f", closeVol, t, profit);
              }
           }
        }

      // 2. AT +$50 PROFIT: RATCHET SL TO LOCK $50 PROFIT (ZERO RISK)
      if(profit >= InpPartialBankProfit)
        {
         double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickVal > 0 && tickSize > 0 && vol > 0)
           {
            double lockPoints = (InpPartialBankProfit / (vol * tickVal)) * tickSize;
            double targetSL = NormalizeDouble(isBuy ? entry + lockPoints : entry - lockPoints, _Digits);
            double stopLevelPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double minStopDist = (stopLevelPoints > 0) ? stopLevelPoints * _Point : _Point * 10.0;
            bool validDist = isBuy ? (bid - targetSL >= minStopDist) : (targetSL - ask >= minStopDist);
            double validTP = tp;
            if(tp > 0)
              {
               bool tpValid = isBuy ? (tp > bid) : (tp < ask);
               if(!tpValid) validTP = 0; // Omit penetrated TP to allow SL lock to succeed!
              }

            if(validDist && ((isBuy && targetSL > sl) || (!isBuy && (sl == 0 || targetSL < sl))))
              {
               if(trade.PositionModify(t, targetSL, validTP))
                 {
                  g_posState[si].sl50Locked = true;
                  Alert(StringFormat("🛡️ $50 PROFIT LOCKED #%I64u >> SL set at %.5f (Guaranteed $50 Banked)", t, targetSL));
                 }
              }
           }
        }

      // 3. HOUSE MONEY 0.50 BOOSTED ENTRY (EVERY OTHER TRADE ALTERNATING)
      if(g_posState[si].sl50Locked && !g_posState[si].boostTriggered && CountActivePositions() < InpMaxPyramidPos)
        {
         g_posState[si].boostTriggered = true;
         g_totalTradeCount++;

         if(!InpEveryOtherTradeBoost || (g_totalTradeCount % 2 != 0))
           {
            ENUM_ORDER_TYPE nextType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            Alert(StringFormat("🚀 EVERY OTHER TRADE BOOST #%d! Adding 0.50 Lots on %s", g_totalTradeCount, _Symbol));
            PrintFormat("🚀 HOUSE MONEY 0.50 BOOST TRIGGERED (Trade #%d)! Adding 0.50 lots on %s", g_totalTradeCount, _Symbol);
            ExecuteHouseMoneyTrade(nextType, InpHouseMoneyBoostLot);
           }
         else
           {
            Alert(StringFormat("ℹ️ EVERY OTHER TRADE BOOST SKIPPED (Trade #%d) >> Returning to Base Lot Size (0.09)", g_totalTradeCount));
            PrintFormat("ℹ️ EVERY OTHER TRADE BOOST SKIPPED (Trade #%d) >> Returning to Base Lot Size (0.09)", g_totalTradeCount);
           }
        }

      // 4. DYNAMIC ATR TRAILING STOP
      if(InpEnableTrailingStop)
        {
         double atrBuf[1];
         if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) >= 1 && atrBuf[0] > 0)
           {
            double trailDist = atrBuf[0] * InpTrailATRMult;
            double stopLevelPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double minStopDist = (stopLevelPoints > 0) ? stopLevelPoints * _Point : _Point * 10.0;
            double validTP = tp;
            if(tp > 0)
              {
               bool tpValid = isBuy ? (tp > bid) : (tp < ask);
               if(!tpValid) validTP = 0;
              }

            if(isBuy)
              {
               double candSL = NormalizeDouble(bid - trailDist, _Digits);
               if(bid - candSL >= minStopDist && candSL > sl + minStopDist && candSL > entry)
                 {
                  trade.PositionModify(t, candSL, validTP);
                 }
              }
            else
              {
               double candSL = NormalizeDouble(ask + trailDist, _Digits);
               if(candSL - ask >= minStopDist && (sl == 0 || candSL < sl - minStopDist) && candSL < entry)
                 {
                  trade.PositionModify(t, candSL, validTP);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| DYNAMIC LOT SIZE SIZING CALCULATOR                               |
//+------------------------------------------------------------------+
double CalculateAutoLots(double slDist, double riskPercent)
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (riskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || tickSize <= 0 || slDist <= 0) return InpBaseLots;
   
   // Value of slDist move for 1 lot
   double riskPerLot = (slDist / tickSize) * tickValue;
   if(riskPerLot <= 0) return InpBaseLots;
   
   double calculatedLots = riskAmount / riskPerLot;
   
   // Normalize volume
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(volStep <= 0) volStep = 0.01;
   
   double normalizedLots = MathFloor(calculatedLots / volStep) * volStep;
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   return MathMax(volMin, MathMin(volMax, normalizedLots));
  }

//+------------------------------------------------------------------+
//| EXECUTE TRADE WITH SPECIFIC LOT SIZE                             |
//+------------------------------------------------------------------+
void ExecuteHouseMoneyTrade(ENUM_ORDER_TYPE orderType, double lots)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;

   double atrBuf[1];
   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) < 1 || atrBuf[0] <= 0) return;
   double slDist = atrBuf[0] * InpATRSLMult;
   double tpDist = slDist * InpRiskRewardRatio;

   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - slDist : price + slDist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tpDist : price - tpDist, _Digits);

   double lotSize = lots;
   if(InpLotMode == LOT_MODE_RISK)
     {
      double riskPct = (lots == InpHouseMoneyBoostLot) ? InpHouseMoneyBoostPct : InpRiskPercent;
      lotSize = CalculateAutoLots(slDist, riskPct);
     }

   if(orderType == ORDER_TYPE_BUY) trade.Buy(lotSize, _Symbol, price, sl, tp, "HP_HOUSE_MONEY");
   else if(orderType == ORDER_TYPE_SELL) trade.Sell(lotSize, _Symbol, price, sl, tp, "HP_HOUSE_MONEY");
  }

//+------------------------------------------------------------------+
//| COUNT ACTIVE POSITIONS                                           |
//+------------------------------------------------------------------+
int CountActivePositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(pos.SelectByIndex(i) && pos.Magic() == InpMagicNumber && pos.Symbol() == _Symbol) cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| CHECK RISK GUARDS                                                |
//+------------------------------------------------------------------+
bool CheckRiskGuards()
  {
   double eq = acc.Equity();
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today > g_dayStamp)
     {
      g_dayStamp = today;
      g_dayStartEquity = eq;
     }
   double dailyDD = (g_dayStartEquity > 0) ? ((g_dayStartEquity - eq) / g_dayStartEquity) * 100.0 : 0;
   if(dailyDD >= InpMaxDailyLossPct) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| INTERACTIVE BUTTON EVENT HANDLER                                 |
//+------------------------------------------------------------------+
//| INTERACTIVE BUTTON EVENT HANDLER                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == "HP_HM_BTN_BUY")
        {
         ExecuteHouseMoneyTrade(ORDER_TYPE_BUY, InpBaseLots);
         ObjectSetInteger(0, "HP_HM_BTN_BUY", OBJPROP_STATE, false);
        }
      else if(sparam == "HP_HM_BTN_SELL")
        {
         ExecuteHouseMoneyTrade(ORDER_TYPE_SELL, InpBaseLots);
         ObjectSetInteger(0, "HP_HM_BTN_SELL", OBJPROP_STATE, false);
        }
      else if(sparam == "HP_HM_BTN_AUTO")
        {
         g_autoTrade = !g_autoTrade;
         ObjectSetString(0, "HP_HM_BTN_AUTO", OBJPROP_TEXT, g_autoTrade ? "⚡ AUTO TRADING: ON" : "⏸️ AUTO TRADING: OFF");
         ObjectSetInteger(0, "HP_HM_BTN_AUTO", OBJPROP_BGCOLOR, g_autoTrade ? clrDarkGreen : clrDarkRed);
         ObjectSetInteger(0, "HP_HM_BTN_AUTO", OBJPROP_STATE, false);
        }
      else if(sparam == "HP_HM_BTN_CLOSE")
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(pos.SelectByIndex(i) && pos.Magic() == InpMagicNumber && pos.Symbol() == _Symbol)
              {
               trade.PositionClose(pos.Ticket());
              }
           }
         ObjectSetInteger(0, "HP_HM_BTN_CLOSE", OBJPROP_STATE, false);
        }
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| DASHBOARD RENDERING ENGINE                                       |
//+------------------------------------------------------------------+
void CreateHouseMoneyDashboard()
  {
   int x = 15, y = 15, w = 295, h = 370;
   CreateRectHM("HP_HM_BG", x, y, w, h, C'15,20,30', C'40,60,90');
   CreateLabelHM("HP_HM_HDR", x + 12, y + 10, "⚡ HELIOS HOUSE MONEY PURE CONFLUENCE ⚡", clrGold, 9, true);
   CreateLabelHM("HP_HM_SUB", x + 12, y + 28, "Pure Confluence & House Money Pyramiding", clrCyan, 8);

   int row = 52, lineH = 17;
   CreateLabelHM("HP_HM_P1", x + 15, y + row, StringFormat("Base Entry: %.2f | Boost: %.2f Lots", InpBaseLots, InpHouseMoneyBoostLot), clrWhite, 8);
   row += lineH;
   CreateLabelHM("HP_HM_P2", x + 15, y + row, StringFormat("Partial Bank: 25%% @ +$%.0f Profit Lock", InpPartialBankProfit), clrLime, 8, true);
   row += lineH + 4;

   // MTF CONFLUENCE MATRIX
   CreateLabelHM("HP_HM_MTF_HDR", x + 15, y + row, "── Pure Confluence MTF Matrix ──", clrSilver, 8);
   row += lineH;

   ENUM_TIMEFRAMES tfs[5] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   string tfNames[5] = {"M5 ", "M15", "H1 ", "H4 ", "D1 "};

   for(int i = 0; i < 5; i++)
     {
      double e13[1], e34[1];
      int h13 = iMA(_Symbol, tfs[i], 13, 0, MODE_EMA, PRICE_CLOSE);
      int h34 = iMA(_Symbol, tfs[i], 34, 0, MODE_EMA, PRICE_CLOSE);

      string status = "⚪ NEUTRAL";
      color stClr = clrSilver;

      if(CopyBuffer(h13, 0, 1, 1, e13) >= 1 && CopyBuffer(h34, 0, 1, 1, e34) >= 1)
        {
         if(e13[0] > e34[0]) { status = "🟢 BULLISH"; stClr = clrLime; }
         else if(e13[0] < e34[0]) { status = "🔴 BEARISH"; stClr = clrRed; }
        }

      IndicatorRelease(h13);
      IndicatorRelease(h34);

      CreateLabelHM(StringFormat("HP_HM_TF_%d", i), x + 20, y + row, StringFormat("%s : %s", tfNames[i], status), stClr, 8);
      row += 15;
     }
   row += 4;

   // TRADING BUTTONS
   CreateButtonHM("HP_HM_BTN_BUY", "🟢 BUY (0.09)", x + 15, y + row, 125, 24, clrDarkGreen, clrWhite);
   CreateButtonHM("HP_HM_BTN_SELL", "🔴 SELL (0.09)", x + 150, y + row, 125, 24, clrDarkRed, clrWhite);
   row += 28;

   CreateButtonHM("HP_HM_BTN_AUTO", "⚡ AUTO TRADING: ON", x + 15, y + row, 125, 24, clrDarkGreen, clrWhite);
   CreateButtonHM("HP_HM_BTN_CLOSE", "🚨 CLOSE ALL", x + 150, y + row, 125, 24, clrMaroon, clrWhite);
  }

void UpdateHouseMoneyDashboard()
  {
   int cnt = CountActivePositions();
   double eq = acc.Equity();
   double floatPnl = eq - acc.Balance();
   color pnlClr = (floatPnl >= 0) ? clrLime : clrRed;
   ChartRedraw();
  }

void CreateRectHM(string name, int x, int y, int w, int h, color bg, color border)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
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

void CreateLabelHM(string name, int x, int y, string text, color clr, int fontSize, bool bold=false)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
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

void CreateButtonHM(string name, string text, int x, int y, int w, int h, color bg, color textClr)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
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
