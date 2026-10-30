//+------------------------------------------------------------------+
//|                                 RoundLevel_Kijun_RSI_EA_v7.mq5   |
//|  v4: zone = entry validator for its side; entry on any close     |
//|      beyond the zone (armed/re-armed); zone ignored past $5      |
//|  v5: zone dies after 2 consecutive SL, its level is prohibited   |
//|  v6: zone filter applies to its own level only (input), fill mode|
//|  v7: daily loss limit and daily target inputs                    |
//|  XAUUSD: round-number close breakout + Kijun/Cloud + RSI filter  |
//|  v2: nearest levels only, display options, distance threshold,   |
//|      RSI-failed zone box, level block after repeated SL          |
//+------------------------------------------------------------------+
#property copyright "RoundLevel Kijun RSI EA"
#property version   "7.00"
#property strict

#include <Trade/Trade.mqh>

enum ENUM_ZONE_SCOPE
  {
   ZONE_SAME_LEVEL = 0,   // zone only validates setups on its own level
   ZONE_WHOLE_SIDE = 1    // zone validates every setup on its side (any level)
  };

//--- PHASE 1: round levels
input group "=== Phase 1: Round Levels ==="
input double          InpLevelStep       = 10.0;        // Round level step (price units, $)
input color           InpUpperLineColor  = clrGold;     // Upper round line color
input color           InpLowerLineColor  = clrDeepSkyBlue; // Lower round line color
input color           InpBlockedColor    = clrRed;      // Color of a blocked level (after repeated SL)
input ENUM_LINE_STYLE InpLevelStyle      = STYLE_SOLID; // Round line style
input int             InpLevelWidth      = 3;           // Round line thickness (1-5)
input bool            InpShowLevelLabels = true;        // Show price label next to each round line
input int             InpLevelFontSize   = 11;          // Label font size
input double          InpMinBreakPoints  = 1;           // Min close distance beyond level (points)

//--- PHASE 2: Ichimoku
input group "=== Phase 2: Ichimoku ==="
input int             InpTenkan          = 9;           // Tenkan period (needed only for cloud calc)
input int             InpKijun           = 26;          // Kijun period (also cloud shift)
input int             InpSenkouB         = 52;          // Senkou Span B period
input bool            InpHideBuiltInIchimoku = true;    // Hide the built-in Ichimoku (Tenkan/Chikou...) in tester
input bool            InpDrawIchimoku    = true;        // Draw Ichimoku elements below
input bool            InpShowKijun       = true;        // Show Kijun-sen
input bool            InpShowCloud       = true;        // Show cloud (Senkou A/B fill)
input bool            InpShowSenkouLines = false;       // Also show Senkou A/B edge lines
input int             InpDrawBars        = 300;         // Bars to draw back
input color           InpKijunColor      = clrOrange;   // Kijun color
input int             InpKijunWidth      = 4;           // Kijun thickness
input color           InpCloudBullColor  = C'28,78,62'; // Cloud color (Senkou A above B)
input color           InpCloudBearColor  = C'92,42,48'; // Cloud color (Senkou B above A)
input color           InpSenkouAColor    = clrSeaGreen; // Senkou A line color
input color           InpSenkouBColor    = clrIndianRed;// Senkou B line color

//--- PHASE 3: RSI
input group "=== Phase 3: RSI ==="
input int             InpRsiPeriod       = 14;          // RSI period
input ENUM_APPLIED_PRICE InpRsiPrice     = PRICE_CLOSE; // RSI applied price
input double          InpRsiUpper        = 66.0;        // RSI upper band
input double          InpRsiLower        = 33.0;        // RSI lower band
input int             InpRsiMaPeriod     = 14;          // RSI smoothing SMA length
input bool            InpUseRsiMaFilter  = false;       // Also require RSI > SMA (buy) / RSI < SMA (sell)
input bool            InpShowRsiWindow   = true;        // Show RSI in a chart sub-window

//--- PHASE 4: entry filters
input group "=== Phase 4: Entry Filters ==="
input bool            InpUseCloudFilter  = true;        // Require price above/below cloud
input bool            InpUseKijunFilter  = true;        // Require price above/below Kijun
input bool            InpUseRsiFilter    = true;        // Require RSI not saturated
input bool            InpUseDistFilter   = true;        // Skip if close is too far beyond the round level
input double          InpMaxDistFromLevel= 5.0;         // Max distance of close from the level ($)
input bool            InpAllowBuy        = true;        // Allow buy setups
input bool            InpAllowSell       = true;        // Allow sell setups

//--- zone (RSI-failed first attempt)
input group "=== Zone: RSI-failed first attempt ==="
input bool            InpUseZone         = true;        // Use zone box after an RSI-saturated breakout
input bool            InpZoneCancelOnReclaim = false;   // Also cancel zone if price closes back across its level (off = zone lives until a new same-side zone is born)
input color           InpZoneBuyColor    = C'20,90,60'; // Buy zone box color
input color           InpZoneSellColor   = C'110,40,45';// Sell zone box color
input color           InpZoneDeadColor   = clrDimGray;  // Zone color when it is beyond the distance threshold (ignored)
input ENUM_ZONE_SCOPE InpZoneFilterScope = ZONE_SAME_LEVEL; // Where a live zone acts as entry filter

//--- level block
input group "=== Level Block (repeated SL) ==="
input int             InpMaxFailsPerLevel   = 2;        // Consecutive SL on a zone: zone is dropped and its level prohibited
input bool            InpFailsCountOnlyZone = true;     // Count only losses of zone trades
input bool            InpResetFailsOnWin    = true;     // A winning trade resets that level's SL count
input int             InpReleaseLevels      = 1;        // Level released when price closes this many steps away

input group "=== Risk / SL / TP ==="
input double          InpTpPips          = 55.0;        // Take profit (pips)
input double          InpSlPips          = 30.0;        // Stop loss (pips)
input double          InpPipInPoints     = 10.0;        // 1 pip = how many points (gold 2-digit: 10 => 0.10)
input double          InpRiskMoney       = 10.0;        // Risk per trade (account currency)
input bool            InpUseMinLotIfSmall= false;       // If calculated lot < min lot: trade min lot (else skip)

input group "=== Daily Limits ==="
input double          InpDailyLossLimit  = 0.0;         // Daily loss limit in account currency (0 = off)
input double          InpDailyTarget     = 0.0;         // Daily profit target in account currency (0 = off)

input group "=== General ==="
input int             InpMaxPositions    = 1;           // Max open positions for this EA
input int             InpMaxSpreadPoints = 0;           // Max spread in points (0 = off)
input int             InpSlippage        = 30;          // Max slippage (points)
input long            InpMagic           = 20261010;    // Magic number
input string          InpComment         = "RoundKijunRSI"; // Order comment

//--- types
struct Snap
  {
   double   c1, c2, h1, l1;
   double   kij, cTop, cBot;
   double   rsi, rsiMa;
   datetime t1;
  };

struct Zone
  {
   int      dir;      // +1 buy zone, -1 sell zone
   double   level;
   double   hi, lo;   // box = high/low of the first attempt bar
   datetime t0;
   bool     armed;    // true = a close beyond the box may trigger an entry
   int      fails;    // consecutive SL of trades taken from this zone
  };

struct LevelState
  {
   double   level;
   int      fails;
   bool     blocked;
  };

struct PosInfo
  {
   ulong    posId;
   double   level;
   bool     zone;
   int      dir;
  };

//--- globals
CTrade     trade;
int        hIchi = INVALID_HANDLE;
int        hRsi  = INVALID_HANDLE;
datetime   lastBar = 0;
string     PFX = "RLK_";
Zone       g_zones[];
LevelState g_ls[];
PosInfo    g_pos[];

//+------------------------------------------------------------------+
int OnInit()
  {
   TesterHideIndicators(InpHideBuiltInIchimoku);   // applies to handles created next
   hIchi = iIchimoku(_Symbol, _Period, InpTenkan, InpKijun, InpSenkouB);
   TesterHideIndicators(!InpShowRsiWindow);
   hRsi  = iRSI(_Symbol, _Period, InpRsiPeriod, InpRsiPrice);
   if(hIchi == INVALID_HANDLE || hRsi == INVALID_HANDLE)
     {
      Print("Indicator handle error: ", GetLastError());
      return INIT_FAILED;
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpShowRsiWindow && !MQLInfoInteger(MQL_TESTER))
      ChartIndicatorAdd(0, 1, hRsi);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   if(hIchi != INVALID_HANDLE) IndicatorRelease(hIchi);
   if(hRsi  != INVALID_HANDLE) IndicatorRelease(hRsi);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == lastBar) return;        // once per new bar, on closed-bar data
   lastBar = t;

   CheckSignal();
   DrawAll();
  }

//+------------------------------------------------------------------+
//| Market snapshot of last closed bar (shift 1)                      |
//+------------------------------------------------------------------+
bool GetSnap(Snap &s)
  {
   s.c1 = iClose(_Symbol, _Period, 1);
   s.c2 = iClose(_Symbol, _Period, 2);
   s.h1 = iHigh (_Symbol, _Period, 1);
   s.l1 = iLow  (_Symbol, _Period, 1);
   s.t1 = iTime (_Symbol, _Period, 1);
   if(s.c1 == 0 || s.c2 == 0) return false;

   double kij[1], sa[1], sb[1];
   if(CopyBuffer(hIchi, 1, 1, 1, kij) != 1) return false;
   if(CopyBuffer(hIchi, 2, 1, 1, sa)  != 1) return false;
   if(CopyBuffer(hIchi, 3, 1, 1, sb)  != 1) return false;
   s.kij  = kij[0];
   s.cTop = MathMax(sa[0], sb[0]);
   s.cBot = MathMin(sa[0], sb[0]);

   double rsi[];
   ArraySetAsSeries(rsi, true);
   int need = MathMax(1, InpRsiMaPeriod);
   if(CopyBuffer(hRsi, 0, 1, need, rsi) != need) return false;
   s.rsi = rsi[0];
   double sum = 0;
   for(int i = 0; i < need; i++) sum += rsi[i];
   s.rsiMa = sum / need;
   return true;
  }

//+------------------------------------------------------------------+
//| Filters                                                           |
//+------------------------------------------------------------------+
bool TrendOk(int dir, const Snap &s)
  {
   if(dir > 0)
     {
      if(InpUseCloudFilter && !(s.c1 > s.cTop)) return false;
      if(InpUseKijunFilter && !(s.c1 > s.kij))  return false;
     }
   else
     {
      if(InpUseCloudFilter && !(s.c1 < s.cBot)) return false;
      if(InpUseKijunFilter && !(s.c1 < s.kij))  return false;
     }
   return true;
  }

bool RsiSaturated(int dir, const Snap &s)
  {
   if(!InpUseRsiFilter) return false;
   return (dir > 0) ? (s.rsi > InpRsiUpper) : (s.rsi < InpRsiLower);
  }

bool RsiOk(int dir, const Snap &s)
  {
   if(RsiSaturated(dir, s)) return false;
   if(InpUseRsiMaFilter)
     {
      if(dir > 0 && !(s.rsi > s.rsiMa)) return false;
      if(dir < 0 && !(s.rsi < s.rsiMa)) return false;
     }
   return true;
  }

bool DistOk(int dir, double level, const Snap &s)
  {
   if(!InpUseDistFilter) return true;
   double d = (dir > 0) ? (s.c1 - level) : (level - s.c1);
   return (d <= InpMaxDistFromLevel + 1e-9);
  }

//+------------------------------------------------------------------+
//| Main signal logic                                                 |
//+------------------------------------------------------------------+
void CheckSignal()
  {
   Snap s;
   if(!GetSnap(s)) return;

   ReleaseBlocks(s.c1);
   UpdateZones(s);

   double brk    = InpMinBreakPoints * _Point;
   double lvlUp  = MathFloor(s.c1 / InpLevelStep + 1e-9) * InpLevelStep;  // level at/below close
   double lvlDn  = MathCeil (s.c1 / InpLevelStep - 1e-9) * InpLevelStep;  // level at/above close

   bool breakUp = (s.c1 >= lvlUp + brk) && (s.c2 <= lvlUp);
   bool breakDn = (s.c1 <= lvlDn - brk) && (s.c2 >= lvlDn);

   if(breakUp && InpAllowBuy)       HandleBreak(+1, lvlUp, s);
   else if(breakDn && InpAllowSell) HandleBreak(-1, lvlDn, s);
  }

void HandleBreak(int dir, double level, const Snap &s)
  {
   if(IsBlocked(level)) return;
   if(!TrendOk(dir, s) || !DistOk(dir, level, s)) return;

   if(RsiOk(dir, s))
     {
      // normal setup: no zone needed. Only if a live (not beyond-threshold) zone exists
      // on this side must price already be beyond that zone.
      if(ZoneFilterOk(dir, level, s)) TryOpen(dir, level, false);
      return;
     }
   // only RSI failed (saturated) -> remember first attempt as a zone
   if(InpUseZone && RsiSaturated(dir, s) && !ZoneExists(dir, level))
      AddZone(dir, level, s);
  }

//+------------------------------------------------------------------+
//| Zones                                                             |
//+------------------------------------------------------------------+
// a zone whose break-edge is already farther than the threshold from its level
// can never give a valid entry, so it stops being a filter and a trigger
bool ZoneDead(const Zone &z)
  {
   if(!InpUseDistFilter) return false;
   double d = (z.dir > 0) ? (z.hi - z.level) : (z.level - z.lo);
   return (d + InpMinBreakPoints * _Point > InpMaxDistFromLevel + 1e-9);
  }

// entry validator: with a live zone on this side, price must be beyond that zone
bool ZoneFilterOk(int dir, double level, const Snap &s)
  {
   if(!InpUseZone) return true;
   double brk = InpMinBreakPoints * _Point;
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      if(g_zones[i].dir != dir) continue;
      if(InpZoneFilterScope == ZONE_SAME_LEVEL &&
         MathAbs(g_zones[i].level - level) >= InpLevelStep * 0.25) continue;   // other level: not our zone
      if(ZoneDead(g_zones[i])) return true;
      return (dir > 0) ? (s.c1 >= g_zones[i].hi + brk)
                       : (s.c1 <= g_zones[i].lo - brk);
     }
   return true;   // no zone on this side -> normal setups run freely
  }

bool ZoneExists(int dir, double level)
  {
   for(int i = 0; i < ArraySize(g_zones); i++)
      if(g_zones[i].dir == dir && MathAbs(g_zones[i].level - level) < InpLevelStep * 0.25)
         return true;
   return false;
  }

void AddZone(int dir, double level, const Snap &s)
  {
   // a new zone replaces any older zone of the SAME side (any level); the other side is untouched
   for(int i = ArraySize(g_zones) - 1; i >= 0; i--)
      if(g_zones[i].dir == dir) RemoveZone(i);

   int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1);
   g_zones[n].dir   = dir;
   g_zones[n].level = level;
   g_zones[n].hi    = s.h1;
   g_zones[n].lo    = s.l1;
   g_zones[n].t0    = s.t1;
   g_zones[n].armed = true;
   g_zones[n].fails = 0;
  }

void RemoveZone(int idx)
  {
   int n = ArraySize(g_zones);
   for(int i = idx; i < n - 1; i++) g_zones[i] = g_zones[i + 1];
   ArrayResize(g_zones, n - 1);
  }

void UpdateZones(const Snap &s)
  {
   double brk = InpMinBreakPoints * _Point;
   for(int i = ArraySize(g_zones) - 1; i >= 0; i--)
     {
      int  d = g_zones[i].dir;
      bool remove = false;

      if(InpZoneCancelOnReclaim &&
         ((d > 0 && s.c1 < g_zones[i].level) || (d < 0 && s.c1 > g_zones[i].level)))
         remove = true;
      else
        {
         // close back inside the box re-arms the zone
         if(d > 0 && s.c1 <= g_zones[i].hi) g_zones[i].armed = true;
         if(d < 0 && s.c1 >= g_zones[i].lo) g_zones[i].armed = true;

         // any close beyond the box edge (even 1 tick) while armed = setup
         bool broke = (d > 0) ? (s.c1 >= g_zones[i].hi + brk)
                              : (s.c1 <= g_zones[i].lo - brk);
         if(broke && g_zones[i].armed && !ZoneDead(g_zones[i]))
           {
            bool   allowed = (d > 0) ? InpAllowBuy : InpAllowSell;
            double lv      = g_zones[i].level;
            if(allowed && !IsBlocked(lv) && TrendOk(d, s) && DistOk(d, lv, s) && RsiOk(d, s))
               if(TryOpen(d, lv, true)) g_zones[i].armed = false;
           }
        }
      if(remove) RemoveZone(i);
     }
  }

//+------------------------------------------------------------------+
//| Level fail counter / block                                        |
//+------------------------------------------------------------------+
int FindLS(double level)
  {
   for(int i = 0; i < ArraySize(g_ls); i++)
      if(MathAbs(g_ls[i].level - level) < InpLevelStep * 0.25) return i;
   return -1;
  }

bool IsBlocked(double level)
  {
   int i = FindLS(level);
   return (i >= 0 && g_ls[i].blocked);
  }

void RemoveLS(int idx)
  {
   int n = ArraySize(g_ls);
   for(int i = idx; i < n - 1; i++) g_ls[i] = g_ls[i + 1];
   ArrayResize(g_ls, n - 1);
  }

void RegisterFail(double level)
  {
   int i = FindLS(level);
   if(i < 0)
     {
      i = ArraySize(g_ls);
      ArrayResize(g_ls, i + 1);
      g_ls[i].level = level; g_ls[i].fails = 0; g_ls[i].blocked = false;
     }
   g_ls[i].fails++;
   if(g_ls[i].fails >= InpMaxFailsPerLevel)
     {
      g_ls[i].blocked = true;
      PrintFormat("Level %.2f blocked after %d SL", level, g_ls[i].fails);
     }
  }

void RegisterWin(double level)
  {
   if(!InpResetFailsOnWin) return;
   int i = FindLS(level);
   if(i >= 0 && !g_ls[i].blocked) g_ls[i].fails = 0;
  }

// a blocked level is released once price closes far enough away (a new level is "seen")
void ReleaseBlocks(double c1)
  {
   for(int i = ArraySize(g_ls) - 1; i >= 0; i--)
      if(g_ls[i].blocked && MathAbs(c1 - g_ls[i].level) >= InpLevelStep * InpReleaseLevels - 1e-9)
        {
         PrintFormat("Level %.2f released", g_ls[i].level);
         RemoveLS(i);
        }
  }

//+------------------------------------------------------------------+
//| Position bookkeeping + SL detection                               |
//+------------------------------------------------------------------+
void AddPos(ulong id, double level, bool zone, int dir)
  {
   int n = ArraySize(g_pos);
   ArrayResize(g_pos, n + 1);
   g_pos[n].posId = id; g_pos[n].level = level; g_pos[n].zone = zone; g_pos[n].dir = dir;
  }

// prohibit a level until price has "seen" another level (see ReleaseBlocks)
void BlockLevel(double level)
  {
   int i = FindLS(level);
   if(i < 0)
     {
      i = ArraySize(g_ls);
      ArrayResize(g_ls, i + 1);
      g_ls[i].level = level;
     }
   g_ls[i].fails   = InpMaxFailsPerLevel;
   g_ls[i].blocked = true;
   PrintFormat("Level %.2f prohibited (zone failed)", level);
  }

// SL of a trade taken from a zone: 2 consecutive SL -> zone is removed and level prohibited
void ZoneRegisterFail(int dir, double level)
  {
   for(int i = 0; i < ArraySize(g_zones); i++)
      if(g_zones[i].dir == dir && MathAbs(g_zones[i].level - level) < InpLevelStep * 0.25)
        {
         g_zones[i].fails++;
         if(g_zones[i].fails >= InpMaxFailsPerLevel)
           {
            RemoveZone(i);
            BlockLevel(level);
           }
         return;
        }
   RegisterFail(level);   // zone was already replaced -> count on the level instead
  }

void ZoneRegisterWin(int dir, double level)
  {
   if(!InpResetFailsOnWin) return;
   for(int i = 0; i < ArraySize(g_zones); i++)
      if(g_zones[i].dir == dir && MathAbs(g_zones[i].level - level) < InpLevelStep * 0.25)
         g_zones[i].fails = 0;
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal)) return;
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) return;

   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   ulong  posId  = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   long   reason = HistoryDealGetInteger(deal, DEAL_REASON);
   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);

   for(int i = 0; i < ArraySize(g_pos); i++)
     {
      if(g_pos[i].posId != posId) continue;
      double level = g_pos[i].level;
      bool   zone  = g_pos[i].zone;
      int    pdir  = g_pos[i].dir;

      if(reason == DEAL_REASON_SL)
        {
         if(zone)                        ZoneRegisterFail(pdir, level);
         else if(!InpFailsCountOnlyZone) RegisterFail(level);
        }
      else if(profit > 0)
        {
         if(zone) ZoneRegisterWin(pdir, level);
         RegisterWin(level);
        }

      int n = ArraySize(g_pos);
      for(int j = i; j < n - 1; j++) g_pos[j] = g_pos[j + 1];
      ArrayResize(g_pos, n - 1);
      break;
     }
  }

//+------------------------------------------------------------------+
//| Trading                                                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Daily P/L of this EA (symbol + magic), server day, incl. floating |
//+------------------------------------------------------------------+
double DailyPnL()
  {
   double   pnl      = 0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);

   if(HistorySelect(dayStart, TimeCurrent() + 60))
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0) continue;
         if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagic) continue;
         if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
         long ty = HistoryDealGetInteger(tk, DEAL_TYPE);
         if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL) continue;
         pnl += HistoryDealGetDouble(tk, DEAL_PROFIT)
              + HistoryDealGetDouble(tk, DEAL_SWAP)
              + HistoryDealGetDouble(tk, DEAL_COMMISSION)
              + HistoryDealGetDouble(tk, DEAL_FEE);
        }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return pnl;
  }

// true = no new trades for the rest of the day
bool DailyLimitHit()
  {
   if(InpDailyLossLimit <= 0 && InpDailyTarget <= 0) return false;

   static datetime msgDay = 0;
   double   pnl = DailyPnL();
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   bool     hit = false;

   if(InpDailyLossLimit > 0 && pnl <= -InpDailyLossLimit)
     {
      hit = true;
      if(msgDay != day) PrintFormat("Daily loss limit reached (%.2f). No new trades today.", pnl);
     }
   else if(InpDailyTarget > 0 && pnl >= InpDailyTarget)
     {
      hit = true;
      if(msgDay != day) PrintFormat("Daily target reached (%.2f). No new trades today.", pnl);
     }
   if(hit) msgDay = day;
   return hit;
  }

bool TryOpen(int dir, double level, bool zone)
  {
   if(DailyLimitHit()) return false;
   if(CountPositions() >= InpMaxPositions) return false;
   if(InpMaxSpreadPoints > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints) return false;
   return OpenTrade(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, level, zone);
  }

bool OpenTrade(ENUM_ORDER_TYPE type, double level, bool zone)
  {
   double pip   = InpPipInPoints * _Point;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(type == ORDER_TYPE_BUY)
     { sl = price - InpSlPips * pip; tp = price + InpTpPips * pip; }
   else
     { sl = price + InpSlPips * pip; tp = price - InpTpPips * pip; }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lot = CalcLot(type, price, sl);
   if(lot <= 0)
     {
      Print("Lot calc failed or risk too small for min lot - trade skipped.");
      return false;
     }

   string cmt = InpComment + (zone ? "_Z" : "");
   bool res = (type == ORDER_TYPE_BUY) ? trade.Buy (lot, _Symbol, price, sl, tp, cmt)
                                       : trade.Sell(lot, _Symbol, price, sl, tp, cmt);
   if(!res || trade.ResultRetcode() != TRADE_RETCODE_DONE)
     {
      Print("Order failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
     }

   ulong posId = 0;
   ulong deal  = trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal))
      posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(posId == 0) posId = trade.ResultOrder();
   AddPos(posId, level, zone, (type == ORDER_TYPE_BUY) ? 1 : -1);
   return true;
  }

//+------------------------------------------------------------------+
//| Lot so that hitting SL loses ~InpRiskMoney                        |
//+------------------------------------------------------------------+
double CalcLot(ENUM_ORDER_TYPE type, double price, double sl)
  {
   double p = 0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, price, sl, p) || p >= 0) return 0;

   double lot  = InpRiskMoney / MathAbs(p);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / step + 1e-9) * step;
   if(lot < vmin)
     {
      if(InpUseMinLotIfSmall) lot = vmin; else return 0;
     }
   lot = MathMin(lot, vmax);

   int d = 0; double st = step;
   while(d < 8 && MathAbs(st - MathRound(st)) > 1e-9) { st *= 10; d++; }
   return NormalizeDouble(lot, d);
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
//| Drawing                                                           |
//+------------------------------------------------------------------+
void DrawAll()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   ObjectsDeleteAll(0, PFX);
   DrawLevels();
   DrawZones();
   if(InpDrawIchimoku) DrawIchimoku();
   ChartRedraw();
  }

// only the nearest round line above and the nearest below the price
void DrawLevels()
  {
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double upper = MathFloor(bid / InpLevelStep + 1e-9) * InpLevelStep + InpLevelStep;
   double lower = MathCeil (bid / InpLevelStep - 1e-9) * InpLevelStep - InpLevelStep;
   DrawLine("U", upper, InpUpperLineColor);
   DrawLine("D", lower, InpLowerLineColor);
  }

void DrawLine(string tag, double lv, color clr)
  {
   color use = IsBlocked(lv) ? InpBlockedColor : clr;

   string nm = PFX + "L_" + tag;
   ObjectCreate(0, nm, OBJ_HLINE, 0, 0, lv);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, use);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, InpLevelStyle);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, InpLevelWidth);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);

   if(InpShowLevelLabels)
     {
      string tn = PFX + "T_" + tag;
      datetime tt = iTime(_Symbol, _Period, 0) + PeriodSeconds() * 3;
      ObjectCreate(0, tn, OBJ_TEXT, 0, tt, lv);
      ObjectSetString (0, tn, OBJPROP_TEXT, DoubleToString(lv, 2));
      ObjectSetInteger(0, tn, OBJPROP_COLOR, use);
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, InpLevelFontSize);
      ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
     }
  }

void DrawZones()
  {
   datetime tEnd = iTime(_Symbol, _Period, 0) + PeriodSeconds();
   for(int i = 0; i < ArraySize(g_zones); i++)
     {
      string nm = PFX + "Z_" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_zones[i].t0, g_zones[i].hi, tEnd, g_zones[i].lo);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, ZoneDead(g_zones[i]) ? InpZoneDeadColor
                                          : (g_zones[i].dir > 0 ? InpZoneBuyColor : InpZoneSellColor));
      ObjectSetInteger(0, nm, OBJPROP_FILL, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
     }
  }

void DrawIchimoku()
  {
   if(!InpShowKijun && !InpShowCloud && !InpShowSenkouLines) return;

   int n = InpDrawBars;
   double k[], a[], b[];
   datetime tm[];
   ArraySetAsSeries(k, true); ArraySetAsSeries(a, true);
   ArraySetAsSeries(b, true); ArraySetAsSeries(tm, true);
   if(CopyBuffer(hIchi, 1, 0, n + 1, k) <= 0) return;
   if(CopyBuffer(hIchi, 2, 0, n + 1, a) <= 0) return;
   if(CopyBuffer(hIchi, 3, 0, n + 1, b) <= 0) return;
   if(CopyTime(_Symbol, _Period, 0, n + 1, tm) <= 0) return;

   int cnt = MathMin(ArraySize(tm), MathMin(ArraySize(k), MathMin(ArraySize(a), ArraySize(b))));
   for(int i = 0; i < cnt; i++)
     {
      bool okAB = (a[i] != EMPTY_VALUE && b[i] != EMPTY_VALUE && a[i] != 0 && b[i] != 0);

      if(InpShowCloud && okAB)
        {
         datetime tEnd = (i == 0) ? tm[0] + PeriodSeconds() : tm[i - 1];
         string nm = PFX + "C" + IntegerToString(i);
         ObjectCreate(0, nm, OBJ_RECTANGLE, 0, tm[i], a[i], tEnd, b[i]);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, (a[i] >= b[i]) ? InpCloudBullColor : InpCloudBearColor);
         ObjectSetInteger(0, nm, OBJPROP_FILL, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
        }

      if(i < cnt - 1)
        {
         if(InpShowKijun)
            Seg("K", i, tm[i + 1], k[i + 1], tm[i], k[i], InpKijunColor, InpKijunWidth, false);
         if(InpShowSenkouLines)
           {
            Seg("A", i, tm[i + 1], a[i + 1], tm[i], a[i], InpSenkouAColor, 1, true);
            Seg("B", i, tm[i + 1], b[i + 1], tm[i], b[i], InpSenkouBColor, 1, true);
           }
        }
     }
  }

void Seg(string tag, int i, datetime t1, double p1, datetime t2, double p2, color clr, int w, bool back)
  {
   if(p1 == EMPTY_VALUE || p2 == EMPTY_VALUE || p1 == 0 || p2 == 0) return;
   string nm = PFX + tag + IntegerToString(i);
   ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK, back);
  }
//+------------------------------------------------------------------+