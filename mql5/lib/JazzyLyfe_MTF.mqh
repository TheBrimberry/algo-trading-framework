//+------------------------------------------------------------------+
//|                                              JazzyLyfe_MTF.mqh    |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|        Multi-Timeframe trend cascade  D1 -> H4 -> H1 -> M15       |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//| Grade  : A++                                                     |
//|                                                                  |
//| Every JAZZYLYFE EA decides direction from a top-down cascade.    |
//| Higher timeframes set the regime, lower timeframes time entry.   |
//| Bias on each TF = EMA-fast vs EMA-slow + close position, scored  |
//| -1 (down) / 0 (flat) / +1 (up). The cascade only returns a BUY   |
//| or SELL when the required alignment depth agrees; otherwise NONE.|
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"

#ifndef __JAZZYLYFE_MTF_MQH__
#define __JAZZYLYFE_MTF_MQH__

enum ENUM_JL_BIAS
  {
   JL_BIAS_SELL = -1,
   JL_BIAS_NONE =  0,
   JL_BIAS_BUY  =  1
  };

//+------------------------------------------------------------------+
//| CJazzyLyfeMTF                                                    |
//+------------------------------------------------------------------+
class CJazzyLyfeMTF
  {
private:
   string            m_symbol;
   int               m_ema_fast;
   int               m_ema_slow;
   ENUM_TIMEFRAMES   m_tf[4];      // D1, H4, H1, M15
   int               m_count;      // number of TFs in cascade
   int               m_min_align;  // how many of the top TFs must agree

   //--- handle cache so we create indicators once
   int               m_hFast[4];
   int               m_hSlow[4];

   int               BiasOnTF(int idx)
     {
      if(m_hFast[idx] == INVALID_HANDLE || m_hSlow[idx] == INVALID_HANDLE)
         return(0);

      double fast[1], slow[1];  // only current bar value needed
      if(CopyBuffer(m_hFast[idx], 0, 0, 1, fast) < 1) return(0);
      if(CopyBuffer(m_hSlow[idx], 0, 0, 1, slow) < 1) return(0);

      double close = iClose(m_symbol, m_tf[idx], 0);
      if(close == 0) return(0);

      int score = 0;
      if(fast[0] > slow[0]) score++;        // fast above slow
      if(fast[0] < slow[0]) score--;
      if(close   > fast[0]) score++;        // price above fast
      if(close   < fast[0]) score--;

      if(score >=  1) return( 1);
      if(score <= -1) return(-1);
      return(0);
     }

public:
                     CJazzyLyfeMTF(void) :
                     m_symbol(""), m_ema_fast(21), m_ema_slow(50),
                     m_count(4), m_min_align(3)
     {
      for(int i = 0; i < 4; i++) { m_hFast[i] = INVALID_HANDLE; m_hSlow[i] = INVALID_HANDLE; }
     }

                    ~CJazzyLyfeMTF(void)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_hFast[i] != INVALID_HANDLE) IndicatorRelease(m_hFast[i]);
         if(m_hSlow[i] != INVALID_HANDLE) IndicatorRelease(m_hSlow[i]);
        }
     }

   //--- call once in OnInit. min_align = how many of the TOP timeframes
   //--- must agree before a directional bias is returned (default 3/4).
   bool              Init(string symbol, int ema_fast = 21, int ema_slow = 50,
                          int min_align = 3)
     {
      m_symbol    = symbol;
      m_ema_fast  = ema_fast;
      m_ema_slow  = ema_slow;
      m_min_align = min_align;

      m_tf[0] = PERIOD_D1;
      m_tf[1] = PERIOD_H4;
      m_tf[2] = PERIOD_H1;
      m_tf[3] = PERIOD_M15;
      m_count = 4;

      for(int i = 0; i < m_count; i++)
        {
         m_hFast[i] = iMA(m_symbol, m_tf[i], m_ema_fast, 0, MODE_EMA, PRICE_CLOSE);
         m_hSlow[i] = iMA(m_symbol, m_tf[i], m_ema_slow, 0, MODE_EMA, PRICE_CLOSE);
         if(m_hFast[i] == INVALID_HANDLE || m_hSlow[i] == INVALID_HANDLE)
           {
            Print("[JL-MTF] failed to create MA handle on TF index ", i);
            return(false);
           }
        }
      return(true);
     }

   //--- top-down verdict. Returns BUY/SELL only when the top m_min_align
   //--- timeframes all share the same non-zero bias AND M15 confirms.
   ENUM_JL_BIAS      Bias()
     {
      int b[4];
      for(int i = 0; i < m_count; i++) b[i] = BiasOnTF(i);

      //--- count agreement among the top (higher) timeframes
      int up = 0, dn = 0;
      for(int i = 0; i < m_min_align && i < m_count; i++)
        {
         if(b[i] > 0) up++;
         if(b[i] < 0) dn++;
        }

      //--- M15 (entry TF) must confirm the higher-TF regime
      int entry = b[m_count - 1];

      if(up >= m_min_align && entry > 0) return(JL_BIAS_BUY);
      if(dn >= m_min_align && entry < 0) return(JL_BIAS_SELL);
      return(JL_BIAS_NONE);
     }

   //--- raw per-TF read for dashboards / logging
   void              Snapshot(int &outD1, int &outH4, int &outH1, int &outM15)
     {
      outD1  = BiasOnTF(0);
      outH4  = BiasOnTF(1);
      outH1  = BiasOnTF(2);
      outM15 = BiasOnTF(3);
     }

   string            Describe()
     {
      int d1, h4, h1, m15;
      Snapshot(d1, h4, h1, m15);
      return(StringFormat("D1=%d H4=%d H1=%d M15=%d", d1, h4, h1, m15));
     }
  };

#endif // __JAZZYLYFE_MTF_MQH__
//+------------------------------------------------------------------+
