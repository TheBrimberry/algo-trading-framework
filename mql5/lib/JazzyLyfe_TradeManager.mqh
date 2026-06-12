//+------------------------------------------------------------------+
//|                                      JazzyLyfe_TradeManager.mqh   |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|  Open-trade lifecycle management for every JAZZYLYFE EA          |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//| Grade  : A++                                                     |
//|                                                                  |
//| Features (all optional via inputs):                              |
//|   * Spread filter    — skip entry if spread > max points         |
//|   * Breakeven stop   — move SL to entry+buffer once price hits   |
//|                        1R in profit                              |
//|   * Trailing stop    — trail SL behind price once in breakeven   |
//|   * Partial close    — close InpPartialPct% of position at 1R   |
//|   * Trade journal    — append every open/close to a CSV file     |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"

#ifndef __JAZZYLYFE_TRADE_MANAGER_MQH__
#define __JAZZYLYFE_TRADE_MANAGER_MQH__

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| CJazzyLyfeTradeManager                                           |
//+------------------------------------------------------------------+
class CJazzyLyfeTradeManager
  {
private:
   string   m_symbol;
   long     m_magic;
   CTrade   m_trade;

   //--- config
   double   m_max_spread_points;   // 0 = disabled
   bool     m_use_breakeven;
   double   m_be_buffer_points;    // extra points above entry for BE SL
   bool     m_use_trailing;
   double   m_trail_step_points;   // trail step size in points
   bool     m_use_partial;
   double   m_partial_pct;         // portion of position to close at 1R (0..1)
   bool     m_use_journal;
   string   m_journal_path;

   //--- per-position state (keyed by ticket) — simple parallel arrays
   //--- (MQL5 has no std::map; 64 slots covers typical fleet usage)
   ulong    m_tickets[64];
   bool     m_be_done[64];         // breakeven already applied
   bool     m_partial_done[64];    // partial close already done
   int      m_slot_count;

   int      FindSlot(ulong ticket)
     {
      for(int i = 0; i < m_slot_count; i++)
         if(m_tickets[i] == ticket) return(i);
      return(-1);
     }

   int      AddSlot(ulong ticket)
     {
      if(m_slot_count >= 64) return(-1);
      int s = m_slot_count++;
      m_tickets[s]     = ticket;
      m_be_done[s]     = false;
      m_partial_done[s]= false;
      return(s);
     }

   void     RemoveSlot(int idx)
     {
      if(idx < 0 || idx >= m_slot_count) return;
      m_slot_count--;
      m_tickets[idx]      = m_tickets[m_slot_count];
      m_be_done[idx]      = m_be_done[m_slot_count];
      m_partial_done[idx] = m_partial_done[m_slot_count];
     }

   void     Journal(string msg)
     {
      if(!m_use_journal) return;
      int h = FileOpen(m_journal_path, FILE_WRITE|FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
      if(h == INVALID_HANDLE) return;
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), m_symbol, msg);
      FileClose(h);
     }

public:
                     CJazzyLyfeTradeManager(void) :
                     m_symbol(""), m_magic(0),
                     m_max_spread_points(0), m_use_breakeven(true),
                     m_be_buffer_points(50), m_use_trailing(true),
                     m_trail_step_points(150), m_use_partial(true),
                     m_partial_pct(0.5), m_use_journal(true),
                     m_journal_path("JazzyLyfe_Journal.csv"),
                     m_slot_count(0) {}

   void Init(string symbol, long magic,
             double max_spread_points = 0,
             bool   use_breakeven     = true,
             double be_buffer_points  = 50,
             bool   use_trailing      = true,
             double trail_step_points = 150,
             bool   use_partial       = true,
             double partial_pct       = 0.5,
             bool   use_journal       = true)
     {
      m_symbol             = symbol;
      m_magic              = magic;
      m_max_spread_points  = max_spread_points;
      m_use_breakeven      = use_breakeven;
      m_be_buffer_points   = be_buffer_points;
      m_use_trailing       = use_trailing;
      m_trail_step_points  = trail_step_points;
      m_use_partial        = use_partial;
      m_partial_pct        = partial_pct;
      m_use_journal        = use_journal;
      m_slot_count         = 0;
      m_trade.SetExpertMagicNumber(magic);
      PrintFormat("[JL-TM] armed: spread<%.0f be=%s trail=%s partial=%.0f%%",
                  max_spread_points,
                  use_breakeven ? "ON" : "off",
                  use_trailing  ? "ON" : "off",
                  partial_pct * 100);
     }

   //--- call before every entry attempt; returns false if spread is too wide
   bool SpreadOK()
     {
      if(m_max_spread_points <= 0) return(true);
      double ask   = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid   = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) return(true);
      double spread_pts = (ask - bid) / point;
      if(spread_pts > m_max_spread_points)
        {
         PrintFormat("[JL-TM] spread %.1f pts > max %.1f -> entry skipped",
                     spread_pts, m_max_spread_points);
         return(false);
        }
      return(true);
     }

   //--- call after every successful trade.Buy() / trade.Sell() to register the position
   void RegisterOpen(ulong ticket, double entry, double sl, double tp,
                     string side, double lots)
     {
      AddSlot(ticket);
      Journal(StringFormat("OPEN,%s,ticket=%I64u,entry=%.5f,sl=%.5f,tp=%.5f,lots=%.2f",
                           side, ticket, entry, sl, tp, lots));
     }

   //--- call every new bar (or tick) for each open position of this EA
   void Manage()
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC)  != m_magic)  continue;

         int slot = FindSlot(ticket);
         if(slot < 0) slot = AddSlot(ticket); // position opened before restart
         if(slot < 0) continue;

         double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl      = PositionGetDouble(POSITION_SL);
         double tp      = PositionGetDouble(POSITION_TP);
         double current = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume  = PositionGetDouble(POSITION_VOLUME);
         long   ptype   = PositionGetInteger(POSITION_TYPE);
         bool   is_buy  = (ptype == POSITION_TYPE_BUY);

         double stop_dist = MathAbs(entry - sl);   // original risk in price
         if(stop_dist <= 0) continue;

         //--- 1R profit distance
         double one_r = stop_dist;

         double profit_dist = is_buy ? (current - entry) : (entry - current);

         //--- PARTIAL CLOSE at 1R
         if(m_use_partial && !m_partial_done[slot] && profit_dist >= one_r)
           {
            double close_vol = NormalizeDouble(volume * m_partial_pct,
                                              (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
            double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
            if(step > 0) close_vol = MathFloor(close_vol / step) * step;
            close_vol = MathMax(close_vol, SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN));
            if(close_vol < volume)
              {
               if(m_trade.PositionClosePartial(ticket, close_vol))
                 {
                  m_partial_done[slot] = true;
                  Journal(StringFormat("PARTIAL,ticket=%I64u,closed=%.2f,price=%.5f",
                                      ticket, close_vol, current));
                  PrintFormat("[JL-TM] partial close %.2f lots at 1R on ticket %I64u",
                              close_vol, ticket);
                 }
              }
           }

         //--- BREAKEVEN: move SL to entry + buffer once price reaches 1R
         if(m_use_breakeven && !m_be_done[slot] && profit_dist >= one_r)
           {
            double new_sl = is_buy
                            ? entry + m_be_buffer_points * point
                            : entry - m_be_buffer_points * point;
            bool already_be = is_buy ? (sl >= new_sl) : (sl <= new_sl);
            if(!already_be)
              {
               if(m_trade.PositionModify(ticket, new_sl, tp))
                 {
                  m_be_done[slot] = true;
                  Journal(StringFormat("BREAKEVEN,ticket=%I64u,new_sl=%.5f", ticket, new_sl));
                  PrintFormat("[JL-TM] breakeven set on ticket %I64u -> SL %.5f", ticket, new_sl);
                 }
              }
            else
               m_be_done[slot] = true;
           }

         //--- TRAILING STOP: trail once in breakeven
         if(m_use_trailing && m_be_done[slot])
           {
            double trail_sl = is_buy
                              ? current - m_trail_step_points * point
                              : current + m_trail_step_points * point;
            bool should_move = is_buy ? (trail_sl > sl) : (trail_sl < sl);
            if(should_move)
              {
               if(m_trade.PositionModify(ticket, trail_sl, tp))
                  PrintFormat("[JL-TM] trail SL moved to %.5f on ticket %I64u", trail_sl, ticket);
              }
           }
        }

      //--- purge closed positions from slot tracking
      for(int s = m_slot_count - 1; s >= 0; s--)
        {
         if(!PositionSelectByTicket(m_tickets[s]))
            RemoveSlot(s);
        }
     }

   //--- call when a position is confirmed closed (e.g. from OnTradeTransaction)
   void RegisterClose(ulong ticket, double close_price, double profit)
     {
      Journal(StringFormat("CLOSE,ticket=%I64u,price=%.5f,profit=%.2f",
                           ticket, close_price, profit));
      int slot = FindSlot(ticket);
      if(slot >= 0) RemoveSlot(slot);
     }
  };

#endif // __JAZZYLYFE_TRADE_MANAGER_MQH__
//+------------------------------------------------------------------+
