//+------------------------------------------------------------------+
//|                                            RSI_DelayedEntryEA.mq5  |
//|                                             Copyright 2025         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"

// Include required MT5 files
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

// Create global trade object
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Input Parameters
input int    RSI_Period = 14;         // RSI Period
input int    RSI_Overbought = 70;     // RSI Overbought Level
input int    RSI_Oversold = 30;       // RSI Oversold Level
input bool   RequireClose = true;     // Require candle close confirmation
input double LotSize = 0.1;           // Trading Lot Size
input int    TakeProfit = 1200;       // Take Profit in points
input int    StopLoss = 600;          // Stop Loss in points
input bool   UseTrailingStop = false; // Enable/Disable trailing stop
input int    TrailingStart = 100;     // Start trailing after this many points in profit
input int    TrailingStep = 100;      // Points to maintain from current price
input double DailyProfitTarget = 200; // Daily profit target in account currency
input double DailyLossLimit = 200;    // Daily loss limit in account currency
input double TotalProfitTarget = 1000;// Total account profit target
input double MaxDrawdown = 1000;      // Maximum total drawdown allowed
input double MaxSpread = 3.0;         // Maximum allowed spread in pips
input bool   UseTimer = true;         // Enable/Disable trading hours
input int    StartHour = 2;          // Trading start hour (0-23)
input int    EndHour = 22;           // Trading end hour (0-23)
input bool   AllowMultipleTrades = false; // Allow multiple trades per signal
input int    MaxOpenTrades = 5;      // Maximum number of open trades allowed

// Limit Order Parameters
input bool   UseLimitOrders = false;  // Enable/Disable limit order entry
input int    DelayedEntryPoints = 10; // Points away for limit order entry
input int    CancelLimitPoints = 10;  // Points in opposite direction to cancel limit
input color  SignalLineColor = clrYellow; // Color for signal line
input bool   DrawSignalLines = true;  // Draw lines at signal points

// Global Variables
double initialBalance;
double initialAccountBalance;
datetime lastTradeDay = 0;
double g_previousRSI = 0.0;
datetime lastSignalTime = 0;
double g_signalPrice = 0;
bool buySignalActive = false;
bool sellSignalActive = false;
int signalLineCounter = 0;

// Limit Order Variables
bool limitOrderPlaced = false;
ulong limitTicket = 0;
ENUM_ORDER_TYPE pendingOrderType = ORDER_TYPE_BUY_LIMIT;
double cancelLevel = 0;

// Handle for RSI indicator
int rsiHandle;

// Add at the top after global variables:
double point; // Store point value with multiplier
int digits;   // Store digits for the symbol

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI indicator
    rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    if(rsiHandle == INVALID_HANDLE)
    {
        Print("Error creating RSI indicator");
        return INIT_FAILED;
    }

    // Calculate point value
    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(digits == 3 || digits == 5)
        point *= 10;

    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    initialAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Get initial RSI value
    double rsiBuffer[];
    ArraySetAsSeries(rsiBuffer, true);
    CopyBuffer(rsiHandle, 0, 1, 1, rsiBuffer);
    g_previousRSI = rsiBuffer[0];
    
    if(UseTimer)
    {
        if(StartHour < 0 || StartHour > 23 || EndHour < 0 || EndHour > 23)
        {
            Print("Invalid trading hours! Hours must be between 0-23");
            return INIT_PARAMETERS_INCORRECT;
        }
    }
    
    // Configure trade object
    trade.SetExpertMagicNumber(123456); // Set unique magic number
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(_Symbol);
    trade.SetDeviationInPoints(30); // Equivalent to slippage of 3

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release RSI indicator handle
    if(rsiHandle != INVALID_HANDLE)
        IndicatorRelease(rsiHandle);
        
    CleanupSignalLines();
    if(UseLimitOrders) DeletePendingOrders();
}

//+------------------------------------------------------------------+
//| Check for closed trades                                            |
//+------------------------------------------------------------------+
void CheckForClosedTrades()
{
    // Check if any limits are hit first
    if(IsTotalLimitHit() || IsDailyTargetHit())
    {
        if(UseLimitOrders)
        {
            DeletePendingOrders();
            CleanupSignalLines();
        }
        return;
    }

    // Get history deals for the current day
    HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
    
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket <= 0) continue;

        // Check if deal is from this EA and symbol
        if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol && 
           HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == trade.RequestMagic())
        {
            // Check if deal was closed in the last tick
            if(HistoryDealGetInteger(dealTicket, DEAL_TIME) >= iTime(_Symbol, PERIOD_CURRENT, 0))
            {
                ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                bool wasBuy = (dealType == DEAL_TYPE_BUY);
                double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                
                // Reset signals
                buySignalActive = false;
                sellSignalActive = false;
                g_signalPrice = 0;
                limitOrderPlaced = false;
                limitTicket = 0;
                pendingOrderType = ORDER_TYPE_BUY_LIMIT;
                cancelLevel = 0;
                CleanupSignalLines();
                
                // If it was a stop loss, open new market order immediately
                if(dealProfit < 0 && !IsTotalLimitHit() && !IsDailyTargetHit() && CountOpenTrades() == 0)
                {
                    double stopLossPrice, takeProfitPrice;
                    if(wasBuy)
                    {
                        stopLossPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) - StopLoss * point;
                        takeProfitPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TakeProfit * point;
                        
                        trade.Buy(LotSize, _Symbol, 0, stopLossPrice, takeProfitPrice, "RSI EA Buy");
                    }
                    else
                    {
                        stopLossPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + StopLoss * point;
                        takeProfitPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TakeProfit * point;
                        
                        trade.Sell(LotSize, _Symbol, 0, stopLossPrice, takeProfitPrice, "RSI EA Sell");
                    }
                }
                break;
            }
        }
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
    ObjectCreate(0, "Label_Signal", OBJ_TEXT, 0, TimeCurrent(), price);
    ObjectSetString(0, "Label_Signal", OBJPROP_TEXT, "Signal Price");
    ObjectCreate(0, "Label_Limit", OBJ_TEXT, 0, TimeCurrent(), limitPrice);
    ObjectSetString(0, "Label_Limit", OBJPROP_TEXT, isBuySignal ? "Buy Limit" : "Sell Limit");
    ObjectCreate(0, "Label_Cancel", OBJ_TEXT, 0, TimeCurrent(), cancelPrice);
    ObjectSetString(0, "Label_Cancel", OBJPROP_TEXT, "Cancel Level");
}

//+------------------------------------------------------------------+
//| Clean up signal lines                                             |
//+------------------------------------------------------------------+
void CleanupSignalLines()
{
    for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "SignalLine_") >= 0 || StringFind(name, "SignalLabel_") >= 0 ||
           StringFind(name, "Label_") >= 0)
        {
            ObjectDelete(0, name);
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
        if(orderInfo.Select(limitTicket))
        {
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)orderInfo.OrderType();
            if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
            {
                if(!trade.OrderDelete(limitTicket))
                {
                    Print("Failed to delete pending order #", limitTicket, ". Error: ", GetLastError());
                }
            }
        }
        limitTicket = 0;
        limitOrderPlaced = false;
        pendingOrderType = ORDER_TYPE_BUY_LIMIT;
        cancelLevel = 0;
    }
}

//+------------------------------------------------------------------+
//| Count current open trades                                          |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol)
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
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int currentHour = dt.hour;
    
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
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return (dt.hour == 0);
}

//+------------------------------------------------------------------+
//| Check if spread is too high                                        |
//+------------------------------------------------------------------+
bool IsSpreadTooHigh()
{
    double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) / 10.0;
    return (currentSpread > MaxSpread);
}

//+------------------------------------------------------------------+
//| Close all open positions                                          |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol)
            {
                trade.PositionClose(positionInfo.Ticket());
                if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
                {
                    Print("Failed to close position #", positionInfo.Ticket(), 
                          ". Error: ", trade.ResultRetcode());
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
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol)
            {
                ENUM_POSITION_TYPE posType = positionInfo.PositionType();
                double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                                    SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                                    
                if(posType == POSITION_TYPE_BUY)
                {
                    double currentProfit = currentPrice - positionInfo.PriceOpen();
                    if(currentProfit >= TrailingStart * point)
                    {
                        double newStopLoss = currentPrice - TrailingStep * point;
                        if(newStopLoss > positionInfo.StopLoss() + point)
                        {
                            trade.PositionModify(positionInfo.Ticket(), 
                                               newStopLoss, 
                                               positionInfo.TakeProfit());
                        }
                    }
                }
                else if(posType == POSITION_TYPE_SELL)
                {
                    double currentProfit = positionInfo.PriceOpen() - currentPrice;
                    if(currentProfit >= TrailingStart * point)
                    {
                        double newStopLoss = currentPrice + TrailingStep * point;
                        if(positionInfo.StopLoss() == 0 || newStopLoss < positionInfo.StopLoss() - point)
                        {
                            trade.PositionModify(positionInfo.Ticket(), 
                                               newStopLoss, 
                                               positionInfo.TakeProfit());
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
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
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
    datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
    
    if(currentDay != lastTradeDay)
    {
        initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        lastTradeDay = currentDay;
        return false;
    }
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
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
    
    if(pendingOrderType == ORDER_TYPE_BUY_LIMIT)
    {
        return (SymbolInfoDouble(_Symbol, SYMBOL_BID) >= cancelLevel);
    }
    else if(pendingOrderType == ORDER_TYPE_SELL_LIMIT)
    {
        return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= cancelLevel);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Place limit order                                                 |
//+------------------------------------------------------------------+
void PlaceLimitOrder(bool isBuySignal, double localSignalPrice)
{
    // Check if there's already a limit order or if we have open trades
    if(limitOrderPlaced || limitTicket > 0) return;
    
    // Check limits before placing limit order
    if(IsTotalLimitHit() || IsDailyTargetHit())
    {
        Print("Account limits reached - not placing limit order");
        return;
    }
    
    double limitPrice, stopLossPrice, takeProfitPrice;
    
    if(isBuySignal)
    {
        limitPrice = localSignalPrice - DelayedEntryPoints * point;
        stopLossPrice = limitPrice - StopLoss * point;
        takeProfitPrice = limitPrice + TakeProfit * point;
        cancelLevel = localSignalPrice + CancelLimitPoints * point;
        pendingOrderType = ORDER_TYPE_BUY_LIMIT;
    }
    else
    {
        limitPrice = localSignalPrice + DelayedEntryPoints * point;
        stopLossPrice = limitPrice + StopLoss * point;
        takeProfitPrice = limitPrice - TakeProfit * point;
        cancelLevel = localSignalPrice - CancelLimitPoints * point;
        pendingOrderType = ORDER_TYPE_SELL_LIMIT;
    }
    
    // Set flags before placing order to prevent race conditions
    limitOrderPlaced = true;
    
    if(trade.OrderOpen(_Symbol, pendingOrderType, LotSize, 0, limitPrice, 
                      stopLossPrice, takeProfitPrice, 0, 0, "RSI EA Limit"))
    {
        limitTicket = trade.ResultOrder();
        DrawLimitOrderLines(localSignalPrice, limitPrice, cancelLevel, isBuySignal);
        Print("Limit order placed at ", limitPrice, " Cancel level: ", cancelLevel);
    }
    else
    {
        Print("Error placing limit order: ", GetLastError());
        // Reset flags if order placement failed
        limitOrderPlaced = false;
        limitTicket = 0;
        pendingOrderType = ORDER_TYPE_BUY_LIMIT;
        cancelLevel = 0;
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
    if(!orderInfo.Select(limitTicket)) return;
    
    // If order is no longer pending, it was either filled or cancelled
    ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)orderInfo.OrderType();
    if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
    {
        // Reset limit order flags
        limitOrderPlaced = false;
        limitTicket = 0;
        pendingOrderType = ORDER_TYPE_BUY_LIMIT;
        cancelLevel = 0;
        CleanupSignalLines();
    }
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
    double currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) / 10.0;
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
    comment += "Current Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
    comment += "Current Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
    comment += "Total Profit: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY) - initialAccountBalance, 2) + "\n";
    comment += "Current Drawdown: " + DoubleToString(initialAccountBalance - AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n\n";
    
    comment += "--- Daily Statistics ---\n";
    comment += "Daily Starting Balance: " + DoubleToString(initialBalance, 2) + "\n";
    comment += "Daily P/L: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY) - initialBalance, 2) + "\n";
    comment += "Daily Profit Target: " + DoubleToString(DailyProfitTarget, 2) + "\n";
    comment += "Daily Loss Limit: " + DoubleToString(DailyLossLimit, 2);
    
    if(UseLimitOrders && limitOrderPlaced)
    {
        comment += "\n\n--- Limit Order Status ---\n";
        comment += "Type: " + (pendingOrderType == ORDER_TYPE_BUY_LIMIT ? "BUY LIMIT" : "SELL LIMIT") + "\n";
        if(orderInfo.Select(limitTicket))
        {
            comment += "Entry Price: " + DoubleToString(orderInfo.PriceOpen(), _Digits) + "\n";
            comment += "Stop Loss: " + DoubleToString(orderInfo.StopLoss(), _Digits) + "\n";
            comment += "Take Profit: " + DoubleToString(orderInfo.TakeProfit(), _Digits) + "\n";
        }
        comment += "Cancel Level: " + DoubleToString(cancelLevel, _Digits) + "\n";
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
    if(!AllowMultipleTrades && CountOpenTrades() > 0) return;
    
    // Check trading conditions
    if(IsFirstHourOfDay() || IsSpreadTooHigh()) return;
    
    // Calculate current and previous RSI
    double rsiBuffer[];
    ArraySetAsSeries(rsiBuffer, true);
    
    if(CopyBuffer(rsiHandle, 0, 0, 2, rsiBuffer) != 2)
    {
        Print("Error copying RSI buffer data");
        return;
    }
    
    double currentRSI = rsiBuffer[0];
    double localPrevRSI = rsiBuffer[1];
    
    // Trading logic
    if(CheckRSIConditions(currentRSI, localPrevRSI, true))  // Oversold condition - BUY Signal
    {
        if(UseLimitOrders)  // Changed condition check
        {
            if(!limitOrderPlaced && limitTicket == 0)
            {
                PlaceLimitOrder(true, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
            }
        }
        else  // Only execute market orders if limit orders are disabled
        {
            if(!buySignalActive)
            {
                buySignalActive = true;
                sellSignalActive = false;
                g_signalPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                lastSignalTime = iTime(_Symbol, PERIOD_CURRENT, 0);
                DrawSignalLine(g_signalPrice, true);
            }
            
            double stopLossPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) - StopLoss * point;
            double takeProfitPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TakeProfit * point;
            
            if(trade.Buy(LotSize, _Symbol, 0, stopLossPrice, takeProfitPrice, "RSI EA Buy"))
            {
                Print("Buy order opened - RSI: ", currentRSI);
                buySignalActive = false;
                g_signalPrice = 0;
                CleanupSignalLines();
            }
            else
            {
                Print("OrderSend failed with error #", GetLastError());
            }
        }
    }
    else if(CheckRSIConditions(currentRSI, localPrevRSI, false))  // Overbought condition - SELL Signal
    {
        if(UseLimitOrders)  // Changed condition check
        {
            if(!limitOrderPlaced && limitTicket == 0)
            {
                PlaceLimitOrder(false, SymbolInfoDouble(_Symbol, SYMBOL_BID));
            }
        }
        else  // Only execute market orders if limit orders are disabled
        {
            if(!sellSignalActive)
            {
                sellSignalActive = true;
                buySignalActive = false;
                g_signalPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                lastSignalTime = iTime(_Symbol, PERIOD_CURRENT, 0);
                DrawSignalLine(g_signalPrice, false);
            }
            
            double stopLossPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + StopLoss * point;
            double takeProfitPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TakeProfit * point;
            
            if(trade.Sell(LotSize, _Symbol, 0, stopLossPrice, takeProfitPrice, "RSI EA Sell"))
            {
                Print("Sell order opened - RSI: ", currentRSI);
                sellSignalActive = false;
                g_signalPrice = 0;
                CleanupSignalLines();
            }
            else
            {
                Print("OrderSend failed with error #", GetLastError());
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
    ObjectCreate(0, labelName, OBJ_TEXT, 0, TimeCurrent(), price);
    ObjectSetString(0, labelName, OBJPROP_TEXT, isBuySignal ? "Buy Signal" : "Sell Signal");
    ObjectSetInteger(0, labelName, OBJPROP_COLOR, SignalLineColor);
} 