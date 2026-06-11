//+------------------------------------------------------------------+
//|                                           JazzyLyfe_Sizing.mqh    |
//|                            JAZZYLYFE / Brimberry LLC  (c) 2026    |
//|        Kelly-Criterion position sizing, broker-constraint aware   |
//+------------------------------------------------------------------+
//| Author : JAZZYLYFE                                               |
//| Grade  : A++                                                     |
//|                                                                  |
//| Lot = risk_$ / (stop_distance_in_money_per_lot). Risk_$ is set   |
//| by a fractional-Kelly estimate clamped to a hard max risk %, so  |
//| a hot win-rate never lets the EA oversize past prop-firm limits. |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE / Brimberry LLC"
#property link      "https://github.com/TheBrimberry"

#ifndef __JAZZYLYFE_SIZING_MQH__
#define __JAZZYLYFE_SIZING_MQH__

//+------------------------------------------------------------------+
//| CJazzyLyfeSizing                                                 |
//+------------------------------------------------------------------+
class CJazzyLyfeSizing
  {
private:
   string            m_symbol;
   double            m_max_risk_pct;   // hard cap per trade (e.g. 1.0%)
   double            m_kelly_fraction; // fraction of full Kelly (e.g. 0.25)

   double            NormalizeLot(double lot)
     {
      double minlot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxlot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0) step = 0.01;
      lot = MathFloor(lot / step) * step;
      lot = MathMax(minlot, MathMin(maxlot, lot));
      return(lot);
     }

public:
                     CJazzyLyfeSizing(void) :
                     m_symbol(""), m_max_risk_pct(1.0), m_kelly_fraction(0.25) {}

   void              Init(string symbol, double max_risk_pct = 1.0,
                          double kelly_fraction = 0.25)
     {
      m_symbol         = symbol;
      m_max_risk_pct   = max_risk_pct;
      m_kelly_fraction = kelly_fraction;
     }

   //--- Fractional Kelly: f* = W - (1-W)/R, then scaled & clamped.
   //--- W = win rate (0..1), R = avg win / avg loss (payoff ratio).
   double            KellyRiskPct(double win_rate, double payoff_ratio)
     {
      if(payoff_ratio <= 0) return(0.0);
      double k = win_rate - (1.0 - win_rate) / payoff_ratio;
      if(k <= 0) return(0.0);                    // no edge -> no trade
      double risk = k * m_kelly_fraction * 100.0; // to percent
      return(MathMin(risk, m_max_risk_pct));      // never exceed hard cap
     }

   //--- Convert a risk% + stop distance (in POINTS, not pips) into a normalized lot.
   //--- Example: XAUUSD 150-pip stop = 1500 points (point=0.01).
   //--- Example: EURUSD 20-pip stop  = 200 points  (point=0.00001).
   double            LotForRisk(double risk_pct, double stop_points)
     {
      if(stop_points <= 0) return(0.0);

      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_cash = equity * risk_pct / 100.0;

      double tick_val  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(tick_val <= 0 || tick_size <= 0 || point <= 0) return(0.0);

      // money lost per 1.00 lot over the stop distance
      double value_per_point = tick_val * (point / tick_size);
      double loss_per_lot    = stop_points * value_per_point;
      if(loss_per_lot <= 0) return(0.0);

      double lot = risk_cash / loss_per_lot;
      return(NormalizeLot(lot));
     }

   //--- one-shot: edge stats + stop -> ready-to-trade lot
   double            Lot(double win_rate, double payoff_ratio, double stop_points)
     {
      double risk = KellyRiskPct(win_rate, payoff_ratio);
      if(risk <= 0) return(0.0);
      return(LotForRisk(risk, stop_points));
     }
  };

#endif // __JAZZYLYFE_SIZING_MQH__
//+------------------------------------------------------------------+
