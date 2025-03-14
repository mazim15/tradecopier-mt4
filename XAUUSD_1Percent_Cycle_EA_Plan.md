# XAUUSD 1% Cycle EA Development Plan

## Overview

This document outlines the development plan for an MT4 Expert Advisor that implements a high-probability breakout strategy for XAUUSD (Gold), targeting 1% gain per 14-day cycle for prop firm challenges.

## Strategy Summary

The EA will identify periods of consolidation in XAUUSD and enter trades when price breaks out with momentum, aiming to capture a quick 1% account gain. Once the target is achieved, the EA will cease trading until the next cycle begins.

## 1. Core Components

### A. Input Parameters

#### Risk Management
- Account risk percentage (default: 0.5%)
- Target profit percentage (default: 1%)
- Maximum attempts per cycle (default: 3)
  
#### Strategy Parameters
- Consolidation detection period (default: 12 bars)
- Volatility threshold (ATR or BB width)
- Breakout confirmation strength
- Momentum indicator settings (RSI, MACD)
  
#### Time Filters
- Trading session hours (London/NY)
- Day of week filters
- Cycle start date/time

#### Trade Management
- Stop loss multiplier (based on ATR)
- Take profit calculation method
- Trailing stop activation and parameters

### B. Core Functions

#### Market Analysis Module
- `DetectConsolidation()` - Identify low volatility periods
- `IdentifySupportResistance()` - Find key price levels
- `CalculateVolatility()` - Measure current market volatility
- `CheckMomentum()` - Analyze momentum indicators

#### Signal Generation Module
- `DetectBreakout()` - Identify valid breakout conditions
- `ValidateSignal()` - Apply additional confirmation filters
- `DetermineDirection()` - Decide long or short bias

#### Risk Management Module
- `CalculatePositionSize()` - Determine lot size based on risk parameters
- `SetStopLoss()` - Calculate appropriate stop loss level
- `SetTakeProfit()` - Calculate take profit to achieve 1% account gain
- `TrackCycleProgress()` - Monitor performance within current cycle

#### Trade Execution Module
- `OpenPosition()` - Execute trade with proper parameters
- `ModifyPosition()` - Adjust stops/targets as needed
- `ClosePosition()` - Exit trades based on conditions
- `HandleErrors()` - Manage trading errors

#### Monitoring & Logging Module
- `LogTradeActivity()` - Record all trade actions
- `CalculatePerformance()` - Track success rate and metrics
- `NotifyUser()` - Send alerts on key events

## 2. Implementation Workflow

### Phase 1: Framework Setup
1. Create basic EA structure with input parameters
2. Implement time filtering functionality
3. Set up cycle tracking mechanism
4. Establish logging and notification system

### Phase 2: Strategy Implementation
1. Develop consolidation detection algorithm
2. Implement support/resistance identification
3. Create breakout detection logic
4. Add momentum confirmation filters

### Phase 3: Risk Management
1. Build position sizing calculator
2. Implement dynamic stop loss placement
3. Create take profit calculation based on account % target
4. Add trailing stop functionality

### Phase 4: Trade Management
1. Develop order execution functions
2. Implement trade modification logic
3. Create trade exit conditions
4. Add error handling and recovery

### Phase 5: Testing & Optimization
1. Backtest on historical XAUUSD data
2. Optimize key parameters
3. Forward test on demo account
4. Implement safeguards against common issues

## 3. Technical Specifications

### Data Requirements
- Timeframes: H4 (primary), H1 and M15 (confirmation)
- Indicators: ATR, Bollinger Bands, RSI, MACD
- Price data: OHLC for XAUUSD

### Execution Logic Flow
1. On each new bar:
   - Check if within trading hours
   - Check if within active cycle
   - Check if maximum attempts reached
   - Analyze market conditions
   - Generate signals if conditions met

2. On signal detection:
   - Calculate position size
   - Determine entry, stop loss, take profit levels
   - Execute trade with proper parameters

3. On open position:
   - Monitor for trailing stop conditions
   - Check for exit criteria
   - Update cycle tracking data

4. On cycle completion:
   - Reset attempt counter
   - Log performance metrics
   - Prepare for next cycle

### Safety Features
- Maximum spread filter
- Slippage protection
- Disconnect handling
- News event avoidance
- Multiple attempt management

## 4. Code Structure Outline 

// Main EA file structure
extern parameters
global variables
int OnInit()
// Initialize variables, validate parameters
// Load previous cycle data if exists
void OnDeinit()
// Clean up, save state
void OnTick()
// Main trading logic
// Check time filters
// Check for open positions
// Analyze market if no position
// Execute trades on valid signals
// Manage existing trades
// Market analysis functions
bool IsConsolidation()
bool IsBreakout()
bool HasMomentumConfirmation()
// Trade management functions
double CalculateLotSize()
double DetermineStopLoss()
double DetermineTakeProfit()
bool ExecuteTrade()
bool ModifyTrade()
// Utility functions
bool IsNewBar()
bool IsTradingHours()
bool IsNewsTime()
void LogActivity()

## 5. Risk Management Framework

### Position Sizing
- Calculate position size to achieve exactly 1% account growth at take profit level
- Risk no more than 0.5% of account on any single trade
- This creates a 1:2 risk-reward ratio minimum

### Example Calculation
For a $100,000 account:
- Target profit: $1,000 (1%)
- Maximum risk: $500 (0.5%)
- If stop loss is 20 pips and take profit is 40 pips, position size would be calculated accordingly

### Stop Loss Placement
- Place stops at logical technical levels (below support for longs, above resistance for shorts)
- Typical stop distance: 20-30 pips for XAUUSD, but adjust based on current volatility
- Never move stop loss to a worse position

### Take Profit Strategy
- Set take profit to achieve exactly 1% account growth
- Consider scaling out: take 0.7% at first target, remaining 0.3% at extended target
- Use trailing stops after 0.7% is secured to potentially capture more without risking the core profit

### Trade Management Rules
1. Only take setups with clear technical validation
2. Trade only during optimal sessions (avoid low-liquidity periods)
3. No trading during major gold-impacting news events
4. Maximum 2-3 attempts per cycle if initial trades fail
5. Once 1% is achieved, stop trading until the next cycle

## 6. Testing & Validation Plan

### Unit Testing
- Test each function independently
- Verify calculations with manual checks
- Validate signal generation against visual chart analysis

### Integration Testing
- Test complete workflow with controlled inputs
- Verify position sizing calculations
- Confirm cycle tracking functionality

### Backtesting
- Test on minimum 2 years of historical data
- Verify performance across different market conditions
- Analyze drawdown and success rate

### Optimization
- Fine-tune consolidation detection parameters
- Optimize breakout confirmation thresholds
- Adjust risk parameters for best performance

### Forward Testing
- Run on demo account for minimum 2 cycles
- Monitor real-time performance
- Verify all safety features

## 7. Implementation Timeline

1. **Week 1**: Framework setup and basic functionality
2. **Week 2**: Strategy implementation and signal generation
3. **Week 3**: Risk management and trade execution
4. **Week 4**: Testing, optimization, and refinement

## 8. Future Enhancements

- Multi-timeframe analysis for improved entry timing
- Machine learning for pattern recognition
- Adaptive parameters based on market conditions
- Dashboard for visual monitoring
- Remote monitoring capabilities

## 9. Key Performance Indicators

- Success rate (% of cycles where 1% target is achieved)
- Average trades per cycle
- Average time to achieve target
- Maximum drawdown
- Risk-adjusted return ratio

## 10. Conclusion

This EA is designed with a conservative approach focused on achieving a modest but consistent 1% return per 14-day cycle. The emphasis is on high-probability setups, strict risk management, and preserving capital while meeting the target quickly to minimize exposure time in the market.

