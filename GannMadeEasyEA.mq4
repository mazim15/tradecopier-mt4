//+------------------------------------------------------------------+
//|                                               GannMadeEasyEA.mq4 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Input Parameters
input double LotSize = 0.01;              // Position size
input bool UseFixedLotSize = true;        // Use fixed lot size (if false, risk percentage is used)
input double RiskPercent = 1.0;           // Risk percentage (if Fixed Lot Size is false)
input int MagicNumber = 12345;            // Magic Number for this EA
input int MaxSpread = 50;                 // Maximum allowed spread in points
input int SlipPage = 3;                   // Slippage in points
input bool EnableBuySignals = true;       // Enable Buy signals
input bool EnableSellSignals = true;      // Enable Sell signals
input bool CloseOppositeSignals = false;  // Close opposite positions on new signal
input bool UseMultipleTargets = false;    // Use multiple take profit targets
input double TP1Percent = 100;            // Percentage of position to close at TP1 (if using multiple targets)
input double TP2Percent = 50;             // Percentage of position to close at TP2 (if using multiple targets)
input int ObjectCheckInterval = 1;        // How often to check for new objects (in seconds)

// Trailing Stop Parameters
input bool UseTrailingStop = false;       // Enable trailing stop loss
input int TrailingStart = 50;             // Points of profit before trailing begins
input int TrailingStep = 10;              // Trailing step in points

// Breakeven Parameters
input bool UseBreakEven = false;          // Enable breakeven stop
input int BreakEvenPoints = 20;           // Points of profit before breakeven
input int BreakEvenPips = 2;              // Pips of profit to secure at breakeven

// Time Filter Parameters
input bool UseTimeFilter = false;         // Enable time filtering
input int StartHour = 8;                  // Start hour (0-23) in server time
input int EndHour = 16;                   // End hour (0-23) in server time

// Add these input parameters after the Time Filter parameters
input bool ShowDashboard = true;          // Show statistics dashboard
input int DashboardX = 20;                // Dashboard X position
input int DashboardY = 20;                // Dashboard Y position
input color DashboardColor = clrDarkSlateGray; // Dashboard background color
input color DashboardTextColor = clrWhite; // Dashboard text color
input int DashboardFontSize = 8;          // Dashboard font size
input int DashboardWidth = 200;           // Dashboard width
input int DashboardHeight = 160;          // Dashboard height

// Add these input parameters to the dashboard section
input bool ShowTradeLog = true;           // Show recent trade log
input int TradeLogLines = 5;              // Number of trade log lines to display
input color WinColor = clrLimeGreen;      // Color for winning trades
input color LossColor = clrRed;           // Color for losing trades

// Add these risk management parameters after the dashboard parameters
input string RiskManagement = "------- Risk Management Settings -------"; // Risk Management
input bool UseRiskLimits = true;          // Enable risk management limits
input double MaxLossPerTrade = 100.0;     // Maximum loss per trade (in account currency)
input double MaxLossPerDay = 300.0;       // Maximum loss per day (in account currency)
input double MaxLossTotal = 1000.0;       // Maximum total loss (in account currency)
input double MaxProfitPerDay = 500.0;     // Maximum profit per day (in account currency)
input double TotalProfitTarget = 2000.0;  // Total profit target (in account currency)
input bool ResetDailyLimitsAtDayStart = true; // Reset daily limits at the start of each trading day

// Global variables
datetime lastCheck = 0;
string lastSignalProcessed = "";

// Add these global variables after the existing global variables
int totalTrades = 0;
int winTrades = 0;
int lossTrades = 0;
double totalProfit = 0.0;
double totalLoss = 0.0;
double maxDrawdown = 0.0;
double peakBalance = 0.0;
int consecutiveWins = 0;
int consecutiveLosses = 0;
int maxConsecutiveWins = 0;
int maxConsecutiveLosses = 0;
datetime lastStatsUpdate = 0;

// Add these global variables
string tradeLogLines[];                   // Array to store trade log lines
color tradeLogColors[];                   // Array to store trade log colors
int tradeLogCount = 0;                    // Count of trade log entries

// Add these global variables after the existing global variables
double dailyProfit = 0.0;                 // Profit/loss for current day
datetime lastDayChecked = 0;              // Last day we checked for daily reset
bool tradingHalted = false;               // Flag to indicate if trading is halted due to limits
string haltReason = "";                   // Reason for halting trading
double initialEquity = 0.0;               // Initial equity when EA started

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Verify that we can trade
   if(!IsTradeAllowed())
   {
      Print("Trading is not allowed for this account/expert");
      return INIT_FAILED;
   }
   
   // Initialize dashboard if enabled
   if(ShowDashboard) CreateDashboard();
   
   // Load historical stats
   LoadStats();
   
   // Initialize risk management
   initialEquity = AccountEquity();
   lastDayChecked = TimeCurrent();
   
   Print("GannMadeEasyEA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up dashboard objects
   if(ShowDashboard) DeleteDashboard();
   
   // Save stats for next session
   SaveStats();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we're allowed to trade
   if(!IsTradeAllowed()) return;
   
   // Check risk management limits
   if(UseRiskLimits) 
   {
      CheckRiskLimits();
      CheckTradeMaxLoss(); // Add this new function call to check max loss per trade
   }
   
   // If trading is halted due to risk limits, don't process further
   if(tradingHalted) return;
   
   // Check if time filter allows trading
   if(!IsTradeTimeAllowed()) return;
   
   // Check if spread is too high
   if(MarketInfo(Symbol(), MODE_SPREAD) > MaxSpread) return;
   
   // Update trading statistics (only once per minute to reduce resource usage)
   if(TimeCurrent() - lastStatsUpdate >= 60)
   {
      UpdateStats();
      if(ShowDashboard) UpdateDashboard();
      lastStatsUpdate = TimeCurrent();
   }
   
   // Check for trailing stop and breakeven conditions
   if(UseTrailingStop) CheckTrailingStops();
   if(UseBreakEven) CheckBreakEven();
   
   // Only check for new objects periodically to reduce load
   if(TimeCurrent() - lastCheck >= ObjectCheckInterval)
   {
      CheckForGannSignals();
      lastCheck = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Check if current time allows trading                             |
//+------------------------------------------------------------------+
bool IsTradeTimeAllowed()
{
   if(!UseTimeFilter) return true;
   
   int currentHour = Hour();
   if(StartHour < EndHour)
   {
      // Normal case: e.g., 8-16
      return (currentHour >= StartHour && currentHour < EndHour);
   }
   else
   {
      // Overnight case: e.g., 22-6
      return (currentHour >= StartHour || currentHour < EndHour);
   }
}

//+------------------------------------------------------------------+
//| Check and update trailing stops for open positions               |
//+------------------------------------------------------------------+
void CheckTrailingStops()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            if(OrderType() == OP_BUY)
            {
               double newSL = NormalizeDouble(Bid - TrailingStep * Point, Digits);
               if((Bid - OrderOpenPrice()) > TrailingStart * Point && 
                  (newSL > OrderStopLoss() || OrderStopLoss() == 0))
               {
                  bool res = OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrGreen);
                  if(res)
                     Print("Trailing stop updated for buy order #", OrderTicket(), " to ", newSL);
                  else
                     Print("Error updating trailing stop: ", GetLastError());
               }
            }
            else if(OrderType() == OP_SELL)
            {
               double newSL = NormalizeDouble(Ask + TrailingStep * Point, Digits);
               if((OrderOpenPrice() - Ask) > TrailingStart * Point && 
                  (newSL < OrderStopLoss() || OrderStopLoss() == 0))
               {
                  bool res = OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed);
                  if(res)
                     Print("Trailing stop updated for sell order #", OrderTicket(), " to ", newSL);
                  else
                     Print("Error updating trailing stop: ", GetLastError());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check and update breakeven stops for open positions              |
//+------------------------------------------------------------------+
void CheckBreakEven()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            if(OrderType() == OP_BUY)
            {
               if((Bid - OrderOpenPrice()) > BreakEvenPoints * Point)
               {
                  double newSL = OrderOpenPrice() + BreakEvenPips * Point;
                  if(newSL > OrderStopLoss() || OrderStopLoss() == 0)
                  {
                     bool res = OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrGreen);
                     if(res)
                        Print("Breakeven stop set for buy order #", OrderTicket(), " to ", newSL);
                     else
                        Print("Error setting breakeven stop: ", GetLastError());
                  }
               }
            }
            else if(OrderType() == OP_SELL)
            {
               if((OrderOpenPrice() - Ask) > BreakEvenPoints * Point)
               {
                  double newSL = OrderOpenPrice() - BreakEvenPips * Point;
                  if(newSL < OrderStopLoss() || OrderStopLoss() == 0)
                  {
                     bool res = OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed);
                     if(res)
                        Print("Breakeven stop set for sell order #", OrderTicket(), " to ", newSL);
                     else
                        Print("Error setting breakeven stop: ", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for new Gann signals                                       |
//+------------------------------------------------------------------+
void CheckForGannSignals()
{
   // Find the latest signal arrow (GANN-UP or GANN-DN)
   datetime latestArrowTime = 0;
   string signalType = "";
   
   for(int i = 0; i < ObjectsTotal(); i++)
   {
      string objName = ObjectName(i);
      
      // Check if this is a Gann signal arrow
      if(StringFind(objName, "GANN-UP") == 0 || StringFind(objName, "GANN-DN") == 0)
      {
         datetime objTime = (datetime)ObjectGet(objName, OBJPROP_TIME1);
         
         // Only consider new signals (not already processed)
         if(objTime > latestArrowTime && objName != lastSignalProcessed)
         {
            latestArrowTime = objTime;
            signalType = objName;
         }
      }
   }
   
   // If we found a new signal, process it
   if(latestArrowTime > 0 && signalType != "")
   {
      ProcessGannSignal(signalType, latestArrowTime);
      lastSignalProcessed = signalType;
   }
}

//+------------------------------------------------------------------+
//| Process a Gann signal                                            |
//+------------------------------------------------------------------+
void ProcessGannSignal(string signalType, datetime signalTime)
{
   bool isBuySignal = (StringFind(signalType, "GANN-UP") == 0);
   bool isSellSignal = (StringFind(signalType, "GANN-DN") == 0);
   
   if((!isBuySignal && !isSellSignal) || (isBuySignal && !EnableBuySignals) || (isSellSignal && !EnableSellSignals))
      return;
   
   // Find the related signal objects (signal level, stop level, target levels)
   double signalPrice = FindObjectPrice("GANN-SIGNAL LEVEL");
   double stopLoss = FindObjectPrice("GANN-STOP LEVEL");
   double takeProfit1 = FindObjectPrice("GANN-TARGET LEVEL 1");
   double takeProfit2 = FindObjectPrice("GANN-TARGET LEVEL 2");
   double takeProfit3 = FindObjectPrice("GANN-TARGET LEVEL 3");
   
   // If we couldn't find the necessary levels, abort
   if(signalPrice == 0 || stopLoss == 0 || takeProfit1 == 0)
   {
      Print("Could not find all necessary price levels for the signal");
      return;
   }
   
   // Log the signal information
   Print("New Gann signal detected: ", isBuySignal ? "BUY" : "SELL");
   Print("Signal Price: ", signalPrice, ", Stop Loss: ", stopLoss, ", Take Profit 1: ", takeProfit1);
   
   // Close opposite positions if configured
   if(CloseOppositeSignals)
   {
      if(isBuySignal) CloseAllPositions(OP_SELL);
      else CloseAllPositions(OP_BUY);
   }
   
   // Open the new position
   if(isBuySignal)
   {
      OpenBuyOrder(signalPrice, stopLoss, takeProfit1, takeProfit2, takeProfit3);
   }
   else
   {
      OpenSellOrder(signalPrice, stopLoss, takeProfit1, takeProfit2, takeProfit3);
   }
}

//+------------------------------------------------------------------+
//| Find the price value of a given object                          |
//+------------------------------------------------------------------+
double FindObjectPrice(string objectNamePrefix)
{
   for(int i = 0; i < ObjectsTotal(); i++)
   {
      string objName = ObjectName(i);
      
      if(StringFind(objName, objectNamePrefix) == 0)
      {
         // Different object types store their price in different properties
         int objType = ObjectType(objName);
         
         if(objType == OBJ_HLINE)
         {
            return ObjectGet(objName, OBJPROP_PRICE1);
         }
         else if(objType == OBJ_TREND || objType == OBJ_TEXT)
         {
            return ObjectGet(objName, OBJPROP_PRICE1);
         }
      }
   }
   
   return 0; // Object not found
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLossPrice)
{
   if(UseFixedLotSize) return LotSize;
   
   double riskAmount = AccountBalance() * RiskPercent / 100;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   
   // Calculate the price difference in points
   double priceDiff = MathAbs(entryPrice - stopLossPrice) / Point;
   
   // Calculate lot size based on risk
   double lotSize = NormalizeDouble(riskAmount / (priceDiff * tickValue / tickSize), 2);
   
   // Check minimum and maximum lot sizes
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   
   lotSize = MathMax(minLot, lotSize);
   lotSize = MathMin(maxLot, lotSize);
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep; // Round to lot step
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Close all positions of specified type                            |
//+------------------------------------------------------------------+
void CloseAllPositions(int posType)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderType() == posType)
         {
            bool result = false;
            if(posType == OP_BUY)
               result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(Symbol(), MODE_BID), SlipPage, clrRed);
            else
               result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(Symbol(), MODE_ASK), SlipPage, clrRed);
            
            if(!result)
               Print("Error closing order: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open a buy order                                                 |
//+------------------------------------------------------------------+
void OpenBuyOrder(double signalPrice, double stopLoss, double takeProfit1, double takeProfit2, double takeProfit3)
{
   double price = MarketInfo(Symbol(), MODE_ASK);
   
   // Calculate lot size
   double lots = CalculateLotSize(price, stopLoss);
   
   if(UseMultipleTargets && takeProfit2 > 0 && takeProfit3 > 0)
   {
      // Calculate the lot sizes for each target
      double lots1 = NormalizeDouble(lots * TP1Percent / 100, 2);
      double lots2 = NormalizeDouble(lots * TP2Percent / 100, 2);
      double lots3 = NormalizeDouble(lots - lots1 - lots2, 2);
      
      // Make sure we don't have negative lot sizes due to rounding
      if(lots1 <= 0) lots1 = MarketInfo(Symbol(), MODE_MINLOT);
      if(lots2 <= 0) lots2 = MarketInfo(Symbol(), MODE_MINLOT);
      if(lots3 <= 0) lots3 = MarketInfo(Symbol(), MODE_MINLOT);
      
      // Open three positions with different take profits
      int ticket1 = OrderSend(Symbol(), OP_BUY, lots1, price, SlipPage, stopLoss, takeProfit1, 
                         "GannME BUY TP1", MagicNumber, 0, clrGreen);
                         
      int ticket2 = OrderSend(Symbol(), OP_BUY, lots2, price, SlipPage, stopLoss, takeProfit2, 
                         "GannME BUY TP2", MagicNumber, 0, clrGreen);
                         
      int ticket3 = OrderSend(Symbol(), OP_BUY, lots3, price, SlipPage, stopLoss, takeProfit3, 
                         "GannME BUY TP3", MagicNumber, 0, clrGreen);
      
      if(ticket1 <= 0 || ticket2 <= 0 || ticket3 <= 0)
      {
         Print("Error opening orders: ", GetLastError());
      }
      else
      {
         Print("Buy orders opened with multiple targets");
      }
   }
   else
   {
      // Open a single position with the first take profit
      int ticket = OrderSend(Symbol(), OP_BUY, lots, price, SlipPage, stopLoss, takeProfit1, 
                         "GannME BUY", MagicNumber, 0, clrGreen);
      
      if(ticket <= 0)
      {
         Print("Order send error: ", GetLastError());
      }
      else
      {
         Print("Buy order opened at: ", price, " SL: ", stopLoss, " TP: ", takeProfit1, " Lots: ", lots);
      }
   }
}

//+------------------------------------------------------------------+
//| Open a sell order                                                |
//+------------------------------------------------------------------+
void OpenSellOrder(double signalPrice, double stopLoss, double takeProfit1, double takeProfit2, double takeProfit3)
{
   double price = MarketInfo(Symbol(), MODE_BID);
   
   // Calculate lot size
   double lots = CalculateLotSize(price, stopLoss);
   
   if(UseMultipleTargets && takeProfit2 > 0 && takeProfit3 > 0)
   {
      // Calculate the lot sizes for each target
      double lots1 = NormalizeDouble(lots * TP1Percent / 100, 2);
      double lots2 = NormalizeDouble(lots * TP2Percent / 100, 2);
      double lots3 = NormalizeDouble(lots - lots1 - lots2, 2);
      
      // Make sure we don't have negative lot sizes due to rounding
      if(lots1 <= 0) lots1 = MarketInfo(Symbol(), MODE_MINLOT);
      if(lots2 <= 0) lots2 = MarketInfo(Symbol(), MODE_MINLOT);
      if(lots3 <= 0) lots3 = MarketInfo(Symbol(), MODE_MINLOT);
      
      // Open three positions with different take profits
      int ticket1 = OrderSend(Symbol(), OP_SELL, lots1, price, SlipPage, stopLoss, takeProfit1, 
                         "GannME SELL TP1", MagicNumber, 0, clrRed);
                         
      int ticket2 = OrderSend(Symbol(), OP_SELL, lots2, price, SlipPage, stopLoss, takeProfit2, 
                         "GannME SELL TP2", MagicNumber, 0, clrRed);
                         
      int ticket3 = OrderSend(Symbol(), OP_SELL, lots3, price, SlipPage, stopLoss, takeProfit3, 
                         "GannME SELL TP3", MagicNumber, 0, clrRed);
      
      if(ticket1 <= 0 || ticket2 <= 0 || ticket3 <= 0)
      {
         Print("Error opening orders: ", GetLastError());
      }
      else
      {
         Print("Sell orders opened with multiple targets");
      }
   }
   else
   {
      // Open a single position with the first take profit
      int ticket = OrderSend(Symbol(), OP_SELL, lots, price, SlipPage, stopLoss, takeProfit1, 
                         "GannME SELL", MagicNumber, 0, clrRed);
      
      if(ticket <= 0)
      {
         Print("Order send error: ", GetLastError());
      }
      else
      {
         Print("Sell order opened at: ", price, " SL: ", stopLoss, " TP: ", takeProfit1, " Lots: ", lots);
      }
   }
}

//+------------------------------------------------------------------+
//| Create the statistics dashboard                                  |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   // Create dashboard background panel
   string panelName = "GannEA_Dashboard_BG";
   ObjectCreate(0, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, DashboardX);
   ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, DashboardY);
   ObjectSetInteger(0, panelName, OBJPROP_XSIZE, DashboardWidth);
   
   // Adjust height if trade log is enabled
   int dashboardHeight = DashboardHeight;
   if(ShowTradeLog)
      dashboardHeight += TradeLogLines * 20 + 30; // Additional height for trade log
      
   // Add extra height for risk management info if enabled
   if(UseRiskLimits)
      dashboardHeight += 80; // Extra height for risk management section
       
   ObjectSetInteger(0, panelName, OBJPROP_YSIZE, dashboardHeight);
   ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, DashboardColor);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, panelName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, panelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, panelName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, panelName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, panelName, OBJPROP_ZORDER, 0);
   
   // Create title label
   string titleName = "GannEA_Dashboard_Title";
   ObjectCreate(0, titleName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, titleName, OBJPROP_XDISTANCE, DashboardX + 10);
   ObjectSetInteger(0, titleName, OBJPROP_YDISTANCE, DashboardY + 15);
   ObjectSetString(0, titleName, OBJPROP_TEXT, "GannMadeEasy Statistics");
   ObjectSetString(0, titleName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, titleName, OBJPROP_FONTSIZE, DashboardFontSize + 1);
   ObjectSetInteger(0, titleName, OBJPROP_COLOR, DashboardTextColor);
   ObjectSetInteger(0, titleName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, titleName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   
   // Create stat labels (these will be updated with values in UpdateDashboard)
   int yOffset = 40;
   CreateLabel("GannEA_Dashboard_TotalTrades", "Total Trades:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_TotalTrades_Val", "0", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_WinRate", "Win Rate:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_WinRate_Val", "0.0%", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_ProfitFactor", "Profit Factor:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_ProfitFactor_Val", "0.0", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_NetProfit", "Net Profit:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_NetProfit_Val", "0.0", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_AvgWin", "Avg Win:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_AvgWin_Val", "0.0", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_AvgLoss", "Avg Loss:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_AvgLoss_Val", "0.0", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_MaxDD", "Max Drawdown:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_MaxDD_Val", "0.0", DashboardX + 150, DashboardY + yOffset);
   
   yOffset += 20;
   CreateLabel("GannEA_Dashboard_ConsecWins", "Max Consec. Wins:", DashboardX + 10, DashboardY + yOffset);
   CreateLabel("GannEA_Dashboard_ConsecWins_Val", "0", DashboardX + 150, DashboardY + yOffset);
   
   // Risk management section if enabled
   if(UseRiskLimits)
   {
      yOffset += 30;
      CreateLabel("GannEA_Dashboard_RiskTitle", "Risk Management Status:", DashboardX + 10, DashboardY + yOffset);
      
      yOffset += 20;
      CreateLabel("GannEA_Dashboard_DailyPL", "Daily P/L:", DashboardX + 10, DashboardY + yOffset);
      CreateLabel("GannEA_Dashboard_DailyPL_Val", "0.0", DashboardX + 150, DashboardY + yOffset);
      
      yOffset += 20;
      CreateLabel("GannEA_Dashboard_TradingStatus", "Trading Status:", DashboardX + 10, DashboardY + yOffset);
      CreateLabel("GannEA_Dashboard_TradingStatus_Val", "Active", DashboardX + 150, DashboardY + yOffset);
   }
   
   // Create win/loss ratio visual bar
   yOffset += 30;
   CreateLabel("GannEA_Dashboard_WinLossBar", "Win/Loss Ratio:", DashboardX + 10, DashboardY + yOffset);
   yOffset += 15;
   
   // Win bar background
   string winBarBgName = "GannEA_Dashboard_WinBar_BG";
   ObjectCreate(0, winBarBgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, winBarBgName, OBJPROP_XDISTANCE, DashboardX + 10);
   ObjectSetInteger(0, winBarBgName, OBJPROP_YDISTANCE, DashboardY + yOffset);
   ObjectSetInteger(0, winBarBgName, OBJPROP_XSIZE, DashboardWidth - 20);
   ObjectSetInteger(0, winBarBgName, OBJPROP_YSIZE, 10);
   ObjectSetInteger(0, winBarBgName, OBJPROP_BGCOLOR, clrDarkGray);
   ObjectSetInteger(0, winBarBgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, winBarBgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   // Win bar (will be updated with actual ratio)
   string winBarName = "GannEA_Dashboard_WinBar";
   ObjectCreate(0, winBarName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, winBarName, OBJPROP_XDISTANCE, DashboardX + 10);
   ObjectSetInteger(0, winBarName, OBJPROP_YDISTANCE, DashboardY + yOffset);
   ObjectSetInteger(0, winBarName, OBJPROP_XSIZE, 0);  // Will be updated
   ObjectSetInteger(0, winBarName, OBJPROP_YSIZE, 10);
   ObjectSetInteger(0, winBarName, OBJPROP_BGCOLOR, WinColor);
   ObjectSetInteger(0, winBarName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, winBarName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   // Create trade log section if enabled
   if(ShowTradeLog)
   {
      yOffset += 30;
      CreateLabel("GannEA_Dashboard_TradeLog", "Recent Trades:", DashboardX + 10, DashboardY + yOffset);
      
      // Create text labels for each trade log line
      for(int i = 0; i < TradeLogLines; i++)
      {
         yOffset += 20;
         string logLineName = "GannEA_Dashboard_LogLine_" + IntegerToString(i);
         ObjectCreate(0, logLineName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, logLineName, OBJPROP_XDISTANCE, DashboardX + 10);
         ObjectSetInteger(0, logLineName, OBJPROP_YDISTANCE, DashboardY + yOffset);
         ObjectSetString(0, logLineName, OBJPROP_TEXT, "");
         ObjectSetString(0, logLineName, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, logLineName, OBJPROP_FONTSIZE, DashboardFontSize);
         ObjectSetInteger(0, logLineName, OBJPROP_COLOR, DashboardTextColor);
         ObjectSetInteger(0, logLineName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, logLineName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      }
      
      // Initialize the trade log arrays
      ArrayResize(tradeLogLines, TradeLogLines);
      ArrayResize(tradeLogColors, TradeLogLines);
      for(int i = 0; i < TradeLogLines; i++)
      {
         tradeLogLines[i] = "";
         tradeLogColors[i] = DashboardTextColor;
      }
   }
}

//+------------------------------------------------------------------+
//| Create a text label for the dashboard                            |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, DashboardFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, DashboardTextColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Update dashboard with current statistics                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   // Update statistics values
   ObjectSetString(0, "GannEA_Dashboard_TotalTrades_Val", OBJPROP_TEXT, IntegerToString(totalTrades));
   
   double winRate = (totalTrades > 0) ? (double)winTrades / totalTrades * 100.0 : 0.0;
   ObjectSetString(0, "GannEA_Dashboard_WinRate_Val", OBJPROP_TEXT, DoubleToString(winRate, 1) + "%");
   
   double profitFactor = (totalLoss != 0) ? MathAbs(totalProfit / totalLoss) : 0.0;
   if(totalLoss == 0 && totalProfit > 0) profitFactor = 999.9; // Avoid division by zero
   ObjectSetString(0, "GannEA_Dashboard_ProfitFactor_Val", OBJPROP_TEXT, DoubleToString(profitFactor, 1));
   
   double netProfit = totalProfit + totalLoss; // totalLoss is already negative
   ObjectSetString(0, "GannEA_Dashboard_NetProfit_Val", OBJPROP_TEXT, DoubleToString(netProfit, 2));
   
   // Calculate and display average win and loss
   double avgWin = (winTrades > 0) ? totalProfit / winTrades : 0;
   double avgLoss = (lossTrades > 0) ? totalLoss / lossTrades : 0;
   ObjectSetString(0, "GannEA_Dashboard_AvgWin_Val", OBJPROP_TEXT, DoubleToString(avgWin, 2));
   ObjectSetString(0, "GannEA_Dashboard_AvgLoss_Val", OBJPROP_TEXT, DoubleToString(avgLoss, 2));
   
   ObjectSetString(0, "GannEA_Dashboard_MaxDD_Val", OBJPROP_TEXT, DoubleToString(maxDrawdown, 2));
   ObjectSetString(0, "GannEA_Dashboard_ConsecWins_Val", OBJPROP_TEXT, IntegerToString(maxConsecutiveWins));
   
   // Update risk management info
   if(UseRiskLimits)
   {
      ObjectSetString(0, "GannEA_Dashboard_DailyPL_Val", OBJPROP_TEXT, DoubleToString(dailyProfit, 2));
      
      if(tradingHalted)
      {
         ObjectSetString(0, "GannEA_Dashboard_TradingStatus_Val", OBJPROP_TEXT, "HALTED: " + haltReason);
         ObjectSetInteger(0, "GannEA_Dashboard_TradingStatus_Val", OBJPROP_COLOR, LossColor);
      }
      else
      {
         ObjectSetString(0, "GannEA_Dashboard_TradingStatus_Val", OBJPROP_TEXT, "Active");
         ObjectSetInteger(0, "GannEA_Dashboard_TradingStatus_Val", OBJPROP_COLOR, WinColor);
      }
   }
   
   // Update win/loss ratio bar
   int barWidth = DashboardWidth - 20;
   int winBarWidth = 0;
   if(totalTrades > 0)
      winBarWidth = (int)MathRound(barWidth * winRate / 100.0);
   
   ObjectSetInteger(0, "GannEA_Dashboard_WinBar", OBJPROP_XSIZE, winBarWidth);
   
   // Update trade log if enabled
   if(ShowTradeLog)
   {
      for(int i = 0; i < TradeLogLines; i++)
      {
         string logLineName = "GannEA_Dashboard_LogLine_" + IntegerToString(i);
         if(i < tradeLogCount)
         {
            ObjectSetString(0, logLineName, OBJPROP_TEXT, tradeLogLines[i]);
            ObjectSetInteger(0, logLineName, OBJPROP_COLOR, tradeLogColors[i]);
         }
         else
         {
            ObjectSetString(0, logLineName, OBJPROP_TEXT, "");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all dashboard objects                                     |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
   ObjectDelete(0, "GannEA_Dashboard_BG");
   ObjectDelete(0, "GannEA_Dashboard_Title");
   ObjectDelete(0, "GannEA_Dashboard_TotalTrades");
   ObjectDelete(0, "GannEA_Dashboard_TotalTrades_Val");
   ObjectDelete(0, "GannEA_Dashboard_WinRate");
   ObjectDelete(0, "GannEA_Dashboard_WinRate_Val");
   ObjectDelete(0, "GannEA_Dashboard_ProfitFactor");
   ObjectDelete(0, "GannEA_Dashboard_ProfitFactor_Val");
   ObjectDelete(0, "GannEA_Dashboard_NetProfit");
   ObjectDelete(0, "GannEA_Dashboard_NetProfit_Val");
   ObjectDelete(0, "GannEA_Dashboard_AvgWin");
   ObjectDelete(0, "GannEA_Dashboard_AvgWin_Val");
   ObjectDelete(0, "GannEA_Dashboard_AvgLoss");
   ObjectDelete(0, "GannEA_Dashboard_AvgLoss_Val");
   ObjectDelete(0, "GannEA_Dashboard_MaxDD");
   ObjectDelete(0, "GannEA_Dashboard_MaxDD_Val");
   ObjectDelete(0, "GannEA_Dashboard_ConsecWins");
   ObjectDelete(0, "GannEA_Dashboard_ConsecWins_Val");
   ObjectDelete(0, "GannEA_Dashboard_WinLossBar");
   ObjectDelete(0, "GannEA_Dashboard_WinBar_BG");
   ObjectDelete(0, "GannEA_Dashboard_WinBar");
   
   if(UseRiskLimits)
   {
      ObjectDelete(0, "GannEA_Dashboard_RiskTitle");
      ObjectDelete(0, "GannEA_Dashboard_DailyPL");
      ObjectDelete(0, "GannEA_Dashboard_DailyPL_Val");
      ObjectDelete(0, "GannEA_Dashboard_TradingStatus");
      ObjectDelete(0, "GannEA_Dashboard_TradingStatus_Val");
   }
   
   if(ShowTradeLog)
   {
      ObjectDelete(0, "GannEA_Dashboard_TradeLog");
      for(int i = 0; i < TradeLogLines; i++)
      {
         string logLineName = "GannEA_Dashboard_LogLine_" + IntegerToString(i);
         ObjectDelete(0, logLineName);
      }
   }
}

//+------------------------------------------------------------------+
//| Update trading statistics                                        |
//+------------------------------------------------------------------+
void UpdateStats()
{
   // Reset temporary variables
   double currentBalance = AccountBalance();
   double currentEquity = AccountEquity();
   
   // Check for closed orders since last update
   int historyTotal = OrdersHistoryTotal();
   for(int i = 0; i < historyTotal; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         // Only process orders from this EA (matching MagicNumber)
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
         {
            // Check if the order was closed after the last stats update
            if(OrderCloseTime() > lastStatsUpdate && OrderCloseTime() <= TimeCurrent())
            {
               double profit = OrderProfit() + OrderSwap() + OrderCommission();
               
               // Update daily profit/loss
               dailyProfit += profit;
               
               totalTrades++;
               
               if(profit > 0)
               {
                  winTrades++;
                  totalProfit += profit;
                  consecutiveWins++;
                  consecutiveLosses = 0;
                  
                  if(consecutiveWins > maxConsecutiveWins)
                     maxConsecutiveWins = consecutiveWins;
                     
                  // Add to trade log
                  if(ShowTradeLog)
                     AddTradeLogEntry(OrderTicket(), OrderType(), OrderLots(), OrderOpenPrice(), 
                                     OrderClosePrice(), profit, true);
               }
               else
               {
                  lossTrades++;
                  totalLoss += profit; // profit is negative here
                  consecutiveLosses++;
                  consecutiveWins = 0;
                  
                  if(consecutiveLosses > maxConsecutiveLosses)
                     maxConsecutiveLosses = consecutiveLosses;
                     
                  // Add to trade log
                  if(ShowTradeLog)
                     AddTradeLogEntry(OrderTicket(), OrderType(), OrderLots(), OrderOpenPrice(), 
                                     OrderClosePrice(), profit, false);
               }
            }
         }
      }
   }
   
   // Update peak balance and drawdown
   if(currentBalance > peakBalance)
      peakBalance = currentBalance;
   
   double currentDrawdown = peakBalance - currentEquity;
   if(currentDrawdown > maxDrawdown)
      maxDrawdown = currentDrawdown;
}

//+------------------------------------------------------------------+
//| Add entry to trade log                                           |
//+------------------------------------------------------------------+
void AddTradeLogEntry(int ticket, int type, double lots, double openPrice, double closePrice, double profit, bool isWin)
{
   // Create log entry text
   string direction = (type == OP_BUY) ? "BUY" : "SELL";
   string logEntry = StringFormat("#%d %s %.2f → %.2f ($%.2f)", 
                                 ticket, direction, openPrice, closePrice, profit);
   
   // Shift existing entries down
   for(int i = TradeLogLines - 1; i > 0; i--)
   {
      tradeLogLines[i] = tradeLogLines[i - 1];
      tradeLogColors[i] = tradeLogColors[i - 1];
   }
   
   // Add new entry at the top
   tradeLogLines[0] = logEntry;
   tradeLogColors[0] = isWin ? WinColor : LossColor;
   
   // Update count of log entries
   if(tradeLogCount < TradeLogLines)
      tradeLogCount++;
}

//+------------------------------------------------------------------+
//| Save statistics to file                                          |
//+------------------------------------------------------------------+
void SaveStats()
{
   string fileName = "GannMadeEasyEA_Stats_" + Symbol() + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = FileOpen(fileName, FILE_WRITE|FILE_CSV);
   
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, "TotalTrades", totalTrades);
      FileWrite(handle, "WinTrades", winTrades);
      FileWrite(handle, "LossTrades", lossTrades);
      FileWrite(handle, "TotalProfit", totalProfit);
      FileWrite(handle, "TotalLoss", totalLoss);
      FileWrite(handle, "MaxDrawdown", maxDrawdown);
      FileWrite(handle, "PeakBalance", peakBalance);
      FileWrite(handle, "MaxConsecutiveWins", maxConsecutiveWins);
      FileWrite(handle, "MaxConsecutiveLosses", maxConsecutiveLosses);
      
      FileClose(handle);
   }
   else
   {
      Print("Failed to save statistics to file: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Load statistics from file                                        |
//+------------------------------------------------------------------+
void LoadStats()
{
   string fileName = "GannMadeEasyEA_Stats_" + Symbol() + "_" + IntegerToString(MagicNumber) + ".csv";
   
   if(FileIsExist(fileName))
   {
      int handle = FileOpen(fileName, FILE_READ|FILE_CSV);
      
      if(handle != INVALID_HANDLE)
      {
         string paramName;
         
         // Read each line and set appropriate variables
         while(!FileIsEnding(handle))
         {
            paramName = FileReadString(handle);
            
            if(paramName == "TotalTrades")
               totalTrades = (int)FileReadNumber(handle);
            else if(paramName == "WinTrades")
               winTrades = (int)FileReadNumber(handle);
            else if(paramName == "LossTrades")
               lossTrades = (int)FileReadNumber(handle);
            else if(paramName == "TotalProfit")
               totalProfit = FileReadNumber(handle);
            else if(paramName == "TotalLoss")
               totalLoss = FileReadNumber(handle);
            else if(paramName == "MaxDrawdown")
               maxDrawdown = FileReadNumber(handle);
            else if(paramName == "PeakBalance")
               peakBalance = FileReadNumber(handle);
            else if(paramName == "MaxConsecutiveWins")
               maxConsecutiveWins = (int)FileReadNumber(handle);
            else if(paramName == "MaxConsecutiveLosses")
               maxConsecutiveLosses = (int)FileReadNumber(handle);
            else
               FileReadNumber(handle); // Skip unknown parameters
         }
         
         FileClose(handle);
         
         // Initialize peakBalance if it's 0
         if(peakBalance == 0) peakBalance = AccountBalance();
         
         Print("Statistics loaded from file");
      }
      else
      {
         Print("Failed to load statistics from file: ", GetLastError());
      }
   }
   else
   {
      Print("No previous statistics file found, starting fresh");
      peakBalance = AccountBalance();
   }
}

//+------------------------------------------------------------------+
//| Check risk management limits                                     |
//+------------------------------------------------------------------+
void CheckRiskLimits()
{
   // Reset daily limits if we're on a new day
   if(ResetDailyLimitsAtDayStart)
   {
      datetime currentTime = TimeCurrent();
      int currentDay = TimeDay(currentTime);
      int lastDay = TimeDay(lastDayChecked);
      
      if(currentDay != lastDay)
      {
         Print("New trading day detected. Resetting daily profit/loss counters.");
         dailyProfit = 0.0;
         lastDayChecked = currentTime;
         
         // If trading was halted due to daily limits, resume it
         if(tradingHalted && (haltReason == "Daily Loss Limit" || haltReason == "Daily Profit Target"))
         {
            tradingHalted = false;
            haltReason = "";
            Print("Trading resumed for new day");
         }
      }
   }
   
   // Calculate current profit/loss status
   double currentEquity = AccountEquity();
   double totalPL = currentEquity - initialEquity;
   
   // Get current daily profit including floating P/L from open positions
   double currentDailyProfit = CalculateCurrentDailyProfit();
   
   // Check total profit target
   if(totalPL >= TotalProfitTarget)
   {
      if(!tradingHalted)
      {
         // Close all open trades first
         CloseAllOpenTrades("Total Profit Target reached");
         
         tradingHalted = true;
         haltReason = "Total Profit Target";
         Print("Trading halted: Total profit target of ", TotalProfitTarget, " reached. Current profit: ", totalPL);
      }
      return;
   }
   
   // Check total loss limit
   if(totalPL <= -MaxLossTotal)
   {
      if(!tradingHalted)
      {
         // Close all open trades first
         CloseAllOpenTrades("Total Loss Limit reached");
         
         tradingHalted = true;
         haltReason = "Total Loss Limit";
         Print("Trading halted: Maximum total loss of ", MaxLossTotal, " reached. Current loss: ", MathAbs(totalPL));
      }
      return;
   }
   
   // Check daily profit limit
   if(currentDailyProfit >= MaxProfitPerDay)
   {
      if(!tradingHalted)
      {
         // Close all open trades first
         CloseAllOpenTrades("Daily Profit Target reached");
         
         tradingHalted = true;
         haltReason = "Daily Profit Target";
         Print("Trading halted: Maximum daily profit of ", MaxProfitPerDay, " reached. Current daily profit: ", currentDailyProfit);
      }
      return;
   }
   
   // Check daily loss limit
   if(currentDailyProfit <= -MaxLossPerDay)
   {
      if(!tradingHalted)
      {
         // Close all open trades first
         CloseAllOpenTrades("Daily Loss Limit reached");
         
         tradingHalted = true;
         haltReason = "Daily Loss Limit";
         Print("Trading halted: Maximum daily loss of ", MaxLossPerDay, " reached. Current daily loss: ", MathAbs(currentDailyProfit));
      }
      return;
   }
   
   // If we get here and trading was halted (but conditions no longer apply), resume trading
   if(tradingHalted && (haltReason == "Daily Loss Limit" || haltReason == "Daily Profit Target"))
   {
      tradingHalted = false;
      haltReason = "";
      Print("Trading resumed as risk conditions are now favorable");
   }
}

//+------------------------------------------------------------------+
//| Calculate current daily profit including open positions          |
//+------------------------------------------------------------------+
double CalculateCurrentDailyProfit()
{
   double floatingPL = 0.0;
   
   // Get floating P/L from open positions
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            // Only include positions opened today
            if(TimeDay(OrderOpenTime()) == TimeDay(TimeCurrent()))
            {
               floatingPL += OrderProfit() + OrderSwap() + OrderCommission();
            }
         }
      }
   }
   
   // Return combined closed + floating P/L for today
   return dailyProfit + floatingPL;
}

//+------------------------------------------------------------------+
//| Close all open trades                                            |
//+------------------------------------------------------------------+
void CloseAllOpenTrades(string reason)
{
   Print("Closing all open trades - Reason: ", reason);
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            bool result = false;
            
            if(OrderType() == OP_BUY)
               result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), SlipPage, clrRed);
            else if(OrderType() == OP_SELL)
               result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), SlipPage, clrRed);
               
            if(result)
               Print("Closed order #", OrderTicket(), " due to ", reason);
            else
               Print("Failed to close order #", OrderTicket(), " Error: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check max loss per trade and close if necessary                  |
//+------------------------------------------------------------------+
void CheckTradeMaxLoss()
{
   // Only process if risk limits are enabled
   if(!UseRiskLimits) return;
   
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         // Only check orders for current symbol and with our magic number
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            double currentProfit = OrderProfit() + OrderSwap() + OrderCommission();
            
            // If loss exceeds our max loss per trade limit, close the position
            if(currentProfit < -MaxLossPerTrade)
            {
               bool result = false;
               
               if(OrderType() == OP_BUY)
                  result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), SlipPage, clrRed);
               else if(OrderType() == OP_SELL)
                  result = OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), SlipPage, clrRed);
               
               if(result)
                  Print("Closed order #", OrderTicket(), " due to max loss per trade limit (", currentProfit, ")");
               else
                  Print("Failed to close order #", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
   }
} 