//+------------------------------------------------------------------+
//|                                        JazzyLyfe_FTMO_Guard.mqh   |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|         FTMO / FXIFY / prop-firm compliance & drawdown guard     |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//| Grade  : A++                                                     |
//|                                                                  |
//| Soft limits  -> stop opening NEW trades, raise warning           |
//|   Daily soft : 4.5%   |  Total soft : 9.0%                       |
//| Hard limits  -> flatten everything, halt the EA for the session  |
//|   Daily hard : 5.0%   |  Total hard : 10.0%                      |
//|                                                                  |
//| Tracks the broker server day-roll so the daily anchor resets at  |
//| the prop firm's daily reset. Anchors on the HIGHER of            |
//| balance/equity at day open (FTMO uses balance-or-equity start).  |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"

#ifndef __JAZZYLYFE_FTMO_GUARD_MQH__
#define __JAZZYLYFE_FTMO_GUARD_MQH__

#include <Trade/Trade.mqh>

//--- Guard verdicts returned to the EA each tick
enum ENUM_JL_GUARD_STATE
  {
   JL_GUARD_OK        = 0,   // trading permitted normally
   JL_GUARD_SOFT_DAY  = 1,   // daily soft hit  -> no new trades today
   JL_GUARD_SOFT_MAX  = 2,   // total soft hit  -> no new trades
   JL_GUARD_HARD_DAY  = 3,   // daily hard hit  -> flattened + halted
   JL_GUARD_HARD_MAX  = 4    // total hard hit  -> flattened + halted
  };

//+------------------------------------------------------------------+
//| CJazzyLyfeFTMOGuard                                              |
//+------------------------------------------------------------------+
class CJazzyLyfeFTMOGuard
  {
private:
   //--- configuration (percent of starting balance)
   double            m_daily_soft_pct;
   double            m_daily_hard_pct;
   double            m_total_soft_pct;
   double            m_total_hard_pct;

   //--- anchors
   double            m_account_start_balance; // balance the challenge began with
   double            m_day_anchor_equity;     // equity/balance at day open
   datetime          m_current_day;           // server day currently anchored
   bool              m_halted;                // hard breach latch (session)
   ENUM_JL_GUARD_STATE m_halt_reason;         // which hard limit triggered the halt
   long              m_magic;                 // owning EA magic (for flatten)
   string            m_tag;                   // log prefix

   datetime          ServerDayStart()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return(StructToTime(dt));
     }

   void              RollDayIfNeeded()
     {
      datetime today = ServerDayStart();
      if(today != m_current_day)
        {
         m_current_day      = today;
         // FTMO daily reference = higher of balance or equity at reset
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
         m_day_anchor_equity = MathMax(bal, eq);
         PrintFormat("%s daily anchor reset -> %.2f", m_tag, m_day_anchor_equity);
        }
     }

   void              FlattenAll()
     {
      CTrade trade;
      trade.SetExpertMagicNumber(m_magic);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(m_magic != 0 && PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         trade.PositionClose(ticket);
        }
     }

public:
                     CJazzyLyfeFTMOGuard(void) :
                     m_daily_soft_pct(4.5), m_daily_hard_pct(5.0),
                     m_total_soft_pct(9.0), m_total_hard_pct(10.0),
                     m_account_start_balance(0), m_day_anchor_equity(0),
                     m_current_day(0), m_halted(false),
                     m_halt_reason(JL_GUARD_OK), m_magic(0),
                     m_tag("[JL-FTMO]") {}

   //--- call once in OnInit
   void              Init(long magic,
                          double start_balance = 0.0,
                          double daily_soft = 4.5, double daily_hard = 5.0,
                          double total_soft = 9.0, double total_hard = 10.0)
     {
      m_magic = magic;
      m_account_start_balance = (start_balance > 0.0)
                                ? start_balance
                                : AccountInfoDouble(ACCOUNT_BALANCE);
      m_daily_soft_pct = daily_soft;  m_daily_hard_pct = daily_hard;
      m_total_soft_pct = total_soft;  m_total_hard_pct = total_hard;
      m_halted = false;
      m_halt_reason = JL_GUARD_OK;
      m_current_day = 0;
      RollDayIfNeeded();
      PrintFormat("%s armed. start=%.2f daily %.1f/%.1f%% total %.1f/%.1f%%",
                  m_tag, m_account_start_balance,
                  m_daily_soft_pct, m_daily_hard_pct,
                  m_total_soft_pct, m_total_hard_pct);
     }

   //--- current drawdowns in percent (positive = loss)
   double            DailyDDPercent()
     {
      if(m_day_anchor_equity <= 0) return(0.0);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return((m_day_anchor_equity - eq) / m_day_anchor_equity * 100.0);
     }

   double            TotalDDPercent()
     {
      if(m_account_start_balance <= 0) return(0.0);
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return((m_account_start_balance - eq) / m_account_start_balance * 100.0);
     }

   //--- call every OnTick BEFORE evaluating signals
   ENUM_JL_GUARD_STATE Check()
     {
      RollDayIfNeeded();

      if(m_halted)
         return(m_halt_reason); // return the exact reason that triggered the halt

      double dd_day = DailyDDPercent();
      double dd_max = TotalDDPercent();

      //--- HARD breaches: flatten + latch (total checked first - higher priority)
      if(dd_max >= m_total_hard_pct)
        {
         FlattenAll(); m_halted = true; m_halt_reason = JL_GUARD_HARD_MAX;
         PrintFormat("%s HARD MAX %.2f%% >= %.2f%% -> FLATTEN & HALT",
                     m_tag, dd_max, m_total_hard_pct);
         return(JL_GUARD_HARD_MAX);
        }
      if(dd_day >= m_daily_hard_pct)
        {
         FlattenAll(); m_halted = true; m_halt_reason = JL_GUARD_HARD_DAY;
         PrintFormat("%s HARD DAY %.2f%% >= %.2f%% -> FLATTEN & HALT",
                     m_tag, dd_day, m_daily_hard_pct);
         return(JL_GUARD_HARD_DAY);
        }

      //--- SOFT breaches: block new entries, keep managing open trades
      if(dd_max >= m_total_soft_pct)
        {
         PrintFormat("%s SOFT MAX %.2f%% -> no new trades", m_tag, dd_max);
         return(JL_GUARD_SOFT_MAX);
        }
      if(dd_day >= m_daily_soft_pct)
        {
         PrintFormat("%s SOFT DAY %.2f%% -> no new trades", m_tag, dd_day);
         return(JL_GUARD_SOFT_DAY);
        }

      return(JL_GUARD_OK);
     }

   //--- convenience gates for the EA
   bool              CanOpenNew()      { ENUM_JL_GUARD_STATE s = Check(); return(s == JL_GUARD_OK); }
   bool              IsHalted()        { return(m_halted); }
   void              ResetSession()    { m_halted = false; m_halt_reason = JL_GUARD_OK; }

   //--- dashboard helpers
   double            DailyRoomPct()    { return(m_daily_hard_pct - DailyDDPercent()); }
   double            TotalRoomPct()    { return(m_total_hard_pct - TotalDDPercent()); }
  };

#endif // __JAZZYLYFE_FTMO_GUARD_MQH__
//+------------------------------------------------------------------+
