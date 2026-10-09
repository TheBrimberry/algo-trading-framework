//+------------------------------------------------------------------+
//|             JAZZYLYFE_Mosquito_v2_Oracle.mq5                     |
//|  Author : JAZZYLYFE | Jason Lamar Brimberry | Brimberry LLC      |
//|  Magic  : 888003  |  Symbol : XRPUSD                             |
//|  Grade  : A++     |  Version: 2.0.0 — Upcomers Oracle Edition   |
//|  STATS  : 65.1% WR | PF 2.22 | 63 trades | STRONG               |
//|  STRATEGY: Mean-reversion at extreme RSI + S/R bounce            |
//|            XRPUSD overextensions snap back fast — Mosquito       |
//|            strikes at the reversal wick with tight ATR stops.    |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE | TheBrimberry | Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "2.00"
#property description "JAZZYLYFE Mosquito v2 — XRPUSD 65.1% WR PF 2.22 — Upcomers Oracle — Grade A++"

#include <Trade\Trade.mqh>
CTrade trade;
enum ENUM_DIR{DIR_BOTH=0,DIR_BUY=1,DIR_SELL=2};

input group "=== IDENTITY ==="
input long   InpMagic      =888003;input string InpComment="JLMSQ2-ORC";
input group "=== ORACLE LIMITS ==="
input double InpDailyPct   =4.0;input double InpDRSPct=5.0;input double InpTradePct=2.0;
input double InpDFlatBuf   =1.5;input double InpDRSFlatBuf=1.5;input double InpTCloseBuf=0.5;
input double InpEntBlkDay  =2.0;input double InpEntBlkDRS=2.0;input bool InpLock=true;
input group "=== SIZING ==="
input double InpBase=0.01;input double InpMax=0.01;input double InpMin=0.01;
input double InpT1=1.0;input double InpT2=2.0;input double InpT3=3.0;
input group "=== SIGNAL (RSI Mean-Reversion + S/R) ==="
input int    InpEMA_F=13;input int InpEMA_S=89;input int InpEMA_T=200;
input int    InpATR_P=14;input double InpStopMult=1.6;
input int    InpRSI_P=21;input int InpRSI_OB=75;input int InpRSI_OS=25;
input int    InpStoch_K=14;input int InpStoch_D=3;input int InpStoch_Slow=3;
input int    InpStoch_OB=80;input int InpStoch_OS=20;
input int    InpSR_Back=30;   // S/R swing lookback
input double InpSR_Tol=1.5;   // ATR tolerance for S/R proximity
input int    InpMTF_Min=2;
input group "=== TARGETS ==="
input double InpBE_R=0.7;input double InpTP1_R=1.0;input double InpTP2_R=1.618;
input double InpTP3_R=2.618;input double InpTP1Pct=40.0;input double InpTP2Pct=30.0;
input double InpTrail=2.0;input double InpTrailT=1.2;
input group "=== SESSION ==="
input bool InpLondon=true;input bool InpNY=true;input bool InpFriClose=true;input int InpFriH=19;
input group "=== FILTERS ==="
input ENUM_DIR InpDir=DIR_BOTH;input bool InpInv=false;
input int InpMinBars=6;input double InpMaxSpr=150.0;input int InpMaxPos=2;

double g_HWM=0,g_DayPeak=0;datetime g_DayStamp=0;bool g_DLock=false,g_DRSLock=false;string g_GV="";
int g_hEMA_F[4],g_hEMA_S[4],g_hEMA_T[4],g_hATR[4],g_hRSI,g_hStoch;
ENUM_TIMEFRAMES g_TF[4];
datetime g_LBar=0;int g_BSince=0;
struct SPos{ulong t;double iv,rd;bool tp1,tp2,be,pc1000;};SPos g_pos[];

double DAnchor(){return g_DayPeak;}
double DailyH(){return DAnchor()*(1-InpDailyPct/100);}
double DailyF(){return DAnchor()*(1-(InpDailyPct-InpDFlatBuf)/100);}
double DailyE(){return DAnchor()*(1-InpEntBlkDay/100);}
double DRSH(){return g_HWM*(1-InpDRSPct/100);}
double DRSF(){return g_HWM*(1-(InpDRSPct-InpDRSFlatBuf)/100);}
double DRSE(){return g_HWM*(1-(InpDRSPct-InpEntBlkDRS)/100);}
double TClose(double eq){return eq*(InpTradePct-InpTCloseBuf)/100;}

void SGV(){GlobalVariableSet(g_GV+"HWM",g_HWM);GlobalVariableSet(g_GV+"DAYPK",g_DayPeak);
  GlobalVariableSet(g_GV+"DAYTS",(double)(long)g_DayStamp);GlobalVariableSet(g_GV+"DAYLOCK",g_DLock?1.0:0.0);}
void LGV(){double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  if(GlobalVariableCheck(g_GV+"HWM"))g_HWM=MathMax(eq,GlobalVariableGet(g_GV+"HWM"));
  datetime today=(datetime)(((long)TimeGMT()/86400)*86400);
  if(GlobalVariableCheck(g_GV+"DAYTS")&&(datetime)(long)GlobalVariableGet(g_GV+"DAYTS")==today){
    g_DayStamp=today;g_DayPeak=GlobalVariableGet(g_GV+"DAYPK");g_DLock=(GlobalVariableGet(g_GV+"DAYLOCK")>0.5);}
  else{g_DayStamp=today;g_DayPeak=eq;}}
double Buf(int h,int b=0,int sh=1){double x[1];return CopyBuffer(h,b,sh,1,x)==1?x[0]:0;}

int MTFScore(){double px=SymbolInfoDouble(_Symbol,SYMBOL_BID);int sc=0;
  for(int i=0;i<4;i++){double ef=Buf(g_hEMA_F[i]),et=Buf(g_hEMA_T[i]),es=Buf(g_hEMA_S[i]);
    if(ef>0&&et>0){if(px>et&&ef>es)sc++;else if(px<et&&ef<es)sc--;}}return sc;}

// Find nearest S/R level — H4 swing highs/lows
double NearestSR(bool bull){
  double h[],l[]; ArraySetAsSeries(h,true);ArraySetAsSeries(l,true);
  if(CopyHigh(_Symbol,PERIOD_H4,1,InpSR_Back,h)<InpSR_Back)return 0;
  if(CopyLow(_Symbol,PERIOD_H4,1,InpSR_Back,l)<InpSR_Back)return 0;
  double px=SymbolInfoDouble(_Symbol,SYMBOL_BID),best=0;
  for(int i=2;i<InpSR_Back-2;i++){
    double level=bull?l[i]:h[i];
    bool swing=bull?(l[i]<l[i-1]&&l[i]<l[i+1]):(h[i]>h[i-1]&&h[i]>h[i+1]);
    if(!swing)continue;
    if(bull&&level<=px){if(best==0||level>best)best=level;}
    if(!bull&&level>=px){if(best==0||level<best)best=level;}}
  return best;}

bool SessOK(){MqlDateTime d;TimeToStruct(TimeGMT(),d);int h=d.hour;
  return(InpLondon&&h>=7&&h<12)||(InpNY&&h>=12&&h<17);}

double ComputeLots(double sd){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);double lots=InpBase;
  double dd=DAnchor()>0?100*(DAnchor()-eq)/DAnchor():0;
  if(dd>=InpT3)lots=InpMin;else if(dd>=InpT2)lots=MathMax(InpMin,InpBase*0.35);
  else if(dd>=InpT1)lots=MathMax(InpMin,InpBase*0.60);
  if(sd>0){double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    if(tv>0&&ts>0){double lpl=(sd/ts)*tv,bud=MathMin(eq/100,MathMin(MathMax(0,eq-DRSH())/3,MathMax(0,eq-DailyH())/3));
      if(lpl>0&&bud>0)lots=MathMin(lots,bud/lpl);}}
  lots=MathMin(lots,InpMax);double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  if(step<=0)step=0.01;lots=MathFloor(lots/step+1e-9)*step;return lots<InpMin?0:lots;}

bool EntOK(bool buy){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  if(g_DLock&&InpLock)return false;if(g_DRSLock)return false;
  if(eq<=DailyE()||eq<=DRSE())return false;
  int cnt=0;double last_px=0;bool all_in_profit=true;
  for(int i=PositionsTotal()-1;i>=0;i--){
    ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic){
      cnt++;
      double flt=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(flt<=0)all_in_profit=false;
      double open_px=PositionGetDouble(POSITION_PRICE_OPEN);
      if(last_px==0)last_px=open_px;
      else if(buy&&open_px>last_px)last_px=open_px;
      else if(!buy&&open_px<last_px)last_px=open_px;
    }
  }
  if(cnt>=InpMaxPos)return false;
  if(cnt>0&&!all_in_profit)return false;
  if(cnt>0&&last_px>0){
    double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
    double cur_px=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double min_dist=100*pt;
    if(buy&&cur_px<last_px+min_dist)return false;
    if(!buy&&cur_px>last_px-min_dist)return false;
  }
  double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
  if(pt>0&&(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/pt>InpMaxSpr)return false;
  MqlDateTime fd;TimeToStruct(TimeCurrent(),fd);if(InpFriClose&&fd.day_of_week==5&&fd.hour>=InpFriH)return false;
  if(g_BSince<InpMinBars)return false;
  for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(!PositionSelectByTicket(t))continue;
    if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
    if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)!=buy)return false;}
  return true;}

int RawSig(){
  int sc=MTFScore();if(MathAbs(sc)<InpMTF_Min)return 0;
  double rsi=Buf(g_hRSI),stK=Buf(g_hStoch,0),stD=Buf(g_hStoch,1);
  double atr=Buf(g_hATR[3]);if(atr<=0)return 0;
  int sig=0;
  // Oversold reversal: RSI < OS AND stoch < OS AND hook up
  if(rsi<InpRSI_OS&&stK<InpStoch_OS&&stK>stD&&sc>=InpMTF_Min)sig=1;
  // Overbought reversal: RSI > OB AND stoch > OB AND hook down
  if(rsi>InpRSI_OB&&stK>InpStoch_OB&&stK<stD&&sc<=-InpMTF_Min)sig=-1;
  if(sig==0)return 0;
  bool buy=(sig>0);
  // Must be near an S/R level (within InpSR_Tol × ATR)
  double sr=NearestSR(buy);
  if(sr>0){double dist=MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-sr);if(dist>atr*InpSR_Tol)return 0;}
  return sig;}

int PosIdx(ulong t,bool mk){int n=ArraySize(g_pos);for(int i=0;i<n;i++)if(g_pos[i].t==t)return i;
  if(!mk)return -1;ArrayResize(g_pos,n+1);g_pos[n].t=t;g_pos[n].iv=0;g_pos[n].rd=0;
  g_pos[n].tp1=false;g_pos[n].tp2=false;g_pos[n].be=false;g_pos[n].pc1000=false;return n;}
void Prune(){for(int i=ArraySize(g_pos)-1;i>=0;i--)if(!PositionSelectByTicket(g_pos[i].t)){for(int j=i;j<ArraySize(g_pos)-1;j++)g_pos[j]=g_pos[j+1];ArrayResize(g_pos,ArraySize(g_pos)-1);}}

bool CPart(ulong t,double pct){if(!PositionSelectByTicket(t))return false;
  double vol=PositionGetDouble(POSITION_VOLUME),step=SymbolInfoDouble(PositionGetString(POSITION_SYMBOL),SYMBOL_VOLUME_STEP);
  if(step<=0)step=0.01;double cv=MathFloor(vol*pct/100/step+1e-9)*step;
  double vmin=SymbolInfoDouble(PositionGetString(POSITION_SYMBOL),SYMBOL_VOLUME_MIN);
  return(cv>=vmin&&cv<vol)?trade.PositionClosePartial(t,cv):false;}

void ManagePos(){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  for(int i=PositionsTotal()-1;i>=0;i--){
    ulong t=PositionGetTicket(i);if(!PositionSelectByTicket(t))continue;
    if(PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
    string sym=PositionGetString(POSITION_SYMBOL);bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
    double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
    double vol=PositionGetDouble(POSITION_VOLUME),flt=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
    double bid=SymbolInfoDouble(sym,SYMBOL_BID),ask=SymbolInfoDouble(sym,SYMBOL_ASK),px=buy?bid:ask;
    int dig=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);double pt=SymbolInfoDouble(sym,SYMBOL_POINT);
    long lvl=SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);double md=(double)lvl*pt;
    if(flt<=-TClose(eq)){trade.PositionClose(t);continue;}
    int si=PosIdx(t,true);if(g_pos[si].iv<=0)g_pos[si].iv=vol;
    if(!g_pos[si].pc1000&&(flt>=1000.0||flt<=-1000.0)){if(CPart(t,50.0)){g_pos[si].pc1000=true;PrintFormat("UNIVERSAL $1000 BREACH >> Partial closed 50%% on ticket %d (P&L: $%.2f)",t,flt);}}
    if(sl==0.0){double atr=Buf(g_hATR[3]);if(atr<=0)continue;
      double sd=atr*InpStopMult;double nsl=NormalizeDouble(buy?entry-sd:entry+sd,dig);
      double ntp=NormalizeDouble(buy?entry+sd*InpTP3_R:entry-sd*InpTP3_R,dig);
      if(trade.PositionModify(t,nsl,ntp)){g_pos[si].rd=sd;sl=nsl;}}
    else if(g_pos[si].rd<=0)g_pos[si].rd=MathAbs(entry-sl);
    double R=g_pos[si].rd;if(R<=0)continue;double mR=buy?(px-entry)/R:(entry-px)/R;
    if(!g_pos[si].tp1&&mR>=InpTP1_R){if(CPart(t,InpTP1Pct))g_pos[si].tp1=true;}
    if(g_pos[si].tp1&&!g_pos[si].tp2&&mR>=InpTP2_R){if(CPart(t,InpTP2Pct))g_pos[si].tp2=true;}
    double dsl=0;if(!g_pos[si].be&&mR>=InpBE_R){dsl=buy?entry+3*pt:entry-3*pt;g_pos[si].be=true;}
    if(g_pos[si].be){double atrH=Buf(g_hATR[2]);int sc=MTFScore();bool opp=(buy&&sc<=-2)||(!buy&&sc>=2);
      double chase=buy?px-atrH*(opp?InpTrailT:InpTrail):px+atrH*(opp?InpTrailT:InpTrail);
      if(dsl==0)dsl=chase;else dsl=buy?MathMax(dsl,chase):MathMin(dsl,chase);}
    if(dsl!=0){dsl=NormalizeDouble(dsl,dig);bool tight=buy?(dsl>sl+pt):(sl==0||dsl<sl-pt);
      bool valid=buy?(dsl<bid-md):(dsl>ask+md);if(tight&&valid)trade.PositionModify(t,dsl,tp);}}}

void AccGuard(){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  datetime today=(datetime)(((long)TimeGMT()/86400)*86400);
  if(today!=g_DayStamp){g_DayStamp=today;g_DayPeak=eq;g_DLock=false;SGV();}
  if(eq>g_HWM){g_HWM=eq;SGV();}if(eq>g_DayPeak){g_DayPeak=eq;SGV();}
  if(eq<=DRSF()){if(!g_DRSLock){g_DRSLock=true;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}}
  else if(g_DRSLock&&eq>DRSE())g_DRSLock=false;
  if(!g_DLock&&eq<=DailyF()){g_DLock=true;SGV();for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}
  if((g_DLock&&InpLock)||g_DRSLock)for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}

void TryEntry(){
  if(!SessOK())return;int raw=RawSig();if(raw==0)return;
  int sig=InpInv?-raw:raw;if(InpDir==DIR_BUY&&sig<0)return;if(InpDir==DIR_SELL&&sig>0)return;
  bool buy=(sig>0);if(!EntOK(buy))return;
  double atr=Buf(g_hATR[3]);if(atr<=0)return;double sd=atr*InpStopMult;
  double px=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
  int dig=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
  double sl=NormalizeDouble(buy?px-sd:px+sd,dig),tp=NormalizeDouble(buy?px+sd*InpTP3_R:px-sd*InpTP3_R,dig);
  double lots=ComputeLots(sd);if(lots<=0)return;
  bool ok=buy?trade.Buy(lots,_Symbol,0,sl,tp,InpComment):trade.Sell(lots,_Symbol,0,sl,tp,InpComment);
  if(ok){g_BSince=0;ulong t=trade.ResultDeal();if(t>0){int si=PosIdx(t,true);g_pos[si].iv=lots;g_pos[si].rd=sd;}
    PrintFormat("MSQ2 >> %s %.2f lots MTF=%d RSI=%.1f",buy?"BUY":"SELL",lots,MTFScore(),Buf(g_hRSI));}
  else Print("MSQ2 >> FAILED: ",trade.ResultRetcodeDescription());}

void FriG(){if(!InpFriClose)return;MqlDateTime d;TimeToStruct(TimeCurrent(),d);
  if(d.day_of_week==5&&d.hour>=InpFriH)for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}

void Dash(){double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  Comment("╔═ JAZZYLYFE Mosquito v2 — XRPUSD — Oracle ════╗\n║ 65.1% WR | PF 2.22 | Magic "+string(InpMagic)+"\n║ Eq $"+DoubleToString(eq,2)+" | HWM $"+DoubleToString(g_HWM,2)+"\n║ Daily room $"+DoubleToString(eq-DailyH(),2)+" | DRS room $"+DoubleToString(eq-DRSH(),2)+"\n║ RSI="+DoubleToString(Buf(g_hRSI),1)+" | MTF="+string(MTFScore())+" | Lock: "+(g_DLock||g_DRSLock?"YES":"none")+"\n╚═ JAZZYLYFE | TheBrimberry | Brimberry LLC ════╝");}

int OnInit(){
  g_GV="JLUPC_"+string(AccountInfoInteger(ACCOUNT_LOGIN))+"_";
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);g_HWM=eq;g_DayPeak=eq;g_DayStamp=(datetime)(((long)TimeGMT()/86400)*86400);
  LGV();if(g_HWM<eq)g_HWM=eq;
  g_TF[0]=PERIOD_D1;g_TF[1]=PERIOD_H4;g_TF[2]=PERIOD_H1;g_TF[3]=PERIOD_M15;
  for(int i=0;i<4;i++){g_hEMA_F[i]=iMA(_Symbol,g_TF[i],InpEMA_F,0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_S[i]=iMA(_Symbol,g_TF[i],InpEMA_S,0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_T[i]=iMA(_Symbol,g_TF[i],InpEMA_T,0,MODE_EMA,PRICE_CLOSE);
    g_hATR[i]=iATR(_Symbol,g_TF[i],InpATR_P);}
  g_hRSI=iRSI(_Symbol,PERIOD_M15,InpRSI_P,PRICE_CLOSE);
  g_hStoch=iStochastic(_Symbol,PERIOD_M15,InpStoch_K,InpStoch_D,InpStoch_Slow,MODE_SMA,STO_LOWHIGH);
  trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(150);
  EventSetTimer(1);Print("Mosquito v2 Oracle >> ONLINE | ",_Symbol);return INIT_SUCCEEDED;}
void OnDeinit(const int r){EventKillTimer();GlobalVariableSet(g_GV+"HWM",g_HWM);Comment("");}
void OnTick(){datetime bar=iTime(_Symbol,PERIOD_M15,0);bool nb=(bar!=g_LBar);if(nb){g_LBar=bar;g_BSince++;}
  AccGuard();if(g_DLock||g_DRSLock){Dash();return;}ManagePos();if(nb)TryEntry();FriG();Prune();Dash();}
void OnTimer(){AccGuard();ManagePos();}
//+------------------------------------------------------------------+
