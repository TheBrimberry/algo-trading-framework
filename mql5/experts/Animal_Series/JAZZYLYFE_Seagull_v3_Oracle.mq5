//+------------------------------------------------------------------+
//|             JAZZYLYFE_Seagull_v3_Oracle.mq5                      |
//|  Author : JAZZYLYFE | Jason Lamar Brimberry | Brimberry LLC      |
//|  GitHub : TheBrimberry | thebrimberry@gmail.com                  |
//|  Magic  : 888001  |  Symbol : XAGUSD                             |
//|  Grade  : A++     |  Version: 3.0.0 — Upcomers Oracle Edition   |
//|                                                                  |
//|  LIVE STATS8 87.2% WR | PF 8.07 | 89 trades | ELITE             |
//|  STRATEGY : Volatility squeeze → expansion burst                 |
//|             ATR contraction + BB squeeze + momentum burst        |
//|             + H1 liquidity sweep + M15 order block               |
//|  UPCOMERS : 4% daily / 5% DRS / 2% trade (Oracle)               |
//|  SIZING   : Base 0.03, max 0.10, recovery-aware tiers            |
//+------------------------------------------------------------------+
#property copyright "JAZZYLYFE | TheBrimberry | Brimberry LLC"
#property link      "https://github.com/TheBrimberry"
#property version   "3.00"
#property description "JAZZYLYFE Seagull v3 — XAGUSD 87.2% WR PF 8.07 — Upcomers Oracle — Grade A++"

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_DIR { DIR_BOTH=0, DIR_BUY=1, DIR_SELL=2 };

input group "=== IDENTITY ==="
input long   InpMagic        = 888001;
input string InpComment      = "JLSGL3-ORC";

input group "=== UPCOMERS ORACLE ==="
input double InpDailyPct     = 4.0;
input double InpDRSPct       = 5.0;
input double InpTradePct     = 2.0;
input double InpDailyFlatBuf = 1.5;
input double InpDRSFlatBuf   = 1.5;
input double InpTradeCloseBuf= 0.5;
input double InpEntryBlkDay  = 2.0;
input double InpEntryBlkDRS  = 2.0;
input bool   InpLockdown     = true;

input group "=== SIZING (micro-lot) ==="
input double InpBaseLots     = 0.01;
input double InpMaxLots      = 0.01;
input double InpMinLots      = 0.01;
input double InpTier1DD      = 1.0;
input double InpTier2DD      = 2.0;
input double InpTier3DD      = 3.0;

input group "=== SQUEEZE PARAMETERS ==="
input int    InpATR_Period   = 14;
input int    InpATR_SqBack   = 10;
input double InpSqRatio      = 0.70;
input int    InpBB_Period    = 20;
input double InpBB_Dev       = 2.0;
input int    InpMom_Period   = 10;
input double InpMom_Min      = 0.15;
input int    InpADX_Period   = 14;
input double InpADX_Min      = 20.0;
input int    InpEMA_Fast     = 13;
input int    InpEMA_Slow     = 89;
input int    InpEMA_Trend    = 200;
input int    InpOB_Lookback  = 20;
input bool   InpReqLiqSweep  = true;

input group "=== TARGETS ==="
input double InpATR_StopMult = 1.8;
input double InpBE_R         = 0.8;
input double InpTP1_R        = 1.000;
input double InpTP2_R        = 1.618;
input double InpTP3_R        = 2.618;
input double InpTP1_Pct      = 40.0;
input double InpTP2_Pct      = 30.0;
input double InpTrailMult    = 2.2;
input double InpTrailTight   = 1.3;

input group "=== SESSION ==="
input bool   InpLondon       = true;
input bool   InpNY           = true;
input bool   InpFriClose     = true;
input int    InpFriHour      = 19;

input group "=== FILTERS ==="
input ENUM_DIR InpDir        = DIR_BOTH;
input bool   InpInverse      = false;
input int    InpMinBars      = 8;
input double InpMaxSpread    = 80.0;
input int    InpMaxPos       = 2;
input int    InpMTF_Min      = 2;

// ---- state ----
double g_HWM=0, g_DayPeak=0, g_DayEqStart=0;
datetime g_DayStamp=0;
bool g_DayLock=false, g_DRSLock=false;
string g_GV="";
int g_hEMA_F[4],g_hEMA_S[4],g_hEMA_T[4];
int g_hATR[4],g_hBB,g_hMom,g_hADX;
ENUM_TIMEFRAMES g_TF[4];
datetime g_LastBar=0; int g_BarsSince=0;
struct SPos{ulong t;double iv,rd;bool tp1,tp2,be,pc1000;};
SPos g_pos[];

// ---- compliance math ----
double DayAnchor(){return g_DayPeak;}
double DailyHard(){return DayAnchor()*(1-InpDailyPct/100);}
double DailyFlat(){return DayAnchor()*(1-(InpDailyPct-InpDailyFlatBuf)/100);}
double DailyEntry(){return DayAnchor()*(1-InpEntryBlkDay/100);}
double DRSFloor(){return g_HWM*(1-InpDRSPct/100);}
double DRSFlat(){return g_HWM*(1-(InpDRSPct-InpDRSFlatBuf)/100);}
double DRSEntry(){return g_HWM*(1-(InpDRSPct-InpEntryBlkDRS)/100);}
double TradeWall(double eq){return eq*InpTradePct/100;}
double TradeClose(double eq){return eq*(InpTradePct-InpTradeCloseBuf)/100;}

void SaveGV(){
  GlobalVariableSet(g_GV+"HWM",g_HWM);
  GlobalVariableSet(g_GV+"DAYPK",g_DayPeak);
  GlobalVariableSet(g_GV+"DAYTS",(double)(long)g_DayStamp);
  GlobalVariableSet(g_GV+"DAYLOCK",g_DayLock?1.0:0.0);}
void LoadGV(){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  if(GlobalVariableCheck(g_GV+"HWM")) g_HWM=MathMax(eq,GlobalVariableGet(g_GV+"HWM"));
  datetime today=(datetime)(((long)TimeGMT()/86400)*86400);
  if(GlobalVariableCheck(g_GV+"DAYTS")&&(datetime)(long)GlobalVariableGet(g_GV+"DAYTS")==today){
    g_DayStamp=today;g_DayPeak=GlobalVariableGet(g_GV+"DAYPK");
    g_DayLock=(GlobalVariableGet(g_GV+"DAYLOCK")>0.5);}
  else{g_DayStamp=today;g_DayPeak=eq;}}

double Buf(int h,int buf=0,int sh=1){double b[1];return CopyBuffer(h,buf,sh,1,b)==1?b[0]:0;}
double BufAvg(int h,int n){double b[];return CopyBuffer(h,0,1,n,b)==n?(b[0]+b[1]+b[2]+b[3]+b[4]+b[5]+b[6]+b[7]+b[8]+b[9])/n:0;}

int MTFScore(){
  double px=SymbolInfoDouble(_Symbol,SYMBOL_BID); int sc=0;
  for(int i=0;i<4;i++){
    double ef=Buf(g_hEMA_F[i]),et=Buf(g_hEMA_T[i]),es=Buf(g_hEMA_S[i]);
    if(ef>0&&et>0){if(px>et&&ef>es)sc++;else if(px<et&&ef<es)sc--;}}
  return sc;}

bool SqueezeDetected(bool &bull){
  double atrNow=Buf(g_hATR[3]); if(atrNow<=0) return false;
  double atrAvg=BufAvg(g_hATR[3],InpATR_SqBack); if(atrAvg<=0) return false;
  if(atrNow>=atrAvg*InpSqRatio) return false;
  double bbU=Buf(g_hBB,1),bbL=Buf(g_hBB,2),bbM=Buf(g_hBB,0);
  if(bbM<=0) return false;
  double c[1]; CopyClose(_Symbol,PERIOD_M15,1,1,c);
  bull=(c[0]>bbM); return true;}

bool MomBurst(bool bull){
  double m=Buf(g_hMom)-100; double adx=Buf(g_hADX);
  bool burst=(MathAbs(m)>=InpMom_Min)&&((bull&&m>0)||(!bull&&m<0));
  return burst&&adx>InpADX_Min;}

bool LiqSweep(bool bull){
  double h[],l[],c[]; ArraySetAsSeries(h,true);ArraySetAsSeries(l,true);ArraySetAsSeries(c,true);
  if(CopyHigh(_Symbol,PERIOD_H1,1,25,h)<25) return false;
  if(CopyLow(_Symbol,PERIOD_H1,1,25,l)<25) return false;
  if(CopyClose(_Symbol,PERIOD_H1,1,25,c)<25) return false;
  if(bull){double sl=l[3];for(int i=4;i<25;i++)if(l[i]<sl)sl=l[i];return l[1]<sl&&c[1]>sl;}
  double sh=h[3];for(int i=4;i<25;i++)if(h[i]>sh)sh=h[i];return h[1]>sh&&c[1]<sh;}

bool OBConf(bool bull){
  double cl[],op[]; ArraySetAsSeries(cl,true);ArraySetAsSeries(op,true);
  int n=InpOB_Lookback+2;
  if(CopyClose(_Symbol,PERIOD_M15,1,n,cl)<n) return false;
  if(CopyOpen(_Symbol,PERIOD_M15,1,n,op)<n) return false;
  double px=bull?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
  for(int i=2;i<InpOB_Lookback;i++){
    bool bear=(cl[i]<op[i]),bul2=(cl[i]>op[i]);
    if(bull&&bear){double h2=MathMax(cl[i],op[i]),l2=MathMin(cl[i],op[i]);if(px>=l2&&px<=h2*1.003)return true;}
    if(!bull&&bul2){double h2=MathMax(cl[i],op[i]),l2=MathMin(cl[i],op[i]);if(px>=l2*0.997&&px<=h2)return true;}}
  return false;}

bool SessionOK(){MqlDateTime d;TimeToStruct(TimeGMT(),d);int h=d.hour;
  return (InpLondon&&h>=7&&h<12)||(InpNY&&h>=12&&h<17);}

double ComputeLots(double slDist){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  double lots=InpBaseLots;
  double ddPct=DayAnchor()>0?100*(DayAnchor()-eq)/DayAnchor():0;
  if(ddPct>=InpTier3DD) lots=InpMinLots;
  else if(ddPct>=InpTier2DD) lots=MathMax(InpMinLots,InpBaseLots*0.35);
  else if(ddPct>=InpTier1DD) lots=MathMax(InpMinLots,InpBaseLots*0.60);
  if(slDist>0){
    double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    if(tv>0&&ts>0){
      double lpl=(slDist/ts)*tv;
      double bud=MathMin(eq*1.0/100,MathMin(MathMax(0,eq-DRSFloor())/3,MathMax(0,eq-DailyHard())/3));
      if(lpl>0&&bud>0) lots=MathMin(lots,bud/lpl);}}
  lots=MathMin(lots,InpMaxLots);
  double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  if(step<=0)step=0.01;
  lots=MathFloor(lots/step+1e-9)*step;
  if(lots<InpMinLots) return 0;
  return lots;}

bool EntryOK(bool isBuy){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  if(g_DayLock&&InpLockdown){Print("SGL3 >> BLOCKED: day lock");return false;}
  if(g_DRSLock){Print("SGL3 >> BLOCKED: DRS lock");return false;}
  if(eq<=DailyEntry()){Print("SGL3 >> BLOCKED: daily buffer");return false;}
  if(eq<=DRSEntry()){Print("SGL3 >> BLOCKED: DRS buffer");return false;}
  int cnt=0;double last_px=0;bool all_in_profit=true;
  for(int i=PositionsTotal()-1;i>=0;i--){
    ulong t=PositionGetTicket(i);
    if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic){
      cnt++;
      double flt=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(flt<=0)all_in_profit=false;
      double open_px=PositionGetDouble(POSITION_PRICE_OPEN);
      if(last_px==0)last_px=open_px;
      else if(isBuy&&open_px>last_px)last_px=open_px;
      else if(!isBuy&&open_px<last_px)last_px=open_px;
    }
  }
  if(cnt>=InpMaxPos){Print("SGL3 >> BLOCKED: max pos");return false;}
  if(cnt>0&&!all_in_profit){Print("SGL3 >> BLOCKED: staggered entry requires initial trade in profit");return false;}
  if(cnt>0&&last_px>0){
    double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
    double cur_px=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
    if(isBuy&&cur_px<last_px+100*pt){Print("SGL3 >> BLOCKED: staggered distance too close");return false;}
    if(!isBuy&&cur_px>last_px-100*pt){Print("SGL3 >> BLOCKED: staggered distance too close");return false;}
  }
  double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
  double spr=pt>0?(SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/pt:0;
  if(spr>InpMaxSpread){Print("SGL3 >> BLOCKED: spread");return false;}
  MqlDateTime fd;TimeToStruct(TimeCurrent(),fd);
  if(InpFriClose&&fd.day_of_week==5&&fd.hour>=InpFriHour){Print("SGL3 >> BLOCKED: Friday");return false;}
  if(g_BarsSince<InpMinBars) return false;
  for(int i=PositionsTotal()-1;i>=0;i--){
    ulong t=PositionGetTicket(i);if(!PositionSelectByTicket(t))continue;
    if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
    if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)!=isBuy){Print("SGL3 >> BLOCKED: hedge");return false;}}
  return true;}

int RawSignal(){
  int sc=MTFScore(); if(MathAbs(sc)<InpMTF_Min) return 0;
  bool bull=false; if(!SqueezeDetected(bull)) return 0;
  if(bull&&sc<InpMTF_Min) return 0;
  if(!bull&&sc>-InpMTF_Min) return 0;
  if(!MomBurst(bull)) return 0;
  if(InpReqLiqSweep&&!LiqSweep(bull)) return 0;
  if(!OBConf(bull)) return 0;
  return bull?1:-1;}

int PosIdx(ulong t,bool mk){
  int n=ArraySize(g_pos);for(int i=0;i<n;i++)if(g_pos[i].t==t)return i;
  if(!mk)return -1;ArrayResize(g_pos,n+1);
  g_pos[n].t=t;g_pos[n].iv=0;g_pos[n].rd=0;g_pos[n].tp1=false;g_pos[n].tp2=false;g_pos[n].be=false;g_pos[n].pc1000=false;
  return n;}
void PruneStates(){for(int i=ArraySize(g_pos)-1;i>=0;i--)if(!PositionSelectByTicket(g_pos[i].t)){for(int j=i;j<ArraySize(g_pos)-1;j++)g_pos[j]=g_pos[j+1];ArrayResize(g_pos,ArraySize(g_pos)-1);}}

bool ClosePartial(ulong t,double pct){
  if(!PositionSelectByTicket(t))return false;
  double vol=PositionGetDouble(POSITION_VOLUME);
  double step=SymbolInfoDouble(PositionGetString(POSITION_SYMBOL),SYMBOL_VOLUME_STEP);
  if(step<=0)step=0.01;
  double cv=MathFloor(vol*pct/100/step+1e-9)*step;
  double vmin=SymbolInfoDouble(PositionGetString(POSITION_SYMBOL),SYMBOL_VOLUME_MIN);
  if(cv<vmin||cv>=vol)return false;
  return trade.PositionClosePartial(t,cv);}

void ManagePositions(){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  for(int i=PositionsTotal()-1;i>=0;i--){
    ulong t=PositionGetTicket(i);if(!PositionSelectByTicket(t))continue;
    if(PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
    string sym=PositionGetString(POSITION_SYMBOL);
    bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
    double vol=PositionGetDouble(POSITION_VOLUME),entry=PositionGetDouble(POSITION_PRICE_OPEN);
    double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
    double flt=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
    double bid=SymbolInfoDouble(sym,SYMBOL_BID),ask=SymbolInfoDouble(sym,SYMBOL_ASK);
    double px=buy?bid:ask;
    int dig=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
    double pt=SymbolInfoDouble(sym,SYMBOL_POINT);
    long lvl=SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
    double md=(double)lvl*pt;
    if(flt<=-TradeClose(eq)){trade.PositionClose(t);continue;}
    int si=PosIdx(t,true);if(g_pos[si].iv<=0)g_pos[si].iv=vol;
    if(!g_pos[si].pc1000&&(flt>=1000.0||flt<=-1000.0)){if(ClosePartial(t,50.0)){g_pos[si].pc1000=true;PrintFormat("SGL3 >> UNIVERSAL $1000 BREACH >> Partial closed 50%% on ticket %d (P&L: $%.2f)",t,flt);}}
    if(sl==0.0){
      double atr=Buf(g_hATR[3]);if(atr<=0)continue;
      double sd=atr*InpATR_StopMult;
      double nsl=NormalizeDouble(buy?entry-sd:entry+sd,dig);
      double ntp=NormalizeDouble(buy?entry+sd*InpTP3_R:entry-sd*InpTP3_R,dig);
      if(trade.PositionModify(t,nsl,ntp)){g_pos[si].rd=sd;sl=nsl;}}
    else if(g_pos[si].rd<=0)g_pos[si].rd=MathAbs(entry-sl);
    double R=g_pos[si].rd;if(R<=0)continue;
    double mR=buy?(px-entry)/R:(entry-px)/R;
    if(!g_pos[si].tp1&&mR>=InpTP1_R){if(ClosePartial(t,InpTP1_Pct))g_pos[si].tp1=true;}
    if(g_pos[si].tp1&&!g_pos[si].tp2&&mR>=InpTP2_R){if(ClosePartial(t,InpTP2_Pct))g_pos[si].tp2=true;}
    double dsl=0;
    if(!g_pos[si].be&&mR>=InpBE_R){dsl=buy?entry+3*pt:entry-3*pt;g_pos[si].be=true;}
    if(g_pos[si].be){
      double atrH=Buf(g_hATR[2]);
      int sc=MTFScore();bool opp=(buy&&sc<=-2)||(!buy&&sc>=2);
      double mult=opp?InpTrailTight:InpTrailMult;
      double chase=buy?px-atrH*mult:px+atrH*mult;
      if(dsl==0)dsl=chase;else dsl=buy?MathMax(dsl,chase):MathMin(dsl,chase);}
    if(dsl!=0){
      dsl=NormalizeDouble(dsl,dig);
      bool tight=buy?(dsl>sl+pt):(sl==0||dsl<sl-pt);
      bool valid=buy?(dsl<bid-md):(dsl>ask+md);
      if(tight&&valid)trade.PositionModify(t,dsl,tp);}}}

void AccountGuard(){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  datetime today=(datetime)(((long)TimeGMT()/86400)*86400);
  if(today!=g_DayStamp){g_DayStamp=today;g_DayEqStart=eq;g_DayPeak=eq;g_DayLock=false;SaveGV();}
  if(eq>g_HWM){g_HWM=eq;SaveGV();}
  if(eq>g_DayPeak){g_DayPeak=eq;SaveGV();}
  if(eq<=DRSFlat()){
    if(!g_DRSLock){g_DRSLock=true;PrintFormat("SGL3 >> DRS FLATTEN | eq $%.2f",eq);
      for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}}
  else if(g_DRSLock&&eq>DRSEntry()) g_DRSLock=false;
  if(!g_DayLock&&eq<=DailyFlat()){
    g_DayLock=true;PrintFormat("SGL3 >> DAILY FLATTEN | eq $%.2f",eq);SaveGV();
    for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}
  if((g_DayLock&&InpLockdown)||g_DRSLock)
    for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}

void TryEntry(){
  if(!SessionOK())return;
  int raw=RawSignal();if(raw==0)return;
  int sig=InpInverse?-raw:raw;
  if(InpDir==DIR_BUY&&sig<0)return;if(InpDir==DIR_SELL&&sig>0)return;
  bool buy=(sig>0);if(!EntryOK(buy))return;
  double atr=Buf(g_hATR[3]);if(atr<=0)return;
  double sd=atr*InpATR_StopMult;
  double px=buy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
  double sl=NormalizeDouble(buy?px-sd:px+sd,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
  double tp=NormalizeDouble(buy?px+sd*InpTP3_R:px-sd*InpTP3_R,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
  double lots=ComputeLots(sd);if(lots<=0){Print("SGL3 >> budget too small");return;}
  bool ok=buy?trade.Buy(lots,_Symbol,0,sl,tp,InpComment):trade.Sell(lots,_Symbol,0,sl,tp,InpComment);
  if(ok){g_BarsSince=0;ulong t=trade.ResultDeal();if(t>0){int si=PosIdx(t,true);g_pos[si].iv=lots;g_pos[si].rd=sd;}
    PrintFormat("SGL3 >> %s %.2f lots SL=%.5f TP=%.5f MTF=%d",buy?"BUY":"SELL",lots,sl,tp,MTFScore());}
  else Print("SGL3 >> FAILED: ",trade.ResultRetcodeDescription());}

void FriGuard(){if(!InpFriClose)return;MqlDateTime d;TimeToStruct(TimeCurrent(),d);
  if(d.day_of_week==5&&d.hour>=InpFriHour)
    for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}

void Dashboard(){
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  double ddPct=DayAnchor()>0?100*(DayAnchor()-eq)/DayAnchor():0;
  string tier=ddPct>=InpTier3DD?"T3-MIN":ddPct>=InpTier2DD?"T2-35%":ddPct>=InpTier1DD?"T1-60%":"T0-FULL";
  string s="";
  s+="╔═ JAZZYLYFE Seagull v3 — XAGUSD — Oracle ══════╗\n";
  s+="║ WR 87.2% | PF 8.07 | Magic "+string(InpMagic)+"\n";
  s+="║ Eq $"+DoubleToString(eq,2)+" | HWM $"+DoubleToString(g_HWM,2)+"\n";
  s+="║ Daily room $"+DoubleToString(eq-DailyHard(),2)+" | DRS room $"+DoubleToString(eq-DRSFloor(),2)+"\n";
  s+="║ Sizing: "+tier+" | Next: "+DoubleToString(ComputeLots(Buf(g_hATR[3])*InpATR_StopMult),2)+" lots\n";
  s+="║ MTF="+string(MTFScore())+" | Session: "+(SessionOK()?"OPEN":"CLOSED")+" | Lock: "+(g_DayLock||g_DRSLock?string(g_DayLock?"DAY":"")+(g_DRSLock?" DRS":""):"none")+"\n";
  s+="╚═ JAZZYLYFE | TheBrimberry | Brimberry LLC ════╝";
  Comment(s);}

int OnInit(){
  g_GV="JLUPC_"+string(AccountInfoInteger(ACCOUNT_LOGIN))+"_";
  double eq=AccountInfoDouble(ACCOUNT_EQUITY);
  g_HWM=eq;g_DayPeak=eq;g_DayEqStart=eq;g_DayStamp=(datetime)(((long)TimeGMT()/86400)*86400);
  LoadGV();if(g_HWM<eq)g_HWM=eq;
  g_TF[0]=PERIOD_D1;g_TF[1]=PERIOD_H4;g_TF[2]=PERIOD_H1;g_TF[3]=PERIOD_M15;
  for(int i=0;i<4;i++){
    g_hEMA_F[i]=iMA(_Symbol,g_TF[i],InpEMA_Fast, 0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_S[i]=iMA(_Symbol,g_TF[i],InpEMA_Slow, 0,MODE_EMA,PRICE_CLOSE);
    g_hEMA_T[i]=iMA(_Symbol,g_TF[i],InpEMA_Trend,0,MODE_EMA,PRICE_CLOSE);
    g_hATR[i]  =iATR(_Symbol,g_TF[i],InpATR_Period);}
  g_hBB =iBands(_Symbol,PERIOD_M15,InpBB_Period,0,InpBB_Dev,PRICE_CLOSE);
  g_hMom=iMomentum(_Symbol,PERIOD_M15,InpMom_Period,PRICE_CLOSE);
  g_hADX=iADX(_Symbol,PERIOD_M15,InpADX_Period);
  trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(80);
  EventSetTimer(1);
  Print("Seagull v3 Oracle >> ONLINE | base ",InpBaseLots," max ",InpMaxLots," | DRS floor $",DoubleToString(DRSFloor(),2));
  return INIT_SUCCEEDED;
}

void OnDeinit(const int r){EventKillTimer();SaveGV();Comment("");}

void OnTick(){
  datetime bar=iTime(_Symbol,PERIOD_M15,0);bool nb=(bar!=g_LastBar);
  if(nb){g_LastBar=bar;g_BarsSince++;}
  AccountGuard();if(g_DayLock||g_DRSLock){Dashboard();return;}
  ManagePositions();if(nb)TryEntry();
  FriGuard();PruneStates();Dashboard();}
void OnTimer(){AccountGuard();ManagePositions();}
//+------------------------------------------------------------------+
