//+------------------------------------------------------------------+
//|                                       Donchian_Channel_EA.mq5    |
//|                          Custom MT5 EA - Donchian Channel Strategy|
//|                                                                  |
//|  Multi-timeframe Donchian Channel strategy EA with shared        |
//|  Basket Floating P/L money management system.                    |
//|                                                                  |
//|  Key Features:                                                   |
//|  - 4 selectable timeframes with adjustable Donchian Period       |
//|  - Same Direction / Inverse Direction modes                      |
//|  - 1-4 timeframe simultaneous live-touch confirmation            |
//|  - Exact PLOT_SHIFT = 1 behavior matching supplied indicator     |
//|  - No touch-memory; signals must be valid simultaneously         |
//|  - Shared Basket ID across multiple EA instances/symbols         |
//|  - Combined Basket Floating + Realized P/L monitoring            |
//|  - Max Basket Loss/Profit with automatic close & daily lock      |
//|  - Manual Reset_Daily_Lock and auto-reset at 00:00 server time   |
//|  - Maximum 1 open trade per EA instance/pair                     |
//|  - On-chart Donchian level visualization & signal arrows         |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.20"
#property strict

#resource "Donchian Channel.ex5"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_MODE
  {
   SameDirection,      // Same Direction
   InverseDirection    // Inverse Direction
  };

enum ENUM_SIGNAL_TYPE
  {
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL
  };

//+------------------------------------------------------------------+
//| Input Parameters - Core Strategy                                  |
//+------------------------------------------------------------------+
input string              InpSep1                = "══════════════════════════";  // ══ Core Strategy Settings ══
input ENUM_STRATEGY_MODE  Strategy_Mode          = SameDirection;                // Strategy Mode
input int                 Confirm_Directions     = 3;                           // Confirm Directions (1-4)
input ENUM_TIMEFRAMES     Timeframe_1            = PERIOD_M5;                   // Timeframe 1
input ENUM_TIMEFRAMES     Timeframe_2            = PERIOD_M15;                  // Timeframe 2
input ENUM_TIMEFRAMES     Timeframe_3            = PERIOD_M30;                  // Timeframe 3
input ENUM_TIMEFRAMES     Timeframe_4            = PERIOD_H1;                   // Timeframe 4
input int                 Period_of_Channel      = 50;                          // Period of the Channel
input bool                Showprice_of_the_Level = true;                        // Show Price of the Level
input double              LotSize                = 1.25;                        // Lot Size
input int                 TP_Pips                = 40;                          // Take Profit (Pips)
input int                 SL_Pips                = 40;                          // Stop Loss (Pips)
input int                 Magic_Number           = 32134;                       // Magic Number
input string              Comment_Text           = "";                          // Comment

//+------------------------------------------------------------------+
//| Input Parameters - Basket Money Management                        |
//+------------------------------------------------------------------+
input string              InpSep2                    = "══════════════════════════";  // ══ Basket Management ══
input bool                Enable_Basket_Floating_PL  = true;                         // Enable Basket Floating P/L
input int                 Basket_ID                  = 1;                             // Basket ID
input double              Max_Basket_Loss_USD        = 1000;                          // Max Basket Loss (USD) [0=Disabled]
input double              Max_Basket_Profit_USD      = 2000;                          // Max Basket Profit (USD) [0=Disabled]
input bool                Lock_Trading_After_Target  = true;                          // Lock Trading After Target
input bool                Reset_Daily_Lock           = false;                         // Reset Daily Lock (Manual)

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
CTrade            g_trade;              // Trade execution object
ENUM_TIMEFRAMES   g_timeframes[4];      // Array of monitored timeframes
int               g_confirmDir;         // Validated confirm directions (1-4)
double            g_pipValue;           // Pip value for this symbol
string            g_basketTag;          // Comment tag for basket identification
string            g_gvLockName;         // GV name: basket lock state
string            g_gvLockDateName;     // GV name: lock date (for daily reset)
string            g_gvClosingName;      // GV name: closing flag (prevents duplicate ops)
string            g_objPrefix;          // Unique prefix for chart objects
int               g_indHandle;          // Donchian Channel indicator handle for chart visual

//--- Realized P/L cache (to avoid recalculating on every tick)
int               g_lastDealCount;      // Last known deal count for cache invalidation
double            g_cachedRealizedPL;   // Cached realized P/L value
datetime          g_cachedDate;         // Date of cached value

//--- Color arrays for Donchian level visualization
color             g_upperColors[4];     // Colors for upper Donchian levels
color             g_lowerColors[4];     // Colors for lower Donchian levels

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Validate Period_of_Channel
   if(Period_of_Channel < 2)
     {
      Print("Error: Period_of_Channel must be >= 2. Current value: ", Period_of_Channel);
      return(INIT_FAILED);
     }

//--- Validate LotSize
   if(LotSize <= 0)
     {
      Print("Error: LotSize must be > 0. Current value: ", LotSize);
      return(INIT_FAILED);
     }

//--- Store timeframes in array for iteration
   g_timeframes[0] = Timeframe_1;
   g_timeframes[1] = Timeframe_2;
   g_timeframes[2] = Timeframe_3;
   g_timeframes[3] = Timeframe_4;

//--- Validate and clamp Confirm_Directions to 1-4
   g_confirmDir = MathMax(1, MathMin(4, Confirm_Directions));
   if(g_confirmDir != Confirm_Directions)
      Print("Warning: Confirm_Directions clamped from ", Confirm_Directions, " to ", g_confirmDir);

//--- Calculate pip value for this symbol
   g_pipValue = GetPipValue();
   if(g_pipValue == 0)
     {
      Print("Error: Unable to determine pip value for ", _Symbol);
      return(INIT_FAILED);
     }

//--- Setup basket identification tag (embedded in trade comments)
   g_basketTag = "[B" + IntegerToString(Basket_ID) + "]";

//--- Setup Global Variable names for cross-chart coordination
   g_gvLockName     = "DC_BasketLock_" + IntegerToString(Basket_ID);
   g_gvLockDateName = "DC_LockDate_"   + IntegerToString(Basket_ID);
   g_gvClosingName  = "DC_Closing_"    + IntegerToString(Basket_ID);

//--- Initialize closing flag GV if it doesn't exist
   if(!GlobalVariableCheck(g_gvClosingName))
      GlobalVariableSet(g_gvClosingName, 0);

//--- Configure CTrade object
   g_trade.SetExpertMagicNumber(Magic_Number);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(DetectFillingMode());

//--- Setup unique chart object prefix (prevents conflicts between instances)
   g_objPrefix = "DC_" + IntegerToString(Magic_Number) + "_";

//--- Setup visualization colors for each timeframe
//--- Upper channels: blue shades | Lower channels: red shades
   g_upperColors[0] = clrDodgerBlue;
   g_upperColors[1] = clrRoyalBlue;
   g_upperColors[2] = clrCornflowerBlue;
   g_upperColors[3] = clrSteelBlue;
   g_lowerColors[0] = clrOrangeRed;
   g_lowerColors[1] = clrTomato;
   g_lowerColors[2] = clrCoral;
   g_lowerColors[3] = clrSalmon;

//--- Initialize realized P/L cache
   g_lastDealCount   = -1;
   g_cachedRealizedPL = 0;
   g_cachedDate       = 0;

//--- Handle Manual Reset of Daily Lock
   if(Reset_Daily_Lock)
     {
      ClearBasketLock();
      Print("Manual basket lock reset for Basket_ID: ", Basket_ID);
     }

//--- Attach Donchian Channel indicator to chart for live visual lines (Blue/Gray/Red)
   g_indHandle = iCustom(_Symbol, PERIOD_CURRENT, "::Donchian Channel.ex5", Period_of_Channel, Showprice_of_the_Level);
   if(g_indHandle == INVALID_HANDLE)
      g_indHandle = iCustom(_Symbol, PERIOD_CURRENT, "Donchian Channel", Period_of_Channel, Showprice_of_the_Level);
   if(g_indHandle == INVALID_HANDLE)
      g_indHandle = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Donchian Channel", Period_of_Channel, Showprice_of_the_Level);

   if(g_indHandle != INVALID_HANDLE)
     {
      if(ChartIndicatorAdd(0, 0, g_indHandle))
         Print("Donchian Channel indicator attached to chart successfully (handle: ", g_indHandle, ")");
      else
         Print("Warning: ChartIndicatorAdd returned error: ", GetLastError());
     }
   else
     {
      Print("Note: Donchian Channel indicator handle invalid; using built-in object line renderer.");
     }

//--- Display initialization summary
   Print("==============================================");
   Print("Donchian Channel EA v1.20 Initialized");
   Print("Symbol: ", _Symbol, " | Magic: ", Magic_Number);
   Print("Strategy: ", EnumToString(Strategy_Mode));
   Print("Confirm Directions: ", g_confirmDir, " of 4");
   Print("Timeframes: ", EnumToString(Timeframe_1), ", ",
         EnumToString(Timeframe_2), ", ",
         EnumToString(Timeframe_3), ", ",
         EnumToString(Timeframe_4));
   Print("Donchian Period: ", Period_of_Channel, " (PLOT_SHIFT = 1)");
   Print("Lot: ", DoubleToString(LotSize, 2),
         " | TP: ", TP_Pips, " pips | SL: ", SL_Pips, " pips");
   Print("Basket_ID: ", Basket_ID, " | Tag: ", g_basketTag);
   Print("Basket P/L: ", (Enable_Basket_Floating_PL ? "Enabled" : "Disabled"));
   if(Enable_Basket_Floating_PL)
     {
      Print("Max Loss: ", (Max_Basket_Loss_USD > 0
            ? DoubleToString(Max_Basket_Loss_USD, 2) + " USD" : "Disabled"));
      Print("Max Profit: ", (Max_Basket_Profit_USD > 0
            ? DoubleToString(Max_Basket_Profit_USD, 2) + " USD" : "Disabled"));
     }
   Print("Basket tracks: Floating P/L + Daily Realized P/L");
   Print("==============================================");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Remove attached Donchian Channel indicator from chart
   if(g_indHandle != INVALID_HANDLE)
     {
      int totalInd = ChartIndicatorsTotal(0, 0);
      for(int i = totalInd - 1; i >= 0; i--)
        {
         string indName = ChartIndicatorName(0, 0, i);
         if(StringFind(indName, "Donchian Channel") >= 0)
            ChartIndicatorDelete(0, 0, indName);
        }
      IndicatorRelease(g_indHandle);
      g_indHandle = INVALID_HANDLE;
     }

//--- Remove all chart objects created by this EA instance
   CleanupChartObjects();

//--- Clear chart comment
   Comment("");

   Print("Donchian Channel EA removed from ", _Symbol, " | Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function - Main execution loop                         |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- 1. Check for automatic daily lock reset (new day at 00:00 server time)
   CheckDailyReset();

//--- 2. Monitor Basket P/L (Floating + Realized) and handle thresholds
   if(Enable_Basket_Floating_PL)
       MonitorBasketPL();

//--- 3. Update chart display (Donchian lines, signal arrows, info panel)
   DrawDonchianChannel();
   UpdateChartDisplay();

//--- 4. If basket is locked, block all new entries
   if(Enable_Basket_Floating_PL && IsBasketLocked())
      return;

//--- 5. Check if this instance already has an open trade (max 1 per pair)
   if(HasOpenTrade())
      return;

//--- 6. Evaluate all timeframes for a valid Donchian signal
   ENUM_SIGNAL_TYPE signal = CheckSignal();

//--- 7. Open trade if signal meets confirmation threshold
   if(signal != SIGNAL_NONE)
     {
      double price = (signal == SIGNAL_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(OpenTrade(signal))
         DrawSignalArrow(signal, price);
     }
  }

//+------------------------------------------------------------------+
//| ==================== SIGNAL LOGIC =============================== |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get Donchian Channel levels for a specific timeframe               |
//|                                                                    |
//| PLOT_SHIFT = 1 Behavior (matches supplied indicator exactly):      |
//|                                                                    |
//| The supplied Donchian Channel indicator calculates at each bar i:  |
//|   Upper = Highest High of bars [i-Period+1] to [i]                |
//|   Lower = Lowest Low   of bars [i-Period+1] to [i]                |
//|                                                                    |
//| With PLOT_SHIFT = 1, buffer[i] is visually displayed at bar i+1.  |
//|                                                                    |
//| Therefore, the level shown at the CURRENT bar (bar 0 in time-     |
//| series) is the buffer value from bar 1, which was calculated       |
//| using the High/Low of the previous 'Period' bars ending at bar 1. |
//|                                                                    |
//| Implementation: CopyHigh/CopyLow starting from bar 1 for Period   |
//| bars, then find the max/min. This produces the exact same level    |
//| the user sees on their chart at the current bar position.          |
//+------------------------------------------------------------------+
bool GetDonchianLevels(ENUM_TIMEFRAMES tf, double &upper, double &lower)
  {
   double highArr[], lowArr[];

//--- Copy 'Period' bars of High data starting from bar index 1
//--- Bar 1 = last fully completed bar (not the current forming bar)
//--- This matches the indicator: buffer calculated from bars ending at
//--- the previous bar, then displayed one bar forward (PLOT_SHIFT = 1)
   if(CopyHigh(_Symbol, tf, 1, Period_of_Channel, highArr) != Period_of_Channel)
      return false;

   if(CopyLow(_Symbol, tf, 1, Period_of_Channel, lowArr) != Period_of_Channel)
      return false;

//--- Find highest high and lowest low in the range
   int highIdx = ArrayMaximum(highArr);
   int lowIdx  = ArrayMinimum(lowArr);

   if(highIdx < 0 || lowIdx < 0)
      return false;

   upper = highArr[highIdx];
   lower = lowArr[lowIdx];

   return true;
  }

//+------------------------------------------------------------------+
//| Check for trade signal across all 4 timeframes                     |
//|                                                                    |
//| STRICT SIMULTANEOUS TOUCH CONFIRMATION:                            |
//| - On each tick, evaluate ALL 4 timeframes independently            |
//| - A TF confirms only if the CURRENT live price is at/past the     |
//|   applicable Donchian level at THIS moment                         |
//| - NO touch memory: if a TF touched earlier and moved away, that   |
//|   old touch CANNOT be combined with current touches from others    |
//| - Signal is valid only if enough TFs confirm simultaneously        |
//|                                                                    |
//| Same Direction:    Upper -> BUY,  Lower -> SELL                   |
//| Inverse Direction: Upper -> SELL, Lower -> BUY                    |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE CheckSignal()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int buyConfirm  = 0;
   int sellConfirm = 0;

   for(int i = 0; i < 4; i++)
     {
      double upper, lower;

      //--- Get the shifted Donchian levels for this timeframe
      if(!GetDonchianLevels(g_timeframes[i], upper, lower))
         continue;

      //--- Check if current price reaches or passes the Upper Donchian level
      //--- "Reaches or passes" = price >= upper (no tolerance, no candle-close needed)
      if(bid >= upper)
        {
         if(Strategy_Mode == SameDirection)
            buyConfirm++;
         else  // InverseDirection
            sellConfirm++;
        }

      //--- Check if current price reaches or passes the Lower Donchian level
      //--- "Reaches or passes" = price <= lower (no tolerance, no candle-close needed)
      if(bid <= lower)
        {
         if(Strategy_Mode == SameDirection)
            sellConfirm++;
         else  // InverseDirection
            buyConfirm++;
        }
     }

//--- Check if enough timeframes confirm simultaneously
   if(buyConfirm >= g_confirmDir)
      return SIGNAL_BUY;

   if(sellConfirm >= g_confirmDir)
      return SIGNAL_SELL;

   return SIGNAL_NONE;
  }

//+------------------------------------------------------------------+
//| ==================== TRADE MANAGEMENT =========================== |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if this EA instance already has an open position             |
//| Maximum 1 open trade per EA instance/pair at a time               |
//| Identified by matching Symbol AND Magic_Number                     |
//+------------------------------------------------------------------+
bool HasOpenTrade()
  {
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == Magic_Number)
           {
            return true;
           }
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Open a trade with TP, SL, Magic Number, and Basket tag comment    |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_SIGNAL_TYPE signal)
  {
   if(signal == SIGNAL_NONE)
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tp  = 0;
   double sl  = 0;

//--- Build trade comment: basket tag + user's custom comment
   string comment = g_basketTag;
   if(Comment_Text != "")
      comment += " " + Comment_Text;

   if(signal == SIGNAL_BUY)
     {
      //--- Calculate TP and SL for BUY (0 = disabled)
      if(TP_Pips > 0)
         tp = NormalizeDouble(ask + TP_Pips * g_pipValue, _Digits);
      if(SL_Pips > 0)
         sl = NormalizeDouble(ask - SL_Pips * g_pipValue, _Digits);

      if(g_trade.Buy(LotSize, _Symbol, ask, sl, tp, comment))
        {
         Print(">>> BUY opened on ", _Symbol, " @ ", DoubleToString(ask, _Digits),
               " | TP: ", (tp > 0 ? DoubleToString(tp, _Digits) : "None"),
               " | SL: ", (sl > 0 ? DoubleToString(sl, _Digits) : "None"),
               " | Lot: ", DoubleToString(LotSize, 2));
         return true;
        }
      else
        {
         Print("!!! BUY FAILED on ", _Symbol, " | Error: ", GetLastError());
         return false;
        }
     }
   else
      if(signal == SIGNAL_SELL)
        {
         //--- Calculate TP and SL for SELL (0 = disabled)
         if(TP_Pips > 0)
            tp = NormalizeDouble(bid - TP_Pips * g_pipValue, _Digits);
         if(SL_Pips > 0)
            sl = NormalizeDouble(bid + SL_Pips * g_pipValue, _Digits);

         if(g_trade.Sell(LotSize, _Symbol, bid, sl, tp, comment))
           {
            Print(">>> SELL opened on ", _Symbol, " @ ", DoubleToString(bid, _Digits),
                  " | TP: ", (tp > 0 ? DoubleToString(tp, _Digits) : "None"),
                  " | SL: ", (sl > 0 ? DoubleToString(sl, _Digits) : "None"),
                  " | Lot: ", DoubleToString(LotSize, 2));
            return true;
           }
         else
           {
            Print("!!! SELL FAILED on ", _Symbol, " | Error: ", GetLastError());
            return false;
           }
        }

   return false;
  }

//+------------------------------------------------------------------+
//| ==================== BASKET MANAGEMENT ========================== |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate FLOATING Basket P/L (currently open positions only)      |
//| Scans ALL open positions across ALL symbols for basket tag         |
//+------------------------------------------------------------------+
double CalculateFloatingBasketPL()
  {
   double totalPL = 0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         string comment = PositionGetString(POSITION_COMMENT);

         if(StringFind(comment, g_basketTag) >= 0)
           {
            totalPL += PositionGetDouble(POSITION_PROFIT)
                       + PositionGetDouble(POSITION_SWAP);
           }
        }
     }

   return totalPL;
  }

//+------------------------------------------------------------------+
//| Calculate REALIZED Basket P/L (closed deals today)                 |
//|                                                                    |
//| CRITICAL FIX: Without this, trades that close via individual SL    |
//| are NOT counted toward the basket loss. This means cumulative      |
//| daily losses can far exceed the Max_Basket_Loss threshold.         |
//|                                                                    |
//| Algorithm:                                                         |
//| 1. Select all deals from today (00:00 server time to now)          |
//| 2. Find all OPENING deals with our basket tag in comment           |
//| 3. Collect their position IDs                                      |
//| 4. Sum profit/swap/commission from CLOSING deals of those positions|
//|                                                                    |
//| We check the OPENING deal's comment (not closing deal) because     |
//| MT5 may modify the closing deal comment (e.g., "[sl]", "[tp]").    |
//+------------------------------------------------------------------+
double CalculateRealizedBasketPL()
  {
//--- Get start of current trading day (00:00 server time)
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayStart = StructToTime(dt);

//--- Select deal history for today
   if(!HistorySelect(dayStart, TimeCurrent()))
      return 0;

   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0)
      return 0;

//--- First pass: collect position IDs from OPENING deals belonging to our basket
   ulong basketPosIds[];
   int   idCount = 0;

   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN)
         continue;

      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      if(StringFind(comment, g_basketTag) >= 0)
        {
         long posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         ArrayResize(basketPosIds, idCount + 1);
         basketPosIds[idCount] = (ulong)posId;
         idCount++;
        }
     }

   if(idCount == 0)
      return 0;

//--- Second pass: sum profit from CLOSING deals of basket positions
   double realizedPL = 0;

   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;

      long posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);

      //--- Check if this closing deal belongs to a basket position
      for(int j = 0; j < idCount; j++)
        {
         if(basketPosIds[j] == (ulong)posId)
           {
            realizedPL += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                          + HistoryDealGetDouble(ticket, DEAL_SWAP)
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            break;
           }
        }
     }

   return realizedPL;
  }

//+------------------------------------------------------------------+
//| Get cached realized P/L (only recalculates when deal count changes)|
//| This prevents calling HistorySelect on every single tick           |
//+------------------------------------------------------------------+
double GetCachedRealizedPL()
  {
//--- Get start of current trading day
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime dayStart = StructToTime(dt);

//--- Check if we need to reset cache for new day
   if(dayStart != g_cachedDate)
     {
      g_cachedDate       = dayStart;
      g_cachedRealizedPL = 0;
      g_lastDealCount    = -1;
     }

//--- Select history to check deal count
   if(!HistorySelect(dayStart, TimeCurrent()))
      return g_cachedRealizedPL;

   int currentDealCount = HistoryDealsTotal();

//--- Only recalculate if deal count changed (a new deal was added)
   if(currentDealCount != g_lastDealCount)
     {
      g_cachedRealizedPL = CalculateRealizedBasketPL();
      g_lastDealCount    = currentDealCount;
     }

   return g_cachedRealizedPL;
  }

//+------------------------------------------------------------------+
//| Calculate TOTAL Basket P/L = Floating + Realized for today         |
//| This is the key improvement: even after trades close at SL/TP,     |
//| the cumulative daily loss is tracked and enforced.                  |
//+------------------------------------------------------------------+
double CalculateTotalBasketPL()
  {
   double floatingPL = CalculateFloatingBasketPL();
   double realizedPL = GetCachedRealizedPL();
   return floatingPL + realizedPL;
  }

//+------------------------------------------------------------------+
//| Monitor Basket P/L and handle threshold events                     |
//|                                                                    |
//| Uses TOTAL P/L (floating + realized) so that cumulative daily      |
//| losses from trades that hit SL are counted toward the threshold.   |
//+------------------------------------------------------------------+
void MonitorBasketPL()
  {
   if(!Enable_Basket_Floating_PL)
      return;

//--- If another EA instance is already handling a basket close, skip
   if(GlobalVariableCheck(g_gvClosingName))
     {
      if(GlobalVariableGet(g_gvClosingName) > 0)
         return;
     }

//--- Skip if both thresholds are disabled
   if(Max_Basket_Loss_USD <= 0 && Max_Basket_Profit_USD <= 0)
      return;

//--- Calculate TOTAL basket P/L (floating + realized)
   double floatingPL = CalculateFloatingBasketPL();
   double realizedPL = GetCachedRealizedPL();
   double totalPL    = floatingPL + realizedPL;

   bool   shouldClose = false;
   string reason      = "";

//--- Check Max Basket Loss (using total P/L)
   if(Max_Basket_Loss_USD > 0 && totalPL <= -Max_Basket_Loss_USD)
     {
      shouldClose = true;
      reason = "MAX BASKET LOSS";
     }

//--- Check Max Basket Profit (using total P/L)
   if(Max_Basket_Profit_USD > 0 && totalPL >= Max_Basket_Profit_USD)
     {
      shouldClose = true;
      reason = "MAX BASKET PROFIT";
     }

   if(shouldClose)
     {
      //--- Atomically claim the closing flag (prevents duplicate close operations)
      if(!GlobalVariableSetOnCondition(g_gvClosingName, 1, 0))
         return;  // Another instance already claimed the close

      Print("==============================================");
      Print(reason, " REACHED!");
      Print("Total P/L: ", DoubleToString(totalPL, 2), " USD",
            " (Floating: ", DoubleToString(floatingPL, 2),
            " + Realized: ", DoubleToString(realizedPL, 2), ")");
      Print("Closing ALL open positions for Basket_ID: ", Basket_ID);

      //--- Close all currently open basket positions
      CloseAllBasketPositions();

      //--- Set the daily trading lock
      if(Lock_Trading_After_Target)
        {
         SetBasketLock();
         Print("Basket LOCKED for the remainder of the trading day");
        }

      Print("==============================================");

      //--- Release the closing flag
      GlobalVariableSet(g_gvClosingName, 0);

      //--- Invalidate the realized P/L cache (new deals from closing)
      g_lastDealCount = -1;
     }
  }

//+------------------------------------------------------------------+
//| Close ALL open positions belonging to this Basket_ID               |
//+------------------------------------------------------------------+
void CloseAllBasketPositions()
  {
   int total  = PositionsTotal();
   int closed = 0;
   int failed = 0;

//--- Close from last to first to prevent index shift problems
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         string comment = PositionGetString(POSITION_COMMENT);

         if(StringFind(comment, g_basketTag) >= 0)
           {
            string sym    = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);

            if(g_trade.PositionClose(ticket))
              {
               closed++;
               Print("  Closed #", ticket, " ", sym,
                     " P/L: ", DoubleToString(profit, 2));
              }
            else
              {
               failed++;
               Print("  FAILED to close #", ticket, " ", sym,
                     " | Error: ", GetLastError());
              }
           }
        }
     }

   Print("Basket close: ", closed, " closed, ", failed, " failed");
  }

//+------------------------------------------------------------------+
//| ==================== LOCK MANAGEMENT ============================ |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if the basket is currently locked for trading                |
//+------------------------------------------------------------------+
bool IsBasketLocked()
  {
   if(!GlobalVariableCheck(g_gvLockName))
      return false;

   return(GlobalVariableGet(g_gvLockName) > 0);
  }

//+------------------------------------------------------------------+
//| Set the basket lock with current server date                       |
//+------------------------------------------------------------------+
void SetBasketLock()
  {
   GlobalVariableSet(g_gvLockName, 1);

   MqlDateTime dt;
   TimeCurrent(dt);
   double dateVal = dt.year * 10000.0 + dt.mon * 100.0 + dt.day;
   GlobalVariableSet(g_gvLockDateName, dateVal);
  }

//+------------------------------------------------------------------+
//| Clear the basket lock                                              |
//+------------------------------------------------------------------+
void ClearBasketLock()
  {
   GlobalVariableSet(g_gvLockName, 0);
   GlobalVariableSet(g_gvLockDateName, 0);
   GlobalVariableSet(g_gvClosingName, 0);
  }

//+------------------------------------------------------------------+
//| Check for automatic daily reset at 00:00 broker/server time        |
//+------------------------------------------------------------------+
void CheckDailyReset()
  {
   if(!IsBasketLocked())
      return;

   MqlDateTime dt_now;
   TimeCurrent(dt_now);
   double currentDate = dt_now.year * 10000.0 + dt_now.mon * 100.0 + dt_now.day;

   double lockDate = 0;
   if(GlobalVariableCheck(g_gvLockDateName))
      lockDate = GlobalVariableGet(g_gvLockDateName);

   if(lockDate > 0 && currentDate > lockDate)
     {
      ClearBasketLock();

      //--- Also reset the realized P/L cache for the new day
      g_cachedRealizedPL = 0;
      g_lastDealCount    = -1;

      Print("Basket lock AUTO-RESET for new trading day");
      Print("Basket_ID: ", Basket_ID,
            " | New date: ", dt_now.year, ".", dt_now.mon, ".", dt_now.day);
     }
  }

//+------------------------------------------------------------------+
//| ==================== UTILITIES ================================== |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get pip value based on symbol digits                               |
//+------------------------------------------------------------------+
double GetPipValue()
  {
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(digits == 3 || digits == 5)
      return point * 10;
   else
      return point;
  }

//+------------------------------------------------------------------+
//| Auto-detect the appropriate order filling mode for this broker     |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFillingMode()
  {
   long fillMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| ==================== VISUALIZATION ============================== |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Draw Donchian Channel lines & price labels on the chart          |
//| If the indicator is attached via ChartIndicatorAdd, it draws     |
//| the continuous lines natively. If not, this fallback function    |
//| renders the stepped lines (Blue Upper, Gray Middle, Red Lower)   |
//| directly on the chart candles along with the right price tags.   |
//+------------------------------------------------------------------+
void DrawDonchianChannel()
  {
   //--- If native indicator was successfully attached, it handles line drawing
   if(g_indHandle != INVALID_HANDLE)
      return;

   //--- Fallback: draw channel lines directly on the chart candles
   int barsToDraw = 120;
   datetime times[];
   double   highs[], lows[];

   if(CopyTime(_Symbol, PERIOD_CURRENT, 0, barsToDraw + Period_of_Channel + 2, times) <= 0) return;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, barsToDraw + Period_of_Channel + 2, highs) <= 0) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, barsToDraw + Period_of_Channel + 2, lows) <= 0)   return;

   ArraySetAsSeries(times, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   //--- Calculate and draw stepped lines for the last N bars (PLOT_SHIFT = 1)
   for(int i = 0; i < barsToDraw - 1; i++)
     {
      int hIdx = ArrayMaximum(highs, i + 1, Period_of_Channel);
      int lIdx = ArrayMinimum(lows, i + 1, Period_of_Channel);
      if(hIdx < 0 || lIdx < 0) continue;

      double up = highs[hIdx];
      double dn = lows[lIdx];
      double md = (up + dn) / 2.0;

      string upName = g_objPrefix + "LUp_" + IntegerToString(i);
      string mdName = g_objPrefix + "LMd_" + IntegerToString(i);
      string dnName = g_objPrefix + "LDn_" + IntegerToString(i);

      DrawTrendSegment(upName, times[i + 1], up, times[i], up, clrBlue, 2, STYLE_SOLID);
      DrawTrendSegment(mdName, times[i + 1], md, times[i], md, clrGray, 1, STYLE_DOT);
      DrawTrendSegment(dnName, times[i + 1], dn, times[i], dn, clrRed, 2, STYLE_SOLID);
     }

   //--- Draw right price labels at the latest bar (matching indicator style)
   if(Showprice_of_the_Level)
     {
      int h0 = ArrayMaximum(highs, 1, Period_of_Channel);
      int l0 = ArrayMinimum(lows, 1, Period_of_Channel);
      if(h0 >= 0 && l0 >= 0)
        {
         double up0 = highs[h0];
         double dn0 = lows[l0];
         double md0 = (up0 + dn0) / 2.0;
         CreatePriceLabel(g_objPrefix + "Price_UP", times[0], up0, clrBlue);
         CreatePriceLabel(g_objPrefix + "Price_MD", times[0], md0, clrGray);
         CreatePriceLabel(g_objPrefix + "Price_DN", times[0], dn0, clrRed);
        }
     }
  }

//+------------------------------------------------------------------+
//| Draw a trendline segment for channel line fallback               |
//+------------------------------------------------------------------+
void DrawTrendSegment(const string name, datetime t1, double p1, datetime t2, double p2, color clr, int width, ENUM_LINE_STYLE style)
  {
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Create or update a right-price-label on the chart                  |
//| Matches the style used by the supplied Donchian Channel indicator   |
//+------------------------------------------------------------------+
void CreatePriceLabel(const string name, datetime time, double price, color clr)
  {
   if(!ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, time, price))
     {
      //--- Object already exists, just move it
      ObjectMove(0, name, 0, time, price);
     }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
  }

//+------------------------------------------------------------------+
//| Draw a BUY or SELL arrow on the chart when a signal fires          |
//+------------------------------------------------------------------+
void DrawSignalArrow(ENUM_SIGNAL_TYPE signal, double price)
  {
   string name = g_objPrefix + "Sig_" + IntegerToString((int)GetTickCount64());
   int    code = 0;
   color  clr  = clrWhite;

   if(signal == SIGNAL_BUY)
     {
      code = 233;  // Up arrow wingdings
      clr  = clrLime;
      //--- Place arrow slightly below the price for BUY
      price -= 2 * g_pipValue;
     }
   else
      if(signal == SIGNAL_SELL)
        {
         code = 234;  // Down arrow wingdings
         clr  = clrRed;
         //--- Place arrow slightly above the price for SELL
         price += 2 * g_pipValue;
        }
      else
         return;

   if(ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price))
     {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//| Update chart display panel with comprehensive info                 |
//+------------------------------------------------------------------+
void UpdateChartDisplay()
  {
   string nl = "\n";
   string display = "";

   display += "===  DONCHIAN CHANNEL EA v1.10  ===" + nl;
   display += _Symbol + "  |  Magic: " + IntegerToString(Magic_Number) + nl;
   display += "Mode: " + EnumToString(Strategy_Mode)
              + "  |  Confirm: " + IntegerToString(g_confirmDir) + "/4" + nl;
   display += "-------------------------------------" + nl;

//--- Show Donchian levels for each timeframe with touch status
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = 0; i < 4; i++)
     {
      double upper, lower;
      string tfName = EnumToString(g_timeframes[i]);

      if(GetDonchianLevels(g_timeframes[i], upper, lower))
        {
         string touchUpper = (bid >= upper) ? " << HIT" : "";
         string touchLower = (bid <= lower) ? " << HIT" : "";

         display += tfName + ":  UP " + DoubleToString(upper, _Digits) + touchUpper + nl;
         display += "          DN " + DoubleToString(lower, _Digits) + touchLower + nl;
        }
      else
        {
         display += tfName + ":  Waiting for data..." + nl;
        }
     }

//--- Show basket information
   if(Enable_Basket_Floating_PL)
     {
      display += "-------------------------------------" + nl;
      display += "BASKET ID: " + IntegerToString(Basket_ID) + nl;

      double floatingPL = CalculateFloatingBasketPL();
      double realizedPL = GetCachedRealizedPL();
      double totalPL    = floatingPL + realizedPL;

      string sign = (totalPL >= 0) ? "+" : "";
      display += "Total P/L:    " + sign + DoubleToString(totalPL, 2) + " USD" + nl;
      display += "  Floating:   " + DoubleToString(floatingPL, 2) + " USD" + nl;
      display += "  Realized:   " + DoubleToString(realizedPL, 2) + " USD" + nl;

      if(Max_Basket_Loss_USD > 0)
         display += "Max Loss:     -" + DoubleToString(Max_Basket_Loss_USD, 2) + " USD" + nl;
      if(Max_Basket_Profit_USD > 0)
         display += "Max Profit:   +" + DoubleToString(Max_Basket_Profit_USD, 2) + " USD" + nl;

      if(IsBasketLocked())
         display += "Status: >>> LOCKED <<<" + nl;
      else
         display += "Status: ACTIVE" + nl;
     }

   display += "-------------------------------------" + nl;
   display += "Bid: " + DoubleToString(bid, _Digits) + nl;

   Comment(display);
  }

//+------------------------------------------------------------------+
//| Remove all chart objects created by this EA instance               |
//+------------------------------------------------------------------+
void CleanupChartObjects()
  {
   ObjectsDeleteAll(0, g_objPrefix);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
