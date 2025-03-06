//+------------------------------------------------------------------+
//|                                            RSI_DelayedEntryEA.mq4  |
//|                                             Copyright 2025         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

// Input Parameters
extern int    RSI_Period = 14;         // RSI Period
extern int    RSI_Overbought = 70;     // RSI Overbought Level
extern int    RSI_Oversold = 30;       // RSI Oversold Level
extern bool   RequireClose = true;     // Require candle close confirmation
extern double LotSize = 0.1;           // Trading Lot Size
extern int    TakeProfit = 1200;       // Take Profit in points
extern int    StopLoss = 600;          // Stop Loss in points
extern bool   UseTrailingStop = false; // Enable/Disable trailing stop
extern int    TrailingStart = 100;     // Start trailing after this many points in profit
extern int    TrailingStep = 100;      // Points to maintain from current price
extern double DailyProfitTarget = 200; // Daily profit target in account currency
extern double DailyLossLimit = 200;    // Daily loss limit in account currency
extern double TotalProfitTarget = 1000;// Total account profit target
extern double MaxDrawdown = 1000;      // Maximum total drawdown allowed
extern double MaxSpread = 3.0;         // Maximum allowed spread in pips
extern bool   UseTimer = true;         // Enable/Disable trading hours
extern int    StartHour = 2;          // Trading start hour (0-23)
extern int    EndHour = 22;           // Trading end hour (0-23)
extern bool   AllowMultipleTrades = false; // Allow multiple trades per signal
extern int    MaxOpenTrades = 5;      // Maximum number of open trades allowed
extern bool   InvertSignals = false;    // Invert buy/sell signals

// Limit Order Parameters
extern bool   UseLimitOrders = false;  // Enable/Disable limit order entry
extern int    DelayedEntryPoints = 10; // Points away for limit order entry
extern int    CancelLimitPoints = 10;  // Points in opposite direction to cancel limit
extern color  SignalLineColor = clrYellow; // Color for signal line
extern bool   DrawSignalLines = true;  // Draw lines at signal points

// Global Variables
double initialBalance;
double initialAccountBalance;
datetime lastTradeDay = 0;
double g_previousRSI = 0.0;  // Renamed to avoid conflicts
datetime lastSignalTime = 0;
double g_signalPrice = 0;    // Renamed to avoid conflicts
bool buySignalActive = false;
bool sellSignalActive = false;
int signalLineCounter = 0;

// Limit Order Variables
bool limitOrderPlaced = false;
int limitTicket = 0;
ENUM_ORDER_TYPE pendingOrderType = -1;
double cancelLevel = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    initialBalance = AccountBalance();
    initialAccountBalance = AccountBalance();
    g_previousRSI = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE, 1);
    
    if(UseTimer)
    {
        if(StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23)
        {
            Print("Invalid trading hours! Hours must be between 0-23");
            return INIT_PARAMETERS_INCORRECT;
        }
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    CleanupSignalLines();
    if(UseLimitOrders) DeletePendingOrders();
}

//+------------------------------------------------------------------+
//| Check if order was closed by stop loss or take profit              |
//+------------------------------------------------------------------+
void CheckForClosedTrades()
{
    // Check if any limits are hit first
    if(IsTotalLimitHit() || IsDailyTargetHit())
    {
        // If limits are hit, cancel any pending orders
        if(UseLimitOrders)
        {
            DeletePendingOrders();
            CleanupSignalLines();
        }
        return;
    }

    // Check the order history for recently closed orders
    for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            // Only check orders from this EA on this symbol
            if(OrderSymbol() == Symbol() && 
               (StringFind(OrderComment(), "RSI EA") >= 0))
            {
                // Check if order was closed in the last tick
                if(OrderCloseTime() >= iTime(Symbol(), Period(), 0))
                {
                    bool wasBuy = (OrderType() == OP_BUY);
                    
                    // Reset signals
                    buySignalActive = false;
                    sellSignalActive = false;
                    g_signalPrice = 0;
                    limitOrderPlaced = false;
                    limitTicket = 0;
                    pendingOrderType = -1;
                    cancelLevel = 0;
                    CleanupSignalLines();
                    
                    // If it was a stop loss, open new market order immediately
                    // but only if we don't already have an open position
                    if(OrderProfit() < 0 && !IsTotalLimitHit() && !IsDailyTargetHit() && CountOpenTrades() == 0)
                    {
                        double stopLossPrice, takeProfitPrice;
                        if(wasBuy)
                        {
                            stopLossPrice = Bid - StopLoss * Point;
                            takeProfitPrice = Ask + TakeProfit * Point;
                            
                            int ticket = OrderSend(Symbol(), OP_BUY, LotSize, Ask, 3, stopLossPrice, takeProfitPrice,
                                                 "RSI EA Buy", 0, 0, clrGreen);
                                                 
                            if(ticket < 0)
                            {
                                Print("OrderSend failed with error #", GetLastError());
                            }
                            else
                            {
                                Print("Buy order opened after SL hit - Continuing trading");
                            }
                        }
                        else
                        {
                            stopLossPrice = Ask + StopLoss * Point;
                            takeProfitPrice = Bid - TakeProfit * Point;
                            
                            int ticket = OrderSend(Symbol(), OP_SELL, LotSize, Bid, 3, stopLossPrice, takeProfitPrice,
                                                 "RSI EA Sell", 0, 0, clrRed);
                                                 
                            if(ticket < 0)
                            {
                                Print("OrderSend failed with error #", GetLastError());
                            }
                            else
                            {
                                Print("Sell order opened after SL hit - Continuing trading");
                            }
                        }
                    }
                    else
                    {
                        if(OrderProfit() > 0)
                        {
                            Print("Take profit hit - Resetting signals");
                        }
                        else
                        {
                            Print("Stop loss hit - Checking conditions before next trade");
                        }
                    }
                    
                    // Important: Break after handling one closed trade
                    // This prevents processing multiple trades in the same tick
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if any new limit orders have been filled                     |
//+------------------------------------------------------------------+
void CheckLimitOrderFill()
{
    // Skip if no limit orders are placed
    if(!limitOrderPlaced || limitTicket <= 0) return;
    
    // Check if the limit order is still pending
    if(!OrderSelect(limitTicket, SELECT_BY_TICKET)) return;
    
    // If order is no longer pending, it was either filled or cancelled
    if(OrderType() != OP_BUYLIMIT && OrderType() != OP_SELLLIMIT)
    {
        // Reset limit order flags
        limitOrderPlaced = false;
        limitTicket = 0;
        pendingOrderType = -1;
        cancelLevel = 0;
        CleanupSignalLines();
    }
}

//+------------------------------------------------------------------+
//| Draw signal lines for limit orders                                |
//+------------------------------------------------------------------+
void DrawLimitOrderLines(double price, double limitPrice, double cancelPrice, bool isBuySignal)
{
    if(!DrawSignalLines) return;
    
    CleanupSignalLines();
    
    // Draw signal price line
    string signalLineName = "SignalLine_Price";
    ObjectCreate(0, signalLineName, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, signalLineName, OBJPROP_COLOR, SignalLineColor);
    ObjectSetInteger(0, signalLineName, OBJPROP_STYLE, STYLE_SOLID);
    
    // Draw limit entry line
    string limitLineName = "SignalLine_Limit";
    ObjectCreate(0, limitLineName, OBJ_HLINE, 0, 0, limitPrice);
    ObjectSetInteger(0, limitLineName, OBJPROP_COLOR, isBuySignal ? clrGreen : clrRed);
    ObjectSetInteger(0, limitLineName, OBJPROP_STYLE, STYLE_DASH);
    
    // Draw cancel level line
    string cancelLineName = "SignalLine_Cancel";
    ObjectCreate(0, cancelLineName, OBJ_HLINE, 0, 0, cancelPrice);
    ObjectSetInteger(0, cancelLineName, OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, cancelLineName, OBJPROP_STYLE, STYLE_DOT);
    
    // Add labels
    ObjectCreate(0, "Label_Signal", OBJ_TEXT, 0, Time[0], price);
    ObjectSetString(0, "Label_Signal", OBJPROP_TEXT, "Signal Price");
    ObjectCreate(0, "Label_Limit", OBJ_TEXT, 0, Time[0], limitPrice);
    ObjectSetString(0, "Label_Limit", OBJPROP_TEXT, isBuySignal ? "Buy Limit" : "Sell Limit");
    ObjectCreate(0, "Label_Cancel", OBJ_TEXT, 0, Time[0], cancelPrice);
    ObjectSetString(0, "Label_Cancel", OBJPROP_TEXT, "Cancel Level");
}

//+------------------------------------------------------------------+
//| Draw regular signal line                                          |
//+------------------------------------------------------------------+
void DrawSignalLine(double price, bool isBuySignal)
{
    if(!DrawSignalLines) return;
    
    string lineName = "SignalLine_" + IntegerToString(signalLineCounter++);
    ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, lineName, OBJPROP_COLOR, SignalLineColor);
    ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
    
    string labelName = "SignalLabel_" + IntegerToString(signalLineCounter);
    ObjectCreate(0, labelName, OBJ_TEXT, 0, Time[0], price);
    ObjectSetString(0, labelName, OBJPROP_TEXT, isBuySignal ? "Buy Signal" : "Sell Signal");
    ObjectSetInteger(0, labelName, OBJPROP_COLOR, SignalLineColor);
}

//+------------------------------------------------------------------+
//| Clean up signal lines                                             |
//+------------------------------------------------------------------+
void CleanupSignalLines()
{
    for(int i = ObjectsTotal() - 1; i >= 0; i--)
    {
        string name = ObjectName(i);
        if(StringFind(name, "SignalLine_") >= 0 || StringFind(name, "SignalLabel_") >= 0 ||
           StringFind(name, "Label_") >= 0)
        {
            ObjectDelete(name);
        }
    }
}

//+------------------------------------------------------------------+
//| Delete pending orders                                             |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
    if(limitTicket > 0)
    {
        if(OrderSelect(limitTicket, SELECT_BY_TICKET))
        {
            if(OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT)
            {
                bool success = OrderDelete(limitTicket);
                if(!success)
                {
                    Print("Failed to delete pending order #", limitTicket, ". Error: ", GetLastError());
                }
            }
        }
        limitTicket = 0;
        limitOrderPlaced = false;
        pendingOrderType = -1;
        cancelLevel = 0;
    }
}

//+------------------------------------------------------------------+
//| Place limit order                                                 |
//+------------------------------------------------------------------+
void PlaceLimitOrder(bool isBuySignal, double localSignalPrice)
{
    // Check if there's already a limit order or if we have open trades
    if(limitOrderPlaced || limitTicket > 0) return;
    
    // Additional check for any existing orders
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == Symbol())
            {
                // If there's any open trade or pending order, don't place new limit
                return;
            }
        }
    }
    
    // Check limits before placing limit order
    if(IsTotalLimitHit() || IsDailyTargetHit())
    {
        Print("Account limits reached - not placing limit order");
        return;
    }
    
    double limitPrice, stopLossPrice, takeProfitPrice;
    
    if(isBuySignal)
    {
        limitPrice = localSignalPrice - DelayedEntryPoints * Point;
        stopLossPrice = limitPrice - StopLoss * Point;
        takeProfitPrice = limitPrice + TakeProfit * Point;
        // Cancel if price moves above signal price
        cancelLevel = localSignalPrice + CancelLimitPoints * Point;
        pendingOrderType = OP_BUYLIMIT;
    }
    else
    {
        limitPrice = localSignalPrice + DelayedEntryPoints * Point;
        stopLossPrice = limitPrice + StopLoss * Point;
        takeProfitPrice = limitPrice - TakeProfit * Point;
        // Cancel if price moves below signal price
        cancelLevel = localSignalPrice - CancelLimitPoints * Point;
        pendingOrderType = OP_SELLLIMIT;
    }
    
    // Set flags before placing order to prevent race conditions
    limitOrderPlaced = true;
    
    limitTicket = OrderSend(Symbol(), pendingOrderType, LotSize, limitPrice, 3,
                          stopLossPrice, takeProfitPrice, "RSI EA Limit", 0, 0,
                          isBuySignal ? clrGreen : clrRed);
                          
    if(limitTicket > 0)
    {
        DrawLimitOrderLines(localSignalPrice, limitPrice, cancelLevel, isBuySignal);
        Print("Limit order placed at ", limitPrice, " Cancel level: ", cancelLevel);
    }
    else
    {
        Print("Error placing limit order: ", GetLastError());
        // Reset flags if order placement failed
        limitOrderPlaced = false;
        limitTicket = 0;
        pendingOrderType = -1;
        cancelLevel = 0;
    }
}

//+------------------------------------------------------------------+
//| Count current open trades                                          |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == Symbol() && 
               (OrderType() == OP_BUY || OrderType() == OP_SELL))
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    if(!UseTimer) return true;
    
    int currentHour = Hour();
    
    if(EndHour < StartHour)
    {
        return currentHour >= StartHour || currentHour < EndHour;
    }
    
    return currentHour >= StartHour && currentHour < EndHour;
}

//+------------------------------------------------------------------+
//| Check if it's first hour of the day                               |
//+------------------------------------------------------------------+
bool IsFirstHourOfDay()
{
    datetime serverTime = TimeCurrent();
    int currentHour = TimeHour(serverTime);
    return (currentHour == 0);
}

//+------------------------------------------------------------------+
//| Check if spread is too high                                        |
//+------------------------------------------------------------------+
bool IsSpreadTooHigh()
{
    double currentSpread = MarketInfo(Symbol(), MODE_SPREAD) / 10.0;
    return (currentSpread > MaxSpread);
}

//+------------------------------------------------------------------+
//| Close all open positions                                          |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == Symbol())
            {
                if(OrderType() == OP_BUY)
                {
                    bool success = OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrRed);
                    if(!success)
                    {
                        Print("Failed to close BUY order #", OrderTicket(), ". Error: ", GetLastError());
                    }
                }
                else if(OrderType() == OP_SELL)
                {
                    bool success = OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrRed);
                    if(!success)
                    {
                        Print("Failed to close SELL order #", OrderTicket(), ". Error: ", GetLastError());
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                              |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!UseTrailingStop) return;
    
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderSymbol() == Symbol())
            {
                if(OrderType() == OP_BUY)
                {
                    double currentProfit = Bid - OrderOpenPrice();
                    if(currentProfit >= TrailingStart * Point)
                    {
                        double newStopLoss = Bid - TrailingStep * Point;
                        if(newStopLoss > OrderStopLoss() + Point)
                        {
                            bool success = OrderModify(OrderTicket(), OrderOpenPrice(), newStopLoss, OrderTakeProfit(), 0, clrBlue);
                            if(!success)
                            {
                                Print("Failed to modify BUY order #", OrderTicket(), ". Error: ", GetLastError());
                            }
                        }
                    }
                }
                else if(OrderType() == OP_SELL)
                {
                    double currentProfit = OrderOpenPrice() - Ask;
                    if(currentProfit >= TrailingStart * Point)
                    {
                        double newStopLoss = Ask + TrailingStep * Point;
                        if(OrderStopLoss() == 0 || newStopLoss < OrderStopLoss() - Point)
                        {
                            bool success = OrderModify(OrderTicket(), OrderOpenPrice(), newStopLoss, OrderTakeProfit(), 0, clrRed);
                            if(!success)
                            {
                                Print("Failed to modify SELL order #", OrderTicket(), ". Error: ", GetLastError());
                            }
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check total account limits                                        |
//+------------------------------------------------------------------+
bool IsTotalLimitHit()
{
    double currentEquity = AccountEquity();
    double totalProfit = currentEquity - initialAccountBalance;
    double currentDrawdown = initialAccountBalance - currentEquity;
    
    if(totalProfit >= TotalProfitTarget)
    {
        CloseAllPositions();
        Print("Total profit target reached: ", totalProfit);
        return true;
    }
    
    if(currentDrawdown >= MaxDrawdown)
    {
        CloseAllPositions();
        Print("Maximum drawdown hit: ", currentDrawdown);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if daily target is hit                                      |
//+------------------------------------------------------------------+
bool IsDailyTargetHit()
{
    datetime currentDay = iTime(Symbol(), PERIOD_D1, 0);
    
    if(currentDay != lastTradeDay)
    {
        initialBalance = AccountBalance();
        lastTradeDay = currentDay;
        return false;
    }
    
    double currentEquity = AccountEquity();
    double currentBalance = AccountBalance();
    double profitTarget = initialBalance + DailyProfitTarget;
    double lossTarget = initialBalance - DailyLossLimit;
    
    if(currentBalance >= profitTarget || currentBalance <= lossTarget)
    {
        return true;
    }
    
    if(currentEquity >= profitTarget || currentEquity <= lossTarget)
    {
        CloseAllPositions();
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if RSI conditions are met                                    |
//+------------------------------------------------------------------+
bool CheckRSIConditions(double currentRSI, double previousRSI, bool checkBuy)
{
    if(RequireClose)
    {
        if(checkBuy)
            return (currentRSI < RSI_Oversold && previousRSI < RSI_Oversold);
        else
            return (currentRSI > RSI_Overbought && previousRSI > RSI_Overbought);
    }
    else
    {
        if(checkBuy)
            return (currentRSI < RSI_Oversold);
        else
            return (currentRSI > RSI_Overbought);
    }
}

//+------------------------------------------------------------------+
//| Check if limit order should be cancelled                          |
//+------------------------------------------------------------------+
bool ShouldCancelLimit()
{
    if(!limitOrderPlaced || limitTicket <= 0) return false;
    
    if(pendingOrderType == OP_BUYLIMIT)
    {
        return (Bid >= cancelLevel);
    }
    else if(pendingOrderType == OP_SELLLIMIT)
    {
        return (Ask <= cancelLevel);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for stopped out or tp hit orders first
    CheckForClosedTrades();
    
    // Check if any limit orders were filled
    if(UseLimitOrders) CheckLimitOrderFill();
    
    // Update trailing stops for open positions
    ManageTrailingStop();
    
    // Check if limit order should be cancelled
    if(UseLimitOrders && limitOrderPlaced && ShouldCancelLimit())
    {
        Print("Cancelling limit order - price reached cancel level");
        DeletePendingOrders();
        CleanupSignalLines();
    }
    
    // Don't look for new signals if we have a pending limit order
    if(UseLimitOrders && limitOrderPlaced) return;
    
    // Update status display
    double currentSpread = MarketInfo(Symbol(), MODE_SPREAD) / 10.0;
    string statusMsg = "";
    
    if(UseTimer && !IsWithinTradingHours())
    {
        statusMsg = "Trading paused - Outside trading hours (" + IntegerToString(StartHour) + ":00 - " + IntegerToString(EndHour) + ":00)";
    }
    else if(IsFirstHourOfDay())
    {
        statusMsg = "Trading paused - First hour of the day";
    }
    else if(IsSpreadTooHigh())
    {
        statusMsg = "Trading paused - Spread too high: " + DoubleToString(currentSpread, 1) + " pips";
    }
    
    // Display current statistics
    string comment = "";
    if(statusMsg != "")
        comment = "--- Status ---\n" + statusMsg + "\n\n";
        
    comment += "--- Trading Hours ---\n";
    if(UseTimer)
    {
        comment += "Trading Period: " + IntegerToString(StartHour) + ":00 - " + IntegerToString(EndHour) + ":00\n";
        comment += "Current Server Time: " + TimeToString(TimeCurrent(), TIME_MINUTES) + "\n\n";
    }
    else
    {
        comment += "Timer Disabled - Trading 24/7\n\n";
    }
    
    comment += "--- Trade Settings ---\n";
    comment += "Multiple Trades: " + (AllowMultipleTrades ? "Enabled" : "Disabled") + "\n";
    comment += "Trailing Stop: " + (UseTrailingStop ? "Enabled" : "Disabled") + "\n";
    comment += "RSI Close Confirmation: " + (RequireClose ? "Enabled" : "Disabled") + "\n";
    comment += "Limit Orders: " + (UseLimitOrders ? "Enabled" : "Disabled") + "\n";
    if(UseLimitOrders)
    {
        comment += "Entry Points: " + IntegerToString(DelayedEntryPoints) + "\n";
        comment += "Cancel Points: " + IntegerToString(CancelLimitPoints) + "\n";
    }
    comment += "Max Open Trades: " + IntegerToString(MaxOpenTrades) + "\n";
    comment += "Current Open Trades: " + IntegerToString(CountOpenTrades()) + "\n\n";
    
    comment += "--- Market Conditions ---\n";
    comment += "Current Spread: " + DoubleToString(currentSpread, 1) + " pips\n";
    comment += "Maximum Spread: " + DoubleToString(MaxSpread, 1) + " pips\n\n";
    
    comment += "--- Account Statistics ---\n";
    comment += "Initial Account Size: " + DoubleToString(initialAccountBalance, 2) + "\n";
    comment += "Current Balance: " + DoubleToString(AccountBalance(), 2) + "\n";
    comment += "Current Equity: " + DoubleToString(AccountEquity(), 2) + "\n";
    comment += "Total Profit: " + DoubleToString(AccountEquity() - initialAccountBalance, 2) + "\n";
    comment += "Current Drawdown: " + DoubleToString(initialAccountBalance - AccountEquity(), 2) + "\n\n";
    
    comment += "--- Daily Statistics ---\n";
    comment += "Daily Starting Balance: " + DoubleToString(initialBalance, 2) + "\n";
    comment += "Daily P/L: " + DoubleToString(AccountEquity() - initialBalance, 2) + "\n";
    comment += "Daily Profit Target: " + DoubleToString(DailyProfitTarget, 2) + "\n";
    comment += "Daily Loss Limit: " + DoubleToString(DailyLossLimit, 2);
    
    if(UseLimitOrders && limitOrderPlaced)
    {
        comment += "\n\n--- Limit Order Status ---\n";
        comment += "Type: " + (pendingOrderType == OP_BUYLIMIT ? "BUY LIMIT" : "SELL LIMIT") + "\n";
        if(OrderSelect(limitTicket, SELECT_BY_TICKET))
        {
            comment += "Entry Price: " + DoubleToString(OrderOpenPrice(), Digits) + "\n";
            comment += "Stop Loss: " + DoubleToString(OrderStopLoss(), Digits) + "\n";
            comment += "Take Profit: " + DoubleToString(OrderTakeProfit(), Digits) + "\n";
        }
        comment += "Cancel Level: " + DoubleToString(cancelLevel, Digits) + "\n";
    }
    
    Comment(comment);
    
    // Check limits before looking for new trades
    if(IsTotalLimitHit() || IsDailyTargetHit())
    {
        if(UseLimitOrders) DeletePendingOrders();
        return;
    }
    
    // Check if we're outside trading hours
    if(UseTimer && !IsWithinTradingHours()) return;
    
    // Check if we've reached maximum trades
    if(CountOpenTrades() >= MaxOpenTrades) return;
    
    // Check if we already have an open position and multiple trades are not allowed
    if(!AllowMultipleTrades && CountOpenTrades() > 0)
    {
        return;
    }
    
    // Check trading conditions
    if(IsFirstHourOfDay() || IsSpreadTooHigh()) return;
    
    // Calculate current and previous RSI
    double currentRSI = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE, 0);
    double localPrevRSI = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE, 1);
    
    // Trading logic
    if(CheckRSIConditions(currentRSI, localPrevRSI, true))  // Oversold condition - BUY Signal
    {
        if(UseLimitOrders && !limitOrderPlaced && limitTicket == 0)  // Add additional checks
        {
            PlaceLimitOrder(!InvertSignals, Ask);  // Invert if needed
        }
        else
        {
            if(!buySignalActive)
            {
                buySignalActive = true;
                sellSignalActive = false;
                g_signalPrice = Ask;
                lastSignalTime = Time[0];
                DrawSignalLine(g_signalPrice, !InvertSignals);  // Invert if needed
            }
            
            double stopLossPrice, takeProfitPrice;
            int orderType;
            color orderColor;
            string orderComment;
            
            if(!InvertSignals)  // Normal BUY signal
            {
                stopLossPrice = Bid - StopLoss * Point;
                takeProfitPrice = Ask + TakeProfit * Point;
                orderType = OP_BUY;
                orderColor = clrGreen;
                orderComment = "RSI EA Buy";
            }
            else  // Inverted to SELL
            {
                stopLossPrice = Ask + StopLoss * Point;
                takeProfitPrice = Bid - TakeProfit * Point;
                orderType = OP_SELL;
                orderColor = clrRed;
                orderComment = "RSI EA Inverted Sell";
            }
            
            int ticket = OrderSend(Symbol(), orderType, LotSize, 
                                 orderType == OP_BUY ? Ask : Bid, 3, 
                                 stopLossPrice, takeProfitPrice,
                                 orderComment, 0, 0, orderColor);
                                 
            if(ticket < 0)
            {
                Print("OrderSend failed with error #", GetLastError());
            }
            else
            {
                Print(orderComment, " order opened - RSI: ", currentRSI);
                buySignalActive = false;
                g_signalPrice = 0;
                CleanupSignalLines();
            }
        }
    }
    else if(CheckRSIConditions(currentRSI, localPrevRSI, false))  // Overbought condition - SELL Signal
    {
        if(UseLimitOrders && !limitOrderPlaced && limitTicket == 0)  // Add additional checks
        {
            PlaceLimitOrder(!InvertSignals, Bid);  // Invert if needed
        }
        else
        {
            if(!sellSignalActive)
            {
                sellSignalActive = true;
                buySignalActive = false;
                g_signalPrice = Bid;
                lastSignalTime = Time[0];
                DrawSignalLine(g_signalPrice, !InvertSignals);  // Invert if needed
            }
            
            double stopLossPrice, takeProfitPrice;
            int orderType;
            color orderColor;
            string orderComment;
            
            if(!InvertSignals)  // Normal SELL signal
            {
                stopLossPrice = Ask + StopLoss * Point;
                takeProfitPrice = Bid - TakeProfit * Point;
                orderType = OP_SELL;
                orderColor = clrRed;
                orderComment = "RSI EA Sell";
            }
            else  // Inverted to BUY
            {
                stopLossPrice = Bid - StopLoss * Point;
                takeProfitPrice = Ask + TakeProfit * Point;
                orderType = OP_BUY;
                orderColor = clrGreen;
                orderComment = "RSI EA Inverted Buy";
            }
            
            int ticket = OrderSend(Symbol(), orderType, LotSize,
                                 orderType == OP_BUY ? Ask : Bid, 3,
                                 stopLossPrice, takeProfitPrice,
                                 orderComment, 0, 0, orderColor);
                                 
            if(ticket < 0)
            {
                Print("OrderSend failed with error #", GetLastError());
            }
            else
            {
                Print(orderComment, " order opened - RSI: ", currentRSI);
                sellSignalActive = false;
                g_signalPrice = 0;
                CleanupSignalLines();
            }
        }
    }
    else
    {
        // Reset signals if conditions are no longer met
        if(!UseLimitOrders && (buySignalActive || sellSignalActive))
        {
            buySignalActive = false;
            sellSignalActive = false;
            g_signalPrice = 0;
            CleanupSignalLines();
        }
    }
    
    // Update previous RSI value
    g_previousRSI = currentRSI;
}