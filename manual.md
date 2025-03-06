# RSI Delayed Entry EA Manual

## Overview
The RSI Delayed Entry EA is a sophisticated MetaTrader 4 Expert Advisor that trades based on RSI (Relative Strength Index) signals with optional delayed entry using limit orders. It includes comprehensive risk management features, trading hour restrictions, and detailed performance monitoring.

## Key Features
- RSI-based trading strategy
- Optional delayed entry using limit orders
- Comprehensive risk management
- Trading hours restriction
- Multiple trade management options
- Trailing stop functionality
- Daily and total account limits
- Spread monitoring
- Detailed real-time statistics

## Input Parameters

### RSI Settings
- **RSI_Period** (default: 14): The period for RSI calculation
- **RSI_Overbought** (default: 70): RSI level for sell signals
- **RSI_Oversold** (default: 30): RSI level for buy signals
- **RequireClose** (default: true): Require candle close confirmation for signals

### Trade Settings
- **LotSize** (default: 0.1): Trading lot size
- **TakeProfit** (default: 1200): Take profit in points
- **StopLoss** (default: 600): Stop loss in points
- **MaxSlippage** (default: 30): Maximum allowed slippage in points

### Trailing Stop Settings
- **UseTrailingStop** (default: false): Enable/disable trailing stop
- **TrailingStart** (default: 100): Points in profit before trailing starts
- **TrailingStep** (default: 100): Points to maintain from current price

### Risk Management
- **DailyProfitTarget** (default: 200): Daily profit target in account currency
- **DailyLossLimit** (default: 200): Daily loss limit in account currency
- **TotalProfitTarget** (default: 1000): Total account profit target
- **MaxDrawdown** (default: 1000): Maximum allowed drawdown
- **MaxSpread** (default: 3.0): Maximum allowed spread in pips

### Trading Hours
- **UseTimer** (default: true): Enable/disable trading hours restriction
- **StartHour** (default: 2): Trading start hour (0-23)
- **EndHour** (default: 22): Trading end hour (0-23)

### Multiple Trade Settings
- **AllowMultipleTrades** (default: false): Allow multiple trades per signal
- **MaxOpenTrades** (default: 5): Maximum number of open trades allowed

### Limit Order Settings
- **UseLimitOrders** (default: false): Enable/disable limit order entry
- **DelayedEntryPoints** (default: 10): Points away for limit order entry
- **CancelLimitPoints** (default: 10): Points in opposite direction to cancel limit

### Visual Settings
- **SignalLineColor** (default: Yellow): Color for signal line
- **DrawSignalLines** (default: true): Draw lines at signal points

## Trading Logic

### Entry Conditions
1. **Buy Signal**:
   - RSI crosses below oversold level (default: 30)
   - If RequireClose is true, requires confirmation on next candle

2. **Sell Signal**:
   - RSI crosses above overbought level (default: 70)
   - If RequireClose is true, requires confirmation on next candle

### Limit Order Mode
When UseLimitOrders is enabled:
- Buy signals place buy limit orders below current price
- Sell signals place sell limit orders above current price
- Orders are automatically cancelled if price moves beyond CancelLimitPoints

### Risk Management Rules
1. **Daily Limits**:
   - Trading stops when daily profit target is reached
   - Trading stops when daily loss limit is hit

2. **Total Account Limits**:
   - Trading stops when total profit target is reached
   - Trading stops when maximum drawdown is hit

3. **Spread Protection**:
   - No trades when spread exceeds MaxSpread

### Trading Hours
- When UseTimer is enabled, trades only during specified hours
- Hours are in server time (GMT+2 typically for forex brokers)
- No trades during first hour of day for additional protection

## Visual Feedback
1. **Signal Lines**:
   - Yellow lines show signal entry points
   - Green/Red lines show limit order levels
   - Gray lines show cancellation levels

2. **Information Display**:
   - Real-time status updates
   - Current trading conditions
   - Account statistics
   - Daily performance metrics
   - Limit order status (when active)

## Best Practices

### Initial Setup
1. Test on demo account first
2. Start with conservative lot sizes
3. Adjust risk parameters based on account size
4. Verify trading hours match your preferred market sessions

### Risk Management
1. Set realistic daily targets and loss limits
2. Monitor maximum drawdown carefully
3. Adjust MaxSpread based on your broker's typical spreads
4. Use trailing stops for longer-term trades

### Optimization Tips
1. Test different RSI periods for your preferred pairs
2. Adjust DelayedEntryPoints based on market volatility
3. Fine-tune trading hours to match best market conditions
4. Monitor and adjust risk parameters regularly

## Troubleshooting

### Common Issues
1. **No Trades Opening**:
   - Check if spread is too high
   - Verify trading hours settings
   - Confirm daily limits haven't been hit
   - Check for sufficient margin

2. **Unexpected Trade Closures**:
   - Review daily limit settings
   - Check trailing stop parameters
   - Verify stop loss levels

3. **Limit Orders Not Filling**:
   - Check DelayedEntryPoints setting
   - Monitor market volatility
   - Verify broker's limit order policies

## Support
For technical support or feature requests, please contact the developer through the MQL5 community.

## Disclaimer
Past performance is not indicative of future results. Always test thoroughly on a demo account before using on a live account. The developer is not responsible for any losses incurred while using this EA. 