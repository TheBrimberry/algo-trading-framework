//+------------------------------------------------------------------+
//|                                         JazzyLyfe_Controls.mqh    |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|         MANDATORY on every EA: Inverse Mode + Direction Filter    |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//| Grade  : A++                                                     |
//|                                                                  |
//| Inverse Mode  : flips every raw signal (BUY<->SELL). Lets a      |
//|                 losing edge be traded as its profitable inverse. |
//| Direction     : Buy Only / Sell Only / Both. Hard gate applied   |
//|                 AFTER inversion so the filter always wins.       |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"

#ifndef __JAZZYLYFE_CONTROLS_MQH__
#define __JAZZYLYFE_CONTROLS_MQH__

#include "JazzyLyfe_MTF.mqh"   // for ENUM_JL_BIAS

enum ENUM_JL_DIRECTION
  {
   JL_DIR_BOTH      = 0,   // allow longs and shorts
   JL_DIR_BUY_ONLY  = 1,   // longs only
   JL_DIR_SELL_ONLY = 2    // shorts only
  };

//+------------------------------------------------------------------+
//| CJazzyLyfeControls                                               |
//+------------------------------------------------------------------+
class CJazzyLyfeControls
  {
private:
   bool              m_inverse;
   ENUM_JL_DIRECTION m_direction;

public:
                     CJazzyLyfeControls(void) :
                     m_inverse(false), m_direction(JL_DIR_BOTH) {}

   void              Init(bool inverse_mode, ENUM_JL_DIRECTION direction)
     {
      m_inverse   = inverse_mode;
      m_direction = direction;
      PrintFormat("[JL-CTRL] inverse=%s direction=%s",
                  (m_inverse ? "ON" : "off"),
                  (m_direction == JL_DIR_BOTH ? "BOTH" :
                   m_direction == JL_DIR_BUY_ONLY ? "BUY_ONLY" : "SELL_ONLY"));
     }

   //--- take a raw signal, return the tradable signal after
   //--- (1) inversion then (2) the direction filter.
   ENUM_JL_BIAS      Apply(ENUM_JL_BIAS raw)
     {
      ENUM_JL_BIAS sig = raw;

      //--- 1) inversion
      if(m_inverse)
        {
         if(sig == JL_BIAS_BUY)  sig = JL_BIAS_SELL;
         else if(sig == JL_BIAS_SELL) sig = JL_BIAS_BUY;
        }

      //--- 2) direction filter (always wins)
      if(m_direction == JL_DIR_BUY_ONLY  && sig != JL_BIAS_BUY)  return(JL_BIAS_NONE);
      if(m_direction == JL_DIR_SELL_ONLY && sig != JL_BIAS_SELL) return(JL_BIAS_NONE);

      return(sig);
     }

   bool              IsInverse()              { return(m_inverse); }
   ENUM_JL_DIRECTION Direction()              { return(m_direction); }
  };

#endif // __JAZZYLYFE_CONTROLS_MQH__
//+------------------------------------------------------------------+
