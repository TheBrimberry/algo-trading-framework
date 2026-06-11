//+------------------------------------------------------------------+
//|                                              JazzyLyfe_ICT.mqh    |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|     ICT / Smart-Money Concepts: OB, FVG, BOS/CHoCH, Liquidity     |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//| Grade  : A++                                                     |
//|                                                                  |
//| Lightweight, dependency-free structure reads used as confluence  |
//| on the entry timeframe. Each detector returns a simple struct so  |
//| an EA can require N confluences before taking the MTF signal.    |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"

#ifndef __JAZZYLYFE_ICT_MQH__
#define __JAZZYLYFE_ICT_MQH__

struct JLZone
  {
   bool    valid;
   double  high;
   double  low;
   int     dir;     // +1 bullish, -1 bearish
  };

struct JLStructure
  {
   bool    bos;     // break of structure (continuation)
   bool    choch;   // change of character (reversal)
   int     dir;     // +1 up, -1 down
  };

//+------------------------------------------------------------------+
//| CJazzyLyfeICT                                                    |
//+------------------------------------------------------------------+
class CJazzyLyfeICT
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_lookback;

   double            H(int i) { return(iHigh (m_symbol, m_tf, i)); }
   double            L(int i) { return(iLow  (m_symbol, m_tf, i)); }
   double            O(int i) { return(iOpen (m_symbol, m_tf, i)); }
   double            C(int i) { return(iClose(m_symbol, m_tf, i)); }

   //--- swing high/low using a +/-strength fractal
   bool              IsSwingHigh(int i, int strength)
     {
      double h = H(i);
      for(int k = 1; k <= strength; k++)
         if(H(i + k) >= h || H(i - k) >= h) return(false);
      return(true);
     }
   bool              IsSwingLow(int i, int strength)
     {
      double l = L(i);
      for(int k = 1; k <= strength; k++)
         if(L(i + k) <= l || L(i - k) <= l) return(false);
      return(true);
     }

public:
                     CJazzyLyfeICT(void) :
                     m_symbol(""), m_tf(PERIOD_M15), m_lookback(60) {}

   void              Init(string symbol, ENUM_TIMEFRAMES tf = PERIOD_M15,
                          int lookback = 60)
     {
      m_symbol   = symbol;
      m_tf       = tf;
      m_lookback = lookback;
     }

   //--- FAIR VALUE GAP: 3-candle imbalance. Bullish FVG = low[i-1] > high[i+1].
   //--- Only returns the zone if price has NOT already filled it (current price
   //--- is still approaching / at the edge, not trading through it).
   JLZone            FVG()
     {
      JLZone z; z.valid = false; z.dir = 0; z.high = 0; z.low = 0;
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      for(int i = 2; i < m_lookback; i++)
        {
         // bullish FVG: gap between candle i-1 low and candle i+1 high
         if(L(i - 1) > H(i + 1))
           {
            double zHigh = L(i - 1);
            double zLow  = H(i + 1);
            // skip if price has already closed inside or below the zone (filled)
            if(bid <= zHigh) // price is still above or at zone -> valid
              { z.valid = true; z.dir = 1; z.high = zHigh; z.low = zLow; return(z); }
           }
         // bearish FVG: gap between candle i+1 low and candle i-1 high
         if(H(i - 1) < L(i + 1))
           {
            double zHigh = L(i + 1);
            double zLow  = H(i - 1);
            // skip if price has already closed inside or above the zone (filled)
            if(ask >= zLow) // price is still below or at zone -> valid
              { z.valid = true; z.dir = -1; z.high = zHigh; z.low = zLow; return(z); }
           }
        }
      return(z);
     }

   //--- ORDER BLOCK: last opposite candle before an impulsive move.
   //--- Bullish OB = last down candle before a strong up displacement.
   JLZone            OrderBlock()
     {
      JLZone z; z.valid = false; z.dir = 0;
      for(int i = 1; i < m_lookback - 1; i++)
        {
         double body_now  = MathAbs(C(i)   - O(i));
         double body_prev = MathAbs(C(i + 1) - O(i + 1));
         bool   impulse   = body_now > body_prev * 1.5;
         if(!impulse) continue;

         // bullish displacement up, prior candle bearish -> bullish OB
         if(C(i) > O(i) && C(i + 1) < O(i + 1))
           { z.valid = true; z.dir = 1; z.high = H(i + 1); z.low = L(i + 1); return(z); }
         // bearish displacement down, prior candle bullish -> bearish OB
         if(C(i) < O(i) && C(i + 1) > O(i + 1))
           { z.valid = true; z.dir = -1; z.high = H(i + 1); z.low = L(i + 1); return(z); }
        }
      return(z);
     }

   //--- BOS / CHoCH from the two most recent confirmed swings.
   JLStructure       Structure(int strength = 2)
     {
      JLStructure s; s.bos = false; s.choch = false; s.dir = 0;

      double lastHigh = 0, prevHigh = 0, lastLow = 0, prevLow = 0;
      int hits_h = 0, hits_l = 0;

      for(int i = strength; i < m_lookback - strength; i++)
        {
         if(hits_h < 2 && IsSwingHigh(i, strength))
           { if(hits_h == 0) lastHigh = H(i); else prevHigh = H(i); hits_h++; }
         if(hits_l < 2 && IsSwingLow(i, strength))
           { if(hits_l == 0) lastLow = L(i); else prevLow = L(i); hits_l++; }
         if(hits_h >= 2 && hits_l >= 2) break;
        }

      double close = C(0);
      //--- bullish BOS: price closes above most recent swing high
      if(hits_h >= 1 && close > lastHigh) { s.bos = true; s.dir = 1; }
      //--- bearish BOS: price closes below most recent swing low
      if(hits_l >= 1 && close < lastLow)  { s.bos = true; s.dir = -1; }

      //--- CHoCH: higher-high sequence broken to the downside, or vice versa
      if(hits_h >= 2 && hits_l >= 2)
        {
         bool wasUptrend   = (lastHigh > prevHigh && lastLow > prevLow);
         bool wasDowntrend = (lastHigh < prevHigh && lastLow < prevLow);
         if(wasUptrend   && close < lastLow)  { s.choch = true; s.dir = -1; }
         if(wasDowntrend && close > lastHigh) { s.choch = true; s.dir =  1; }
        }
      return(s);
     }

   //--- LIQUIDITY SWEEP: wick pierces a recent swing then closes back inside.
   //--- Uses bar 1 (last CLOSED candle) for confirmed sweep detection.
   //--- dir +1 = buy-side liquidity grabbed below (bullish), -1 = above.
   int               LiquiditySweep(int strength = 2)
     {
      // recent swing low swept (stop-hunt below) -> bullish
      // bar 1 = last closed candle (confirmed)
      for(int i = 1; i < m_lookback - strength; i++)
        {
         if(IsSwingLow(i, strength))
           {
            if(L(1) < L(i) && C(1) > L(i)) return(1);
            break;
           }
        }
      // recent swing high swept (stop-hunt above) -> bearish
      for(int j = 1; j < m_lookback - strength; j++)
        {
         if(IsSwingHigh(j, strength))
           {
            if(H(1) > H(j) && C(1) < H(j)) return(-1);
            break;
           }
        }
      return(0);
     }

   //--- Confluence score in the direction of `bias` (+1 buy / -1 sell).
   //--- Returns 0..4 -> how many SMC reads agree with the bias.
   int               Confluence(int bias)
     {
      int score = 0;
      JLZone fvg = FVG();          if(fvg.valid && fvg.dir == bias) score++;
      JLZone ob  = OrderBlock();   if(ob.valid  && ob.dir  == bias) score++;
      JLStructure st = Structure();
      if((st.bos || st.choch) && st.dir == bias) score++;
      if(LiquiditySweep() == bias) score++;
      return(score);
     }
  };

#endif // __JAZZYLYFE_ICT_MQH__
//+------------------------------------------------------------------+
