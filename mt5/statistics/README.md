# Backtest Statistics Processor

## Overview
Smart incremental processor for MT5 backtest logs that handles multiple symbols and configurations efficiently.

## Features
- ✅ **Incremental Processing**: Only parses new or modified log files
- ✅ **Multi-Symbol Support**: Handles XAUUSD, EURGBP, and any future symbols
- ✅ **Caching**: Maintains `backtest_cache.json` to avoid recomputation
- ✅ **Aggregation**: Groups results by indicator configurations
- ✅ **Dual Output**: Generates both TXT and HTML summary reports
- ✅ **Smart Duplicate Detection**: Automatically removes duplicate tests (keeps first occurrence)
  - Detects: Symbol + Timeframe + Pattern + Trend + Strategy + Initial Deposit
  - Reports how many duplicates were removed

## Usage

### Basic Usage
```bash
cd /home/alin/daytrading/dt-records/mt5/statistics
python3 process_backtests.py
```

### When to Run
1. **After new backtests** - Run to include new results
2. **After adding new symbols** - Automatically detects and processes
3. **After changing configurations** - Updates aggregations

### Output Files
- `config_summary_YYYYMMDDHHMM.html` - **Styled HTML report with symbol tabs**
  - Each symbol has its own tab with separate rankings
  - Click tabs to switch between symbols
  - Beautiful, interactive interface
- `config_summary_YYYYMMDDHHMM.txt` - Plain text report  
- `backtest_cache.json` - Cache file (do not delete)

### Cache Management
The cache tracks:
- Processed log files (by fingerprint: timestamp + size)
- All parsed backtests
- Prevents reprocessing unchanged files

To **force reprocess all logs**:
```bash
rm backtest_cache.json
python3 process_backtests.py
```

## Data Aggregation
Backtests are grouped by:
- **Symbol** (e.g., XAUUSD, EURGBP) - **Each symbol is ranked separately**
- Pattern bars (e.g., 5, 9)
- Trend multiplier (e.g., 2.0, 4.0)
- Strategy (No Partial, 2-Step, 3-Step)

For each symbol + configuration, the script calculates:
- Average ROI across all timeframes
- Average Win Rate
- Average Profit Factor
- Total trades/wins/losses
- Best/Worst timeframes for that symbol

## Log File Location
Default: `~/.wine_mt5-2/drive_c/Program Files/MetaTrader 5/MQL5/Logs/*.log`

To change, edit `LOG_BASE_PATH` in `process_backtests.py`:
```python
LOG_BASE_PATH = Path.home() / ".wine_mt5-2/drive_c/Program Files/MetaTrader 5/MQL5/Logs"
```

## Example Output
```
🏆 TOP 10 CONFIGURATIONS BY AVG ROI:
  1. XAUUSD: 9 bars, Trend 4.0, No Partial Close (Full TP/SL)
     Avg ROI: 134.40% | Timeframes: M1, M5, M15, M30, H1
  2. XAUUSD: 5 bars, Trend 2.0, No Partial Close (Full TP/SL)
     Avg ROI: 102.97% | Timeframes: M1, M5, M15, M30, H1
  3. XAUUSD: 9 bars, Trend 4.0, 3-Step Progressive
     Avg ROI: 98.29% | Timeframes: M1, M5, M15, M30, H1
  ...
  7. EURGBP: 5 bars, Trend 2.0, 3-Step Progressive
     Avg ROI: -47.89% | Timeframes: M1, M5, M15, M30, H1
```

Each symbol is ranked separately, making it easy to:
- **Compare** which symbol works best with each configuration
- **Identify** the best configurations per symbol
- **Choose** the optimal symbol for your trading strategy

### HTML Report Features 🎨
The HTML report includes:
- **📑 Interactive Tabs**: Click to switch between symbols
  - `[EURGBP]` `[XAUUSD]` `[EURUSD]` etc.
- **🏅 Symbol-Specific Rankings**: Each tab shows rankings for that symbol only
  - #1, #2, #3 rankings per symbol
- **📊 Visual Performance Metrics**: Color-coded stats
  - 🟢 Green for positive ROI
  - 🔴 Red for negative ROI
- **⚡ Smooth Animations**: Tab switching with fade effects
- **📱 Responsive Design**: Works on desktop and mobile

## Multi-Symbol Workflow
1. Backtest XAUUSD on various configurations ✅
2. Run processor: `python3 process_backtests.py`
3. Review `config_summary_*.html` - see XAUUSD rankings
4. Backtest EURGBP on same configurations
5. Run processor again - **only new data is parsed**
6. Review updated summary - **each symbol ranked separately**

The script automatically:
- Detects new symbols
- **Ranks each symbol independently** (e.g., XAUUSD #1, EURGBP #7)
- Shows which symbol performs best with each configuration
- Helps you choose the optimal symbol for your strategy

## Duplicate Detection

The script automatically detects and removes duplicate tests. A test is considered duplicate if it has the same:
- Symbol (e.g., XAUUSD)
- Timeframe (e.g., M15)
- Pattern Bars (e.g., 5 or 9)
- Trend Multiplier (e.g., 2.0 or 4.0)
- Strategy (No Partial, 2-Step, 3-Step)
- Initial Deposit (e.g., $10,000)

**When duplicates are found:**
- First occurrence is kept
- Later duplicates are discarded
- Script reports: `🗑️ Removed X duplicate test(s)`

**Example output:**
```
📖 Parsing: 20251119.log
  ✅ Found 129 backtests

📊 Total backtests: 45 (129 new)
   🗑️  Removed 84 duplicate test(s)
```

This prevents accidentally running the same test multiple times from skewing your results.

## Troubleshooting

**No backtests found?**
- Verify log path exists
- Check logs contain "FIRST COMPUTATION COMPLETE" markers
- Verify UTF-16 encoding in MT5 logs

**Want to reset everything?**
```bash
rm backtest_cache.json
rm config_summary_*.txt config_summary_*.html
python3 process_backtests.py
```

**Too many duplicates?**
- The script automatically handles this
- Check your backtesting workflow to avoid re-running same configs
- Each unique config should only be tested once per symbol/timeframe

## Files Structure
```
mt5/statistics/
├── process_backtests.py         # Main script
├── backtest_cache.json          # Cache (auto-generated)
├── config_summary_*.txt         # Summary reports
├── config_summary_*.html        # Styled reports
└── README.md                    # This file
```

