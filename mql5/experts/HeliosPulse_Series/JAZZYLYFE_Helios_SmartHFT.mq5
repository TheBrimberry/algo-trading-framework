//+------------------------------------------------------------------+
//|                                   JAZZYLYFE_Helios_SmartHFT.mq5  |
//|                    Jason Brimberry | JAZZYLYFE | Brimberry LLC   |
//|                                                                  |
//|  HELIOS SMART-HFT v1.01  -  Grade A++                            |
//|  ---------------------------------------------------------------|
//|  Two engines, one thesis, zero mercy on risk:                    |
//|    ENGINE A  HELIOS SESSION : Asian-range accumulation ->        |
//|              Judas sweep detection -> reversal entry in the      |
//|              true direction. The classic HeliosPulse edge.       |
//|    ENGINE B  SMART-HFT MICRO: M1 momentum-burst entries inside   |
//|              session windows, MTF-aligned, spread-gated,         |
//|              rate-capped and hold-time-floored so it stays       |
//|              inside FTMO / Upcomers HFT rules by construction.   |
//|                                                                  |
//|  SMART STOPLOSS : structure + ATR hybrid (Asian boundary /       |
//|    sweep extreme + buffer, clamped to ATR band, spread-floored), |
//|    then a TIGHTEN-ONLY ratchet: breakeven lock at 0.75R,         |
//|    M5 chandelier trail, give-back lock keeping 55% of peak R.    |
//|  SMART TAKEPROFIT: golden ladder 1.000R / 1.618R partials,       |
//|    2.618R runner target; runner rides trail + trend-shift exit.  |
//|  INCREASE ON WINNING: house-money pyramiding - adds fire ONLY    |
//|    once the thesis stop is locked at >= breakeven, each add      |
//|    0.618x the last (non-escalating), capped; plus a win-streak   |
//|    risk multiplier (1.15^streak, cap 1.50x) and anti-martingale  |
//|    on losses (0.85^streak, floor 0.40x). Half-Kelly ceiling.     |
//|  CLOSE ON TREND SHIFT: M15+M5 composite reversal score (EMA      |
//|    regime flip, DI cross, structure break). 0.45 = bank half +   |
//|    tighten; 0.70 for 2 closed M5 bars = close the thesis.        |
//|                                                                  |
//|  COMPLIANCE SHIELD (always on):                                  |
//|    daily-loss soft halt + hard flatten (buffered vs firm limit), |
//|    max-drawdown guard vs persisted equity high-water mark,       |
//|    intraday-PEAK day anchor, per-trade money cap, min hold       |
//|    seconds, max trades/hour + /day, spread cap, one-instance     |
//|    lock, no hedging, BCHUSD permanently banned at init.          |
//|  Multi-timeframe cascade D1/H4/H1/M15 (.35/.30/.22/.13) gates    |
//|  every entry; Inverse Mode + Buy/Sell/Both direction filter.     |
//+------------------------------------------------------------------+
#property copyright "Jason Brimberry | JAZZYLYFE | Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "1.01"
#property description "Helios session logic + prop-safe smart-HFT micro engine. Smart SL/TP, pyramid on winners, close on trend shift. FTMO/Upcomers shielded."

#include <Trade\Trade.mqh>

//============================== INPUTS =============================
enum ENUM_JZ_DIR      { JZ_DIR_BOTH=0, JZ_DIR_BUY_ONLY=1, JZ_DIR_SELL_ONLY=2 };
enum ENUM_JZ_LOTMODE  { JZ_LOT_RISK_PCT=0, JZ_LOT_FIXED=1 };
enum ENUM_JZ_ANCHOR   { JZ_ANCHOR_DAY_OPEN=0, JZ_ANCHOR_INTRADAY_PEAK=1 };

input group "=== IDENTITY ==="
input long              InpMagic             = 20271500;      // Magic number (fleet-registry safe)
input string            InpTag               = "JZ-HeliosSmartHFT"; // Order comment tag

input group "=== ENGINES ==="
input bool              InpUseHeliosSession  = true;          // ENGINE A: Helios Judas-sweep reversal
input bool              InpUseMicroHFT       = true;          // ENGINE B: Smart-HFT micro momentum (prop-safe)
input ENUM_JZ_DIR       InpDirectionFilter   = JZ_DIR_BOTH;   // Trade direction filter
input bool              InpInverseMode       = false;         // Inverse Mode (flip all signals)

input group "=== SESSIONS (server time, hours 0-23) ==="
input int               InpAsiaStartHour     = 0;             // Asian range start
input int               InpAsiaEndHour       = 7;             // Asian range end
input int               InpLondonStartHour   = 7;             // London window start
input int               InpLondonEndHour     = 12;            // London window end
input int               InpNYStartHour       = 13;            // New York window start
input int               InpNYEndHour         = 20;            // New York window end
input bool              InpTradeLondon       = true;          // Trade London window
input bool              InpTradeNY           = true;          // Trade New York window
input int               InpBiasValidMinutes  = 120;           // Judas bias validity (minutes)
input string            InpBlockWindows      = "";            // News blocks "HH:MM-HH:MM;..." (server, optional)

input group "=== MULTI-TIMEFRAME CASCADE ==="
input double            InpW_D1              = 0.35;          // Weight D1
input double            InpW_H4              = 0.30;          // Weight H4
input double            InpW_H1              = 0.22;          // Weight H1
input double            InpW_M15             = 0.13;          // Weight M15
input double            InpScoreThreshold    = 0.35;          // Min composite |score| to allow entries
input double            InpAdxMin            = 18.0;          // ADX credibility floor per TF

input group "=== SMART-HFT MICRO (Engine B) ==="
input int               InpM1FastEMA         = 8;             // M1 fast EMA
input int               InpM1SlowEMA         = 21;            // M1 slow EMA
input double            InpM1BodyATR         = 0.60;          // Min closed-bar body as x ATR(M1)
input int               InpMaxTradesPerHour  = 6;             // Rate cap per hour (prop-safe)
input int               InpMaxTradesPerDay   = 20;            // Rate cap per day
input int               InpMinSecondsBetween = 90;            // Min seconds between new entries
input int               InpMinHoldSeconds    = 150;           // Min hold before voluntary close (avg-hold rules)

input group "=== SMART STOPLOSS / TAKEPROFIT ==="
input double            InpSL_ATRmult        = 1.60;          // ATR(M15) reference multiple
input double            InpSL_MinATR         = 0.80;          // Clamp: min SL as x ATR(M15)
input double            InpSL_MaxATR         = 2.20;          // Clamp: max SL as x ATR(M15)
input double            InpSL_BufferATR      = 0.25;          // Structure buffer as x ATR(M15)
input int               InpSL_SpreadFloor    = 8;             // SL floor as x current spread
input double            InpBE_TriggerR       = 0.75;          // Breakeven lock trigger (R)
input double            InpBE_OffsetR        = 0.08;          // Breakeven offset (R)
input double            InpChandelierATR     = 2.00;          // M5 chandelier trail (x ATR M5)
input double            InpGivebackArmR      = 1.20;          // Give-back lock arms at (R)
input double            InpGivebackKeep      = 0.55;          // Keep this fraction of peak R
input double            InpTP1_R             = 1.000;         // Ladder rung 1 (R)  [golden]
input double            InpTP2_R             = 1.618;         // Ladder rung 2 (R)  [golden]
input double            InpTP3_R             = 2.618;         // Runner target (R)  [golden]
input double            InpTP1_Pct           = 40.0;          // % closed at rung 1
input double            InpTP2_Pct           = 30.0;          // % closed at rung 2

input group "=== INCREASE ON WINNING (house-money pyramid) ==="
input bool              InpAllowAdds         = true;          // Pyramid on winners
input int               InpMaxAdds           = 2;             // Max adds per thesis
input double            InpAddTriggerR       = 0.80;          // First add earliest at (R) profit
input double            InpAddSizeFactor     = 0.618;         // Each add = factor x previous size
input double            InpWinStreakMult     = 1.15;          // Risk multiplier per win (^streak)
input double            InpWinStreakCap      = 1.50;          // Win-streak multiplier cap
input double            InpLossStreakMult    = 0.85;          // Anti-martingale per loss (^streak)
input double            InpLossStreakFloor   = 0.40;          // Anti-martingale floor

input group "=== CLOSE ON TREND SHIFT ==="
input double            InpShiftPartial      = 0.45;          // Score: bank 50% + tighten leash
input double            InpShiftClose        = 0.70;          // Score: close the thesis
input int               InpShiftConfirmBars  = 2;             // Closed M5 bars above close score
input double            InpTightLeashATR     = 1.10;          // Tightened leash (x ATR M5)

input group "=== RISK & COMPLIANCE SHIELD (FTMO/Upcomers) ==="
input ENUM_JZ_LOTMODE   InpLotMode           = JZ_LOT_RISK_PCT; // Sizing mode
input double            InpRiskPct           = 0.50;          // Risk % of equity per thesis
input double            InpFixedLots         = 0.10;          // Fixed lots (if mode = FIXED)
input double            InpRiskCeilingPct    = 1.00;          // Hard money cap per thesis (% equity)
input double            InpFirmDailyPct      = 5.0;           // FIRM daily loss limit % (FTMO 5 / Oracle 4)
input double            InpFirmMaxPct        = 10.0;          // FIRM max drawdown % (FTMO 10 / Oracle 5)
input double            InpSoftBuffer        = 0.60;          // Soft halt at this fraction of firm limit
input double            InpHardBuffer        = 0.80;          // Hard flatten at this fraction of firm limit
input ENUM_JZ_ANCHOR    InpAnchorMode        = JZ_ANCHOR_INTRADAY_PEAK; // Daily-loss anchor
input int               InpResetServerHour   = 0;             // Daily reset hour (server)
input double            InpMaxSpreadPoints   = 35;            // Max spread (points) to act
input int               InpSlippagePoints    = 10;            // Max slippage (points)
input int               InpMaxPositions      = 3;             // Max open positions this magic (base+adds)
input double            InpAccountStartBal   = 0;             // Challenge start balance (0 = auto first run)

input group "=== PANEL ==="
input bool              InpShowPanel         = true;          // Show dashboard
input int               InpPanelX            = 12;            // Panel X
input int               InpPanelY            = 22;            // Panel Y

//============================== STATE ==============================
CTrade   trade;
string   g_lock  = "";
string   g_gvHWM = "", g_gvDayId = "", g_gvAnchor = "", g_gvPeakEq = "", g_gvWinStk = "", g_gvLossStk = "";

// indicator handles
int hEMAf_D1=INVALID_HANDLE,hEMAs_D1=INVALID_HANDLE,hADX_D1=INVALID_HANDLE;
int hEMAf_H4=INVALID_HANDLE,hEMAs_H4=INVALID_HANDLE,hADX_H4=INVALID_HANDLE;
int hEMAf_H1=INVALID_HANDLE,hEMAs_H1=INVALID_HANDLE,hADX_H1=INVALID_HANDLE;
int hEMAf_M15=INVALID_HANDLE,hEMAs_M15=INVALID_HANDLE,hADX_M15=INVALID_HANDLE,hATR_M15=INVALID_HANDLE;
int hEMAf_M5=INVALID_HANDLE,hEMAs_M5=INVALID_HANDLE,hADX_M5=INVALID_HANDLE,hATR_M5=INVALID_HANDLE;
int hEMAf_M1=INVALID_HANDLE,hEMAs_M1=INVALID_HANDLE,hATR_M1=INVALID_HANDLE;

// compliance / day state
long     g_dayId          = -1;
double   g_dayAnchor      = 0.0;      // equity at reset (or rebuilt)
double   g_dayPeakEq      = 0.0;      // intraday equity peak
double   g_hwm            = 0.0;      // lifetime equity high-water mark
bool     g_softHalt       = false;
bool     g_hardHalt       = false;
int      g_winStreak      = 0;
int      g_lossStreak     = 0;
int      g_tradesToday    = 0;
int      g_tradesThisHour = 0;
int      g_hourStamp      = -1;
datetime g_lastEntryTime  = 0;

// Helios session state
double   g_asiaHigh = 0.0, g_asiaLow = 0.0;
long     g_asiaDay  = -1;
int      g_judasBias      = 0;        // +1 long bias (sweep of low), -1 short bias (sweep of high)
datetime g_judasSetAt     = 0;
double   g_sweepExtreme   = 0.0;      // extreme of the Judas sweep (stop anchor)
datetime g_lastM5Bar      = 0;
datetime g_lastM1Bar      = 0;

// thesis state (one thesis at a time)
int      g_thesisDir      = 0;        // +1 / -1 / 0 none
ulong    g_baseTicket     = 0;
double   g_baseEntry      = 0.0;
double   g_Rpts           = 0.0;      // 1R in points (from base initial stop)
double   g_baseInitVol    = 0.0;
double   g_lastAddVol     = 0.0;
int      g_addCount       = 0;
int      g_ladderStage    = 0;        // 0 none, 1 after TP1, 2 after TP2
double   g_peakPrice      = 0.0;      // closed-bar favorable extreme
double   g_peakR          = 0.0;
datetime g_thesisOpenTime = 0;
double   g_thesisRealized = 0.0;
int      g_shiftBars      = 0;        // consecutive closed M5 bars with score >= close thr
bool     g_tightLeash     = false;

//============================== UTILS ==============================
double Pt()               { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }
double Ask()              { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double Bid()              { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double SpreadPts()        { return (Ask() - Bid()) / Pt(); }
int    StopsLevelPts()    { return (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL); }
double Equity()           { return AccountInfoDouble(ACCOUNT_EQUITY); }

double NormPrice(double p){ int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS); return NormalizeDouble(p,d); }

double NormVolume(double v)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   v = MathFloor(v / step + 1e-9) * step;
   if(v > vmax) v = vmax;
   if(v < vmin) return 0.0;                    // REFUSE below broker minimum - never over-risk
   return NormalizeDouble(v, 8);
}

double MoneyPerPointPerLot()
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0 || tv <= 0.0) return 0.0;      // no tick data -> caller must refuse to trade
   return tv * (Pt() / ts);
}

bool Buf(int handle, int bufIdx, int count, double &out[])
{
   if(handle == INVALID_HANDLE) return false;
   ArraySetAsSeries(out, true);
   return (CopyBuffer(handle, bufIdx, 0, count, out) == count);
}

long CurDayId() { return (long)((TimeCurrent() - (long)InpResetServerHour * 3600) / 86400); }

//---------------------------------------------------- block windows
bool InBlockWindow()
{
   if(StringLen(InpBlockWindows) < 9) return false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int nowMin = dt.hour * 60 + dt.min;
   string parts[];
   int n = StringSplit(InpBlockWindows, ';', parts);
   for(int i = 0; i < n; i++)
   {
      string w = parts[i]; StringTrimLeft(w); StringTrimRight(w);
      int dash = StringFind(w, "-");
      if(dash < 0) continue;
      string a = StringSubstr(w, 0, dash), b = StringSubstr(w, dash + 1);
      int ah=0, am=0, bh=0, bm=0;
      int ac = StringFind(a, ":"), bc = StringFind(b, ":");
      if(ac < 0 || bc < 0) continue;
      ah=(int)StringToInteger(StringSubstr(a,0,ac)); am=(int)StringToInteger(StringSubstr(a,ac+1));
      bh=(int)StringToInteger(StringSubstr(b,0,bc)); bm=(int)StringToInteger(StringSubstr(b,bc+1));
      int s = ah*60+am, e = bh*60+bm;
      if(s <= e) { if(nowMin >= s && nowMin <= e) return true; }
      else       { if(nowMin >= s || nowMin <= e) return true; }   // overnight window
   }
   return false;
}

bool InHourWindow(int startH, int endH)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(startH <= endH) return (dt.hour >= startH && dt.hour < endH);
   return (dt.hour >= startH || dt.hour < endH);
}
bool InTradeSession()
{
   if(InpTradeLondon && InHourWindow(InpLondonStartHour, InpLondonEndHour)) return true;
   if(InpTradeNY     && InHourWindow(InpNYStartHour,     InpNYEndHour))     return true;
   return false;
}

//============================ MTF CASCADE ==========================
// per-TF score in [-1,+1]: EMA regime (0.6) + fast-EMA slope (0.4), halved if ADX weak
double TFScore(int hf, int hs, int ha)
{
   double f[], s[], a[];
   if(!Buf(hf,0,3,f) || !Buf(hs,0,3,s) || !Buf(ha,0,2,a)) return 0.0;
   double sc = 0.0;
   sc += 0.6 * (f[1] > s[1] ? 1.0 : -1.0);
   sc += 0.4 * (f[1] > f[2] ? 1.0 : -1.0);
   if(a[1] < InpAdxMin) sc *= 0.5;
   return sc;
}
double CompositeScore()
{
   double wsum = InpW_D1 + InpW_H4 + InpW_H1 + InpW_M15;
   if(wsum <= 0.0) return 0.0;
   double sc = InpW_D1  * TFScore(hEMAf_D1,  hEMAs_D1,  hADX_D1)
             + InpW_H4  * TFScore(hEMAf_H4,  hEMAs_H4,  hADX_H4)
             + InpW_H1  * TFScore(hEMAf_H1,  hEMAs_H1,  hADX_H1)
             + InpW_M15 * TFScore(hEMAf_M15, hEMAs_M15, hADX_M15);
   return sc / wsum;
}

//====================== TREND-SHIFT REVERSAL SCORE =================
// how hard M15 (0.6) + M5 (0.4) argue AGAINST direction dir; 0..1
double TFReversal(int dir, int hf, int hs, int ha, ENUM_TIMEFRAMES tf)
{
   double f[], s[], adxm[], dip[], dim[];
   if(!Buf(hf,0,3,f) || !Buf(hs,0,3,s)) return 0.0;
   double r = 0.0;
   // EMA regime flipped against us
   if((dir > 0 && f[1] < s[1]) || (dir < 0 && f[1] > s[1])) r += 0.40;
   // DI cross against us
   if(Buf(ha,1,2,dip) && Buf(ha,2,2,dim) && Buf(ha,0,2,adxm))
      if(((dir > 0 && dim[1] > dip[1]) || (dir < 0 && dip[1] > dim[1])) && adxm[1] >= InpAdxMin) r += 0.30;
   // structure break: close beyond last swing against us (10-bar swing, closed bars)
   int hiIdx = iHighest(_Symbol, tf, MODE_HIGH, 10, 2);
   int loIdx = iLowest (_Symbol, tf, MODE_LOW,  10, 2);
   double swingHi = (hiIdx >= 0 ? iHigh(_Symbol, tf, hiIdx) : 0.0);
   double swingLo = (loIdx >= 0 ? iLow (_Symbol, tf, loIdx) : 0.0);
   double c1 = iClose(_Symbol, tf, 1);
   if(dir > 0 && swingLo > 0.0 && c1 < swingLo) r += 0.30;
   if(dir < 0 && swingHi > 0.0 && c1 > swingHi) r += 0.30;
   return MathMin(r, 1.0);
}
double TrendShiftScore(int dir)
{
   if(dir == 0) return 0.0;
   return 0.6 * TFReversal(dir, hEMAf_M15, hEMAs_M15, hADX_M15, PERIOD_M15)
        + 0.4 * TFReversal(dir, hEMAf_M5,  hEMAs_M5,  hADX_M5,  PERIOD_M5);
}

//=========================== HELIOS SESSION ========================
void UpdateAsianRange()
{
   long d = CurDayId();
   if(g_asiaDay == d && g_asiaHigh > 0.0) return;      // already built today
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpAsiaEndHour) return;                // range not complete yet
   // build from today's M5 bars inside the Asian window
   datetime dayStart = (datetime)(TimeCurrent() - (dt.hour*3600 + dt.min*60 + dt.sec));
   datetime aStart   = (datetime)(dayStart + (long)InpAsiaStartHour * 3600);
   datetime aEnd     = (datetime)(dayStart + (long)InpAsiaEndHour   * 3600);
   double hi = 0.0, lo = 0.0;
   int bars = iBars(_Symbol, PERIOD_M5);
   int scan = MathMin(bars - 1, 400);
   for(int i = 1; i <= scan; i++)
   {
      datetime bt = iTime(_Symbol, PERIOD_M5, i);
      if(bt < aStart) break;
      if(bt >= aEnd)  continue;
      double h = iHigh(_Symbol, PERIOD_M5, i), l = iLow(_Symbol, PERIOD_M5, i);
      if(hi == 0.0 || h > hi) hi = h;
      if(lo == 0.0 || l < lo) lo = l;
   }
   if(hi > 0.0 && lo > 0.0 && hi > lo)
   {
      g_asiaHigh = hi; g_asiaLow = lo; g_asiaDay = d;
      g_judasBias = 0; g_sweepExtreme = 0.0;
   }
}

// on each closed M5 bar inside London: detect the Judas sweep
void UpdateJudasBias()
{
   if(g_asiaHigh <= 0.0 || g_asiaDay != CurDayId()) return;
   if(!InHourWindow(InpLondonStartHour, InpLondonEndHour)) return;
   double h1 = iHigh(_Symbol, PERIOD_M5, 1), l1 = iLow(_Symbol, PERIOD_M5, 1), c1 = iClose(_Symbol, PERIOD_M5, 1);
   if(h1 > g_asiaHigh && c1 < g_asiaHigh)   // swept the high, rejected -> SHORT bias
   { g_judasBias = -1; g_judasSetAt = TimeCurrent(); g_sweepExtreme = h1; }
   else if(l1 < g_asiaLow && c1 > g_asiaLow) // swept the low, rejected -> LONG bias
   { g_judasBias = +1; g_judasSetAt = TimeCurrent(); g_sweepExtreme = l1; }
   if(g_judasBias != 0 && (TimeCurrent() - g_judasSetAt) > (long)InpBiasValidMinutes * 60)
   { g_judasBias = 0; g_sweepExtreme = 0.0; }
}

//============================ COMPLIANCE ===========================
void RollDayIfNeeded()
{
   long d = CurDayId();
   if(d == g_dayId) return;
   g_dayId = d;
   g_dayAnchor = Equity();
   g_dayPeakEq = g_dayAnchor;
   g_tradesToday = 0;
   g_softHalt = false; g_hardHalt = false;
   GlobalVariableSet(g_gvDayId,  (double)g_dayId);
   GlobalVariableSet(g_gvAnchor, g_dayAnchor);
   GlobalVariableSet(g_gvPeakEq, g_dayPeakEq);
}

void UpdateShield()
{
   RollDayIfNeeded();
   double eq = Equity();
   if(eq > g_hwm)      { g_hwm = eq;      GlobalVariableSet(g_gvHWM, g_hwm); }
   if(eq > g_dayPeakEq){ g_dayPeakEq = eq; GlobalVariableSet(g_gvPeakEq, g_dayPeakEq); }

   double anchor  = (InpAnchorMode == JZ_ANCHOR_INTRADAY_PEAK ? g_dayPeakEq : g_dayAnchor);
   double baseRef = (InpAccountStartBal > 0.0 ? InpAccountStartBal : g_hwm);
   if(baseRef <= 0.0) baseRef = eq;

   double dayLossPct = (anchor > 0.0 ? (anchor - eq) / anchor * 100.0 : 0.0);
   double ddPct      = (g_hwm  > 0.0 ? (g_hwm  - eq) / g_hwm  * 100.0 : 0.0);

   double softDay = InpFirmDailyPct * InpSoftBuffer;
   double hardDay = InpFirmDailyPct * InpHardBuffer;
   double softDD  = InpFirmMaxPct   * InpSoftBuffer;
   double hardDD  = InpFirmMaxPct   * InpHardBuffer;

   if(dayLossPct >= hardDay || ddPct >= hardDD)
   {
      if(!g_hardHalt)
      {
         g_hardHalt = true; g_softHalt = true;
         Print("JZ SHIELD: HARD limit buffer hit (day ", DoubleToString(dayLossPct,2),
               "% / dd ", DoubleToString(ddPct,2), "%) - flattening and halting until reset.");
         CloseThesis("HARD-SHIELD", true);
      }
   }
   else if(dayLossPct >= softDay || ddPct >= softDD)
   {
      if(!g_softHalt)
      {
         g_softHalt = true;
         Print("JZ SHIELD: SOFT halt (day ", DoubleToString(dayLossPct,2),
               "% / dd ", DoubleToString(ddPct,2), "%) - no new risk today.");
      }
   }
}

bool CanOpenNewRisk()
{
   if(g_hardHalt || g_softHalt)                       return false;
   if(!InTradeSession())                              return false;
   if(InBlockWindow())                                return false;
   if(SpreadPts() > InpMaxSpreadPoints)               return false;
   if(g_tradesToday    >= InpMaxTradesPerDay)         return false;
   if(g_tradesThisHour >= InpMaxTradesPerHour)        return false;
   if((TimeCurrent() - g_lastEntryTime) < InpMinSecondsBetween) return false;
   if(OwnPositionCount() >= InpMaxPositions)          return false;
   return true;
}

bool DirAllowed(int dir)
{
   if(dir > 0 && InpDirectionFilter == JZ_DIR_SELL_ONLY) return false;
   if(dir < 0 && InpDirectionFilter == JZ_DIR_BUY_ONLY)  return false;
   return true;
}

//============================ POSITIONS ============================
int OwnPositionCount()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
   }
   return n;
}

double OwnTotalVolume()
{
   double v = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      v += PositionGetDouble(POSITION_VOLUME);
   }
   return v;
}

//============================ SIZING ===============================
double StreakMultiplier()
{
   double m = 1.0;
   if(g_winStreak  > 0) m = MathMin(InpWinStreakCap, MathPow(InpWinStreakMult, g_winStreak));
   if(g_lossStreak > 0) m = MathMax(InpLossStreakFloor, MathPow(InpLossStreakMult, g_lossStreak));
   return m;
}

// half-Kelly ceiling from realized streak stats is approximated by the capped
// streak multiplier; the absolute money ceiling below is the hard governor.
double LotsForRisk(double slPts, double riskPctOverride)
{
   if(slPts <= 0.0) return 0.0;
   if(InpLotMode == JZ_LOT_FIXED) return NormVolume(InpFixedLots);
   double mpp = MoneyPerPointPerLot();
   if(mpp <= 0.0) { Print("JZ: no tick value data - refusing to size."); return 0.0; }
   double eq      = Equity();
   double riskPct = MathMin(riskPctOverride * StreakMultiplier(), InpRiskCeilingPct); // ceiling LAST
   double money   = eq * riskPct / 100.0;
   return NormVolume(money / (slPts * mpp));
}

//========================= SMART STOPLOSS ==========================
// structure + ATR hybrid, spread-floored. Returns stop PRICE for dir at entryPx.
double SmartInitialStop(int dir, double entryPx, double structurePx)
{
   double atrArr[];
   if(!Buf(hATR_M15, 0, 2, atrArr)) return 0.0;
   double atr = atrArr[1];
   if(atr <= 0.0) return 0.0;
   double dist;
   if(structurePx > 0.0)
      dist = MathAbs(entryPx - structurePx) + InpSL_BufferATR * atr;
   else
      dist = InpSL_ATRmult * atr;
   dist = MathMax(dist, InpSL_MinATR * atr);
   dist = MathMin(dist, InpSL_MaxATR * atr);
   dist = MathMax(dist, InpSL_SpreadFloor * SpreadPts() * Pt());
   dist = MathMax(dist, (StopsLevelPts() + 2) * Pt());
   return NormPrice(dir > 0 ? entryPx - dist : entryPx + dist);
}

//============================ ENTRIES ==============================
void OpenThesis(int dir, double structurePx, string why)
{
   if(!DirAllowed(dir)) return;
   double entry = (dir > 0 ? Ask() : Bid());
   double sl    = SmartInitialStop(dir, entry, structurePx);
   if(sl <= 0.0) return;
   double slPts = MathAbs(entry - sl) / Pt();
   double lots  = LotsForRisk(slPts, InpRiskPct);
   if(lots <= 0.0) { Print("JZ: size below broker minimum at this stop - trade refused (", why, ")"); return; }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   bool ok = (dir > 0)
      ? trade.Buy (lots, _Symbol, 0.0, sl, 0.0, InpTag + "|" + why)
      : trade.Sell(lots, _Symbol, 0.0, sl, 0.0, InpTag + "|" + why);
   if(!ok) { Print("JZ: entry failed (", why, ") ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription()); return; }

   // adopt thesis state from the live position (fill price may differ)
   g_thesisDir      = dir;
   g_baseTicket     = FindNewestOwnTicket();
   if(g_baseTicket > 0 && PositionSelectByTicket(g_baseTicket))
   {
      g_baseEntry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double liveSL = PositionGetDouble(POSITION_SL);
      g_Rpts        = MathAbs(g_baseEntry - (liveSL > 0.0 ? liveSL : sl)) / Pt();
      g_baseInitVol = PositionGetDouble(POSITION_VOLUME);
   }
   else { g_baseEntry = entry; g_Rpts = slPts; g_baseInitVol = lots; }
   g_lastAddVol     = g_baseInitVol;
   g_addCount       = 0;
   g_ladderStage    = 0;
   g_peakPrice      = g_baseEntry;
   g_peakR          = 0.0;
   g_thesisOpenTime = TimeCurrent();
   g_thesisRealized = 0.0;
   g_shiftBars      = 0;
   g_tightLeash     = false;
   g_lastEntryTime = TimeCurrent();
   g_tradesToday++; g_tradesThisHour++;
   Print("JZ ENTRY [", why, "] dir=", dir, " lots=", DoubleToString(lots,2),
         " R=", DoubleToString(g_Rpts,0), "pts streakMult=", DoubleToString(StreakMultiplier(),2));
}

ulong FindNewestOwnTicket()
{
   ulong best = 0; datetime bt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= bt) { bt = t; best = tk; }
   }
   return best;
}

// ENGINE A - Helios Judas reversal (on closed M5 bar)
void TryHeliosEntry()
{
   if(!InpUseHeliosSession || g_thesisDir != 0 || g_judasBias == 0) return;
   if(!CanOpenNewRisk()) return;
   int dir = g_judasBias;
   if(InpInverseMode) dir = -dir;
   double comp = CompositeScore();
   // reversal trade: composite must not be STRONGLY against the bias
   if(dir > 0 && comp < -InpScoreThreshold) return;
   if(dir < 0 && comp >  InpScoreThreshold) return;
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   double atrArr[]; if(!Buf(hATR_M5,0,2,atrArr)) return;
   bool confirmed = (g_judasBias < 0 && c1 < g_asiaHigh - 0.10 * atrArr[1])
                 || (g_judasBias > 0 && c1 > g_asiaLow  + 0.10 * atrArr[1]);
   if(!confirmed) return;
   OpenThesis(dir, g_sweepExtreme, "HELIOS-JUDAS");
   if(g_thesisDir != 0) { g_judasBias = 0; g_sweepExtreme = 0.0; }  // bias consumed
}

// ENGINE B - Smart-HFT micro momentum (on closed M1 bar)
void TryMicroEntry()
{
   if(!InpUseMicroHFT || g_thesisDir != 0) return;
   if(!CanOpenNewRisk()) return;
   double comp = CompositeScore();
   if(MathAbs(comp) < InpScoreThreshold) return;
   int dir = (comp > 0.0 ? +1 : -1);
   if(InpInverseMode) dir = -dir;
   if(!DirAllowed(dir)) return;
   if(g_judasBias != 0 && dir != (InpInverseMode ? -g_judasBias : g_judasBias)) return; // never fight fresh session bias

   double f[], s[], atr1[];
   if(!Buf(hEMAf_M1,0,3,f) || !Buf(hEMAs_M1,0,3,s) || !Buf(hATR_M1,0,2,atr1)) return;
   double o1 = iOpen(_Symbol,PERIOD_M1,1), c1 = iClose(_Symbol,PERIOD_M1,1);
   double body = MathAbs(c1 - o1);
   if(atr1[1] <= 0.0 || body < InpM1BodyATR * atr1[1]) return;
   bool longSig  = (f[2] <= s[2] && f[1] > s[1] && c1 > f[1]);
   bool shortSig = (f[2] >= s[2] && f[1] < s[1] && c1 < f[1]);
   if(InpInverseMode) { bool t = longSig; longSig = shortSig; shortSig = t; }
   if(dir > 0 && !longSig)  return;
   if(dir < 0 && !shortSig) return;
   OpenThesis(dir, 0.0, "SMART-HFT");
}

//====================== INCREASE ON WINNING ========================
void TryPyramidAdd()
{
   if(!InpAllowAdds || g_thesisDir == 0 || g_addCount >= InpMaxAdds) return;
   if(!CanOpenNewRisk()) return;
   if(g_Rpts <= 0.0) return;
   if(g_peakR < InpAddTriggerR + 0.30 * g_addCount) return;   // each add needs fresh progress
   if(!ThesisStopAtOrBeyondBE()) return;                      // HOUSE MONEY ONLY - no added downside
   // momentum re-confirmation: last closed M5 pushed a new favorable extreme
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   if(g_thesisDir > 0 && c1 < g_peakPrice) return;
   if(g_thesisDir < 0 && c1 > g_peakPrice) return;
   double comp = CompositeScore();
   if(g_thesisDir > 0 && comp <  InpScoreThreshold) return;
   if(g_thesisDir < 0 && comp > -InpScoreThreshold) return;

   double vol = NormVolume(g_lastAddVol * InpAddSizeFactor);  // NON-ESCALATING
   if(vol <= 0.0) return;
   double entry = (g_thesisDir > 0 ? Ask() : Bid());
   double atrArr[]; if(!Buf(hATR_M5,0,2,atrArr)) return;
   double dist = MathMax(InpChandelierATR * atrArr[1], (StopsLevelPts()+2)*Pt());
   double sl   = NormPrice(g_thesisDir > 0 ? entry - dist : entry + dist);
   // never place an add's stop worse than the locked thesis stop
   double lockSL = ThesisLockedStop();
   if(lockSL > 0.0)
   {
      if(g_thesisDir > 0) sl = MathMax(sl, lockSL);
      else                sl = MathMin(sl, lockSL);
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   bool ok = (g_thesisDir > 0)
      ? trade.Buy (vol, _Symbol, 0.0, sl, 0.0, InpTag + "|ADD" + IntegerToString(g_addCount + 1))
      : trade.Sell(vol, _Symbol, 0.0, sl, 0.0, InpTag + "|ADD" + IntegerToString(g_addCount + 1));
   if(ok)
   {
      g_addCount++; g_lastAddVol = vol;
      g_lastEntryTime = TimeCurrent();
      g_tradesToday++; g_tradesThisHour++;
      Print("JZ ADD #", g_addCount, " ", DoubleToString(vol,2), " lots at ", DoubleToString(g_peakR,2), "R (house money)");
   }
}

bool ThesisStopAtOrBeyondBE()
{
   if(g_baseTicket == 0 || !PositionSelectByTicket(g_baseTicket)) return false;
   double sl = PositionGetDouble(POSITION_SL);
   if(sl <= 0.0) return false;
   if(g_thesisDir > 0) return (sl >= g_baseEntry);
   return (sl <= g_baseEntry);
}
double ThesisLockedStop()
{
   if(g_baseTicket == 0 || !PositionSelectByTicket(g_baseTicket)) return 0.0;
   return PositionGetDouble(POSITION_SL);
}

//===================== SMART TP LADDER + RATCHET ===================
double CurrentR()
{
   if(g_thesisDir == 0 || g_Rpts <= 0.0) return 0.0;
   double px = (g_thesisDir > 0 ? Bid() : Ask());
   return (g_thesisDir > 0 ? (px - g_baseEntry) : (g_baseEntry - px)) / (g_Rpts * Pt());
}

void UpdatePeakOnClosedM5()
{
   if(g_thesisDir == 0) return;
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   if(g_thesisDir > 0 && c1 > g_peakPrice) g_peakPrice = c1;
   if(g_thesisDir < 0 && c1 < g_peakPrice) g_peakPrice = c1;
   double pk = (g_thesisDir > 0 ? (g_peakPrice - g_baseEntry) : (g_baseEntry - g_peakPrice)) / (g_Rpts * Pt());
   if(pk > g_peakR) g_peakR = pk;
}

void ManageLadder()
{
   if(g_thesisDir == 0 || g_baseTicket == 0) return;
   if(!PositionSelectByTicket(g_baseTicket)) return;
   double vol = PositionGetDouble(POSITION_VOLUME);
   double r   = CurrentR();
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(g_ladderStage < 1 && r >= InpTP1_R)
   {
      double part = NormVolume(g_baseInitVol * InpTP1_Pct / 100.0);
      if(part > 0.0 && vol - part >= vmin - 1e-9)
         if(trade.PositionClosePartial(g_baseTicket, part)) { g_ladderStage = 1; Print("JZ LADDER: banked ", DoubleToString(part,2), " @ ", DoubleToString(InpTP1_R,3), "R"); }
   }
   if(g_ladderStage < 2 && r >= InpTP2_R)
   {
      if(PositionSelectByTicket(g_baseTicket))
      {
         vol = PositionGetDouble(POSITION_VOLUME);
         double part = NormVolume(g_baseInitVol * InpTP2_Pct / 100.0);
         if(part > 0.0 && vol - part >= vmin - 1e-9)
            if(trade.PositionClosePartial(g_baseTicket, part)) { g_ladderStage = 2; Print("JZ LADDER: banked ", DoubleToString(part,2), " @ ", DoubleToString(InpTP2_R,3), "R"); }
      }
   }
   if(r >= InpTP3_R) CloseThesis("RUNNER-2.618R", false);   // golden runner target
}

void RatchetStops()
{
   if(g_thesisDir == 0 || g_Rpts <= 0.0) return;
   double atrArr[]; if(!Buf(hATR_M5,0,2,atrArr)) return;
   double atr = atrArr[1]; if(atr <= 0.0) return;
   double leash = (g_tightLeash ? InpTightLeashATR : InpChandelierATR) * atr;
   double r = CurrentR();
   double Rpx = g_Rpts * Pt();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double curSL = PositionGetDouble(POSITION_SL);
      double want  = curSL;

      if(g_thesisDir > 0)
      {
         if(r >= InpBE_TriggerR)             want = MathMax(want, g_baseEntry + InpBE_OffsetR * Rpx);
         want = MathMax(want, g_peakPrice - leash);                                  // chandelier (closed-bar anchor)
         if(g_peakR >= InpGivebackArmR)      want = MathMax(want, g_baseEntry + InpGivebackKeep * g_peakR * Rpx);
         double maxAllowed = Bid() - (StopsLevelPts() + 1) * Pt();
         want = MathMin(want, maxAllowed);
         if(want > curSL + Pt())             trade.PositionModify(tk, NormPrice(want), PositionGetDouble(POSITION_TP));
      }
      else
      {
         if(r >= InpBE_TriggerR)             want = (curSL <= 0.0 ? g_baseEntry - InpBE_OffsetR * Rpx : MathMin(want, g_baseEntry - InpBE_OffsetR * Rpx));
         double ch = g_peakPrice + leash;
         want = (want <= 0.0 ? ch : MathMin(want, ch));
         if(g_peakR >= InpGivebackArmR)      want = MathMin(want, g_baseEntry - InpGivebackKeep * g_peakR * Rpx);
         double minAllowed = Ask() + (StopsLevelPts() + 1) * Pt();
         want = MathMax(want, minAllowed);
         if(curSL <= 0.0 || want < curSL - Pt()) trade.PositionModify(tk, NormPrice(want), PositionGetDouble(POSITION_TP));
      }
   }
}

//====================== CLOSE ON TREND SHIFT =======================
void ManageTrendShift()   // evaluated on closed M5 bars
{
   if(g_thesisDir == 0) return;
   double score = TrendShiftScore(g_thesisDir);
   if(score >= InpShiftClose) g_shiftBars++;
   else                       g_shiftBars = 0;

   bool heldLongEnough = (TimeCurrent() - g_thesisOpenTime) >= InpMinHoldSeconds;

   if(g_shiftBars >= InpShiftConfirmBars && heldLongEnough)
   {
      CloseThesis("TREND-SHIFT " + DoubleToString(score,2), false);
      return;
   }
   if(score >= InpShiftPartial && !g_tightLeash && heldLongEnough)
   {
      g_tightLeash = true;                          // collapse the leash
      if(g_baseTicket > 0 && PositionSelectByTicket(g_baseTicket) && g_ladderStage < 1 && CurrentR() > 0.10)
      {
         double vol  = PositionGetDouble(POSITION_VOLUME);
         double part = NormVolume(vol * 0.50);
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(part > 0.0 && vol - part >= vmin - 1e-9)
            if(trade.PositionClosePartial(g_baseTicket, part))
               Print("JZ SHIFT-GUARD: banked 50% at score ", DoubleToString(score,2));
      }
   }
}

void CloseThesis(string why, bool force)
{
   if(!force && g_thesisDir != 0 && (TimeCurrent() - g_thesisOpenTime) < InpMinHoldSeconds) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      trade.PositionClose(tk, InpSlippagePoints);
   }
   if(g_thesisDir != 0) Print("JZ CLOSE [", why, "]");
}

//===================== THESIS FINALIZE / STREAKS ===================
void OnTradeTransaction(const MqlTradeTransaction &tr, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(tr.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(tr.deal)) return;
   if(HistoryDealGetString(tr.deal, DEAL_SYMBOL) != _Symbol) return;
   if((long)HistoryDealGetInteger(tr.deal, DEAL_MAGIC) != InpMagic) return;
   long entry = HistoryDealGetInteger(tr.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
   g_thesisRealized += HistoryDealGetDouble(tr.deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(tr.deal, DEAL_SWAP)
                     + HistoryDealGetDouble(tr.deal, DEAL_COMMISSION);
   if(OwnPositionCount() == 0 && g_thesisDir != 0)
   {
      if(g_thesisRealized > 0.0) { g_winStreak++;  g_lossStreak = 0; }
      else                       { g_lossStreak++; g_winStreak  = 0; }
      GlobalVariableSet(g_gvWinStk,  (double)g_winStreak);
      GlobalVariableSet(g_gvLossStk, (double)g_lossStreak);
      Print("JZ THESIS DONE: ", DoubleToString(g_thesisRealized,2), " -> streak W", g_winStreak, "/L", g_lossStreak);
      ResetThesis();
   }
}
void ResetThesis()
{
   g_thesisDir = 0; g_baseTicket = 0; g_baseEntry = 0.0; g_Rpts = 0.0;
   g_baseInitVol = 0.0; g_lastAddVol = 0.0; g_addCount = 0; g_ladderStage = 0;
   g_peakPrice = 0.0; g_peakR = 0.0; g_thesisRealized = 0.0;
   g_shiftBars = 0; g_tightLeash = false; g_thesisOpenTime = 0;
}

// restart safety: re-adopt an existing own position as the live thesis
void AdoptExistingThesis()
{
   ulong tk = FindNewestOwnTicket();
   if(tk == 0) return;
   if(!PositionSelectByTicket(tk)) return;
   g_baseTicket = tk;
   g_thesisDir  = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? +1 : -1);
   g_baseEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double atrArr[];
   double fallback = (Buf(hATR_M15,0,2,atrArr) ? InpSL_ATRmult * atrArr[1] : 100 * Pt());
   g_Rpts       = (sl > 0.0 ? MathAbs(g_baseEntry - sl) : fallback) / Pt();
   if(g_Rpts <= 0.0) g_Rpts = fallback / Pt();
   g_baseInitVol   = PositionGetDouble(POSITION_VOLUME);
   g_lastAddVol    = g_baseInitVol;
   g_addCount      = MathMax(0, OwnPositionCount() - 1);
   g_ladderStage   = 2;                    // conservative: no re-banking after restart
   g_peakPrice     = g_baseEntry;
   g_peakR         = MathMax(0.0, CurrentR());
   g_thesisOpenTime= (datetime)PositionGetInteger(POSITION_TIME);
   Print("JZ: adopted existing thesis ticket ", tk, " dir=", g_thesisDir, " R=", DoubleToString(g_Rpts,0), "pts (ladder disabled post-restart)");
}

//============================== PANEL ==============================
#define JZP "JZHSH_"
void PLabel(string id, int x, int y, string txt, color clr, int fs=9)
{
   string nm = JZP + id;
   if(ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fs);
      ObjectSetString (0, nm, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
}
void DrawPanel()
{
   if(!InpShowPanel) return;
   string bg = JZP + "BG";
   if(ObjectFind(0, bg) < 0)
   {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpPanelX - 6);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpPanelY - 6);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, 330);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, 168);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'12,17,24');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, C'40,60,80');
      ObjectSetInteger(0, bg, OBJPROP_BACK, true);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   }
   int x = InpPanelX, y = InpPanelY, dy = 16;
   double eq = Equity();
   double anchor = (InpAnchorMode == JZ_ANCHOR_INTRADAY_PEAK ? g_dayPeakEq : g_dayAnchor);
   double dayPct = (anchor > 0.0 ? (eq - anchor) / anchor * 100.0 : 0.0);
   double ddPct  = (g_hwm  > 0.0 ? (g_hwm - eq) / g_hwm * 100.0 : 0.0);
   string state  = (g_hardHalt ? "HARD HALT" : (g_softHalt ? "SOFT HALT" : "ACTIVE"));
   color  stc    = (g_hardHalt ? clrOrangeRed : (g_softHalt ? clrGold : clrLimeGreen));
   double comp   = CompositeScore();
   double shift  = TrendShiftScore(g_thesisDir);

   PLabel("T",  x, y,        "HELIOS SMART-HFT v1.01  |  JAZZYLYFE", clrGold, 10);           y += dy + 2;
   PLabel("S",  x, y,        "STATE   : " + state, stc);                                      y += dy;
   PLabel("SE", x, y,        StringFormat("SESSION : %s  spread %.0f  trades %d/%d",
                              (InTradeSession() ? "OPEN" : "CLOSED"), SpreadPts(),
                              g_tradesToday, InpMaxTradesPerDay), clrSilver);                 y += dy;
   PLabel("M",  x, y,        StringFormat("MTF     : %+0.2f  (thr %.2f)   JUDAS %s",
                              comp, InpScoreThreshold,
                              (g_judasBias > 0 ? "LONG" : (g_judasBias < 0 ? "SHORT" : "-"))),
                              (MathAbs(comp) >= InpScoreThreshold ? clrDeepSkyBlue : clrGray)); y += dy;
   PLabel("P",  x, y,        (g_thesisDir == 0 ? "THESIS  : flat"
                              : StringFormat("THESIS  : %s  %.2fR  peak %.2fR  adds %d/%d  L%d",
                                (g_thesisDir > 0 ? "LONG" : "SHORT"), CurrentR(), g_peakR,
                                g_addCount, InpMaxAdds, g_ladderStage)),
                              (g_thesisDir == 0 ? clrGray : clrWhite));                        y += dy;
   PLabel("SH", x, y,        StringFormat("SHIFT   : %.2f  (bank %.2f / close %.2f x%d)%s",
                              shift, InpShiftPartial, InpShiftClose, InpShiftConfirmBars,
                              (g_tightLeash ? "  TIGHT" : "")),
                              (shift >= InpShiftPartial ? clrOrange : clrSilver));             y += dy;
   PLabel("D",  x, y,        StringFormat("DAY P/L : %+.2f%%   DD(HWM): %.2f%%", dayPct, ddPct),
                              (dayPct >= 0 ? clrLimeGreen : clrTomato));                       y += dy;
   PLabel("K",  x, y,        StringFormat("STREAK  : W%d / L%d  -> risk x%.2f  (%s%s)",
                              g_winStreak, g_lossStreak, StreakMultiplier(),
                              (InpInverseMode ? "INV " : ""),
                              (InpDirectionFilter==JZ_DIR_BOTH?"BOTH":(InpDirectionFilter==JZ_DIR_BUY_ONLY?"BUY":"SELL"))),
                              clrSilver);
}
void KillPanel() { ObjectsDeleteAll(0, JZP); }

//=============================== INIT ==============================
int OnInit()
{
   // standing ban
   string sym = _Symbol; StringToUpper(sym);
   if(StringFind(sym, "BCHUSD") >= 0)
   { Print("JZ: BCHUSD is permanently banned. Init refused."); return INIT_FAILED; }

   if(InpAsiaStartHour == InpAsiaEndHour)
   { Print("JZ: Asian window is empty."); return INIT_PARAMETERS_INCORRECT; }
   if(InpTP1_Pct + InpTP2_Pct >= 95.0)
   { Print("JZ: ladder percentages leave no runner."); return INIT_PARAMETERS_INCORRECT; }
   if(InpSoftBuffer >= InpHardBuffer)
   { Print("JZ: soft buffer must be below hard buffer."); return INIT_PARAMETERS_INCORRECT; }

   // one-instance lock per symbol+magic
   g_lock = "JZHSH_LOCK_" + _Symbol + "_" + IntegerToString((int)InpMagic);
   if(GlobalVariableCheck(g_lock) && GlobalVariableGet(g_lock) != (double)ChartID())
   { Print("JZ: another instance already governs ", _Symbol, " magic ", InpMagic, ". Init refused."); return INIT_FAILED; }
   GlobalVariableTemp(g_lock);
   GlobalVariableSet(g_lock, (double)ChartID());

   // handles
   hEMAf_D1  = iMA(_Symbol, PERIOD_D1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMAs_D1  = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hADX_D1   = iADX(_Symbol, PERIOD_D1, 14);
   hEMAf_H4  = iMA(_Symbol, PERIOD_H4, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMAs_H4  = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   hADX_H4   = iADX(_Symbol, PERIOD_H4, 14);
   hEMAf_H1  = iMA(_Symbol, PERIOD_H1, 50,  0, MODE_EMA, PRICE_CLOSE);
   hEMAs_H1  = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hADX_H1   = iADX(_Symbol, PERIOD_H1, 14);
   hEMAf_M15 = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMAs_M15 = iMA(_Symbol, PERIOD_M15, 55, 0, MODE_EMA, PRICE_CLOSE);
   hADX_M15  = iADX(_Symbol, PERIOD_M15, 14);
   hATR_M15  = iATR(_Symbol, PERIOD_M15, 14);
   hEMAf_M5  = iMA(_Symbol, PERIOD_M5, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMAs_M5  = iMA(_Symbol, PERIOD_M5, 55, 0, MODE_EMA, PRICE_CLOSE);
   hADX_M5   = iADX(_Symbol, PERIOD_M5, 14);
   hATR_M5   = iATR(_Symbol, PERIOD_M5, 14);
   hEMAf_M1  = iMA(_Symbol, PERIOD_M1, InpM1FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEMAs_M1  = iMA(_Symbol, PERIOD_M1, InpM1SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR_M1   = iATR(_Symbol, PERIOD_M1, 14);
   if(hEMAf_D1==INVALID_HANDLE || hEMAs_D1==INVALID_HANDLE || hADX_D1==INVALID_HANDLE ||
      hEMAf_H4==INVALID_HANDLE || hEMAs_H4==INVALID_HANDLE || hADX_H4==INVALID_HANDLE ||
      hEMAf_H1==INVALID_HANDLE || hEMAs_H1==INVALID_HANDLE || hADX_H1==INVALID_HANDLE ||
      hEMAf_M15==INVALID_HANDLE|| hEMAs_M15==INVALID_HANDLE|| hADX_M15==INVALID_HANDLE|| hATR_M15==INVALID_HANDLE ||
      hEMAf_M5==INVALID_HANDLE || hEMAs_M5==INVALID_HANDLE || hADX_M5==INVALID_HANDLE || hATR_M5==INVALID_HANDLE ||
      hEMAf_M1==INVALID_HANDLE || hEMAs_M1==INVALID_HANDLE || hATR_M1==INVALID_HANDLE)
   { Print("JZ: indicator handle creation failed."); return INIT_FAILED; }

   // persisted state
   string key = _Symbol + "_" + IntegerToString((int)InpMagic);
   g_gvHWM    = "JZHSH_HWM_"  + key;
   g_gvDayId  = "JZHSH_DAY_"  + key;
   g_gvAnchor = "JZHSH_ANC_"  + key;
   g_gvPeakEq = "JZHSH_PKE_"  + key;
   g_gvWinStk = "JZHSH_WST_"  + key;
   g_gvLossStk= "JZHSH_LST_"  + key;
   g_hwm      = (GlobalVariableCheck(g_gvHWM) ? GlobalVariableGet(g_gvHWM) : MathMax(Equity(), InpAccountStartBal));
   if(g_hwm <= 0.0) g_hwm = Equity();
   g_winStreak  = (GlobalVariableCheck(g_gvWinStk)  ? (int)GlobalVariableGet(g_gvWinStk)  : 0);
   g_lossStreak = (GlobalVariableCheck(g_gvLossStk) ? (int)GlobalVariableGet(g_gvLossStk) : 0);
   if(GlobalVariableCheck(g_gvDayId) && (long)GlobalVariableGet(g_gvDayId) == CurDayId())
   {
      g_dayId     = (long)GlobalVariableGet(g_gvDayId);
      g_dayAnchor = (GlobalVariableCheck(g_gvAnchor) ? GlobalVariableGet(g_gvAnchor) : Equity());
      g_dayPeakEq = (GlobalVariableCheck(g_gvPeakEq) ? GlobalVariableGet(g_gvPeakEq) : g_dayAnchor);
   }
   else RollDayIfNeeded();

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   AdoptExistingThesis();
   EventSetTimer(1);
   Print("JZ HELIOS SMART-HFT v1.01 armed on ", _Symbol,
         "  magic=", InpMagic,
         "  shield day ", DoubleToString(InpFirmDailyPct*InpSoftBuffer,2), "%/",
         DoubleToString(InpFirmDailyPct*InpHardBuffer,2),
         "%  dd ", DoubleToString(InpFirmMaxPct*InpSoftBuffer,2), "%/",
         DoubleToString(InpFirmMaxPct*InpHardBuffer,2), "%");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   KillPanel();
   if(g_lock != "" && GlobalVariableCheck(g_lock) && GlobalVariableGet(g_lock) == (double)ChartID())
      GlobalVariableDel(g_lock);
   int handles[] = { hEMAf_D1,hEMAs_D1,hADX_D1,hEMAf_H4,hEMAs_H4,hADX_H4,
                     hEMAf_H1,hEMAs_H1,hADX_H1,hEMAf_M15,hEMAs_M15,hADX_M15,hATR_M15,
                     hEMAf_M5,hEMAs_M5,hADX_M5,hATR_M5,hEMAf_M1,hEMAs_M1,hATR_M1 };
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
}

void OnTimer() { UpdateShield(); DrawPanel(); }

//=============================== TICK ==============================
void OnTick()
{
   UpdateShield();

   // hour rate-cap bucket
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour != g_hourStamp) { g_hourStamp = dt.hour; g_tradesThisHour = 0; }

   // sanity: thesis says open but nothing is (manual close etc.)
   if(g_thesisDir != 0 && OwnPositionCount() == 0) ResetThesis();

   // ---- closed-bar work
   datetime m5 = iTime(_Symbol, PERIOD_M5, 0);
   if(m5 != g_lastM5Bar)
   {
      g_lastM5Bar = m5;
      UpdateAsianRange();
      UpdateJudasBias();
      UpdatePeakOnClosedM5();
      ManageTrendShift();
      TryHeliosEntry();
      TryPyramidAdd();
   }
   datetime m1 = iTime(_Symbol, PERIOD_M1, 0);
   if(m1 != g_lastM1Bar)
   {
      g_lastM1Bar = m1;
      TryMicroEntry();
   }

   // ---- every-tick management (positions are managed even while halted)
   if(g_thesisDir != 0)
   {
      ManageLadder();
      RatchetStops();
   }
   DrawPanel();
}
//+------------------------------------------------------------------+
//| END - Jason Brimberry | JAZZYLYFE | Brimberry LLC - Grade A++    |
//+------------------------------------------------------------------+
