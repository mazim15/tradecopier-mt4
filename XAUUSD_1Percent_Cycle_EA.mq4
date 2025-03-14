//+------------------------------------------------------------------+
//|                                     XAUUSD_1Percent_Cycle_EA.mq4 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

//--- Input Parameters: Risk Management
input double   InpRiskPercent = 0.5;        // Risk per trade (% of account)
input double   InpTargetPercent = 1.0;      // Target profit per cycle (% of account)
input int      InpMaxAttempts = 3;          // Maximum attempts per cycle
input double   InpMaxSpread = 35;           // Maximum allowed spread (points)
input bool     InpUseScaledExit = true;     // Use scaled exit strategy
input double   InpScaleOutPercent = 0.7;    // Scale out at this % of target
input bool     InpUseBreakEven = true;      // Enable breakeven stop
input double   InpBreakEvenActivation = 0.5; // Breakeven activation (% of target)
input double   InpBreakEvenPips = 10;       // Breakeven pips (added buffer)

//--- Input Parameters: Strategy Parameters
input int      InpConsolidationPeriod = 12; // Consolidation detection period (bars)
input double   InpVolatilityThreshold = 1.2;// Volatility threshold (ATR multiplier)
input double   InpBreakoutStrength = 0.5;   // Breakout confirmation strength
input int      InpRSIPeriod = 14;           // RSI Period
input int      InpRSIOverbought = 70;       // RSI Overbought level
input int      InpRSIOversold = 30;         // RSI Oversold level
input int      InpMACDFast = 12;            // MACD Fast EMA
input int      InpMACDSlow = 26;            // MACD Slow EMA
input int      InpMACDSignal = 9;           // MACD Signal period
input bool     InpUseMultiTimeframe = true; // Use multi-timeframe analysis
input int      InpConfirmationTF = 60;      // Confirmation timeframe (minutes)
input double   InpMinSRDistance = 50;       // Minimum S/R distance (points)

//--- Input Parameters: Time Filters
input int      InpStartHour = 8;            // Trading session start hour (GMT)
input int      InpEndHour = 20;             // Trading session end hour (GMT)
input bool     InpMondayEnabled = true;     // Enable Monday trading
input bool     InpTuesdayEnabled = true;    // Enable Tuesday trading
input bool     InpWednesdayEnabled = true;  // Enable Wednesday trading
input bool     InpThursdayEnabled = true;   // Enable Thursday trading
input bool     InpFridayEnabled = true;     // Enable Friday trading
input string   InpCycleStartDate = "";      // Cycle start date (format: YYYY.MM.DD)

//--- Input Parameters: Trade Management
input double   InpStopLossMultiplier = 1.5; // Stop loss multiplier (based on ATR)
input double   InpTrailingActivation = 0.7; // Trailing stop activation (% of target)
input double   InpTrailingDistance = 20;    // Trailing stop distance (points)
input int      InpMaxSlippage = 30;         // Maximum allowed slippage (points)
input bool     InpCloseOnNewSignal = false; // Close existing trade on new signal
input bool     InpSendAlerts = true;        // Send alerts on trade events
input bool     InpSendEmails = false;       // Send emails on trade events
input bool     InpSaveReports = true;       // Save trade reports to file

//--- Global Variables
datetime g_last_bar_time = 0;
int g_cycle_attempts = 0;
datetime g_cycle_start_time = 0;
datetime g_cycle_end_time = 0;
bool g_cycle_target_reached = false;
double g_account_size = 0;
double g_target_amount = 0;
double g_risk_amount = 0;
int g_ticket = 0;
bool g_trailing_activated = false;

//--- Indicator handles
int g_atr_handle;
int g_rsi_handle;
int g_bb_handle;

// Additional global variables for enhanced market analysis
double g_support_levels[5];
double g_resistance_levels[5];
int g_support_count = 0;
int g_resistance_count = 0;
double g_volatility_ratio = 0;
bool g_news_time = false;

// Additional global variables for risk management
bool g_breakeven_activated = false;
bool g_scaled_out = false;
double g_initial_stop_loss = 0;
double g_initial_risk_amount = 0;
double g_partial_lot_closed = 0;
int g_partial_ticket = 0;

// Additional global variables for trade management and monitoring
int g_last_error = 0;
datetime g_last_error_time = 0;
int g_error_count = 0;
string g_log_filename = "";
int g_consecutive_losses = 0;
double g_max_drawdown = 0;
double g_peak_balance = 0;
double g_trade_start_balance = 0;
bool g_recovery_mode = false;
datetime g_last_trade_time = 0;
int g_trade_count = 0;
double g_total_profit = 0;
double g_total_pips = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize account metrics
   g_account_size = AccountBalance();
   g_target_amount = g_account_size * InpTargetPercent / 100.0;
   g_risk_amount = g_account_size * InpRiskPercent / 100.0;
   
   // Initialize indicator handles - fixing parameter count errors for MT4
   // In MT4, these functions return values, not handles
   // The correct parameter format for MT4 is different from MT5
   g_atr_handle = 0; // Not used in MT4
   g_rsi_handle = 0; // Not used in MT4
   g_bb_handle = 0;  // Not used in MT4
   
   // Initialize cycle timing
   if (InpCycleStartDate != "") {
      g_cycle_start_time = StringToTime(InpCycleStartDate);
      g_cycle_end_time = g_cycle_start_time + 14 * 24 * 60 * 60; // 14 days in seconds
   } else {
      g_cycle_start_time = TimeCurrent();
      g_cycle_end_time = g_cycle_start_time + 14 * 24 * 60 * 60; // 14 days in seconds
   }
   
   // Initialize support and resistance arrays
   ArrayInitialize(g_support_levels, 0);
   ArrayInitialize(g_resistance_levels, 0);
   
   // Initialize log file
   if (InpSaveReports) {
      g_log_filename = "XAUUSD_1Percent_Cycle_EA_" + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
      int file_handle = FileOpen(g_log_filename, FILE_WRITE|FILE_TXT);
      if (file_handle != INVALID_HANDLE) {
         FileWriteString(file_handle, "XAUUSD 1% Cycle EA Log - Started at " + 
                        TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n");
         FileWriteString(file_handle, "Account: " + AccountCompany() + ", " + AccountName() + "\n");
         FileWriteString(file_handle, "Initial Balance: $" + DoubleToString(AccountBalance(), 2) + "\n");
         FileWriteString(file_handle, "Target per cycle: $" + DoubleToString(g_target_amount, 2) + 
                        " (" + DoubleToString(InpTargetPercent, 1) + "%)\n");
         FileWriteString(file_handle, "Risk per trade: $" + DoubleToString(g_risk_amount, 2) + 
                        " (" + DoubleToString(InpRiskPercent, 1) + "%)\n\n");
         FileWriteString(file_handle, "TRADE LOG:\n");
         FileWriteString(file_handle, "-------------------------------------------\n");
         FileClose(file_handle);
      } else {
         Print("Error creating log file: ", GetLastError());
      }
   }
   
   // Initialize performance tracking
   g_peak_balance = AccountBalance();
   g_trade_start_balance = AccountBalance();
   
   // Send initialization notification
   if (InpSendAlerts) {
      Alert("XAUUSD 1% Cycle EA initialized on ", Symbol(), " ", PeriodToString(Period()));
   }
   
   if (InpSendEmails) {
      SendMail("XAUUSD 1% Cycle EA Started", 
              "EA initialized on " + Symbol() + " " + PeriodToString(Period()) + 
              "\nAccount Balance: $" + DoubleToString(AccountBalance(), 2) + 
              "\nTarget: $" + DoubleToString(g_target_amount, 2));
   }
   
   // Log initialization
   Print("XAUUSD 1% Cycle EA initialized");
   Print("Account size: $", g_account_size);
   Print("Target amount: $", g_target_amount);
   Print("Risk amount: $", g_risk_amount);
   Print("Cycle start: ", TimeToString(g_cycle_start_time, TIME_DATE|TIME_MINUTES));
   Print("Cycle end: ", TimeToString(g_cycle_end_time, TIME_DATE|TIME_MINUTES));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // In MT4, we don't need to release indicator handles
   // So we'll remove the IndicatorRelease calls
   
   // Generate final report
   if (InpSaveReports) {
      int file_handle = FileOpen(g_log_filename, FILE_READ|FILE_WRITE|FILE_TXT);
      if (file_handle != INVALID_HANDLE) {
         // Seek to end of file
         FileSeek(file_handle, 0, SEEK_END);
         
         // Write summary
         FileWriteString(file_handle, "\n-------------------------------------------\n");
         FileWriteString(file_handle, "SUMMARY REPORT - " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\n");
         FileWriteString(file_handle, "Total trades: " + IntegerToString(g_trade_count) + "\n");
         FileWriteString(file_handle, "Total profit: $" + DoubleToString(g_total_profit, 2) + 
                        " (" + DoubleToString(g_total_profit / g_trade_start_balance * 100, 2) + "%)\n");
         FileWriteString(file_handle, "Total pips: " + DoubleToString(g_total_pips, 1) + "\n");
         FileWriteString(file_handle, "Maximum drawdown: $" + DoubleToString(g_max_drawdown, 2) + 
                        " (" + DoubleToString(g_max_drawdown / g_peak_balance * 100, 2) + "%)\n");
         FileWriteString(file_handle, "Final balance: $" + DoubleToString(AccountBalance(), 2) + "\n");
         FileWriteString(file_handle, "-------------------------------------------\n");
         FileClose(file_handle);
      }
   }
   
   // Send deinitialization notification
   if (InpSendAlerts) {
      Alert("XAUUSD 1% Cycle EA stopped. Reason: ", GetDeinitReasonText(reason));
   }
   
   if (InpSendEmails) {
      SendMail("XAUUSD 1% Cycle EA Stopped", 
              "EA stopped on " + Symbol() + " " + PeriodToString(Period()) + 
              "\nReason: " + GetDeinitReasonText(reason) + 
              "\nFinal Balance: $" + DoubleToString(AccountBalance(), 2) + 
              "\nTotal Profit: $" + DoubleToString(g_total_profit, 2));
   }
}

//+------------------------------------------------------------------+
//| Convert timeframe to string                                       |
//+------------------------------------------------------------------+
string PeriodToString(int period)
{
   switch(period) {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Get deinitialization reason as text                               |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
   switch(reason) {
      case REASON_PROGRAM:     return "Program";
      case REASON_REMOVE:      return "EA removed from chart";
      case REASON_RECOMPILE:   return "EA recompiled";
      case REASON_CHARTCHANGE: return "Symbol or timeframe changed";
      case REASON_CHARTCLOSE:  return "Chart closed";
      case REASON_PARAMETERS:  return "Parameters changed";
      case REASON_ACCOUNT:     return "Account changed";
      case REASON_TEMPLATE:    return "New template applied";
      case REASON_INITFAILED:  return "Initialization failed";
      case REASON_CLOSE:       return "Terminal closed";
      default:                 return "Unknown reason";
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update performance tracking
   UpdatePerformanceMetrics();
   
   // Check for new bar
   if (!IsNewBar()) return;
   
   // Update account metrics
   UpdateAccountMetrics();
   
   // Check if cycle target reached
   if (g_cycle_target_reached) {
      // If we have an open position, manage it
      if (g_ticket > 0 && OrderSelect(g_ticket, SELECT_BY_TICKET)) {
         if (OrderCloseTime() == 0) {
            ManageOpenTrade();
         } else {
            g_ticket = 0; // Reset ticket if order is closed
         }
      }
      return; // Don't open new trades if target reached
   }
   
   // Check if we're in a valid trading time
   if (!IsTradingTime()) return;
   
   // Check if we're within the cycle period
   if (!IsWithinCycle()) {
      // If cycle ended, start a new one
      if (TimeCurrent() > g_cycle_end_time) {
         StartNewCycle();
      }
      return;
   }
   
   // Check if we've reached maximum attempts
   if (g_cycle_attempts >= InpMaxAttempts) {
      LogTradeActivity("Maximum cycle attempts reached (" + IntegerToString(g_cycle_attempts) + 
                      "/" + IntegerToString(InpMaxAttempts) + ")");
      return;
   }
   
   // Check for open positions
   if (g_ticket > 0) {
      if (OrderSelect(g_ticket, SELECT_BY_TICKET) && OrderCloseTime() == 0) {
         ManageOpenTrade();
         return;
      } else {
         g_ticket = 0; // Reset ticket if order is closed
      }
   }
   
   // Check spread before analysis
   if (CheckSpread()) {
      // Analyze market conditions and generate signals
      AnalyzeMarket();
   }
}

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current_bar_time = iTime(Symbol(), PERIOD_CURRENT, 0);
   if (current_bar_time != g_last_bar_time) {
      g_last_bar_time = current_bar_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if current time is within allowed trading hours             |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   datetime current_time = TimeCurrent();
   int current_hour = TimeHour(current_time);
   int current_day = TimeDayOfWeek(current_time);
   
   // Check trading hours
   if (current_hour < InpStartHour || current_hour >= InpEndHour) {
      return false;
   }
   
   // Check day of week
   switch (current_day) {
      case 1: return InpMondayEnabled;
      case 2: return InpTuesdayEnabled;
      case 3: return InpWednesdayEnabled;
      case 4: return InpThursdayEnabled;
      case 5: return InpFridayEnabled;
      default: return false; // No weekend trading
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within the cycle period                  |
//+------------------------------------------------------------------+
bool IsWithinCycle()
{
   datetime current_time = TimeCurrent();
   return (current_time >= g_cycle_start_time && current_time <= g_cycle_end_time);
}

//+------------------------------------------------------------------+
//| Check if spread is within acceptable limits                       |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   double current_spread = MarketInfo(Symbol(), MODE_SPREAD);
   
   if (current_spread > InpMaxSpread) {
      LogTradeActivity("Spread too high: " + DoubleToString(current_spread, 1) + 
                      " > " + DoubleToString(InpMaxSpread, 1) + " points");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Start a new trading cycle                                         |
//+------------------------------------------------------------------+
void StartNewCycle()
{
   g_cycle_start_time = TimeCurrent();
   g_cycle_end_time = g_cycle_start_time + 14 * 24 * 60 * 60; // 14 days in seconds
   g_cycle_attempts = 0;
   g_cycle_target_reached = false;
   g_trailing_activated = false;
   g_breakeven_activated = false;
   g_scaled_out = false;
   g_partial_lot_closed = 0;
   g_partial_ticket = 0;
   
   // Update account metrics for the new cycle
   UpdateAccountMetrics();
   
   // Log new cycle
   Print("Starting new trading cycle");
   Print("Cycle start: ", TimeToString(g_cycle_start_time, TIME_DATE|TIME_MINUTES));
   Print("Cycle end: ", TimeToString(g_cycle_end_time, TIME_DATE|TIME_MINUTES));
   Print("Account size: $", g_account_size);
   Print("Target amount: $", g_target_amount);
}

//+------------------------------------------------------------------+
//| Update account metrics                                            |
//+------------------------------------------------------------------+
void UpdateAccountMetrics()
{
   double current_balance = AccountBalance();
   double current_equity = AccountEquity();
   
   // Check if target reached
   if (!g_cycle_target_reached && current_equity >= g_account_size + g_target_amount) {
      g_cycle_target_reached = true;
      Print("Cycle target of ", InpTargetPercent, "% reached! Current equity: $", current_equity);
      
      // If we have an open position, consider closing it
      if (g_ticket > 0 && OrderSelect(g_ticket, SELECT_BY_TICKET) && OrderCloseTime() == 0) {
         // Close the position if we've reached our target
         if (OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 5, clrGreen)) {
            Print("Position closed after reaching cycle target");
            g_ticket = 0;
         } else {
            Print("Error closing position: ", GetLastError());
         }
      }
   }
   
   // Update account size if a new cycle is starting
   if (TimeCurrent() >= g_cycle_end_time || g_cycle_target_reached) {
      g_account_size = current_balance;
      g_target_amount = g_account_size * InpTargetPercent / 100.0;
      g_risk_amount = g_account_size * InpRiskPercent / 100.0;
   }
}

//+------------------------------------------------------------------+
//| Analyze market conditions and generate signals                    |
//+------------------------------------------------------------------+
void AnalyzeMarket()
{
   // Update market analysis data
   UpdateMarketData();
   
   // Check for news events
   if (IsNewsTime()) {
      Print("Skipping analysis during news time");
      return;
   }
   
   // Check for consolidation
   if (IsConsolidation()) {
      Print("Market is in consolidation, checking for breakout...");
      
      // Find key support and resistance levels
      IdentifySupportResistanceLevels();
      
      // Check for breakout
      int breakout_direction = DetectBreakout();
      if (breakout_direction != 0) {
         // Validate with momentum
         if (HasMomentumConfirmation(breakout_direction)) {
            // Check multi-timeframe confirmation if enabled
            if (!InpUseMultiTimeframe || HasMultiTimeframeConfirmation(breakout_direction)) {
               // Execute trade
               ExecuteTrade(breakout_direction);
            } else {
               Print("Breakout detected but multi-timeframe confirmation failed");
            }
         } else {
            Print("Breakout detected but momentum confirmation failed");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update market analysis data                                       |
//+------------------------------------------------------------------+
void UpdateMarketData()
{
   // Calculate current market volatility ratio
   double current_atr = iATR(Symbol(), PERIOD_CURRENT, 14, 1);
   double long_term_atr = iATR(Symbol(), PERIOD_CURRENT, 50, 1);
   
   if (long_term_atr > 0) {
      g_volatility_ratio = current_atr / long_term_atr;
   } else {
      g_volatility_ratio = 1.0;
   }
   
   // Check for scheduled news events (placeholder - would need external data source)
   g_news_time = false; // Replace with actual news check if available
   
   // Log market data update
   LogTradeActivity("Market data updated: Volatility ratio = " + DoubleToString(g_volatility_ratio, 2));
}

//+------------------------------------------------------------------+
//| Check if it's a high-impact news time                             |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   // This is a placeholder - in a real implementation, you would:
   // 1. Connect to a news calendar API or use a pre-loaded news schedule
   // 2. Check if current time is within X minutes of high-impact news for XAUUSD
   
   return g_news_time;
}

//+------------------------------------------------------------------+
//| Check if the market is in consolidation                           |
//+------------------------------------------------------------------+
bool IsConsolidation()
{
   double bb_width_sum = 0;
   double atr_sum = 0;
   double price_range_sum = 0;
   double high_low_ratio_sum = 0;
   
   // Calculate average BB width, ATR, and price range over consolidation period
   for (int i = 1; i <= InpConsolidationPeriod; i++) {
      // Fix parameter count for MT4 indicator functions
      double upper_band = iBands(Symbol(), PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE, MODE_UPPER, i);
      double lower_band = iBands(Symbol(), PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE, MODE_LOWER, i);
      double middle_band = iBands(Symbol(), PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE, MODE_MAIN, i);
      double bb_width = upper_band - lower_band;
      double bb_percent = bb_width / middle_band * 100.0;
      bb_width_sum += bb_percent;
      
      // Fix parameter count for ATR
      double atr = iATR(Symbol(), PERIOD_CURRENT, 14, i);
      atr_sum += atr;
      
      double high = iHigh(Symbol(), PERIOD_CURRENT, i);
      double low = iLow(Symbol(), PERIOD_CURRENT, i);
      double range = high - low;
      price_range_sum += range;
      
      // Calculate high-low ratio compared to previous bars
      if (i < InpConsolidationPeriod) {
         double prev_high = iHigh(Symbol(), PERIOD_CURRENT, i+1);
         double prev_low = iLow(Symbol(), PERIOD_CURRENT, i+1);
         double prev_range = prev_high - prev_low;
         
         if (prev_range > 0) {
            high_low_ratio_sum += range / prev_range;
         }
      }
   }
   
   double avg_bb_percent = bb_width_sum / InpConsolidationPeriod;
   double avg_atr = atr_sum / InpConsolidationPeriod;
   double avg_price_range = price_range_sum / InpConsolidationPeriod;
   double avg_high_low_ratio = high_low_ratio_sum / (InpConsolidationPeriod - 1);
   
   // Current values - fix parameter count for MT4 indicator functions
   double current_bb_width = iBands(Symbol(), PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE, MODE_UPPER, 1) - 
                             iBands(Symbol(), PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double current_middle = iBands(Symbol(), PERIOD_CURRENT, 20, 2, 0, PRICE_CLOSE, MODE_MAIN, 1);
   double current_bb_percent = current_bb_width / current_middle * 100.0;
   double current_atr = iATR(Symbol(), PERIOD_CURRENT, 14, 1);
   double current_range = iHigh(Symbol(), PERIOD_CURRENT, 1) - iLow(Symbol(), PERIOD_CURRENT, 1);
   
   // Check if current volatility is below threshold compared to average
   bool low_bb_width = current_bb_percent < avg_bb_percent * InpVolatilityThreshold;
   bool low_atr = current_atr < avg_atr * InpVolatilityThreshold;
   bool low_range = current_range < avg_price_range * InpVolatilityThreshold;
   bool stable_ratio = avg_high_low_ratio > 0.7 && avg_high_low_ratio < 1.3; // Check for stability in ranges
   
   // Calculate price action pattern - looking for narrowing ranges
   bool narrowing_ranges = true;
   double prev_range = 0;
   for (int i = 1; i <= 5; i++) {
      double bar_range = iHigh(Symbol(), PERIOD_CURRENT, i) - iLow(Symbol(), PERIOD_CURRENT, i);
      if (i > 1 && bar_range > prev_range * 1.1) { // 10% tolerance
         narrowing_ranges = false;
         break;
      }
      prev_range = bar_range;
   }
   
   // Log consolidation analysis
   string consolidation_status = (low_bb_width && low_atr && (low_range || stable_ratio)) ? "TRUE" : "FALSE";
   LogTradeActivity("Consolidation analysis: " + consolidation_status + 
                   " (BB: " + DoubleToString(current_bb_percent, 2) + "/" + DoubleToString(avg_bb_percent, 2) + 
                   ", ATR: " + DoubleToString(current_atr, 2) + "/" + DoubleToString(avg_atr, 2) + ")");
   
   return (low_bb_width && low_atr && (low_range || stable_ratio));
}

//+------------------------------------------------------------------+
//| Identify support and resistance levels                            |
//+------------------------------------------------------------------+
void IdentifySupportResistanceLevels()
{
   // Reset arrays
   ArrayInitialize(g_support_levels, 0);
   ArrayInitialize(g_resistance_levels, 0);
   g_support_count = 0;
   g_resistance_count = 0;
   
   // Look for swing highs and lows over a longer period
   int lookback = InpConsolidationPeriod * 3; // Look back 3x the consolidation period
   
   // Find swing highs (resistance)
   for (int i = 2; i < lookback - 2; i++) {
      double high1 = iHigh(Symbol(), PERIOD_CURRENT, i);
      
      // Check if this is a swing high
      if (high1 > iHigh(Symbol(), PERIOD_CURRENT, i-1) && 
          high1 > iHigh(Symbol(), PERIOD_CURRENT, i-2) &&
          high1 > iHigh(Symbol(), PERIOD_CURRENT, i+1) && 
          high1 > iHigh(Symbol(), PERIOD_CURRENT, i+2)) {
         
         // Check if this level is already in our array (within a small range)
         bool level_exists = false;
         for (int j = 0; j < g_resistance_count; j++) {
            if (MathAbs(high1 - g_resistance_levels[j]) < InpMinSRDistance * Point() * 10) {
               level_exists = true;
               // Update with the more extreme value
               g_resistance_levels[j] = MathMax(high1, g_resistance_levels[j]);
               break;
            }
         }
         
         // Add new level if it doesn't exist and we have space
         if (!level_exists && g_resistance_count < ArraySize(g_resistance_levels)) {
            g_resistance_levels[g_resistance_count] = high1;
            g_resistance_count++;
         }
      }
   }
   
   // Find swing lows (support)
   for (int i = 2; i < lookback - 2; i++) {
      double low1 = iLow(Symbol(), PERIOD_CURRENT, i);
      
      // Check if this is a swing low
      if (low1 < iLow(Symbol(), PERIOD_CURRENT, i-1) && 
          low1 < iLow(Symbol(), PERIOD_CURRENT, i-2) &&
          low1 < iLow(Symbol(), PERIOD_CURRENT, i+1) && 
          low1 < iLow(Symbol(), PERIOD_CURRENT, i+2)) {
         
         // Check if this level is already in our array (within a small range)
         bool level_exists = false;
         for (int j = 0; j < g_support_count; j++) {
            if (MathAbs(low1 - g_support_levels[j]) < InpMinSRDistance * Point() * 10) {
               level_exists = true;
               // Update with the more extreme value
               g_support_levels[j] = MathMin(low1, g_support_levels[j]);
               break;
            }
         }
         
         // Add new level if it doesn't exist and we have space
         if (!level_exists && g_support_count < ArraySize(g_support_levels)) {
            g_support_levels[g_support_count] = low1;
            g_support_count++;
         }
      }
   }
   
   // Sort levels from nearest to furthest - fixing MODE_DESCENDING/ASCENDING errors
   if (g_support_count > 1) ArraySort(g_support_levels, g_support_count);
   if (g_resistance_count > 1) ArraySort(g_resistance_levels, g_resistance_count);
   
   // After sorting, we need to reverse the support array to have it in descending order
   if (g_support_count > 1) {
      double temp_array[];
      ArrayResize(temp_array, g_support_count);
      for (int i = 0; i < g_support_count; i++) {
         temp_array[i] = g_support_levels[g_support_count - 1 - i];
      }
      for (int i = 0; i < g_support_count; i++) {
         g_support_levels[i] = temp_array[i];
      }
   }
   
   // Log identified levels
   string support_str = "Support levels: ";
   for (int i = 0; i < g_support_count; i++) {
      support_str += DoubleToString(g_support_levels[i], Digits) + " ";
   }
   
   string resistance_str = "Resistance levels: ";
   for (int i = 0; i < g_resistance_count; i++) {
      resistance_str += DoubleToString(g_resistance_levels[i], Digits) + " ";
   }
   
   LogTradeActivity(support_str);
   LogTradeActivity(resistance_str);
}

//+------------------------------------------------------------------+
//| Detect breakout direction (1 for up, -1 for down, 0 for none)     |
//+------------------------------------------------------------------+
int DetectBreakout()
{
   // Get current price data
   double current_close = iClose(Symbol(), PERIOD_CURRENT, 0);
   double previous_close = iClose(Symbol(), PERIOD_CURRENT, 1);
   
   // Calculate breakout thresholds - fix parameter count for ATR
   double atr = iATR(Symbol(), PERIOD_CURRENT, 14, 1);
   // CHANGE: Reduce breakout threshold for more sensitivity
   double breakout_threshold = atr * InpBreakoutStrength * 0.5;
   
   // Check for upward breakout against nearest resistance
   if (g_resistance_count > 0) {
      double nearest_resistance = g_resistance_levels[0];
      
      // CHANGE: Relax breakout condition
      if (current_close > nearest_resistance) {
         // Log potential breakout
         LogTradeActivity("Potential upward breakout detected. Close: " + DoubleToString(current_close, Digits) + 
                         ", Resistance: " + DoubleToString(nearest_resistance, Digits));
         
         // Check volume confirmation (if available)
         // Fix type conversion warning with explicit cast
         long current_volume = (long)iVolume(Symbol(), PERIOD_CURRENT, 0);
         double avg_volume = 0;
         
         for (int i = 1; i <= 10; i++) {
            // Fix type conversion warning with explicit cast
            avg_volume += (long)iVolume(Symbol(), PERIOD_CURRENT, i);
         }
         avg_volume /= 10;
         
         bool volume_confirms = current_volume > avg_volume * 1.1; // CHANGE: Reduced from 1.2
         
         if (volume_confirms || true) { // Always true for symbols without volume data
            Print("Upward breakout detected. Close: ", current_close, ", Resistance: ", nearest_resistance);
            return 1;
         }
      }
   }
   
   // Check for downward breakout against nearest support
   if (g_support_count > 0) {
      double nearest_support = g_support_levels[0];
      
      // CHANGE: Relax breakout condition
      if (current_close < nearest_support) {
         // Log potential breakout
         LogTradeActivity("Potential downward breakout detected. Close: " + DoubleToString(current_close, Digits) + 
                         ", Support: " + DoubleToString(nearest_support, Digits));
         
         // Check volume confirmation (if available)
         // Fix type conversion warning with explicit cast
         long current_volume = (long)iVolume(Symbol(), PERIOD_CURRENT, 0);
         double avg_volume = 0;
         
         for (int i = 1; i <= 10; i++) {
            // Fix type conversion warning with explicit cast
            avg_volume += (long)iVolume(Symbol(), PERIOD_CURRENT, i);
         }
         avg_volume /= 10;
         
         bool volume_confirms = current_volume > avg_volume * 1.1; // CHANGE: Reduced from 1.2
         
         if (volume_confirms || true) { // Always true for symbols without volume data
            Print("Downward breakout detected. Close: ", current_close, ", Support: ", nearest_support);
            return -1;
         }
      }
   }
   
   return 0; // No breakout
}

//+------------------------------------------------------------------+
//| Check if momentum confirms the breakout direction                 |
//+------------------------------------------------------------------+
bool HasMomentumConfirmation(int direction)
{
   // Get RSI values - fix parameter count for MT4
   double rsi_current = iRSI(Symbol(), PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE, 0);
   double rsi_prev = iRSI(Symbol(), PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE, 1);
   
   // Get MACD values - fix parameter count for MT4
   double macd_main = iMACD(Symbol(), PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 0);
   double macd_signal = iMACD(Symbol(), PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, 0);
   double macd_prev = iMACD(Symbol(), PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, 1);
   
   // Get ADX values
   double adx = iADX(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE, MODE_MAIN, 0);
   double plus_di = iADX(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE, MODE_PLUSDI, 0);
   double minus_di = iADX(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE, MODE_MINUSDI, 0);
   
   // For upward breakout
   if (direction > 0) {
      // CHANGE: Relax RSI condition
      bool rsi_confirm = rsi_current > 40 && rsi_current > rsi_prev;
      
      // CHANGE: Relax MACD condition
      bool macd_confirm = macd_main > macd_signal || macd_main > macd_prev;
      
      // CHANGE: Relax ADX condition
      bool adx_confirm = adx > 15 || plus_di > minus_di;
      
      // Log momentum analysis
      LogTradeActivity("Upward momentum analysis: RSI=" + DoubleToString(rsi_current, 2) + 
                      ", MACD=" + DoubleToString(macd_main, 5) + 
                      ", ADX=" + DoubleToString(adx, 2));
      
      // CHANGE: Need only 1 out of 3 confirmations
      int confirmations = (rsi_confirm ? 1 : 0) + (macd_confirm ? 1 : 0) + (adx_confirm ? 1 : 0);
      return confirmations >= 1;
   }
   // For downward breakout
   else if (direction < 0) {
      // CHANGE: Relax RSI condition
      bool rsi_confirm = rsi_current < 60 && rsi_current < rsi_prev;
      
      // CHANGE: Relax MACD condition
      bool macd_confirm = macd_main < macd_signal || macd_main < macd_prev;
      
      // CHANGE: Relax ADX condition
      bool adx_confirm = adx > 15 || minus_di > plus_di;
      
      // Log momentum analysis
      LogTradeActivity("Downward momentum analysis: RSI=" + DoubleToString(rsi_current, 2) + 
                      ", MACD=" + DoubleToString(macd_main, 5) + 
                      ", ADX=" + DoubleToString(adx, 2));
      
      // CHANGE: Need only 1 out of 3 confirmations
      int confirmations = (rsi_confirm ? 1 : 0) + (macd_confirm ? 1 : 0) + (adx_confirm ? 1 : 0);
      return confirmations >= 1;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for multi-timeframe confirmation                            |
//+------------------------------------------------------------------+
bool HasMultiTimeframeConfirmation(int direction)
{
   // CHANGE: Option to bypass multi-timeframe confirmation
   if (!InpUseMultiTimeframe) return true;
   
   // Get higher timeframe for confirmation
   ENUM_TIMEFRAMES confirmation_tf = PERIOD_CURRENT;
   
   // Convert minutes to timeframe
   switch(InpConfirmationTF) {
      case 5: confirmation_tf = PERIOD_M5; break;
      case 15: confirmation_tf = PERIOD_M15; break;
      case 30: confirmation_tf = PERIOD_M30; break;
      case 60: confirmation_tf = PERIOD_H1; break;
      case 240: confirmation_tf = PERIOD_H4; break;
      case 1440: confirmation_tf = PERIOD_D1; break;
      default: confirmation_tf = PERIOD_H1; // Default to H1
   }
   
   // Check if higher timeframe confirms the direction
   if (direction > 0) {
      // For upward breakout, check if higher timeframe is bullish
      
      // Check moving averages
      double ma_fast = iMA(Symbol(), confirmation_tf, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
      double ma_slow = iMA(Symbol(), confirmation_tf, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
      bool ma_bullish = ma_fast > ma_slow;
      
      // Check RSI
      double rsi = iRSI(Symbol(), confirmation_tf, InpRSIPeriod, PRICE_CLOSE, 0);
      bool rsi_bullish = rsi > 40; // CHANGE: Reduced from 50
      
      // Check price position
      double close = iClose(Symbol(), confirmation_tf, 0);
      double bb_upper = iBands(Symbol(), confirmation_tf, 20, 2, 0, PRICE_CLOSE, MODE_UPPER, 0);
      double bb_lower = iBands(Symbol(), confirmation_tf, 20, 2, 0, PRICE_CLOSE, MODE_LOWER, 0);
      double bb_middle = iBands(Symbol(), confirmation_tf, 20, 2, 0, PRICE_CLOSE, MODE_MAIN, 0);
      bool price_bullish = close > bb_lower; // CHANGE: Relaxed from middle band
      
      // Log multi-timeframe analysis
      LogTradeActivity("Higher TF bullish confirmation: MA=" + (ma_bullish ? "YES" : "NO") + 
                      ", RSI=" + (rsi_bullish ? "YES" : "NO") + 
                      ", Price=" + (price_bullish ? "YES" : "NO"));
      
      // CHANGE: Need only 1 out of 3 confirmations
      int confirmations = (ma_bullish ? 1 : 0) + (rsi_bullish ? 1 : 0) + (price_bullish ? 1 : 0);
      return confirmations >= 1;
   }
   else if (direction < 0) {
      // For downward breakout, check if higher timeframe is bearish
      
      // Check moving averages
      double ma_fast = iMA(Symbol(), confirmation_tf, 20, 0, MODE_EMA, PRICE_CLOSE, 0);
      double ma_slow = iMA(Symbol(), confirmation_tf, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
      bool ma_bearish = ma_fast < ma_slow;
      
      // Check RSI
      double rsi = iRSI(Symbol(), confirmation_tf, InpRSIPeriod, PRICE_CLOSE, 0);
      bool rsi_bearish = rsi < 60; // CHANGE: Increased from 50
      
      // Check price position
      double close = iClose(Symbol(), confirmation_tf, 0);
      double bb_upper = iBands(Symbol(), confirmation_tf, 20, 2, 0, PRICE_CLOSE, MODE_UPPER, 0);
      double bb_lower = iBands(Symbol(), confirmation_tf, 20, 2, 0, PRICE_CLOSE, MODE_LOWER, 0);
      double bb_middle = iBands(Symbol(), confirmation_tf, 20, 2, 0, PRICE_CLOSE, MODE_MAIN, 0);
      bool price_bearish = close < bb_upper; // CHANGE: Relaxed from middle band
      
      // Log multi-timeframe analysis
      LogTradeActivity("Higher TF bearish confirmation: MA=" + (ma_bearish ? "YES" : "NO") + 
                      ", RSI=" + (rsi_bearish ? "YES" : "NO") + 
                      ", Price=" + (price_bearish ? "YES" : "NO"));
      
      // CHANGE: Need only 1 out of 3 confirmations
      int confirmations = (ma_bearish ? 1 : 0) + (rsi_bearish ? 1 : 0) + (price_bearish ? 1 : 0);
      return confirmations >= 1;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade based on signal direction                           |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   // Check if we should close existing trade on new signal
   if (InpCloseOnNewSignal && g_ticket > 0) {
      if (OrderSelect(g_ticket, SELECT_BY_TICKET) && OrderCloseTime() == 0) {
         // Close existing trade if it's in the opposite direction
         if ((direction > 0 && OrderType() == OP_SELL) || (direction < 0 && OrderType() == OP_BUY)) {
            if (OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), InpMaxSlippage, clrViolet)) {
               LogTradeActivity("Closed existing trade due to new signal in opposite direction");
               g_ticket = 0;
            } else {
               LogTradeActivity("Error closing existing trade: " + IntegerToString(GetLastError()));
               return; // Don't proceed if we couldn't close the existing trade
            }
         } else {
            // Same direction, keep the existing trade
            LogTradeActivity("Keeping existing trade as new signal is in same direction");
            return;
         }
      }
   }
   
   // Check spread before execution
   if (!CheckSpread()) {
      LogTradeActivity("Trade execution aborted due to high spread");
      return;
   }
   
   // Check time between trades (avoid rapid trading)
   if (TimeCurrent() - g_last_trade_time < 300) { // 5 minutes minimum between trades
      LogTradeActivity("Trade execution aborted - minimum time between trades not elapsed");
      return;
   }
   
   // Store pre-trade balance for performance tracking
   double pre_trade_balance = AccountBalance();
   
   // Calculate position size
   double stop_loss_pips = CalculateStopLoss(direction);
   double take_profit_pips = CalculateTakeProfit(direction);
   double lot_size = CalculateLotSize(stop_loss_pips);
   
   // Adjust lot size if in recovery mode
   if (g_recovery_mode) {
      lot_size = MathMax(MarketInfo(Symbol(), MODE_MINLOT), lot_size * 0.5);
      LogTradeActivity("Recovery mode active - reducing lot size to " + DoubleToString(lot_size, 2));
   }
   
   // Calculate entry, stop loss and take profit prices
   double entry_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   if (direction < 0) entry_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   double stop_loss_price = direction > 0 ? entry_price - stop_loss_pips * Point() * 10 : entry_price + stop_loss_pips * Point() * 10;
   double take_profit_price = direction > 0 ? entry_price + take_profit_pips * Point() * 10 : entry_price - take_profit_pips * Point() * 10;
   
   // Store initial stop loss for risk management
   g_initial_stop_loss = stop_loss_price;
   g_initial_risk_amount = MathAbs(entry_price - stop_loss_price) * lot_size * MarketInfo(Symbol(), MODE_TICKVALUE) / Point();
   
   // Reset risk management flags
   g_breakeven_activated = false;
   g_scaled_out = false;
   g_trailing_activated = false;
   g_partial_lot_closed = 0;
   g_partial_ticket = 0;
   
   // Execute the trade
   int order_type = direction > 0 ? OP_BUY : OP_SELL;
   string comment = "XAUUSD 1% Cycle EA - Attempt " + IntegerToString(g_cycle_attempts + 1);
   
   // Retry mechanism for order execution
   int retries = 3;
   bool order_placed = false;
   
   while (retries > 0 && !order_placed) {
      g_ticket = OrderSend(Symbol(), order_type, lot_size, entry_price, InpMaxSlippage, 
                          stop_loss_price, take_profit_price, comment, 0, 0, 
                          direction > 0 ? clrBlue : clrRed);
   
   if (g_ticket > 0) {
         order_placed = true;
      } else {
         g_last_error = GetLastError();
         LogTradeActivity("Order execution failed: " + IntegerToString(g_last_error) + 
                         " - " + ErrorDescription(g_last_error));
         
         // Handle specific errors
         switch (g_last_error) {
            case ERR_INVALID_PRICE:
            case ERR_INVALID_STOPS:
            case ERR_INVALID_TRADE_VOLUME:
               // Recalculate parameters and try again
               RefreshRates();
               entry_price = SymbolInfoDouble(Symbol(), direction > 0 ? SYMBOL_ASK : SYMBOL_BID);
               stop_loss_price = direction > 0 ? entry_price - stop_loss_pips * Point() * 10 : entry_price + stop_loss_pips * Point() * 10;
               take_profit_price = direction > 0 ? entry_price + take_profit_pips * Point() * 10 : entry_price - take_profit_pips * Point() * 10;
               break;
               
            case ERR_REQUOTE:
            case ERR_PRICE_CHANGED:
               // Just retry with updated prices
               RefreshRates();
               entry_price = SymbolInfoDouble(Symbol(), direction > 0 ? SYMBOL_ASK : SYMBOL_BID);
               break;
               
            case ERR_SERVER_BUSY:
            case ERR_NO_CONNECTION:
            case ERR_TRADE_TIMEOUT:
               // Wait and retry
               Sleep(1000);
               break;
               
            default:
               // For other errors, just retry
               Sleep(500);
         }
         
         retries--;
      }
   }
   
   if (order_placed) {
      g_cycle_attempts++;
      g_trade_count++;
      g_last_trade_time = TimeCurrent();
      
      // Log trade details
      LogTradeActivity("Trade executed: " + (order_type == OP_BUY ? "BUY" : "SELL") + 
                      " " + DoubleToString(lot_size, 2) + " lots at " + DoubleToString(entry_price, Digits));
      LogTradeActivity("Stop Loss: " + DoubleToString(stop_loss_price, Digits) + 
                      " (" + DoubleToString(stop_loss_pips, 1) + " pips)");
      LogTradeActivity("Take Profit: " + DoubleToString(take_profit_price, Digits) + 
                      " (" + DoubleToString(take_profit_pips, 1) + " pips)");
      LogTradeActivity("Cycle attempt: " + IntegerToString(g_cycle_attempts) + "/" + IntegerToString(InpMaxAttempts));
      LogTradeActivity("Risk amount: $" + DoubleToString(g_initial_risk_amount, 2) + 
                      " (" + DoubleToString(g_initial_risk_amount / g_account_size * 100, 2) + "%)");
      
      // Send notifications
      if (InpSendAlerts) {
         Alert("XAUUSD 1% Cycle EA - New trade opened: ", order_type == OP_BUY ? "BUY" : "SELL", 
               " ", DoubleToString(lot_size, 2), " lots at ", DoubleToString(entry_price, Digits));
      }
      
      if (InpSendEmails) {
         SendMail("XAUUSD 1% Cycle EA - New Trade", 
                 "Trade opened: " + (order_type == OP_BUY ? "BUY" : "SELL") + 
                 " " + DoubleToString(lot_size, 2) + " lots at " + DoubleToString(entry_price, Digits) + 
                 "\nStop Loss: " + DoubleToString(stop_loss_price, Digits) + 
                 "\nTake Profit: " + DoubleToString(take_profit_price, Digits) + 
                 "\nCycle attempt: " + IntegerToString(g_cycle_attempts) + "/" + IntegerToString(InpMaxAttempts));
      }
   } else {
      LogTradeActivity("Failed to execute trade after " + IntegerToString(3 - retries) + " attempts");
      
      // Record error for monitoring
      g_last_error_time = TimeCurrent();
      g_error_count++;
      
      // If too many errors, consider pausing trading
      if (g_error_count >= 5) {
         LogTradeActivity("Too many execution errors - consider checking connection or market conditions");
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate stop loss in pips                                       |
//+------------------------------------------------------------------+
double CalculateStopLoss(int direction)
{
   // Fix parameter count for ATR
   double atr = iATR(Symbol(), PERIOD_CURRENT, 14, 1);
   double atr_stop = atr * InpStopLossMultiplier / (Point() * 10);
   
   // Get nearest support/resistance for technical stop loss
   double technical_stop = 0;
   
   if (direction > 0) {
      // For long positions, find nearest support below current price
      double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double nearest_support = 0;
      double min_distance = DBL_MAX;
      
      // Check all support levels
      for (int i = 0; i < g_support_count; i++) {
         if (g_support_levels[i] < current_price) {
            double distance = current_price - g_support_levels[i];
            if (distance < min_distance) {
               min_distance = distance;
               nearest_support = g_support_levels[i];
            }
         }
      }
      
      // If we found a valid support level, calculate pips
      if (nearest_support > 0) {
         technical_stop = (current_price - nearest_support) / (Point() * 10);
         // Add a small buffer
         technical_stop += 10; // 10 pips buffer
      }
   } else {
      // For short positions, find nearest resistance above current price
      double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      double nearest_resistance = 0;
      double min_distance = DBL_MAX;
      
      // Check all resistance levels
      for (int i = 0; i < g_resistance_count; i++) {
         if (g_resistance_levels[i] > current_price) {
            double distance = g_resistance_levels[i] - current_price;
            if (distance < min_distance) {
               min_distance = distance;
               nearest_resistance = g_resistance_levels[i];
            }
         }
      }
      
      // If we found a valid resistance level, calculate pips
      if (nearest_resistance > 0) {
         technical_stop = (nearest_resistance - current_price) / (Point() * 10);
         // Add a small buffer
         technical_stop += 10; // 10 pips buffer
      }
   }
   
   // Choose the appropriate stop loss method
   double stop_loss_pips = 0;
   
   // If technical stop is valid, use it, otherwise use ATR-based stop
   if (technical_stop > 0) {
      stop_loss_pips = technical_stop;
      LogTradeActivity("Using technical stop loss: " + DoubleToString(stop_loss_pips, 1) + " pips");
   } else {
      stop_loss_pips = atr_stop;
      LogTradeActivity("Using ATR-based stop loss: " + DoubleToString(stop_loss_pips, 1) + " pips");
   }
   
   // Ensure minimum stop loss
   if (stop_loss_pips < 20) stop_loss_pips = 20; // Minimum 20 pips for XAUUSD
   
   // Ensure stop loss doesn't risk more than allowed
   double max_stop_pips = CalculateMaxStopLoss();
   if (stop_loss_pips > max_stop_pips && max_stop_pips > 20) {
      stop_loss_pips = max_stop_pips;
      LogTradeActivity("Stop loss adjusted to maximum allowed: " + DoubleToString(stop_loss_pips, 1) + " pips");
   }
   
   return stop_loss_pips;
}

//+------------------------------------------------------------------+
//| Calculate maximum stop loss based on risk parameters              |
//+------------------------------------------------------------------+
double CalculateMaxStopLoss()
{
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   
   // Calculate maximum stop loss in pips that would risk InpRiskPercent of account
   double max_risk_amount = g_account_size * InpRiskPercent / 100.0;
   double pip_value = tick_value * 10 * min_lot; // Value of 1 pip for minimum lot size
   
   // Maximum stop loss in pips = max risk amount / (pip value * lot size)
   double max_stop_pips = max_risk_amount / pip_value;
   
   return max_stop_pips;
}

//+------------------------------------------------------------------+
//| Calculate take profit in pips to achieve target account growth    |
//+------------------------------------------------------------------+
double CalculateTakeProfit(int direction)
{
   // Calculate stop loss for risk-reward ratio
   double stop_loss_pips = CalculateStopLoss(direction);
   
   // We want at least 1:2 risk-reward ratio
   double min_take_profit_pips = stop_loss_pips * 2;
   
   // Calculate lot size based on stop loss
   double lot_size = CalculateLotSize(stop_loss_pips);
   
   // Calculate take profit pips needed to achieve target account growth
   double pip_value = MarketInfo(Symbol(), MODE_TICKVALUE) * 10; // Value of 1 pip for 1 lot
   double take_profit_pips = g_target_amount / (lot_size * pip_value);
   
   // If using scaled exit, adjust the take profit calculation
   if (InpUseScaledExit) {
      // First target is at InpScaleOutPercent of the total target
      double first_target_pips = take_profit_pips * InpScaleOutPercent;
      
      // Second target is calculated to achieve the remaining target amount
      // with the remaining position size
      double remaining_target = g_target_amount * (1.0 - InpScaleOutPercent);
      double remaining_lot = lot_size * (1.0 - InpScaleOutPercent);
      double second_target_pips = remaining_target / (remaining_lot * pip_value);
      
      // Use the first target for the order's take profit
      take_profit_pips = first_target_pips;
      
      LogTradeActivity("Scaled exit strategy: First target at " + DoubleToString(first_target_pips, 1) + 
                      " pips, Second target at " + DoubleToString(second_target_pips, 1) + " pips");
   }
   
   // Use the larger of the calculated take profit or minimum risk-reward ratio
   take_profit_pips = MathMax(take_profit_pips, min_take_profit_pips);
   
   return take_profit_pips;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk parameters                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double stop_loss_pips)
{
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tick_size = MarketInfo(Symbol(), MODE_TICKSIZE);
   double point = MarketInfo(Symbol(), MODE_POINT);
   
   // Calculate pip value (for XAUUSD, 1 pip = 10 points)
   double pip_value = tick_value * (10 * point / tick_size);
   
   // Calculate lot size based on risk amount and stop loss
   double lot_size = g_risk_amount / (stop_loss_pips * pip_value);
   
   // Normalize lot size to broker's requirements
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   double max_lot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   
   lot_size = MathFloor(lot_size / lot_step) * lot_step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
   
   // Log lot size calculation
   LogTradeActivity("Lot size calculation: Risk=$" + DoubleToString(g_risk_amount, 2) + 
                   ", Stop=" + DoubleToString(stop_loss_pips, 1) + 
                   " pips, Lot=" + DoubleToString(lot_size, 2));
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| Manage open trade (trailing stop, breakeven, scaling out)         |
//+------------------------------------------------------------------+
void ManageOpenTrade()
{
   if (!OrderSelect(g_ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0) {
      g_ticket = 0;
      return;
   }
   
   // Calculate current profit in both money and percentage terms
   double current_profit = OrderProfit() + OrderCommission() + OrderSwap();
   double profit_percent = (current_profit / g_account_size) * 100.0;
   
   // Calculate profit in pips
   double profit_pips = 0;
   if (OrderType() == OP_BUY) {
      profit_pips = (Bid - OrderOpenPrice()) / (Point() * 10);
   } else {
      profit_pips = (OrderOpenPrice() - Ask) / (Point() * 10);
   }
   
   // Log trade status periodically
   static datetime last_status_time = 0;
   if (TimeCurrent() - last_status_time > 3600) { // Log status once per hour
      LogTradeActivity("Trade status: Profit=$" + DoubleToString(current_profit, 2) + 
                     ", (" + DoubleToString(profit_percent, 2) + "%), " + 
                     DoubleToString(profit_pips, 1) + " pips");
      last_status_time = TimeCurrent();
   }
   
   // Check if we should activate breakeven stop - using dollar amount
   double breakeven_activation_amount = g_account_size * InpBreakEvenActivation / 100.0;
   if (InpUseBreakEven && !g_breakeven_activated && current_profit >= breakeven_activation_amount) {
      LogTradeActivity("Breakeven condition met: Current profit $" + DoubleToString(current_profit, 2) + 
                     " >= Activation threshold $" + DoubleToString(breakeven_activation_amount, 2));
      MoveToBreakeven();
   }
   
   // Check if we should scale out
   double scaleout_amount = g_target_amount * InpScaleOutPercent;
   if (InpUseScaledExit && !g_scaled_out && current_profit >= scaleout_amount) {
      LogTradeActivity("Scale-out condition met: Current profit $" + DoubleToString(current_profit, 2) + 
                     " >= Scale-out threshold $" + DoubleToString(scaleout_amount, 2));
      ScaleOutPosition();
   }
   
   // Apply trailing stop as soon as the trade is in profit
   if (current_profit > 0) {
      // Only log activation once
      if (!g_trailing_activated) {
         g_trailing_activated = true;
         LogTradeActivity("Trailing stop activated at $" + DoubleToString(current_profit, 2) + " profit");
      }
      ApplyTrailingStop();
   }
   
   // Check if we've reached target
   if (current_profit >= g_target_amount) {
      g_cycle_target_reached = true;
      LogTradeActivity("Cycle target of $" + DoubleToString(g_target_amount, 2) + 
                     " reached! Current profit: $" + DoubleToString(current_profit, 2));
   }
}

//+------------------------------------------------------------------+
//| Scale out part of the position                                    |
//+------------------------------------------------------------------+
void ScaleOutPosition()
{
   if (!OrderSelect(g_ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0) return;
   
   // Calculate lot size to close
   double total_lot = OrderLots();
   double lot_to_close = total_lot * InpScaleOutPercent;
   double lot_to_keep = total_lot - lot_to_close;
   
   // Normalize lot size
   double lot_step = MarketInfo(Symbol(), MODE_LOTSTEP);
   lot_to_close = MathFloor(lot_to_close / lot_step) * lot_step;
   
   // Ensure minimum lot size
   double min_lot = MarketInfo(Symbol(), MODE_MINLOT);
   if (lot_to_close < min_lot) lot_to_close = min_lot;
   if (lot_to_keep < min_lot) {
      lot_to_close = total_lot; // Close entire position if remainder would be too small
   }
   
   // Close partial position
   bool result = false;
   if (OrderType() == OP_BUY) {
      result = OrderClose(OrderTicket(), lot_to_close, Bid, 5, clrGreen);
   } else {
      result = OrderClose(OrderTicket(), lot_to_close, Ask, 5, clrRed);
   }
   
   if (result) {
      g_scaled_out = true;
      g_partial_lot_closed = lot_to_close;
      
      // If we closed the entire position
      if (lot_to_close >= total_lot) {
         g_ticket = 0;
         LogTradeActivity("Entire position closed at scale-out point");
      } else {
         // Find the new ticket for the remaining position
         for (int i = 0; i < OrdersTotal(); i++) {
            if (OrderSelect(i, SELECT_BY_POS)) {
               if (OrderSymbol() == Symbol() && OrderMagicNumber() == 0 && OrderCloseTime() == 0) {
                  g_ticket = OrderTicket();
                  break;
               }
            }
         }
         
         LogTradeActivity("Scaled out " + DoubleToString(lot_to_close, 2) + 
                         " lots, keeping " + DoubleToString(lot_to_keep, 2) + " lots");
      }
   } else {
      LogTradeActivity("Error scaling out position: " + IntegerToString(GetLastError()));
   }
}

//+------------------------------------------------------------------+
//| Move stop loss to breakeven plus buffer                           |
//+------------------------------------------------------------------+
void MoveToBreakeven()
{
   if (!OrderSelect(g_ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0) return;
   
   // Calculate current profit in dollars
   double current_profit = OrderProfit() + OrderCommission() + OrderSwap();
   
   // Calculate breakeven activation amount
   double breakeven_activation_amount = g_account_size * InpBreakEvenActivation / 100.0;
   
   // Log the current profit status
   LogTradeActivity("Checking breakeven condition: Current profit $" + DoubleToString(current_profit, 2) + 
                  ", Target threshold $" + DoubleToString(breakeven_activation_amount, 2));
   
   double breakeven_level = OrderOpenPrice();
   
   // Add buffer pips to breakeven level
   if (OrderType() == OP_BUY) {
      breakeven_level += InpBreakEvenPips * Point() * 10;
   } else {
      breakeven_level -= InpBreakEvenPips * Point() * 10;
   }
   
   LogTradeActivity("Attempting to move stop loss to breakeven at " + DoubleToString(breakeven_level, Digits));
   
   // Only move stop loss if it would be better than current stop
   if ((OrderType() == OP_BUY && (breakeven_level > OrderStopLoss() || OrderStopLoss() == 0)) ||
       (OrderType() == OP_SELL && (breakeven_level < OrderStopLoss() || OrderStopLoss() == 0))) {
      
      bool success = false;
      int attempts = 0;
      int max_attempts = 3;
      
      while (!success && attempts < max_attempts) {
         success = OrderModify(OrderTicket(), OrderOpenPrice(), breakeven_level, OrderTakeProfit(), 0, clrYellow);
         
         if (success) {
            g_breakeven_activated = true;
            LogTradeActivity("Stop loss successfully moved to breakeven + " + DoubleToString(InpBreakEvenPips, 1) + 
                           " pips: " + DoubleToString(breakeven_level, Digits));
         } else {
            int error = GetLastError();
            LogTradeActivity("Error moving stop to breakeven (attempt " + IntegerToString(attempts+1) + 
                           "): " + IntegerToString(error) + " - " + ErrorDescription(error));
            
            // Wait a moment before retrying
            Sleep(500);
            RefreshRates();
         }
         
         attempts++;
      }
      
      if (!success) {
         LogTradeActivity("Failed to move stop to breakeven after " + IntegerToString(max_attempts) + " attempts");
      }
   } else {
      LogTradeActivity("Current stop loss at " + DoubleToString(OrderStopLoss(), Digits) + 
                     " is already better than breakeven at " + DoubleToString(breakeven_level, Digits));
   }
}

//+------------------------------------------------------------------+
//| Apply trailing stop to open position                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if (!OrderSelect(g_ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0) return;
   
   double current_price = OrderType() == OP_BUY ? Bid : Ask;
   double current_stop = OrderStopLoss();
   
   // Calculate new stop loss
   double new_stop = 0;
   if (OrderType() == OP_BUY) {
      new_stop = current_price - InpTrailingDistance * Point() * 10;
      // Only modify if the new stop is better than the current one
      if (new_stop > current_stop + Point()) {
         // Add retry mechanism for trailing stop
         bool success = false;
         int attempts = 0;
         int max_attempts = 3;
         
         while (!success && attempts < max_attempts) {
            success = OrderModify(OrderTicket(), OrderOpenPrice(), new_stop, OrderTakeProfit(), 0, clrBlue);
            
            if (success) {
               LogTradeActivity("Trailing stop updated to " + DoubleToString(new_stop, Digits) + 
                              " (price: " + DoubleToString(current_price, Digits) + 
                              ", distance: " + DoubleToString(InpTrailingDistance, 1) + " points)");
            } else {
               int error = GetLastError();
               LogTradeActivity("Error updating trailing stop (attempt " + IntegerToString(attempts+1) + 
                              "): " + IntegerToString(error) + " - " + ErrorDescription(error));
               
               // Wait a moment before retrying
               Sleep(500);
               RefreshRates();
               // Update current price after refresh
               current_price = OrderType() == OP_BUY ? Bid : Ask;
               new_stop = current_price - InpTrailingDistance * Point() * 10;
            }
            
            attempts++;
         }
      }
   } else if (OrderType() == OP_SELL) {
      new_stop = current_price + InpTrailingDistance * Point() * 10;
      // Only modify if the new stop is better than the current one
      if (new_stop < current_stop - Point() || current_stop == 0) {
         // Add retry mechanism for trailing stop
         bool success = false;
         int attempts = 0;
         int max_attempts = 3;
         
         while (!success && attempts < max_attempts) {
            success = OrderModify(OrderTicket(), OrderOpenPrice(), new_stop, OrderTakeProfit(), 0, clrRed);
            
            if (success) {
               LogTradeActivity("Trailing stop updated to " + DoubleToString(new_stop, Digits) + 
                              " (price: " + DoubleToString(current_price, Digits) + 
                              ", distance: " + DoubleToString(InpTrailingDistance, 1) + " points)");
            } else {
               int error = GetLastError();
               LogTradeActivity("Error updating trailing stop (attempt " + IntegerToString(attempts+1) + 
                              "): " + IntegerToString(error) + " - " + ErrorDescription(error));
               
               // Wait a moment before retrying
               Sleep(500);
               RefreshRates();
               // Update current price after refresh
               current_price = OrderType() == OP_BUY ? Bid : Ask;
               new_stop = current_price + InpTrailingDistance * Point() * 10;
            }
            
            attempts++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get error description                                             |
//+------------------------------------------------------------------+
string ErrorDescription(int error_code)
{
   string error_string;
   
   switch(error_code) {
      case 0:   error_string = "No error";                                                  break;
      case 1:   error_string = "No error, but the result is unknown";                       break;
      case 2:   error_string = "Common error";                                              break;
      case 3:   error_string = "Invalid trade parameters";                                  break;
      case 4:   error_string = "Trade server is busy";                                      break;
      case 5:   error_string = "Old version of the client terminal";                        break;
      case 6:   error_string = "No connection with trade server";                           break;
      case 7:   error_string = "Not enough rights";                                         break;
      case 8:   error_string = "Too frequent requests";                                     break;
      case 9:   error_string = "Malfunctional trade operation";                             break;
      case 64:  error_string = "Account disabled";                                          break;
      case 65:  error_string = "Invalid account";                                           break;
      case 128: error_string = "Trade timeout";                                             break;
      case 129: error_string = "Invalid price";                                             break;
      case 130: error_string = "Invalid stops";                                             break;
      case 131: error_string = "Invalid trade volume";                                      break;
      case 132: error_string = "Market is closed";                                          break;
      case 133: error_string = "Trade is disabled";                                         break;
      case 134: error_string = "Not enough money";                                          break;
      case 135: error_string = "Price changed";                                             break;
      case 136: error_string = "Off quotes";                                                break;
      case 137: error_string = "Broker is busy";                                            break;
      case 138: error_string = "Requote";                                                   break;
      case 139: error_string = "Order is locked";                                           break;
      case 140: error_string = "Long positions only allowed";                               break;
      case 141: error_string = "Too many requests";                                         break;
      case 145: error_string = "Modification denied because order is too close to market";  break;
      case 146: error_string = "Trade context is busy";                                     break;
      case 147: error_string = "Expirations are denied by broker";                          break;
      case 148: error_string = "Amount of open and pending orders has reached the limit";   break;
      default:  error_string = "Unknown error";
   }
   
   return error_string;
}

//+------------------------------------------------------------------+
//| Log trade activity                                                |
//+------------------------------------------------------------------+
void LogTradeActivity(string message)
{
   // Print to terminal
   Print(message);
   
   // Save to log file if enabled
   if (InpSaveReports) {
      int file_handle = FileOpen(g_log_filename, FILE_READ|FILE_WRITE|FILE_TXT);
      if (file_handle != INVALID_HANDLE) {
         // Seek to end of file
         FileSeek(file_handle, 0, SEEK_END);
         
         // Write timestamped message
         FileWriteString(file_handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + 
                        " - " + message + "\n");
         FileClose(file_handle);
      }
   }
}

//+------------------------------------------------------------------+
//| Update performance metrics                                        |
//+------------------------------------------------------------------+
void UpdatePerformanceMetrics()
{
   double current_balance = AccountBalance();
   double current_equity = AccountEquity();
   
   // Update peak balance
   if (current_balance > g_peak_balance) {
      g_peak_balance = current_balance;
   }
   
   // Calculate current drawdown
   double current_drawdown = g_peak_balance - current_equity;
   if (current_drawdown > g_max_drawdown) {
      g_max_drawdown = current_drawdown;
   }
   
   // Check for recovery mode
   if (g_consecutive_losses >= 2 && !g_recovery_mode) {
      g_recovery_mode = true;
      LogTradeActivity("Entering recovery mode after " + IntegerToString(g_consecutive_losses) + " consecutive losses");
   }
   
   // Exit recovery mode if we've recovered
   if (g_recovery_mode && current_balance > g_trade_start_balance) {
      g_recovery_mode = false;
      g_consecutive_losses = 0;
      LogTradeActivity("Exiting recovery mode - balance recovered");
   }
} 