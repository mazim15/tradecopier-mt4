//+------------------------------------------------------------------+
//|                                                 RangeTrader.mq4   |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "Your Website"
#property version   "1.00"
#property strict

// Input Parameters
input string TimeSettings = "===== Range Time Settings =====";
input int RangeStartHour = 0;
input int RangeStartMinute = 0;
input int RangeEndHour = 1;
input int RangeEndMinute = 0;
input int ClosePendingOrdersAt = 0;  // Hour to close pending orders (0=disabled)

input string OrderSettings = "===== Order Settings =====";
input bool UseMarketExecution = false;  // Use market execution instead of pending orders
input int ExecutionDelay = 0;          // Delay in seconds before executing market orders (0=immediate)
input double LotSize = 0.1;
input int Slippage = 3;
input int StopLoss = 50;
input int TakeProfit = 100;

input string TrailingSettings = "===== Trailing Settings =====";
input int PipsToBreakeven = 20;     // Pips needed to move to breakeven
input int PipsToMoveBeAt = 0;       // Pips above entry to move SL to
input int PipsToTrail = 30;         // Pips needed to activate trailing
input int PipsToMoveWhenTrail = 10; // Pips to trail behind price

// Update panel settings
input string PanelSettings = "===== Panel Settings =====";
input bool ShowPanel = true;
input string PanelTitle = "GBPUSD Robot";  // Updated title
input color PanelBackColor = C'16,18,27';  // Darker navy background
input color PanelTextColor = White;
input color ProfitColor = Lime;
input color LossColor = Red;
input color ButtonColor = C'0,174,239';  // Bright blue for buttons
input color SeparatorColor = C'40,42,54';  // Color for separator lines

// Global Variables
double g_rangeHigh = 0;
double g_rangeLow = 0;
bool g_rangeEnded = false;
int g_buyTicket = 0;
int g_sellTicket = 0;
datetime g_lastTrailingCheck = 0;
int g_magicNumber = 12345;
int g_lastTradeDay = 0;  // Track the day when we last placed orders

// Add these global variables
string g_tradingSession = "";
double g_dailyProfit = 0;
double g_dailyPips = 0;
double g_dailyHigh = 0;
double g_dailyLow = 0;
int g_panelID = 0;
bool g_buyLineTriggered = false;  // Track if buy line was triggered
bool g_sellLineTriggered = false; // Track if sell line was triggered
datetime g_buyLineTouchTime = 0;  // Time when buy line was touched
datetime g_sellLineTouchTime = 0; // Time when sell line was touched
bool g_buyOrderPending = false;   // Flag for pending delayed buy order
bool g_sellOrderPending = false;  // Flag for pending delayed sell order

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Reset variables
   g_rangeHigh = 0;
   g_rangeLow = 0;
   g_rangeEnded = false;
   g_buyTicket = 0;
   g_sellTicket = 0;
   g_lastTradeDay = TimeDay(TimeCurrent());
   g_buyLineTriggered = false;
   g_sellLineTriggered = false;
   g_buyLineTouchTime = 0;
   g_sellLineTouchTime = 0;
   g_buyOrderPending = false;
   g_sellOrderPending = false;
   
   // Initialize panel
   if(ShowPanel)
   {
      CreatePanel();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete pending orders when EA is removed
   DeletePendingOrders();
   
   // Delete range lines
   DeleteRangeLines();
   
   // Delete panel objects
   if(ShowPanel)
   {
      DeletePanel();
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if it's a new day and reset range if needed
   CheckForNewDay();
   
   // Get current time information
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   int currentMinute = TimeMinute(currentTime);
   
   // Debug logging - REMOVED or COMMENTED OUT to reduce journal spam
   // if(currentMinute == 0 && currentHour % 1 == 0) // Log once per hour
   // {
   //    Print("Current time: ", TimeToString(currentTime), 
   //          " Range period: ", IsRangePeriod() ? "Yes" : "No",
   //          " Range ended: ", g_rangeEnded ? "Yes" : "No",
   //          " Has position: ", HasOpenPosition() ? "Yes" : "No");
   // }
   
   // Check if we're in the range period
   if(IsRangePeriod())
   {
      // Update range high and low
      UpdateRange();
      g_rangeEnded = false;
      
      // Remove any existing range lines when still in range period
      if(UseMarketExecution)
      {
         DeleteRangeLines();
         g_buyLineTriggered = false;
         g_sellLineTriggered = false;
      }
   }
   else if(!g_rangeEnded && !HasOpenPosition())
   {
      // Only place orders if the range period has just ended AND we don't have open positions
      
      // Make sure we have valid range values before placing orders
      if(g_rangeHigh > 0 && g_rangeLow > 0 && g_rangeHigh > g_rangeLow)
      {
         if(UseMarketExecution)
         {
            // Draw lines at range boundaries for market execution
            DrawRangeLines();
            Print("Range ended. Drawing lines at High=", g_rangeHigh, " Low=", g_rangeLow);
         }
         else
         {
            // Place pending orders at range boundaries
            PlaceRangeOrders();
         }
         
         g_rangeEnded = true;
         
         // Store the current day when we placed orders or drew lines
         g_lastTradeDay = TimeDay(currentTime);
      }
      else
      {
         // Only print this message once when range ends to avoid spam
         static datetime lastErrorLog = 0;
         if(currentTime - lastErrorLog > 3600) // Log at most once per hour
         {
            Print("Invalid range values. High=", g_rangeHigh, " Low=", g_rangeLow);
            lastErrorLog = currentTime;
         }
      }
   }
   
   // Check if one order was triggered and delete the other
   if(!UseMarketExecution)
   {
      CheckAndDeleteOppositePendingOrder();
   }
   else
   {
      // Check if price touches range lines and execute market orders
      CheckAndExecuteMarketOrders();
   }
   
   // Check if it's time to close pending orders or remove range lines
   if(ClosePendingOrdersAt > 0)
   {
      if(UseMarketExecution)
      {
         CheckTimeToRemoveRangeLines();
      }
      else
      {
         CheckTimeToClosePendingOrders();
      }
   }
   
   // Manage open positions (trailing, breakeven)
   ManagePositions();
   
   // Update panel information
   if(ShowPanel)
   {
      UpdatePanelInfo();
      UpdatePanel();
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within range period                     |
//+------------------------------------------------------------------+
bool IsRangePeriod()
{
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   int currentMinute = TimeMinute(currentTime);
   int currentDay = TimeDay(currentTime);
   
   // Convert all times to minutes for easier comparison
   int currentTimeInMinutes = currentHour * 60 + currentMinute;
   int rangeStartInMinutes = RangeStartHour * 60 + RangeStartMinute;
   int rangeEndInMinutes = RangeEndHour * 60 + RangeEndMinute;
   
   // If we already have an open position for today, we're not in range period
   if(HasOpenPositionForToday())
   {
      return false;
   }
   
   // Handle case where range crosses midnight
   if(rangeStartInMinutes <= rangeEndInMinutes)
   {
      return (currentTimeInMinutes >= rangeStartInMinutes && currentTimeInMinutes < rangeEndInMinutes);
   }
   else
   {
      return (currentTimeInMinutes >= rangeStartInMinutes || currentTimeInMinutes < rangeEndInMinutes);
   }
}

//+------------------------------------------------------------------+
//| Check if we have an open position that was opened today          |
//+------------------------------------------------------------------+
bool HasOpenPositionForToday()
{
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         // Check if this is our order for this symbol
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber)
         {
            // Check if it's a market order (not pending) opened today
            if((OrderType() == OP_BUY || OrderType() == OP_SELL) && OrderOpenTime() >= todayStart)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update the high and low of the range                             |
//+------------------------------------------------------------------+
void UpdateRange()
{
   double currentHigh = High[0];
   double currentLow = Low[0];
   
   // Initialize range values if they're zero
   if(g_rangeHigh == 0 || g_rangeLow == 0)
   {
      g_rangeHigh = currentHigh;
      g_rangeLow = currentLow;
      return;
   }
   
   // Update range high and low
   if(currentHigh > g_rangeHigh) g_rangeHigh = currentHigh;
   if(currentLow < g_rangeLow) g_rangeLow = currentLow;
}

//+------------------------------------------------------------------+
//| Place buy stop and sell stop orders at range boundaries          |
//+------------------------------------------------------------------+
void PlaceRangeOrders()
{
   // Delete any existing pending orders first
   DeletePendingOrders();
   
   // Calculate stop loss and take profit levels
   double buyStopLoss = g_rangeHigh - StopLoss * Point * 10;
   double buyTakeProfit = g_rangeHigh + TakeProfit * Point * 10;
   
   double sellStopLoss = g_rangeLow + StopLoss * Point * 10;
   double sellTakeProfit = g_rangeLow - TakeProfit * Point * 10;
   
   // Place buy stop order at range high
   g_buyTicket = OrderSend(
      Symbol(),
      OP_BUYSTOP,
      LotSize,
      g_rangeHigh,
      Slippage,
      buyStopLoss,
      buyTakeProfit,
      "Range Buy",
      g_magicNumber,
      0,
      clrGreen
   );
   
   if(g_buyTicket < 0)
   {
      Print("Error placing buy stop order: ", GetLastError());
   }
   
   // Place sell stop order at range low
   g_sellTicket = OrderSend(
      Symbol(),
      OP_SELLSTOP,
      LotSize,
      g_rangeLow,
      Slippage,
      sellStopLoss,
      sellTakeProfit,
      "Range Sell",
      g_magicNumber,
      0,
      clrRed
   );
   
   if(g_sellTicket < 0)
   {
      Print("Error placing sell stop order: ", GetLastError());
   }
   
   Print("Range: High=", g_rangeHigh, " Low=", g_rangeLow);
   Print("Orders placed: Buy Ticket=", g_buyTicket, " Sell Ticket=", g_sellTicket);
}

//+------------------------------------------------------------------+
//| Delete all pending orders for this EA                            |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber)
         {
            if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
            {
               OrderDelete(OrderTicket());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (trailing, breakeven)                      |
//+------------------------------------------------------------------+
void ManagePositions()
{
   // Check once per second to avoid excessive processing
   if(TimeCurrent() - g_lastTrailingCheck < 1) return;
   g_lastTrailingCheck = TimeCurrent();
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber)
         {
            // Only manage market orders (not pending)
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
            {
               // Apply breakeven and trailing logic
               if(OrderType() == OP_BUY)
               {
                  ManageBuyPosition();
               }
               else if(OrderType() == OP_SELL)
               {
                  ManageSellPosition();
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage buy position (breakeven and trailing)                     |
//+------------------------------------------------------------------+
void ManageBuyPosition()
{
   double currentPrice = Bid;
   double openPrice = OrderOpenPrice();
   double stopLoss = OrderStopLoss();
   double pipsProfit = (currentPrice - openPrice) / (Point * 10);
   
   // Check for breakeven
   if(PipsToBreakeven > 0 && pipsProfit >= PipsToBreakeven && (stopLoss < openPrice + PipsToMoveBeAt * Point * 10))
   {
      double newStopLoss = openPrice + PipsToMoveBeAt * Point * 10;
      ModifyStopLoss(newStopLoss);
      Print("Moving buy order to breakeven. New SL: ", newStopLoss);
   }
   
   // Check for trailing stop
   if(PipsToTrail > 0 && pipsProfit >= PipsToTrail)
   {
      double trailLevel = currentPrice - PipsToMoveWhenTrail * Point * 10;
      if(stopLoss < trailLevel)
      {
         ModifyStopLoss(trailLevel);
         Print("Trailing buy order. New SL: ", trailLevel);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage sell position (breakeven and trailing)                    |
//+------------------------------------------------------------------+
void ManageSellPosition()
{
   double currentPrice = Ask;
   double openPrice = OrderOpenPrice();
   double stopLoss = OrderStopLoss();
   double pipsProfit = (openPrice - currentPrice) / (Point * 10);
   
   // Check for breakeven
   if(PipsToBreakeven > 0 && pipsProfit >= PipsToBreakeven && (stopLoss > openPrice - PipsToMoveBeAt * Point * 10 || stopLoss == 0))
   {
      double newStopLoss = openPrice - PipsToMoveBeAt * Point * 10;
      ModifyStopLoss(newStopLoss);
      Print("Moving sell order to breakeven. New SL: ", newStopLoss);
   }
   
   // Check for trailing stop
   if(PipsToTrail > 0 && pipsProfit >= PipsToTrail)
   {
      double trailLevel = currentPrice + PipsToMoveWhenTrail * Point * 10;
      if(stopLoss > trailLevel || stopLoss == 0)
      {
         ModifyStopLoss(trailLevel);
         Print("Trailing sell order. New SL: ", trailLevel);
      }
   }
}

//+------------------------------------------------------------------+
//| Modify stop loss for current selected order                      |
//+------------------------------------------------------------------+
void ModifyStopLoss(double newStopLoss)
{
   bool result = OrderModify(
      OrderTicket(),
      OrderOpenPrice(),
      newStopLoss,
      OrderTakeProfit(),
      0,
      clrBlue
   );
   
   if(!result)
   {
      Print("Error modifying order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check if one order was triggered and delete the opposite one     |
//+------------------------------------------------------------------+
void CheckAndDeleteOppositePendingOrder()
{
   bool buyOrderActive = false;
   bool sellOrderActive = false;
   bool buyOrderTriggered = false;
   bool sellOrderTriggered = false;
   
   // First check if our pending orders are still active
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber)
         {
            if(OrderType() == OP_BUYSTOP && OrderTicket() == g_buyTicket)
            {
               buyOrderActive = true;
            }
            else if(OrderType() == OP_SELLSTOP && OrderTicket() == g_sellTicket)
            {
               sellOrderActive = true;
            }
            else if(OrderType() == OP_BUY && OrderComment() == "Range Buy")
            {
               buyOrderTriggered = true;
            }
            else if(OrderType() == OP_SELL && OrderComment() == "Range Sell")
            {
               sellOrderTriggered = true;
            }
         }
      }
   }
   
   // If buy order was triggered, delete sell pending order
   if(buyOrderTriggered && sellOrderActive)
   {
      if(OrderSelect(g_sellTicket, SELECT_BY_TICKET))
      {
         if(OrderType() == OP_SELLSTOP)
         {
            if(OrderDelete(g_sellTicket))
            {
               Print("Sell stop order deleted because buy order was triggered");
               g_sellTicket = 0;
            }
            else
            {
               Print("Error deleting sell stop order: ", GetLastError());
            }
         }
      }
   }
   
   // If sell order was triggered, delete buy pending order
   if(sellOrderTriggered && buyOrderActive)
   {
      if(OrderSelect(g_buyTicket, SELECT_BY_TICKET))
      {
         if(OrderType() == OP_BUYSTOP)
         {
            if(OrderDelete(g_buyTicket))
            {
               Print("Buy stop order deleted because sell order was triggered");
               g_buyTicket = 0;
            }
            else
            {
               Print("Error deleting buy stop order: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if it's time to close pending orders                       |
//+------------------------------------------------------------------+
void CheckTimeToClosePendingOrders()
{
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   
   // If current hour matches the closing hour, delete pending orders
   if(currentHour == ClosePendingOrdersAt)
   {
      bool ordersDeleted = false;
      
      // Check if buy stop order is still active
      if(g_buyTicket > 0)
      {
         if(OrderSelect(g_buyTicket, SELECT_BY_TICKET))
         {
            if(OrderType() == OP_BUYSTOP)
            {
               if(OrderDelete(g_buyTicket))
               {
                  Print("Buy stop order deleted at specified hour: ", ClosePendingOrdersAt);
                  g_buyTicket = 0;
                  ordersDeleted = true;
               }
            }
         }
      }
      
      // Check if sell stop order is still active
      if(g_sellTicket > 0)
      {
         if(OrderSelect(g_sellTicket, SELECT_BY_TICKET))
         {
            if(OrderType() == OP_SELLSTOP)
            {
               if(OrderDelete(g_sellTicket))
               {
                  Print("Sell stop order deleted at specified hour: ", ClosePendingOrdersAt);
                  g_sellTicket = 0;
                  ordersDeleted = true;
               }
            }
         }
      }
      
      // If orders were deleted, reset range ended flag to prepare for next day
      if(ordersDeleted)
      {
         g_rangeEnded = false;
         g_rangeHigh = 0;
         g_rangeLow = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if it's a new day and reset range values if needed         |
//+------------------------------------------------------------------+
void CheckForNewDay()
{
   static datetime lastResetTime = 0;
   datetime currentTime = TimeCurrent();
   int currentDay = TimeDay(currentTime);
   
   // Only check once per hour to avoid excessive processing
   if(currentTime - lastResetTime < 3600) return;
   
   // If it's a new day and we're not in the range period
   if(currentDay != g_lastTradeDay)
   {
      // Only reset if we don't have open positions from today
      if(!HasOpenPositionForToday() && IsNewTradingSession())
      {
         g_rangeHigh = 0;
         g_rangeLow = 0;
         g_rangeEnded = false;
         g_buyLineTriggered = false;
         g_sellLineTriggered = false;
         g_buyLineTouchTime = 0;
         g_sellLineTouchTime = 0;
         g_buyOrderPending = false;
         g_sellOrderPending = false;
         
         // Delete any existing range lines
         if(UseMarketExecution)
         {
            DeleteRangeLines();
         }
         
         g_lastTradeDay = currentDay;
         lastResetTime = currentTime;
         Print("New day detected. Range values reset at ", TimeToString(currentTime));
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we're in a new trading session                          |
//+------------------------------------------------------------------+
bool IsNewTradingSession()
{
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   
   // Consider it a new session if we're at the range start hour
   return (currentHour == RangeStartHour);
}

//+------------------------------------------------------------------+
//| Create the information panel                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
   g_panelID = WindowFind(PanelTitle);
   if(g_panelID == -1)
   {
      g_panelID = 0;
   }
   
   // Create panel background
   ObjectCreate("PanelBG", OBJ_RECTANGLE_LABEL, g_panelID, 0, 0);
   ObjectSet("PanelBG", OBJPROP_CORNER, 0);
   ObjectSet("PanelBG", OBJPROP_XDISTANCE, 10);
   ObjectSet("PanelBG", OBJPROP_YDISTANCE, 20);
   ObjectSet("PanelBG", OBJPROP_XSIZE, 400);     // Keep the width
   ObjectSet("PanelBG", OBJPROP_YSIZE, 180);     // Keep the height
   ObjectSet("PanelBG", OBJPROP_BGCOLOR, PanelBackColor);
   ObjectSet("PanelBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSet("PanelBG", OBJPROP_COLOR, PanelTextColor);
   ObjectSet("PanelBG", OBJPROP_WIDTH, 1);
   ObjectSet("PanelBG", OBJPROP_BACK, false);
   
   // Create title
   ObjectCreate("PanelTitle", OBJ_LABEL, g_panelID, 0, 0);
   ObjectSet("PanelTitle", OBJPROP_CORNER, 0);
   ObjectSet("PanelTitle", OBJPROP_XDISTANCE, 200);  // Center the title
   ObjectSet("PanelTitle", OBJPROP_YDISTANCE, 35);   // Keep position
   ObjectSetText("PanelTitle", PanelTitle, 10, "Arial Bold", PanelTextColor);  // Decreased from 12 to 10
   
   // First row - Daily Profit and Pips
   CreatePanelLabel("DailyProfitLabel", "Daily Profit:", 30, 65);
   CreatePanelLabel("DailyProfitValue", "0.00", 140, 65, ProfitColor);
   
   CreatePanelLabel("DailyPipsLabel", "Daily Pips:", 230, 65);
   CreatePanelLabel("DailyPipsValue", "0.0", 330, 65, ProfitColor);
   
   // Second row - Trading Session and Spread
   CreatePanelLabel("SessionLabel", "Trading Session:", 30, 95);
   CreatePanelLabel("SessionValue", "Asian", 160, 95);
   
   CreatePanelLabel("SpreadLabel", "Current spread:", 230, 95);
   CreatePanelLabel("SpreadValue", "0.8", 340, 95);
   
   // Third row - Daily Low and High
   CreatePanelLabel("DailyLowLabel", "Daily Low:", 30, 125);
   CreatePanelLabel("DailyLowValue", "0.00000", 140, 125);
   
   CreatePanelLabel("DailyHighLabel", "Daily High:", 230, 125);
   CreatePanelLabel("DailyHighValue", "0.00000", 330, 125);
   
   // Create buttons - bottom row
   CreatePanelButton("AllPositionsBtn", "All positions", 30, 155, 105);
   CreatePanelButton("ProfitsBtn", "Profits", 150, 155, 105);
   CreatePanelButton("LossesBtn", "Losses", 270, 155, 105);
}

//+------------------------------------------------------------------+
//| Create a label for the panel                                     |
//+------------------------------------------------------------------+
void CreatePanelLabel(string name, string text, int x, int y, color textColor = CLR_NONE)
{
   ObjectCreate(name, OBJ_LABEL, g_panelID, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, 0);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   
   if(textColor == CLR_NONE) textColor = PanelTextColor;
   ObjectSetText(name, text, 9, "Arial", textColor);  // Decreased from 11 to 9
}

//+------------------------------------------------------------------+
//| Create a button for the panel                                    |
//+------------------------------------------------------------------+
void CreatePanelButton(string name, string text, int x, int y, int width)
{
   ObjectCreate(name, OBJ_BUTTON, g_panelID, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, 0);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSet(name, OBJPROP_XSIZE, width);
   ObjectSet(name, OBJPROP_YSIZE, 22);  // Decreased from 25 to 22
   ObjectSetText(name, text, 9, "Arial Bold", PanelTextColor);  // Decreased from 10 to 9
   
   // Set different colors for buttons
   if(name == "AllPositionsBtn")
      ObjectSet(name, OBJPROP_BGCOLOR, C'0,174,239');  // Blue
   else if(name == "ProfitsBtn")
      ObjectSet(name, OBJPROP_BGCOLOR, C'0,204,0');    // Green
   else if(name == "LossesBtn")
      ObjectSet(name, OBJPROP_BGCOLOR, C'255,0,0');    // Red
      
   ObjectSet(name, OBJPROP_BORDER_COLOR, PanelTextColor);
}

//+------------------------------------------------------------------+
//| Delete the panel and all its objects                             |
//+------------------------------------------------------------------+
void DeletePanel()
{
   ObjectDelete("PanelBG");
   ObjectDelete("PanelTitle");
   ObjectDelete("DailyProfitLabel");
   ObjectDelete("DailyProfitValue");
   ObjectDelete("DailyPipsLabel");
   ObjectDelete("DailyPipsValue");
   ObjectDelete("SessionLabel");
   ObjectDelete("SessionValue");
   ObjectDelete("SpreadLabel");
   ObjectDelete("SpreadValue");
   ObjectDelete("DailyLowLabel");
   ObjectDelete("DailyLowValue");
   ObjectDelete("DailyHighLabel");
   ObjectDelete("DailyHighValue");
   ObjectDelete("AllPositionsBtn");
   ObjectDelete("ProfitsBtn");
   ObjectDelete("LossesBtn");
}

//+------------------------------------------------------------------+
//| Update panel information                                         |
//+------------------------------------------------------------------+
void UpdatePanelInfo()
{
   // Update daily high and low
   g_dailyHigh = iHigh(Symbol(), PERIOD_D1, 0);
   g_dailyLow = iLow(Symbol(), PERIOD_D1, 0);
   
   // Determine current trading session
   int currentHour = TimeHour(TimeCurrent());
   if(currentHour >= 0 && currentHour < 8)
      g_tradingSession = "Asian";
   else if(currentHour >= 8 && currentHour < 16)
      g_tradingSession = "European";
   else
      g_tradingSession = "American";
   
   // Calculate daily profit and pips
   CalculateDailyProfitAndPips();
}

//+------------------------------------------------------------------+
//| Calculate daily profit and pips                                  |
//+------------------------------------------------------------------+
void CalculateDailyProfitAndPips()
{
   g_dailyProfit = 0;
   g_dailyPips = 0;
   
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   
   // Check closed orders first
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber && OrderCloseTime() >= todayStart)
         {
            g_dailyProfit += OrderProfit() + OrderSwap() + OrderCommission();
            
            // Calculate pips
            if(OrderType() == OP_BUY)
               g_dailyPips += (OrderClosePrice() - OrderOpenPrice()) / (Point * 10);
            else if(OrderType() == OP_SELL)
               g_dailyPips += (OrderOpenPrice() - OrderClosePrice()) / (Point * 10);
         }
      }
   }
   
   // Check open orders
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber && OrderOpenTime() >= todayStart)
         {
            g_dailyProfit += OrderProfit() + OrderSwap() + OrderCommission();
            
            // Calculate pips
            double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
            
            if(OrderType() == OP_BUY)
               g_dailyPips += (currentPrice - OrderOpenPrice()) / (Point * 10);
            else if(OrderType() == OP_SELL)
               g_dailyPips += (OrderOpenPrice() - currentPrice) / (Point * 10);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update the panel display                                         |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   // Update profit with color based on value
   color profitColor = (g_dailyProfit >= 0) ? ProfitColor : LossColor;
   ObjectSetText("DailyProfitValue", DoubleToString(g_dailyProfit, 2), 9, "Arial", profitColor);  // Decreased from 11 to 9
   
   // Update pips with color based on value
   color pipsColor = (g_dailyPips >= 0) ? ProfitColor : LossColor;
   ObjectSetText("DailyPipsValue", DoubleToString(g_dailyPips, 1), 9, "Arial", pipsColor);  // Decreased from 11 to 9
   
   // Update other values
   ObjectSetText("SessionValue", g_tradingSession, 9, "Arial", PanelTextColor);  // Decreased from 11 to 9
   ObjectSetText("SpreadValue", DoubleToString(MarketInfo(Symbol(), MODE_SPREAD) / 10, 1), 9, "Arial", PanelTextColor);  // Decreased from 11 to 9
   ObjectSetText("DailyLowValue", DoubleToString(g_dailyLow, 5), 9, "Arial", PanelTextColor);  // Decreased from 11 to 9
   ObjectSetText("DailyHighValue", DoubleToString(g_dailyHigh, 5), 9, "Arial", PanelTextColor);  // Decreased from 11 to 9
}

//+------------------------------------------------------------------+
//| Draw lines at range boundaries                                   |
//+------------------------------------------------------------------+
void DrawRangeLines()
{
   // Delete any existing range lines first
   DeleteRangeLines();
   
   // Draw buy line at range high
   ObjectCreate("RangeBuyLine", OBJ_HLINE, 0, 0, g_rangeHigh);
   ObjectSet("RangeBuyLine", OBJPROP_COLOR, clrGreen);
   ObjectSet("RangeBuyLine", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet("RangeBuyLine", OBJPROP_WIDTH, 2);
   
   // Draw sell line at range low
   ObjectCreate("RangeSellLine", OBJ_HLINE, 0, 0, g_rangeLow);
   ObjectSet("RangeSellLine", OBJPROP_COLOR, clrRed);
   ObjectSet("RangeSellLine", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet("RangeSellLine", OBJPROP_WIDTH, 2);
   
   Print("Range lines drawn: High=", g_rangeHigh, " Low=", g_rangeLow);
}

//+------------------------------------------------------------------+
//| Delete range lines                                               |
//+------------------------------------------------------------------+
void DeleteRangeLines()
{
   ObjectDelete("RangeBuyLine");
   ObjectDelete("RangeSellLine");
}

//+------------------------------------------------------------------+
//| Check if price touches range lines and execute market orders     |
//+------------------------------------------------------------------+
void CheckAndExecuteMarketOrders()
{
   datetime currentTime = TimeCurrent();
   
   // If both lines already triggered, nothing to do
   if(g_buyLineTriggered && g_sellLineTriggered) return;
   
   // Check if we already have an open position for this symbol and magic number
   if(HasOpenPosition()) 
   {
      // If we have an open position, mark both lines as triggered to prevent new trades
      g_buyLineTriggered = true;
      g_sellLineTriggered = true;
      g_buyOrderPending = false;
      g_sellOrderPending = false;
      
      // Delete any remaining lines
      DeleteRangeLines();
      return;
   }
   
   // Check for delayed order execution
   if(g_buyOrderPending && !g_buyLineTriggered)
   {
      // If enough time has passed since the line was touched, execute the order
      if(currentTime >= g_buyLineTouchTime + ExecutionDelay)
      {
         ExecuteMarketBuyOrder();
         g_buyLineTriggered = true;
         g_buyOrderPending = false;
         
         // Delete buy line since it's been triggered
         ObjectDelete("RangeBuyLine");
         
         // Delete sell line since we've taken a buy position
         if(ObjectFind("RangeSellLine") >= 0)
         {
            ObjectDelete("RangeSellLine");
            g_sellLineTriggered = true; // Mark as triggered to avoid further checks
         }
         
         Print("Buy line triggered with ", ExecutionDelay, " second delay. Lines deleted.");
      }
   }
   
   if(g_sellOrderPending && !g_sellLineTriggered)
   {
      // If enough time has passed since the line was touched, execute the order
      if(currentTime >= g_sellLineTouchTime + ExecutionDelay)
      {
         ExecuteMarketSellOrder();
         g_sellLineTriggered = true;
         g_sellOrderPending = false;
         
         // Delete sell line since it's been triggered
         ObjectDelete("RangeSellLine");
         
         // Delete buy line since we've taken a sell position
         if(ObjectFind("RangeBuyLine") >= 0)
         {
            ObjectDelete("RangeBuyLine");
            g_buyLineTriggered = true; // Mark as triggered to avoid further checks
         }
         
         Print("Sell line triggered with ", ExecutionDelay, " second delay. Lines deleted.");
      }
   }
   
   // Check if buy line exists and hasn't been triggered or pending
   if(!g_buyLineTriggered && !g_buyOrderPending && ObjectFind("RangeBuyLine") >= 0)
   {
      double buyLinePrice = ObjectGet("RangeBuyLine", OBJPROP_PRICE1);
      
      // Check if current price is at or above the buy line
      if(Ask >= buyLinePrice)
      {
         if(ExecutionDelay > 0)
         {
            // Mark for delayed execution
            g_buyLineTouchTime = currentTime;
            g_buyOrderPending = true;
            Print("Buy line touched. Order will execute in ", ExecutionDelay, " seconds.");
            
            // Change line color to indicate pending execution
            ObjectSet("RangeBuyLine", OBJPROP_COLOR, clrYellow);
            ObjectSet("RangeBuyLine", OBJPROP_STYLE, STYLE_DASH);
         }
         else
         {
            // Execute immediately
            ExecuteMarketBuyOrder();
            g_buyLineTriggered = true;
            
            // Delete buy line since it's been triggered
            ObjectDelete("RangeBuyLine");
            
            // Delete sell line since we've taken a buy position
            if(ObjectFind("RangeSellLine") >= 0)
            {
               ObjectDelete("RangeSellLine");
               g_sellLineTriggered = true; // Mark as triggered to avoid further checks
            }
            
            Print("Buy line triggered and deleted");
         }
      }
   }
   
   // Check if sell line exists and hasn't been triggered or pending
   if(!g_sellLineTriggered && !g_sellOrderPending && ObjectFind("RangeSellLine") >= 0)
   {
      double sellLinePrice = ObjectGet("RangeSellLine", OBJPROP_PRICE1);
      
      // Check if current price is at or below the sell line
      if(Bid <= sellLinePrice)
      {
         if(ExecutionDelay > 0)
         {
            // Mark for delayed execution
            g_sellLineTouchTime = currentTime;
            g_sellOrderPending = true;
            Print("Sell line touched. Order will execute in ", ExecutionDelay, " seconds.");
            
            // Change line color to indicate pending execution
            ObjectSet("RangeSellLine", OBJPROP_COLOR, clrYellow);
            ObjectSet("RangeSellLine", OBJPROP_STYLE, STYLE_DASH);
         }
         else
         {
            // Execute immediately
            ExecuteMarketSellOrder();
            g_sellLineTriggered = true;
            
            // Delete sell line since it's been triggered
            ObjectDelete("RangeSellLine");
            
            // Delete buy line since we've taken a sell position
            if(ObjectFind("RangeBuyLine") >= 0)
            {
               ObjectDelete("RangeBuyLine");
               g_buyLineTriggered = true; // Mark as triggered to avoid further checks
            }
            
            Print("Sell line triggered and deleted");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute market buy order                                         |
//+------------------------------------------------------------------+
void ExecuteMarketBuyOrder()
{
   // Calculate stop loss and take profit levels
   double stopLoss = Ask - StopLoss * Point * 10;
   double takeProfit = Ask + TakeProfit * Point * 10;
   
   // Execute market buy order
   g_buyTicket = OrderSend(
      Symbol(),
      OP_BUY,
      LotSize,
      Ask,
      Slippage,
      stopLoss,
      takeProfit,
      "Range Buy",
      g_magicNumber,
      0,
      clrGreen
   );
   
   if(g_buyTicket < 0)
   {
      Print("Error placing market buy order: ", GetLastError());
   }
   else
   {
      Print("Market buy order executed at ", Ask, " SL: ", stopLoss, " TP: ", takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Execute market sell order                                        |
//+------------------------------------------------------------------+
void ExecuteMarketSellOrder()
{
   // Calculate stop loss and take profit levels
   double stopLoss = Bid + StopLoss * Point * 10;
   double takeProfit = Bid - TakeProfit * Point * 10;
   
   // Execute market sell order
   g_sellTicket = OrderSend(
      Symbol(),
      OP_SELL,
      LotSize,
      Bid,
      Slippage,
      stopLoss,
      takeProfit,
      "Range Sell",
      g_magicNumber,
      0,
      clrRed
   );
   
   if(g_sellTicket < 0)
   {
      Print("Error placing market sell order: ", GetLastError());
   }
   else
   {
      Print("Market sell order executed at ", Bid, " SL: ", stopLoss, " TP: ", takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Check if it's time to remove range lines                         |
//+------------------------------------------------------------------+
void CheckTimeToRemoveRangeLines()
{
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   
   // If current hour matches the closing hour, delete range lines
   if(currentHour == ClosePendingOrdersAt)
   {
      bool linesDeleted = false;
      
      // Check if buy line exists and hasn't been triggered
      if((!g_buyLineTriggered || g_buyOrderPending) && ObjectFind("RangeBuyLine") >= 0)
      {
         ObjectDelete("RangeBuyLine");
         g_buyLineTriggered = true;
         g_buyOrderPending = false;
         linesDeleted = true;
         Print("Buy line deleted at specified hour: ", ClosePendingOrdersAt);
      }
      
      // Check if sell line exists and hasn't been triggered
      if((!g_sellLineTriggered || g_sellOrderPending) && ObjectFind("RangeSellLine") >= 0)
      {
         ObjectDelete("RangeSellLine");
         g_sellLineTriggered = true;
         g_sellOrderPending = false;
         linesDeleted = true;
         Print("Sell line deleted at specified hour: ", ClosePendingOrdersAt);
      }
      
      // If lines were deleted, reset range ended flag to prepare for next day
      if(linesDeleted)
      {
         g_rangeEnded = false;
         g_rangeHigh = 0;
         g_rangeLow = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we already have an open position                        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         // Check if this is our order for this symbol
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_magicNumber)
         {
            // Check if it's a market order (not pending)
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
            {
               return true;
            }
         }
      }
   }
   return false;
}
//+------------------------------------------------------------------+ 