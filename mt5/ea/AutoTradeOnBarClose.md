# BuyOnBarClose Expert Advisor

## Description

This MT5 Expert Advisor automatically opens BUY or SELL positions based on signals from the EntrySignals indicator when a bar closes, with automatic position sizing based on risk management principles.

## Features

- **Signal-Based Entry**: Opens positions only when EntrySignals indicator shows BUY or SELL signals
- **Bar Close Confirmation**: Waits for bar to close before executing trades
- **Risk Management**: Calculates position size so that Stop Loss equals approximately 1% of equity
- **Dynamic Stop Loss**: 
  - BUY: SL at the low of the closed bar
  - SELL: SL at the high of the closed bar
- **Take Profit**: TP is automatically set at 2x the SL distance (Risk:Reward = 1:2)
- **Smart Volume Calculation**: Automatically adjusts lot size based on account equity and SL distance
- **Bidirectional Trading**: Can trade both long and short positions

## How It Works

1. **Bar Detection**: The EA monitors for new bar formation (previous bar closure)
2. **Signal Detection**: Checks if the EntrySignals indicator placed a BUY or SELL arrow on the closed bar
3. **Entry Execution**: 
   - BUY signal: Opens at current ASK price
   - SELL signal: Opens at current BID price
4. **Stop Loss**: 
   - BUY: Set at the LOW of the previous closed bar
   - SELL: Set at the HIGH of the previous closed bar
5. **Volume Calculation**: 
   - Calculates SL distance in pips
   - Determines lot size so if SL is hit, loss = 1% of equity
   - Normalizes to broker's min/max/step requirements
6. **Take Profit**: 
   - BUY: Set at Entry + (2 × SL distance)
   - SELL: Set at Entry - (2 × SL distance)

## Examples

### BUY Signal Example

Suppose:
- Account equity: $10,000
- EntrySignals indicator shows BUY arrow on closed bar
- Current Ask price: 1.1000
- Previous bar low: 1.0950
- Risk: 1%

Calculation:
- Risk amount: $10,000 × 1% = $100
- SL distance: 1.1000 - 1.0950 = 0.0050 (50 pips)
- Lot size: Calculated to risk $100 over 50 pips
- TP distance: 0.0050 × 2 = 0.0100 (100 pips)
- TP price: 1.1000 + 0.0100 = 1.1100

### SELL Signal Example

Suppose:
- Account equity: $10,000
- EntrySignals indicator shows SELL arrow on closed bar
- Current Bid price: 1.1000
- Previous bar high: 1.1050
- Risk: 1%

Calculation:
- Risk amount: $10,000 × 1% = $100
- SL distance: 1.1050 - 1.1000 = 0.0050 (50 pips)
- Lot size: Calculated to risk $100 over 50 pips
- TP distance: 0.0050 × 2 = 0.0100 (100 pips)
- TP price: 1.1000 - 0.0100 = 1.0900

## Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `RiskPercent` | 1.0 | Risk percentage of equity per trade |
| `MagicNumber` | 123456 | Unique identifier for this EA's orders |
| `TradeComment` | "SignalTrade" | Comment added to all orders |
| `Slippage` | 10 | Maximum allowed slippage in points |
| `SignalPrefix` | "EntrySignal_" | Prefix for signal objects from EntrySignals indicator |

## Installation

### Prerequisites

1. **EntrySignals Indicator**: This EA requires the EntrySignals.mq5 indicator to be installed and running
   - Copy `EntrySignals.mq5` to: `MQL5` → `Indicators`
   - Compile the indicator in MetaEditor (F7)

### Installing the EA

1. Copy `BuyOnBarClose.mq5` to your MT5 data folder:
   - `File` → `Open Data Folder` → `MQL5` → `Experts`
2. Compile the EA in MetaEditor (F7)
3. Restart MT5 or refresh the Navigator panel

### Setup

1. **First**, attach the `EntrySignals` indicator to your chart
   - Configure the indicator parameters (lookback period, trading hours, etc.)
2. **Then**, attach the `BuyOnBarClose` EA to the same chart
   - Ensure AutoTrading is enabled (Ctrl+E)
3. The EA will now monitor for signals and execute trades automatically

## Configuration

### Recommended Settings

- **Timeframe**: M15 or H1 (match with EntrySignals indicator)
- **Risk**: 1% (default) - adjust based on your risk tolerance
- **Symbols**: Works best on trending pairs with clear support/resistance
- **Indicator Settings**: Configure EntrySignals lookback_period and trading hours to suit your strategy

### Risk Management Tips

- Start with 0.5% risk on a demo account
- The EA only trades when the EntrySignals indicator generates a signal
- Monitor drawdown closely as multiple positions can be open simultaneously
- Ensure the EntrySignals indicator is properly configured for your market and timeframe

## Warnings

⚠️ **Important Considerations:**

1. **Signal Dependency**: This EA requires the EntrySignals indicator to function. Without signals, no trades will be executed
2. **No Position Limit**: The EA doesn't check for existing open positions before opening new ones
3. **Market Conditions**: Effectiveness depends on EntrySignals indicator performance
4. **Testing Required**: Always test on a demo account first with your specific indicator settings
5. **Risk**: Multiple concurrent positions can be opened if multiple signals occur
6. **Synchronization**: The indicator must be running on the same chart as the EA

## Enhancements (Future Versions)

Potential improvements:
- Limit maximum number of open positions
- Add minimum bar size filter (avoid small bars with wide SL)
- Trailing stop functionality
- Break-even move after X profit
- Position size multiplier based on signal strength
- Support for multiple indicator signal sources

## Logging

The EA provides detailed logging:
- New bar detection
- Signal detection (BUY/SELL/None)
- Entry price, SL, TP levels
- Lot size calculations with detailed breakdown
- Order execution results
- Error messages and diagnostics

Check the "Experts" tab in MT5 Terminal for all logs.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No trades opening | 1. Check if AutoTrading is enabled (Ctrl+E)<br>2. Verify EntrySignals indicator is attached to the chart<br>3. Check if indicator is generating signals |
| "Invalid lot size" | Check account balance and broker's min lot size |
| "Order execution failed" | Check market is open, sufficient margin available |
| Lot size too small | Increase risk percentage or wait for signals with smaller SL distance |
| EA not detecting signals | 1. Verify SignalPrefix parameter matches indicator<br>2. Check that both EA and indicator are on same chart<br>3. Review Experts log for signal detection messages |
| Wrong signal prefix | If using a modified indicator, update the SignalPrefix parameter |

## License

This EA is provided as-is for educational purposes.
Use at your own risk. Always test thoroughly before live trading.

## Version History

- **v2.00** (2025-11-14): Signal-based trading update
  - Integrated with EntrySignals indicator
  - Added SELL position support
  - Opens trades only on indicator signals
  - Bidirectional trading (long and short)
  - Dynamic SL/TP based on bar high/low
  
- **v1.00** (2025-11-14): Initial release
  - Basic buy-on-bar-close functionality
  - Automatic volume calculation
  - 1% risk management
  - 1:2 risk:reward ratio


