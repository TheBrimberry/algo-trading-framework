//+------------------------------------------------------------------+
//| JazzyLyfe_DarwinexGuard.mq5                                      |
//| Portfolio kill switch for a Darwinex investor MT5 account.       |
//| Watches account-level equity, applies FTMO-style DD caps, and    |
//| force-closes ALL positions when breached. Logs every decision.   |
//|                                                                  |
//| Drop on any chart of the Darwinex investor account. The EA does  |
//| not place trades itself - it only enforces account-wide risk     |
//| limits across whatever DARWINs you've invested in.               |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE - TheBrimberry 2026"
#property link      "https://github.com/TheBrimberry"
#property version   "1.0"
#property strict
#property description "Darwinex investor-account portfolio kill switch (FTMO-style 5/10 DD)"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

enum ENUM_KILL_MODE
{
   KILL_HARD_CLOSE = 0,   // Close every open position immediately
   KILL_SOFT_BLOCK = 1    // Just block new exposure (Darwinex stops mirroring)
};

// --- Inputs -------------------------------------------------------
input double         DailyLossLimit       = 5.0;     // % of day-start equity
input double         MaxAccountDD         = 10.0;    // % of all-time peak equity
input ENUM_KILL_MODE KillMode             = KILL_HARD_CLOSE;
input bool           CloseFridayAt2000    = true;    // Friday 20:00 server-time flatten
input bool           InverseMode          = false;   // Reserved (no signals to invert)
input bool           AlertOnBreach        = true;
input bool           PrintHeartbeat       = true;
input int            HeartbeatMinutes     = 30;

// --- State --------------------------------------------------------
CTrade   trade;
double   peakEquity        = 0.0;
double   dayStartEquity    = 0.0;
datetime currentDay        = 0;
datetime lastHeartbeat     = 0;
bool     killTriggered     = false;
string   killReason        = "";

//+------------------------------------------------------------------+
int OnInit()
{
   peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartEquity = peakEquity;
   currentDay     = iTime(_Symbol, PERIOD_D1, 0);
   lastHeartbeat  = TimeCurrent();
   killTriggered  = false;
   killReason     = "";

   PrintFormat("[DarwinexGuard] init  equity=%.2f  daily_cap=%.1f%%  total_cap=%.1f%%  kill_mode=%s",
               peakEquity, DailyLossLimit, MaxAccountDD,
               KillMode == KILL_HARD_CLOSE ? "HARD" : "SOFT");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("[DarwinexGuard] deinit reason=%d  killed=%s  killReason=%s",
               reason, killTriggered ? "yes" : "no", killReason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Universal $1000 breach 50% partial close check
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         double flt = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(MathAbs(flt) >= 1000.0)
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "PC1000") < 0)
            {
               double vol = PositionGetDouble(POSITION_VOLUME);
               string sym = PositionGetString(POSITION_SYMBOL);
               double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
               if(step <= 0) step = 0.01;
               double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
               double closeVol = MathFloor((vol * 0.5) / step + 1e-9) * step;
               if(closeVol >= vmin && closeVol < vol)
               {
                  if(trade.PositionClosePartial(ticket, closeVol))
                  {
                     PrintFormat("[DarwinexGuard] UNIVERSAL $1000 BREACH >> Partial closed 50%% (%.2f lots) on ticket #%I64u (P&L: $%.2f)", closeVol, ticket, flt);
                  }
               }
            }
         }
      }
   }

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > peakEquity) peakEquity = equity;

   double dailyDDpct = (dayStartEquity > 0.0)
                        ? (dayStartEquity - equity) / dayStartEquity * 100.0
                        : 0.0;
   double totalDDpct = (peakEquity > 0.0)
                        ? (peakEquity - equity) / peakEquity * 100.0
                        : 0.0;

   if(!killTriggered)
   {
      if(dailyDDpct > DailyLossLimit)
         TriggerKill(StringFormat("Daily DD %.2f%% > %.1f%% cap", dailyDDpct, DailyLossLimit));
      else if(totalDDpct > MaxAccountDD)
         TriggerKill(StringFormat("Total DD %.2f%% > %.1f%% cap", totalDDpct, MaxAccountDD));
      else if(CloseFridayAt2000 && IsFridayClose())
         TriggerKill("Friday 20:00 weekend flatten");
   }

   if(PrintHeartbeat && (TimeCurrent() - lastHeartbeat) > HeartbeatMinutes * 60)
   {
      lastHeartbeat = TimeCurrent();
      PrintFormat("[DarwinexGuard] heartbeat  equity=%.2f  peak=%.2f  dailyDD=%.2f%%  totalDD=%.2f%%  killed=%s",
                  equity, peakEquity, dailyDDpct, totalDDpct,
                  killTriggered ? "yes" : "no");
   }
}

//+------------------------------------------------------------------+
void RollDayIfNeeded()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today > currentDay)
   {
      currentDay     = today;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      // A fresh day resets the daily-DD trigger but NOT total-DD or peak.
      // If the previous day's kill was for daily-DD only, allow re-arming.
      if(killTriggered && StringFind(killReason, "Daily DD") == 0)
      {
         double totalDDpct = (peakEquity > 0.0)
                              ? (peakEquity - dayStartEquity) / peakEquity * 100.0
                              : 0.0;
         if(totalDDpct <= MaxAccountDD)
         {
            PrintFormat("[DarwinexGuard] new day - re-arming after daily-DD kill (totalDD=%.2f%%)", totalDDpct);
            killTriggered = false;
            killReason    = "";
         }
      }
   }
}

//+------------------------------------------------------------------+
bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= 20);
}

//+------------------------------------------------------------------+
void TriggerKill(const string reason)
{
   killTriggered = true;
   killReason    = reason;
   PrintFormat("[DarwinexGuard] KILL TRIGGERED -> %s", reason);
   if(AlertOnBreach) Alert("DarwinexGuard KILL: " + reason);

   if(KillMode == KILL_HARD_CLOSE)
      CloseAllPositions(reason);
   // SOFT mode: do nothing - Darwinex stops adding new exposure when the
   // account hits margin pressure. Operator can intervene manually.
}

//+------------------------------------------------------------------+
void CloseAllPositions(const string reason)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(trade.PositionClose(ticket))
      {
         closed++;
         PrintFormat("[DarwinexGuard] closed %s vol=%.2f ticket=%I64u", sym, vol, ticket);
      }
      else
      {
         PrintFormat("[DarwinexGuard] FAILED close %s ticket=%I64u err=%d  retcode=%d",
                     sym, ticket, GetLastError(), trade.ResultRetcode());
      }
   }
   PrintFormat("[DarwinexGuard] %d positions closed (reason: %s)", closed, reason);
}
//+------------------------------------------------------------------+
