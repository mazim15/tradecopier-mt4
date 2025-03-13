//+------------------------------------------------------------------+
//|                                                 TradeCopier.mq4   |
//|                                                                   |
//|                                                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Enumeration for EA mode
enum COPIER_MODE {
   MODE_SENDER,    // Sender
   MODE_RECEIVER   // Receiver
};

// Input parameters
input COPIER_MODE EAMode = MODE_SENDER;       // EA Mode
input string      PipeName = "MT4TradeCopier"; // Pipe Name for communication
input double      LotMultiplier = 1.0;        // Lot size multiplier for receiver
input int         MaxSlippage = 3;            // Maximum allowed slippage in pips
input color       ConnectedColor = clrGreen;  // Color when connected
input color       DisconnectedColor = clrRed; // Color when disconnected

// Global variables
int pipeHandle = INVALID_HANDLE;
bool isConnected = false;
string labelName = "TradeCopierStatus";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize communication pipe
   if(EAMode == MODE_SENDER) {
      pipeHandle = FileOpen("\\\\.\\pipe\\" + PipeName, FILE_WRITE|FILE_BIN);
   } else {
      pipeHandle = FileOpen("\\\\.\\pipe\\" + PipeName, FILE_READ|FILE_BIN);
   }
   
   isConnected = (pipeHandle != INVALID_HANDLE);
   
   // Create visual indicator for connection status
   CreateStatusLabel();
   UpdateStatusLabel();
   
   // Set up timer for regular checks
   EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Close pipe
   if(pipeHandle != INVALID_HANDLE) {
      FileClose(pipeHandle);
      pipeHandle = INVALID_HANDLE;
   }
   
   // Remove visual elements
   ObjectDelete(labelName);
   
   // Kill timer
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Your tick processing code here
   // For this EA, we don't need to do anything special on tick
   // as we're using OnTrade and OnTimer for our main functionality
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer() {
   // Check connection status
   if(EAMode == MODE_SENDER) {
      if(pipeHandle == INVALID_HANDLE) {
         pipeHandle = FileOpen("\\\\.\\pipe\\" + PipeName, FILE_WRITE|FILE_BIN);
         isConnected = (pipeHandle != INVALID_HANDLE);
         UpdateStatusLabel();
      }
   } else {
      if(pipeHandle == INVALID_HANDLE) {
         pipeHandle = FileOpen("\\\\.\\pipe\\" + PipeName, FILE_READ|FILE_BIN);
         isConnected = (pipeHandle != INVALID_HANDLE);
         UpdateStatusLabel();
      } else {
         // Check for new trade signals
         CheckForTradeSignals();
      }
   }
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade() {
   if(EAMode == MODE_SENDER && isConnected) {
      SendTradeSignals();
   }
}

//+------------------------------------------------------------------+
//| Create status label on chart                                     |
//+------------------------------------------------------------------+
void CreateStatusLabel() {
   ObjectCreate(labelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetText(labelName, "Trade Copier: " + (EAMode == MODE_SENDER ? "Sender" : "Receiver"), 10, "Arial", clrWhite);
   ObjectSet(labelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSet(labelName, OBJPROP_XDISTANCE, 10);
   ObjectSet(labelName, OBJPROP_YDISTANCE, 20);
}

//+------------------------------------------------------------------+
//| Update status label on chart                                     |
//+------------------------------------------------------------------+
void UpdateStatusLabel() {
   string statusText = "Trade Copier: " + (EAMode == MODE_SENDER ? "Sender" : "Receiver");
   statusText += " - " + (isConnected ? "Connected" : "Disconnected");
   
   ObjectSetText(labelName, statusText, 10, "Arial", isConnected ? ConnectedColor : DisconnectedColor);
}

//+------------------------------------------------------------------+
//| Send trade signals to receiver                                   |
//+------------------------------------------------------------------+
void SendTradeSignals() {
   if(pipeHandle == INVALID_HANDLE) return;
   
   // Get current open orders
   int totalOrders = OrdersTotal();
   
   // Prepare data to send
   string data = "";
   
   for(int i = 0; i < totalOrders; i++) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         // Only send signals for current symbol
         if(OrderSymbol() == Symbol()) {
            data += OrderTicket() + "," + 
                   OrderSymbol() + "," + 
                   OrderType() + "," + 
                   DoubleToString(OrderLots(), 2) + "," + 
                   DoubleToString(OrderOpenPrice(), 5) + "," + 
                   DoubleToString(OrderStopLoss(), 5) + "," + 
                   DoubleToString(OrderTakeProfit(), 5) + "," + 
                   OrderMagicNumber() + "," + 
                   OrderComment() + ";";
         }
      }
   }
   
   // Send data through pipe
   if(data != "") {
      FileWriteString(pipeHandle, data, StringLen(data));
      FileFlush(pipeHandle);
   }
}

//+------------------------------------------------------------------+
//| Check for trade signals from sender                              |
//+------------------------------------------------------------------+
void CheckForTradeSignals() {
   if(pipeHandle == INVALID_HANDLE) return;
   
   // Check if data is available
   if(FileIsEnding(pipeHandle)) return;
   
   // Read data from pipe
   string data = FileReadString(pipeHandle);
   
   if(data == "") return;
   
   // Process trade signals
   string signals[];
   int signalCount = StringSplit(data, ';', signals);
   
   for(int i = 0; i < signalCount; i++) {
      if(signals[i] == "") continue;
      
      // Parse signal data
      string parts[];
      StringSplit(signals[i], ',', parts);
      
      if(ArraySize(parts) < 9) continue;
      
      int ticket = (int)StringToInteger(parts[0]);
      string symbol = parts[1];
      int type = (int)StringToInteger(parts[2]);
      double lots = NormalizeDouble(StringToDouble(parts[3]) * LotMultiplier, 2);
      double price = NormalizeDouble(StringToDouble(parts[4]), 5);
      double sl = NormalizeDouble(StringToDouble(parts[5]), 5);
      double tp = NormalizeDouble(StringToDouble(parts[6]), 5);
      int magic = (int)StringToInteger(parts[7]);
      string comment = parts[8];
      
      // Check if we already have this trade
      bool tradeExists = false;
      int totalOrders = OrdersTotal();
      
      for(int j = 0; j < totalOrders; j++) {
         if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) {
            if(OrderSymbol() == symbol && OrderMagicNumber() == magic && 
               OrderType() == type && OrderComment() == "Copy: " + ticket) {
               tradeExists = true;
               break;
            }
         }
      }
      
      // Open new trade if it doesn't exist
      if(!tradeExists) {
         OpenTrade(symbol, type, lots, price, sl, tp, magic, "Copy: " + ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Open a new trade based on signal                                 |
//+------------------------------------------------------------------+
bool OpenTrade(string symbol, int type, double lots, double price, 
               double sl, double tp, int magic, string comment) {
   int ticket = -1;
   
   // Adjust for current market price
   double currentPrice = 0;
   if(type == OP_BUY) {
      currentPrice = MarketInfo(symbol, MODE_ASK);
   } else if(type == OP_SELL) {
      currentPrice = MarketInfo(symbol, MODE_BID);
   }
   
   // Check if price is within allowed slippage
   int priceDiff = (int)MathAbs((currentPrice - price) / Point);
   if(priceDiff > MaxSlippage) {
      price = currentPrice; // Use current price if slippage is too high
   }
   
   // Open the trade
   if(type == OP_BUY) {
      ticket = OrderSend(symbol, OP_BUY, lots, MarketInfo(symbol, MODE_ASK), 
                        MaxSlippage, sl, tp, comment, magic, 0, clrBlue);
   } else if(type == OP_SELL) {
      ticket = OrderSend(symbol, OP_SELL, lots, MarketInfo(symbol, MODE_BID), 
                        MaxSlippage, sl, tp, comment, magic, 0, clrRed);
   }
   
   return (ticket > 0);
} 