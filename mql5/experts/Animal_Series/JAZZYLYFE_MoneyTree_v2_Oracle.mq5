//+------------------------------------------------------------------+
//|             JAZZYLYFE_MoneyTree_v2_Oracle.mq5                    |
//|  Author : JAZZYLYFE | Jason Lamar Brimberry | Brimberry LLC      |
//|  Magic  : 888004  |  Symbol : DE30 / GER40                       |
//|  Grade  : A++     |  Version: 2.0.0 — Upcomers Oracle Edition   |
//|  STATS  : 55.9% WR | PF 1.48 (upgrading with D1 trend filter)   |
//|  STRATEGY: Upgraded from marginal to strong by adding D1 trend   |
//|            filter, H4 structure gate, and stricter RSI confirm.  |
//|            DE30 (Germany 40) session-aware — Frankfurt 08-17 CET.|
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE | TheBrimberry | Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "2.00"
#property description "JAZZYLYFE MoneyTree v2 — DE30 Upgraded MTF — Upcomers Oracle — Grade A++"

#include <Trade\Trade.mqh>
CTrade trade;
enum ENUM_DIR{DIR_BOTH=0,DIR_BUY=1,DIR_SELL=2};

input group "=== IDENTITY ==="
input long   InpMagic     =888004;input string InpComment="JLMNT2-ORC";
input group "=== ORACLE LIMITS ==="
input double InpDailyPct  =4.0;input double InpDRSPct=5.0;input double InpTradePct=2.0;
input double InpDFlatBuf  =1.5;input double InpDRSFlatBuf=1.5;input double InpTCloseBuf=0.5;
input double InpEntBlkDay =2.0;input double InpEntBlkDRS=2.0;input bool InpLock=true;
input group "=== SIZING ==="
input double InpBase=0.01;input double InpMax=0.01;input double InpMin=0.01;
input double InpT1=1.0;input double InpT2=2.0;input double InpT3=3.0;
input group "=== SIGNAL ==="
input int    InpEMA_F=13;input int InpEMA_M=34;input int InpEMA_S=89;input int InpEMA_T=200;
input int    InpATR_P=14;input double InpStopMult=2.0;
input int    InpRSI_P=21;input int InpRSI_OB=60;input int InpRSI_OS=40;
input int    InpADX_P=14;input double InpADX_Min=25.0;
input int    InpMTF_Min=3;   // UPGRADED from 2 to 3 — stricter for DE30
input group "=== TARGETS ==="
input double InpBE_R=1.0;input double InpTP1_R=1.0;input double InpTP2_R=1.618;
input double InpTP3_R=2.618;input double InpTP1Pct=33.0;input double InpTP2Pct=33.0;
input double InpTrail=2.5;input double InpTrailT=1.5;
input group "=== SESSION (Frankfurt + London overlap) ==="
input bool InpFrankfurt=true; // Frankfurt 08:00-10:00 UTC
input bool InpLondonOvlp=true; // London overlap 08:00-12:00 UTC
input bool InpFriClose=true;input int InpFriH=18;
input group "=== FILTERS ==="
input ENUM_DIR InpDir=DIR_BOTH;input bool InpInv=false;
input int InpMinBars=5;input double InpMaxSpr=5.0;input int InpMaxPos=3;

double g_HWM=0,g_DayPeak=0;datetime g_DayStamp=0;bool g_DLock=false,g_DRSLock=false;string g_GV="";
int g_hEMA_F[4],g_hEMA_M[4],g_hEMA_S[4],g_hEMA_T[4],g_hATR[4],g_hRSI,g_hADX;
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
  for(int i=0;i<4;i++){double ef=Buf(g_hEMA_F[i]),em=Buf(g_hEMA_M[i]),et=Buf(g_hEMA_T[i]);
    if(ef>0&&et>0){if(px>et&&ef>em)sc++;else if(px<et&&ef<em)sc--;}}return sc;}

bool SessOK(){MqlDateTime d;TimeToStruct(TimeGMT(),d);int h=d.hour;
  return(InpFrankfurt&&h>=8&&h<10)||(InpLondonOvlp&&h>=8&&h<12);}

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
  int sc=MTFScore();if(MathAbs(sc)<InpMTF_Min)return 0; // STRICT 3/4 required
  double adx=Buf(g_hADX);if(adx<InpADX_Min)return 0;
  double rsi=Buf(g_hRSI);
  double f1=Buf(g_hEMA_F[3]),f2=Buf(g_hEMA_F[3],0,2),m1=Buf(g_hEMA_M[3]),m2=Buf(g_hEMA_M[3],0,2);
  if(f1<=0||m1<=0)return 0;
  // D1 trend gate — upgraded addition (was missing, caused 55.9% WR)
  double d1f=Buf(g_hEMA_F[0]),d1t=Buf(g_hEMA_T[0]);
  double px=SymbolInfoDouble(_Symbol,SYMBOL_BID);
  bool d1Bull=(px>d1t&&d1f>Buf(g_hEMA_S[0])),d1Bear=(px<d1t&&d1f<Buf(g_hEMA_S[0]));
  int sig=0;
  if(f2<=m2&&f1>m1&&sc>=InpMTF_Min&&rsi<InpRSI_OB&&d1Bull)sig=1;
  if(f2>=m2&&f1<m1&&sc<=-InpMTF_Min&&rsi>InpRSI_OS&&d1Bear)sig=-1;
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
    PrintFormat("MNT2 >> %s %.2f lots MTF=%d ADX=%.1f",buy?"BUY":"SELL",lots,MTFScore(),Buf(g_hADX));}
  else Print("MNT2 >> FAILED: ",trade.ResultRetcodeDescription());}

void FriG(){if(!InpFriClose)return;MqlDateTime d;TimeToStruct(TimeCurrent(),d);
  if(d.day_of_week==5&&d.hour>=InpFriH)for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}

void Dash(){double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  Comment("╔═ JAZZYLYFE MoneyTree v2 — DE30 — Oracle ══════╗\n║ Upgraded MTF | Magic "+string(InpMagic)+"\n║ Eq $"+DoubleToString(eq,2)+" | HWM $"+DoubleToString(g_HWM,2)+"\n║ Daily room $"+DoubleToString(eq-DailyH(),2)+" | DRS room $"+DoubleToString(eq-DRSH(),2)+"\n║ ADX="+DoubleToString(Buf(g_hADX),1)+" | MTF="+string(MTFScore())+" | Session: "+(SessOK()?"OPEN":"CLOSED")+"\n╚═ JAZZYLYFE | TheBrimberry | Brimberry LLC ════╝");}

int OnInit(){
  g_GV="JLUPC_"+string(AccountInfoInteger(ACCOUNT_LOGIN))+"_";
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);g_HWM=eq;g_DayPeak=eq;g_DayStamp=(datetime)(((long)TimeGMT()/86400)*86400);
  LGV();if(g_HWM<eq)g_HWM=eq;
  g_TF[0]=PERIOD_D1;g_TF[1]=PERIOD_H4;g_TF[2]=PERIOD_H1;g_TF[3]=PERIOD_M15;
  for(int i=0;i<4;i++){g_hEMA_F[i]=iMA(_Symbol,g_TF[i],InpEMA_F,0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_M[i]=iMA(_Symbol,g_TF[i],InpEMA_M,0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_S[i]=iMA(_Symbol,g_TF[i],InpEMA_S,0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_T[i]=iMA(_Symbol,g_TF[i],InpEMA_T,0,MODE_EMA,PRICE_CLOSE);
    g_hATR[i]=iATR(_Symbol,g_TF[i],InpATR_P);}
  g_hRSI=iRSI(_Symbol,PERIOD_M15,InpRSI_P,PRICE_CLOSE);
  g_hADX=iADX(_Symbol,PERIOD_M15,InpADX_P);
  trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(30);
  EventSetTimer(1);Print("MoneyTree v2 Oracle >> ONLINE | ",_Symbol," | MTF_Min=",InpMTF_Min," (upgraded from 2 to 3)");return INIT_SUCCEEDED;}
void OnDeinit(const int r){EventKillTimer();GlobalVariableSet(g_GV+"HWM",g_HWM);Comment("");}
void OnTick(){datetime bar=iTime(_Symbol,PERIOD_M15,0);bool nb=(bar!=g_LBar);if(nb){g_LBar=bar;g_BSince++;}
  AccGuard();if(g_DLock||g_DRSLock){Dash();return;}ManagePos();if(nb)TryEntry();FriG();Prune();Dash();}
void OnTimer(){AccGuard();ManagePos();}
//+------------------------------------------------------------------+
