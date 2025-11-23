//+------------------------------------------------------------------+
//|                                             Sim Trades Indicator |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

// Plot settings for AMA
#property indicator_label1  "AMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Input parameters
input int LookbackWeeks = 6;           // Lookback period in weeks
input int LookbackDays = 0;            // Additional lookback days
int PatternBars = 5;
color HighArrowColor = clrRed;   // High pattern arrow color (Red Down = Sell entry)
color LowArrowColor = clrLime;   // Low pattern arrow color (Green Up = Buy entry)
int ArrowWidth = 1;              // Arrow width
int ArrowOffsetPoints = 10;      // Arrow offset from high/low in points

// AMA (Adaptive Moving Average) parameters
int AMA_Period = 10;             // AMA Period
int AMA_FastEMA = 10;            // Fast EMA Period
int AMA_SlowEMA = 200;           // Slow EMA Period
color AMA_Color = clrBlue;       // AMA Line Color
int AMA_Width = 1;               // AMA Line Width
input double TrendSpreadMultiplier = 1.5;  // Spread multiplier for trend threshold

// Money management parameters
input double InitialDeposit = 10000.0;  // Initial deposit ($)
input double RiskPercent = 1.0;         // Risk per trade (% of equity)
input double TPMultiplier = 2.0;        // Take Profit multiplier (TP = SL × Multiplier)

// Partial close strategy
enum PartialCloseStrategy
{
   STRATEGY_NO_PARTIAL = 0,      // No Partial Close (Full TP/SL only)
   STRATEGY_2_STEPS = 1,          // 2-Step: 50% at 50% TP + BE
   STRATEGY_3_STEPS = 2,          // 3-Step Progressive: 1/3 at 40%, 1/3 at 80%, trail at 100%
   STRATEGY_STEP_LADDER = 3       // Step Ladder: At 90% progress, move both SL & TP by step distance
};

input PartialCloseStrategy PartialStrategy = STRATEGY_NO_PARTIAL; // Partial Close Strategy

// Signal filtering
input bool FilterOppositeSignals = true;  // Filter opposite trend signals (SELL in uptrend, BUY in downtrend)

// Trading time filter
input int TradingStartHour = 3;         // Trading start hour (0-23)
input int TradingEndHour = 22;          // Trading end hour (0-23)
input bool TradeOnMonday = true;        // Trade on Monday
input bool TradeOnTuesday = true;       // Trade on Tuesday
input bool TradeOnWednesday = true;     // Trade on Wednesday
input bool TradeOnThursday = true;      // Trade on Thursday
input bool TradeOnFriday = true;        // Trade on Friday

// Indicator prefix for object names
string indicator_prefix = "simTrades_";

// Unique session identifier for log parsing (helps when multiple tests run in parallel)
string session_id = "";
string session_prefix = "";  // Full prefix to prepend to every log line

// Track last detected pattern's top bar to avoid duplicates
int last_top_bar = -1;

// Track last detected high/low for flat trend filtering
double last_high_value = 0.0;
int last_high_bar = -1;
double last_low_value = 0.0;
int last_low_bar = -1;

// Indicator buffers
double AMA_Buffer[];

// Indicator handles
int AMA_Handle;

// Trend state: 1=uptrend, -1=downtrend, 0=flat
int trend_state = 0;

// Pattern validation counters
int validated_patterns_count = 0;
int invalidated_patterns_count = 0;
int patterns_detected_count = 0;  // Total patterns detected before validation

// Trade tracking structure
struct TradeInfo
{
    datetime entry_time;
    double entry_price;
    double sl_price;
    double tp_price;
    int direction;  // 1=BUY, -1=SELL
    double position_size;  // Lot size
    double risk_amount;    // Risk in dollars
    bool is_active;
    
    // Partial close tracking
    double original_sl;
    double original_tp;
    double original_position_size;
    double current_position_size;
    bool step1_done;
    bool step2_done;
    bool step3_done;
    
    // Cumulative P&L tracking for win/loss determination
    double cumulative_pnl_dollars;  // Track total P&L across partial closes
};

// Trade arrays and statistics
TradeInfo active_trades[];
int total_trades = 0;
int total_wins = 0;
int total_losses = 0;
double total_pips_won = 0.0;
double total_pips_lost = 0.0;

// Money management tracking
double current_equity = 0.0;
double peak_equity = 0.0;
double total_profit_dollars = 0.0;
double total_loss_dollars = 0.0;

// Equity curve tracking by bar
struct EquityPoint
{
    datetime bar_time;
    double equity_value;
    double peak_value;
};
EquityPoint equity_history[];

// Streak tracking
int current_streak = 0;  // Positive for wins, negative for losses
int longest_win_streak = 0;
int longest_loss_streak = 0;

// Time-based performance tracking
double hourly_pnl[24];      // P&L for each hour (0-23)
int hourly_trades[24];       // Trade count for each hour
double weekday_pnl[7];       // P&L for each weekday (0=Sunday, 6=Saturday)
int weekday_trades[7];       // Trade count for each weekday

// Trading session performance (UTC+2 times)
// 0=Sydney (00-09), 1=Tokyo (02-11), 2=London (10-18), 3=New York (15-00)
double session_pnl[4];       // P&L for each session
int session_trades[4];       // Trade count for each session
int session_wins[4];         // Win count for each session
int session_losses[4];       // Loss count for each session

// Previous summary values to detect changes
int prev_total_trades = 0;
int prev_total_wins = 0;
int prev_total_losses = 0;

// Flag to track if first computation is done
bool first_computation_done = false;

// Track current timeframe to detect changes
ENUM_TIMEFRAMES current_timeframe = PERIOD_CURRENT;

//+------------------------------------------------------------------+
//| Get trading session index based on UTC+2 hour                    |
//| 0=Sydney (00-09), 1=Tokyo (02-11), 2=London (10-18), 3=NY (15-00)|
//+------------------------------------------------------------------+
int GetTradingSession(int hour_utc2)
{
    // Session times (UTC+2):
    // Sydney: 00:00 - 09:00
    // Tokyo: 02:00 - 11:00  
    // London: 10:00 - 18:00
    // New York: 15:00 - 23:59 (midnight)
    
    // Assign primary session based on hour
    if(hour_utc2 >= 0 && hour_utc2 <= 1)
        return 0;  // Sydney
    else if(hour_utc2 >= 2 && hour_utc2 <= 9)
        return 1;  // Tokyo (also Sydney overlap, but Tokyo is main)
    else if(hour_utc2 >= 10 && hour_utc2 <= 14)
        return 2;  // London
    else if(hour_utc2 >= 15 && hour_utc2 <= 23)
        return 3;  // New York
    
    return 2;  // Default to London
}

//+------------------------------------------------------------------+
//| Check if trading is allowed at the given time                    |
//+------------------------------------------------------------------+
bool IsTradingTimeAllowed(datetime check_time)
{
    MqlDateTime dt;
    TimeToStruct(check_time, dt);
    
    // Check if it's a weekend (0=Sunday, 6=Saturday)
    if(dt.day_of_week == 0 || dt.day_of_week == 6)
        return false;
    
    // Check specific weekday filters
    if(dt.day_of_week == 1 && !TradeOnMonday)
        return false;
    if(dt.day_of_week == 2 && !TradeOnTuesday)
        return false;
    if(dt.day_of_week == 3 && !TradeOnWednesday)
        return false;
    if(dt.day_of_week == 4 && !TradeOnThursday)
        return false;
    if(dt.day_of_week == 5 && !TradeOnFriday)
        return false;
    
    // Check trading hours
    if(dt.hour >= TradingStartHour && dt.hour <= TradingEndHour)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Get bar body top (close for bullish, open for bearish)          |
//+------------------------------------------------------------------+
double GetBodyTop(const double &open[], const double &close[], int bar_index)
{
    // Bullish bar: close > open, body top is close
    // Bearish bar: close <= open, body top is open
    if(close[bar_index] > open[bar_index])
        return close[bar_index];  // Bullish
    else
        return open[bar_index];   // Bearish
}

//+------------------------------------------------------------------+
//| Get bar body bottom (open for bullish, close for bearish)       |
//+------------------------------------------------------------------+
double GetBodyBottom(const double &open[], const double &close[], int bar_index)
{
    // Bullish bar: close > open, body bottom is open
    // Bearish bar: close <= open, body bottom is close
    if(close[bar_index] > open[bar_index])
        return open[bar_index];   // Bullish
    else
        return close[bar_index];  // Bearish
}

//+------------------------------------------------------------------+
//| Update trend state based on AMA slope at current bar             |
//+------------------------------------------------------------------+
void UpdateTrendState(const int &spread[])
{
    // Compare current AMA to AMA from 10 bars ago to determine trend
    int lookback_bars = 10;
    
    // Make sure we have enough bars
    if(ArraySize(AMA_Buffer) <= lookback_bars)
    {
        trend_state = 0;
        return;
    }
    
    double ama_current = AMA_Buffer[0];       // Most recent AMA
    double ama_previous = AMA_Buffer[lookback_bars];  // AMA 10 bars ago
    
    // Trend logic: Compare current AMA vs previous AMA
    // UPTREND: Current AMA > Previous AMA (rising)
    // DOWNTREND: Current AMA < Previous AMA (falling)
    
    double ama_diff = ama_current - ama_previous;
    
    // Use configurable spread multiplier as minimum threshold to establish trend
    double threshold = spread[0] * TrendSpreadMultiplier * _Point;
    
    if(ama_diff > threshold)
    {
        // Current AMA > Previous AMA = rising trend
        trend_state = 1;  // Uptrend
    }
    else if(ama_diff < -threshold)
    {
        // Current AMA < Previous AMA = falling trend
        trend_state = -1;  // Downtrend
    }
    else
    {
        // AMA values too close, no clear trend
        trend_state = 0;  // Flat/ranging
    }
}

//+------------------------------------------------------------------+
//| Get trend state at a specific bar                                |
//+------------------------------------------------------------------+
int GetTrendAtBar(int bar_index, const int &spread[])
{
    // Compare AMA at bar_index to AMA from 10 bars before it
    int lookback_bars = 10;
    
    // Make sure we have enough bars
    if(bar_index + lookback_bars >= ArraySize(AMA_Buffer))
        return 0;  // Not enough data
    
    double ama_at_bar = AMA_Buffer[bar_index];
    double ama_previous = AMA_Buffer[bar_index + lookback_bars];
    
    double ama_diff = ama_at_bar - ama_previous;
    
    // Use configurable spread multiplier as threshold (same as UpdateTrendState)
    double threshold = spread[bar_index] * TrendSpreadMultiplier * _Point;
    
    if(ama_diff > threshold)
        return 1;  // Uptrend
    else if(ama_diff < -threshold)
        return -1;  // Downtrend
    else
        return 0;  // Flat/ranging
}

//+------------------------------------------------------------------+
//| Display trend state on chart                                     |
//+------------------------------------------------------------------+
void DisplayTrendState()
{
    string trend_text;
    color trend_color;
    
    if(trend_state == 1)
    {
        trend_text = "UPTREND";
        trend_color = clrGreen;
    }
    else if(trend_state == -1)
    {
        trend_text = "DOWNTREND";
        trend_color = clrRed;
    }
    else
    {
        trend_text = "FLAT/NO DATA";
        trend_color = clrGray;
    }
    
    string label_name = indicator_prefix + "TrendLabel";
    if(ObjectFind(0, label_name) < 0)
    {
        ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, 30);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 12);
    }
    
    ObjectSetString(0, label_name, OBJPROP_TEXT, "AMA Trend: " + trend_text);
    ObjectSetInteger(0, label_name, OBJPROP_COLOR, trend_color);
}

//+------------------------------------------------------------------+
//| Display pattern statistics on chart                              |
//+------------------------------------------------------------------+
void DisplayPatternStats()
{
    string stats_text = StringFormat("Patterns - Detected: %d | Valid: %d | Invalid: %d", 
                                     patterns_detected_count,
                                     validated_patterns_count, 
                                     invalidated_patterns_count);
    
    string label_name = indicator_prefix + "StatsLabel";
    if(ObjectFind(0, label_name) < 0)
    {
        ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, 50);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 10);
    }
    
    ObjectSetString(0, label_name, OBJPROP_TEXT, stats_text);
    ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrWhite);
}

//+------------------------------------------------------------------+
//| Record equity snapshot at a specific bar time                     |
//+------------------------------------------------------------------+
void RecordEquitySnapshot(datetime bar_time)
{
    // Find if this bar time already exists
    int existing_idx = -1;
    for(int i = 0; i < ArraySize(equity_history); i++)
    {
        if(equity_history[i].bar_time == bar_time)
        {
            existing_idx = i;
            break;
        }
    }
    
    if(existing_idx >= 0)
    {
        // Update existing snapshot
        equity_history[existing_idx].equity_value = current_equity;
        equity_history[existing_idx].peak_value = peak_equity;
    }
    else
    {
        // Add new snapshot
        int size = ArraySize(equity_history);
        ArrayResize(equity_history, size + 1);
        equity_history[size].bar_time = bar_time;
        equity_history[size].equity_value = current_equity;
        equity_history[size].peak_value = peak_equity;
    }
    
    // Also store as global variables for SimTradesEquity indicator to read
    // Include symbol and timeframe in variable name to avoid collisions
    string eq_var_name = StringFormat("simTrades_%s_%s_equity_%s", 
                                      _Symbol, 
                                      EnumToString((ENUM_TIMEFRAMES)_Period),
                                      TimeToString(bar_time, TIME_DATE|TIME_MINUTES));
    string peak_var_name = StringFormat("simTrades_%s_%s_peak_%s", 
                                        _Symbol, 
                                        EnumToString((ENUM_TIMEFRAMES)_Period),
                                        TimeToString(bar_time, TIME_DATE|TIME_MINUTES));
    GlobalVariableSet(eq_var_name, current_equity);
    GlobalVariableSet(peak_var_name, peak_equity);
}

//+------------------------------------------------------------------+
//| Add new trade to active trades array                             |
//+------------------------------------------------------------------+
void AddTrade(datetime entry_time, double entry_price, double sl_price, double tp_price, int direction)
{
    int size = ArraySize(active_trades);
    ArrayResize(active_trades, size + 1);
    
    // Calculate SL distance in pips
    double sl_distance_pips = MathAbs(entry_price - sl_price) / _Point;
    
    // Calculate risk amount for this trade (% of current equity)
    double risk_amount = current_equity * (RiskPercent / 100.0);
    
    // Calculate pip value per lot (standard)
    // For most forex pairs: 1 standard lot (100,000 units) = $10 per pip
    // We'll use a simplified calculation: pip_value = SymbolInfoDouble contract size × point
    double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pip_value_per_lot = (tick_value / tick_size) * _Point;
    
    // Calculate position size in lots
    double position_size = 0.0;
    if(sl_distance_pips > 0 && pip_value_per_lot > 0)
        position_size = risk_amount / (sl_distance_pips * pip_value_per_lot);
    
    // Apply broker limits
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(position_size < min_lot)
        position_size = min_lot;
    else if(position_size > max_lot)
        position_size = max_lot;
    else
        position_size = MathFloor(position_size / lot_step) * lot_step;
    
    active_trades[size].entry_time = entry_time;
    active_trades[size].entry_price = entry_price;
    active_trades[size].sl_price = sl_price;
    active_trades[size].tp_price = tp_price;
    active_trades[size].direction = direction;
    active_trades[size].position_size = position_size;
    active_trades[size].risk_amount = risk_amount;
    active_trades[size].is_active = true;
    
    // Initialize partial close tracking
    active_trades[size].original_sl = sl_price;
    active_trades[size].original_tp = tp_price;
    active_trades[size].original_position_size = position_size;
    active_trades[size].current_position_size = position_size;
    active_trades[size].step1_done = false;
    active_trades[size].step2_done = false;
    active_trades[size].step3_done = false;
    active_trades[size].cumulative_pnl_dollars = 0.0;  // Initialize cumulative P&L
    
    total_trades++;
}

//+------------------------------------------------------------------+
//| Process 2-Step Partial Close Strategy                            |
//+------------------------------------------------------------------+
void ProcessPartialClose_2Step(int trade_idx, int bar, const datetime &time[], const double &high[], const double &low[], const double &close[], const int &spread[])
{
    if(!active_trades[trade_idx].is_active)
        return;
    
    double range = MathAbs(active_trades[trade_idx].original_tp - active_trades[trade_idx].entry_price);
    double level1 = (active_trades[trade_idx].direction == 1) ? 
                    active_trades[trade_idx].entry_price + range/2.0 : 
                    active_trades[trade_idx].entry_price - range/2.0;
    
    double price = (active_trades[trade_idx].direction == 1) ? low[bar] : high[bar];
    
    // Calculate pip value
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pip_value_per_lot = (tick_value / tick_size) * _Point;
    
    // STEP 1: Close 50% at 50% TP and move SL to BE
    if(!active_trades[trade_idx].step1_done)
    {
        bool trigger1 = (active_trades[trade_idx].direction == 1 && high[bar] >= level1) ||
                       (active_trades[trade_idx].direction == -1 && low[bar] <= level1);
        
        if(trigger1)
        {
            double close_size = active_trades[trade_idx].original_position_size / 2.0;
            double pips_won = MathAbs(level1 - active_trades[trade_idx].entry_price) / _Point;
            double profit_dollars = pips_won * pip_value_per_lot * close_size;
            
            // Book the partial profit (weight pips by position size ratio: 50%)
            double position_ratio = close_size / active_trades[trade_idx].original_position_size;
            total_pips_won += pips_won * position_ratio;
            total_profit_dollars += profit_dollars;
            current_equity += profit_dollars;
            
            // Add to cumulative P&L for this trade
            active_trades[trade_idx].cumulative_pnl_dollars += profit_dollars;
            
            if(current_equity > peak_equity)
                peak_equity = current_equity;
            
            // Record equity snapshot
            RecordEquitySnapshot(time[bar]);
            
            // Update position size
            active_trades[trade_idx].current_position_size -= close_size;
            
            // Move SL to breakeven
            active_trades[trade_idx].sl_price = active_trades[trade_idx].entry_price;
            
            active_trades[trade_idx].step1_done = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Process Step Ladder Strategy (Move SL & TP together)             |
//+------------------------------------------------------------------+
void ProcessPartialClose_StepLadder(int trade_idx, int bar, const datetime &time[], const double &high[], const double &low[], const double &close[], const int &spread[])
{
    if(!active_trades[trade_idx].is_active)
        return;
    
    // Calculate step distance (SL to BE distance, kept constant)
    double stepDistance = MathAbs(active_trades[trade_idx].original_sl - active_trades[trade_idx].entry_price);
    
    // Current SL and TP
    double current_sl = active_trades[trade_idx].sl_price;
    double current_tp = active_trades[trade_idx].tp_price;
    
    if(active_trades[trade_idx].direction == 1)  // BUY trade
    {
        // Calculate 90% progress point: SL + 90% of (TP - SL)
        double range = current_tp - current_sl;
        double trigger_price = current_sl + 0.9 * range;
        
        // Check if price reached 90% of the way to TP
        if(high[bar] >= trigger_price)
        {
            // Move both SL and TP up by stepDistance
            active_trades[trade_idx].sl_price = current_sl + stepDistance;
            active_trades[trade_idx].tp_price = current_tp + stepDistance;
            
            // Record equity snapshot (even though no close, the levels moved)
            RecordEquitySnapshot(time[bar]);
        }
    }
    else  // SELL trade
    {
        // Calculate 90% progress point: SL - 90% of (SL - TP)
        double range = current_sl - current_tp;
        double trigger_price = current_sl - 0.9 * range;
        
        // Check if price reached 90% of the way to TP
        if(low[bar] <= trigger_price)
        {
            // Move both SL and TP down by stepDistance
            active_trades[trade_idx].sl_price = current_sl - stepDistance;
            active_trades[trade_idx].tp_price = current_tp - stepDistance;
            
            // Record equity snapshot (even though no close, the levels moved)
            RecordEquitySnapshot(time[bar]);
        }
    }
}

//+------------------------------------------------------------------+
//| Process 3-Step Partial Close Strategy                            |
//+------------------------------------------------------------------+
void ProcessPartialClose_3Step(int trade_idx, int bar, const datetime &time[], const double &high[], const double &low[], const double &close[], const int &spread[])
{
    if(!active_trades[trade_idx].is_active)
        return;
    
    double range = MathAbs(active_trades[trade_idx].original_tp - active_trades[trade_idx].entry_price);
    double level1 = (active_trades[trade_idx].direction == 1) ? 
                    active_trades[trade_idx].entry_price + range/2.5 : 
                    active_trades[trade_idx].entry_price - range/2.5;
    double level2 = (active_trades[trade_idx].direction == 1) ? 
                    active_trades[trade_idx].entry_price + 2.0*range/2.5 : 
                    active_trades[trade_idx].entry_price - 2.0*range/2.5;
    double level3 = active_trades[trade_idx].original_tp;
    
    // Calculate pip value
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pip_value_per_lot = (tick_value / tick_size) * _Point;
    
    // STEP 1: Close 1/3 at 40% of TP
    if(!active_trades[trade_idx].step1_done)
    {
        bool trigger1 = (active_trades[trade_idx].direction == 1 && high[bar] >= level1) ||
                       (active_trades[trade_idx].direction == -1 && low[bar] <= level1);
        
        if(trigger1)
        {
            double close_size = active_trades[trade_idx].original_position_size / 3.0;
            double pips_won = MathAbs(level1 - active_trades[trade_idx].entry_price) / _Point;
            double profit_dollars = pips_won * pip_value_per_lot * close_size;
            
            // Book the partial profit (weight pips by position size ratio: 1/3)
            double position_ratio = close_size / active_trades[trade_idx].original_position_size;
            total_pips_won += pips_won * position_ratio;
            total_profit_dollars += profit_dollars;
            current_equity += profit_dollars;
            
            // Add to cumulative P&L for this trade
            active_trades[trade_idx].cumulative_pnl_dollars += profit_dollars;
            
            if(current_equity > peak_equity)
                peak_equity = current_equity;
            
            // Record equity snapshot
            RecordEquitySnapshot(time[bar]);
            
            // Update position size
            active_trades[trade_idx].current_position_size -= close_size;
            
            active_trades[trade_idx].step1_done = true;
        }
    }
    
    // STEP 2: Close 1/3 at 80% of TP, move SL to BE, extend TP to 1.25x
    if(active_trades[trade_idx].step1_done && !active_trades[trade_idx].step2_done)
    {
        bool trigger2 = (active_trades[trade_idx].direction == 1 && high[bar] >= level2) ||
                       (active_trades[trade_idx].direction == -1 && low[bar] <= level2);
        
        if(trigger2)
        {
            double close_size = active_trades[trade_idx].original_position_size / 3.0;
            double pips_won = MathAbs(level2 - active_trades[trade_idx].entry_price) / _Point;
            double profit_dollars = pips_won * pip_value_per_lot * close_size;
            
            // Book the partial profit (weight pips by position size ratio: 1/3)
            double position_ratio = close_size / active_trades[trade_idx].original_position_size;
            total_pips_won += pips_won * position_ratio;
            total_profit_dollars += profit_dollars;
            current_equity += profit_dollars;
            
            // Add to cumulative P&L for this trade
            active_trades[trade_idx].cumulative_pnl_dollars += profit_dollars;
            
            if(current_equity > peak_equity)
                peak_equity = current_equity;
            
            // Record equity snapshot
            RecordEquitySnapshot(time[bar]);
            
            // Update position size
            active_trades[trade_idx].current_position_size -= close_size;
            
            // Move SL to BE
            active_trades[trade_idx].sl_price = active_trades[trade_idx].entry_price;
            
            // Extend TP to 1.25x
            double newTP = (active_trades[trade_idx].direction == 1) ? 
                          active_trades[trade_idx].entry_price + range*1.25 :
                          active_trades[trade_idx].entry_price - range*1.25;
            active_trades[trade_idx].tp_price = newTP;
            
            active_trades[trade_idx].step2_done = true;
        }
    }
    
    // STEP 3: Move SL to 80% of range when original TP hit (keep TP at 1.25x from Step 2)
    if(active_trades[trade_idx].step2_done && !active_trades[trade_idx].step3_done)
    {
        bool trigger3 = (active_trades[trade_idx].direction == 1 && high[bar] >= level3) ||
                       (active_trades[trade_idx].direction == -1 && low[bar] <= level3);
        
        if(trigger3)
        {
            // Move SL to 80% of range
            double newSL = (active_trades[trade_idx].direction == 1) ? 
                          active_trades[trade_idx].entry_price + range/1.25 :
                          active_trades[trade_idx].entry_price - range/1.25;
            active_trades[trade_idx].sl_price = newSL;
            
            // Keep TP at 1.25x from Step 2 (don't remove it)
            // active_trades[trade_idx].tp_price remains unchanged
            
            active_trades[trade_idx].step3_done = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Check active trades and close if SL or TP hit                    |
//+------------------------------------------------------------------+
void CheckActiveTrades(const datetime &time[], const double &high[], const double &low[], const double &close[], const int &spread[])
{
    for(int i = 0; i < ArraySize(active_trades); i++)
    {
        if(!active_trades[i].is_active)
            continue;
        
        // Find current bar index for this trade's entry time
        int trade_bar = iBarShift(_Symbol, _Period, active_trades[i].entry_time);
        if(trade_bar < 0)
            continue;  // Trade not yet entered
        
        // Check all bars from entry to current
        for(int bar = trade_bar; bar >= 0; bar--)
        {
            // Process partial closes first (if strategy enabled)
            if(PartialStrategy == STRATEGY_2_STEPS)
            {
                ProcessPartialClose_2Step(i, bar, time, high, low, close, spread);
            }
            else if(PartialStrategy == STRATEGY_STEP_LADDER)
            {
                ProcessPartialClose_StepLadder(i, bar, time, high, low, close, spread);
            }
            else if(PartialStrategy == STRATEGY_3_STEPS)
            {
                ProcessPartialClose_3Step(i, bar, time, high, low, close, spread);
            }
            
            if(active_trades[i].direction == 1)  // BUY trade
            {
                // BUY: Entered at ASK, closes at BID
                // Calculate pip value for this position
                double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                double pip_value_per_lot = (tick_value / tick_size) * _Point;
                
                // Check if SL hit (BID low went below SL)
                if(low[bar] <= active_trades[i].sl_price)
                {
                    // Final close at SL (using current position size, not original)
                    double pips_result = (active_trades[i].sl_price - active_trades[i].entry_price) / _Point;  // Can be + or -
                    double result_dollars = pips_result * pip_value_per_lot * active_trades[i].current_position_size;
                    
                    // Weight pips by position size ratio to avoid double-counting with partial closes
                    double position_ratio = active_trades[i].current_position_size / active_trades[i].original_position_size;
                    
                    // Track win/loss pips and dollars based on actual result
                    if(result_dollars >= 0)  // SL locked in profit (trailing)
                    {
                        double weighted_pips = pips_result * position_ratio;
                        total_pips_won += weighted_pips;
                        total_profit_dollars += result_dollars;
                    }
                    else  // SL was actual loss
                    {
                        double pips_lost = -pips_result;  // Make positive
                        double loss_dollars = -result_dollars;  // Make positive
                        double weighted_pips = pips_lost * position_ratio;
                        total_pips_lost += weighted_pips;
                        total_loss_dollars += loss_dollars;
                    }
                    
                    current_equity += result_dollars;  // Add result (can be + or -)
                    
                    // Add to cumulative P&L
                    active_trades[i].cumulative_pnl_dollars += result_dollars;
                    
                    // Record equity snapshot
                    RecordEquitySnapshot(time[bar]);
                    
                    // Determine if OVERALL trade was win or loss based on cumulative P&L
                    bool is_overall_win = (active_trades[i].cumulative_pnl_dollars > 0);
                    
                    if(is_overall_win)
                    {
                        total_wins++;
                        // Update win streak
                        if(current_streak >= 0)
                            current_streak++;  // Continue or start win streak
                        else
                            current_streak = 1;  // Start new win streak
                        
                        if(current_streak > longest_win_streak)
                            longest_win_streak = current_streak;
                    }
                    else
                    {
                        total_losses++;
                        // Update loss streak
                        if(current_streak <= 0)
                            current_streak--;  // Continue or start loss streak
                        else
                            current_streak = -1;  // Start new loss streak
                        
                    if(MathAbs(current_streak) > longest_loss_streak)
                        longest_loss_streak = MathAbs(current_streak);
                    }
                    
                    // Update time-based statistics (use actual result, can be + or -)
                    MqlDateTime entry_dt;
                    TimeToStruct(active_trades[i].entry_time, entry_dt);
                    hourly_pnl[entry_dt.hour] += result_dollars;
                    hourly_trades[entry_dt.hour]++;
                    weekday_pnl[entry_dt.day_of_week] += result_dollars;
                    weekday_trades[entry_dt.day_of_week]++;
                    
                    // Update session statistics (count as win or loss based on overall trade)
                    int session = GetTradingSession(entry_dt.hour);
                    session_pnl[session] += result_dollars;
                    session_trades[session]++;
                    if(is_overall_win)
                        session_wins[session]++;
                    else
                        session_losses[session]++;
                    
                    active_trades[i].is_active = false;
                    break;
                }
                
                // Check if TP hit (BID high went above TP) - skip if TP is 0
                if(active_trades[i].tp_price > 0 && high[bar] >= active_trades[i].tp_price)
                {
                    // Final close at TP (using current position size, not original) - should always be profit
                    double pips_won = (active_trades[i].tp_price - active_trades[i].entry_price) / _Point;
                    double profit_dollars = pips_won * pip_value_per_lot * active_trades[i].current_position_size;
                    
                    // Weight pips by position size ratio to avoid double-counting with partial closes
                    double position_ratio = active_trades[i].current_position_size / active_trades[i].original_position_size;
                    double weighted_pips = pips_won * position_ratio;
                    
                    total_pips_won += weighted_pips;  // Use weighted pips
                    total_profit_dollars += profit_dollars;
                    current_equity += profit_dollars;
                    
                    // Add to cumulative P&L (profit is positive)
                    active_trades[i].cumulative_pnl_dollars += profit_dollars;
                    
                    // Update peak equity
                    if(current_equity > peak_equity)
                        peak_equity = current_equity;
                    
                    // Record equity snapshot
                    RecordEquitySnapshot(time[bar]);
                    
                    // Determine if OVERALL trade was win or loss based on cumulative P&L
                    bool is_overall_win = (active_trades[i].cumulative_pnl_dollars > 0);
                    
                    if(is_overall_win)
                    {
                        total_wins++;
                        // Update win streak
                        if(current_streak >= 0)
                            current_streak++;  // Continue or start win streak
                        else
                            current_streak = 1;  // Start new win streak
                        
                        if(current_streak > longest_win_streak)
                            longest_win_streak = current_streak;
                    }
                    else
                    {
                        total_losses++;
                        // Update loss streak
                        if(current_streak <= 0)
                            current_streak--;  // Continue or start loss streak
                        else
                            current_streak = -1;  // Start new loss streak
                        
                        if(MathAbs(current_streak) > longest_loss_streak)
                            longest_loss_streak = MathAbs(current_streak);
                    }
                    
                    // Update time-based statistics (use final close result)
                    MqlDateTime entry_dt;
                    TimeToStruct(active_trades[i].entry_time, entry_dt);
                    hourly_pnl[entry_dt.hour] += profit_dollars;
                    hourly_trades[entry_dt.hour]++;
                    weekday_pnl[entry_dt.day_of_week] += profit_dollars;
                    weekday_trades[entry_dt.day_of_week]++;
                    
                    // Update session statistics (count as win or loss based on overall trade)
                    int session = GetTradingSession(entry_dt.hour);
                    session_pnl[session] += profit_dollars;
                    session_trades[session]++;
                    if(is_overall_win)
                        session_wins[session]++;
                    else
                        session_losses[session]++;
                    
                    active_trades[i].is_active = false;
                    break;
                }
            }
            else  // SELL trade
            {
                // SELL: Entered at BID, closes at ASK
                // Calculate pip value for this position
                double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                double pip_value_per_lot = (tick_value / tick_size) * _Point;
                
                // Check if SL hit (ASK high went above SL)
                double ask_high = high[bar] + (spread[bar] * _Point);
                if(ask_high >= active_trades[i].sl_price)
                {
                    // Final close at SL (using current position size, not original)
                    double pips_result = (active_trades[i].entry_price - active_trades[i].sl_price) / _Point;  // Can be + or -
                    double result_dollars = pips_result * pip_value_per_lot * active_trades[i].current_position_size;
                    
                    // Weight pips by position size ratio to avoid double-counting with partial closes
                    double position_ratio = active_trades[i].current_position_size / active_trades[i].original_position_size;
                    
                    // Track win/loss pips and dollars based on actual result
                    if(result_dollars >= 0)  // SL locked in profit (trailing)
                    {
                        double weighted_pips = pips_result * position_ratio;
                        total_pips_won += weighted_pips;
                        total_profit_dollars += result_dollars;
                    }
                    else  // SL was actual loss
                    {
                        double pips_lost = -pips_result;  // Make positive
                        double loss_dollars = -result_dollars;  // Make positive
                        double weighted_pips = pips_lost * position_ratio;
                        total_pips_lost += weighted_pips;
                        total_loss_dollars += loss_dollars;
                    }
                    
                    current_equity += result_dollars;  // Add result (can be + or -)
                    
                    // Add to cumulative P&L
                    active_trades[i].cumulative_pnl_dollars += result_dollars;
                    
                    // Record equity snapshot
                    RecordEquitySnapshot(time[bar]);
                    
                    // Determine if OVERALL trade was win or loss based on cumulative P&L
                    bool is_overall_win = (active_trades[i].cumulative_pnl_dollars > 0);
                    
                    if(is_overall_win)
                    {
                        total_wins++;
                        // Update win streak
                        if(current_streak >= 0)
                            current_streak++;  // Continue or start win streak
                        else
                            current_streak = 1;  // Start new win streak
                        
                        if(current_streak > longest_win_streak)
                            longest_win_streak = current_streak;
                    }
                    else
                    {
                        total_losses++;
                        // Update loss streak
                        if(current_streak <= 0)
                            current_streak--;  // Continue or start loss streak
                        else
                            current_streak = -1;  // Start new loss streak
                        
                        if(MathAbs(current_streak) > longest_loss_streak)
                            longest_loss_streak = MathAbs(current_streak);
                    }
                    
                    // Update time-based statistics (use actual result, can be + or -)
                    MqlDateTime entry_dt;
                    TimeToStruct(active_trades[i].entry_time, entry_dt);
                    hourly_pnl[entry_dt.hour] += result_dollars;
                    hourly_trades[entry_dt.hour]++;
                    weekday_pnl[entry_dt.day_of_week] += result_dollars;
                    weekday_trades[entry_dt.day_of_week]++;
                    
                    // Update session statistics (count as win or loss based on overall trade)
                    int session = GetTradingSession(entry_dt.hour);
                    session_pnl[session] += result_dollars;
                    session_trades[session]++;
                    if(is_overall_win)
                        session_wins[session]++;
                    else
                        session_losses[session]++;
                    
                    active_trades[i].is_active = false;
                    break;
                }
                
                // Check if TP hit (BID low went below TP) - skip if TP is 0
                if(active_trades[i].tp_price > 0 && low[bar] <= active_trades[i].tp_price)
                {
                    // Final close at TP (using current position size, not original) - should always be profit
                    double pips_won = (active_trades[i].entry_price - active_trades[i].tp_price) / _Point;
                    double profit_dollars = pips_won * pip_value_per_lot * active_trades[i].current_position_size;
                    
                    // Weight pips by position size ratio to avoid double-counting with partial closes
                    double position_ratio = active_trades[i].current_position_size / active_trades[i].original_position_size;
                    double weighted_pips = pips_won * position_ratio;
                    
                    total_pips_won += weighted_pips;  // Use weighted pips
                    total_profit_dollars += profit_dollars;
                    current_equity += profit_dollars;
                    
                    // Add to cumulative P&L (profit is positive)
                    active_trades[i].cumulative_pnl_dollars += profit_dollars;
                    
                    // Update peak equity
                    if(current_equity > peak_equity)
                        peak_equity = current_equity;
                    
                    // Record equity snapshot
                    RecordEquitySnapshot(time[bar]);
                    
                    // Determine if OVERALL trade was win or loss based on cumulative P&L
                    bool is_overall_win = (active_trades[i].cumulative_pnl_dollars > 0);
                    
                    if(is_overall_win)
                    {
                        total_wins++;
                        // Update win streak
                        if(current_streak >= 0)
                            current_streak++;  // Continue or start win streak
                        else
                            current_streak = 1;  // Start new win streak
                        
                        if(current_streak > longest_win_streak)
                            longest_win_streak = current_streak;
                    }
                    else
                    {
                        total_losses++;
                        // Update loss streak
                        if(current_streak <= 0)
                            current_streak--;  // Continue or start loss streak
                        else
                            current_streak = -1;  // Start new loss streak
                        
                        if(MathAbs(current_streak) > longest_loss_streak)
                            longest_loss_streak = MathAbs(current_streak);
                    }
                    
                    // Update time-based statistics (use final close result)
                    MqlDateTime entry_dt;
                    TimeToStruct(active_trades[i].entry_time, entry_dt);
                    hourly_pnl[entry_dt.hour] += profit_dollars;
                    hourly_trades[entry_dt.hour]++;
                    weekday_pnl[entry_dt.day_of_week] += profit_dollars;
                    weekday_trades[entry_dt.day_of_week]++;
                    
                    // Update session statistics (count as win or loss based on overall trade)
                    int session = GetTradingSession(entry_dt.hour);
                    session_pnl[session] += profit_dollars;
                    session_trades[session]++;
                    if(is_overall_win)
                        session_wins[session]++;
                    else
                        session_losses[session]++;
                    
                    active_trades[i].is_active = false;
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Print trade summary                                              |
//+------------------------------------------------------------------+
void PrintTradeSummary()
{
    // Don't print until we have at least one trade
    if(total_trades == 0)
        return;
    
    // Calculate statistics
    double win_rate = (total_trades > 0) ? (total_wins * 100.0 / total_trades) : 0.0;
    double avg_win_pips = (total_wins > 0) ? (total_pips_won / total_wins) : 0.0;
    double avg_loss_pips = (total_losses > 0) ? (total_pips_lost / total_losses) : 0.0;
    double net_pips = total_pips_won - total_pips_lost;
    double profit_factor = (total_pips_lost > 0) ? (total_pips_won / total_pips_lost) : 0.0;
    
    // Money management statistics
    double net_profit = total_profit_dollars - total_loss_dollars;
    double roi = (InitialDeposit > 0) ? ((net_profit / InitialDeposit) * 100.0) : 0.0;
    double drawdown = peak_equity - current_equity;
    double drawdown_percent = (peak_equity > 0) ? ((drawdown / peak_equity) * 100.0) : 0.0;
    double avg_win_dollars = (total_wins > 0) ? (total_profit_dollars / total_wins) : 0.0;
    double avg_loss_dollars = (total_losses > 0) ? (total_loss_dollars / total_losses) : 0.0;
    double profit_factor_dollars = (total_loss_dollars > 0) ? (total_profit_dollars / total_loss_dollars) : 0.0;
    
    int active_count = 0;
    for(int i = 0; i < ArraySize(active_trades); i++)
        if(active_trades[i].is_active)
            active_count++;
    
    // Print summary with session prefix on EVERY line to handle parallel execution
    Print(session_prefix, " ");
    Print(session_prefix, " ");
    Print(session_prefix, "========================================");
    Print(session_prefix, "INDICATOR CONFIGURATION");
    Print(session_prefix, "========================================");
    Print(session_prefix, "Symbol: ", _Symbol, " | Timeframe: ", EnumToString((ENUM_TIMEFRAMES)_Period));
    Print(session_prefix, "Lookback: ", LookbackWeeks, " weeks + ", LookbackDays, " days");
    Print(session_prefix, "Pattern: Min ", PatternBars, " bars | Arrow offset: ", ArrowOffsetPoints, " pts");
    Print(session_prefix, "AMA: Period=", AMA_Period, " | Fast=", AMA_FastEMA, " | Slow=", AMA_SlowEMA);
    Print(session_prefix, "Trend: Spread multiplier = ", DoubleToString(TrendSpreadMultiplier, 1));
    Print(session_prefix, "Filter Opposite Signals: ", FilterOppositeSignals ? "ENABLED" : "DISABLED");
    Print(session_prefix, "Money: Initial=$", DoubleToString(InitialDeposit, 2), " | Risk=", DoubleToString(RiskPercent, 1), "% | TP Multiplier=", DoubleToString(TPMultiplier, 1), " (RRR 1:", DoubleToString(TPMultiplier, 1), ")");
    Print(session_prefix, "Trading Hours: ", TradingStartHour, ":00 - ", TradingEndHour, ":00");
    
    // Build weekdays string
    string weekdays = "Trading Days: ";
    bool first = true;
    if(TradeOnMonday)   { if(!first) weekdays += ", "; weekdays += "Mon"; first = false; }
    if(TradeOnTuesday)  { if(!first) weekdays += ", "; weekdays += "Tue"; first = false; }
    if(TradeOnWednesday){ if(!first) weekdays += ", "; weekdays += "Wed"; first = false; }
    if(TradeOnThursday) { if(!first) weekdays += ", "; weekdays += "Thu"; first = false; }
    if(TradeOnFriday)   { if(!first) weekdays += ", "; weekdays += "Fri"; first = false; }
    if(first) weekdays += "NONE (No trading!)";
    Print(session_prefix, weekdays);
    // Strategy name
    string strategyName = "No Partial Close (Full TP/SL)";
    if(PartialStrategy == STRATEGY_2_STEPS)
        strategyName = "2-Step: 50% at 50% TP + BE";
    else if(PartialStrategy == STRATEGY_STEP_LADDER)
        strategyName = "Step Ladder: At 90% progress, move SL & TP by step distance";
    else if(PartialStrategy == STRATEGY_3_STEPS)
        strategyName = "3-Step Progressive";
    
    Print(session_prefix, "========================================");
    Print(session_prefix, "TRADE SUMMARY (RRR 1:", DoubleToString(TPMultiplier, 1), ") - Risk ", DoubleToString(RiskPercent, 1), "% per trade");
    Print(session_prefix, "Strategy: ", strategyName);
    Print(session_prefix, "========================================");
    Print(session_prefix, "ACCOUNT:");
    Print(session_prefix, "  Initial Deposit: $", DoubleToString(InitialDeposit, 2));
    Print(session_prefix, "  Current Equity: $", DoubleToString(current_equity, 2));
    Print(session_prefix, "  Net Profit: $", DoubleToString(net_profit, 2), " (", DoubleToString(roi, 2), "%)");
    Print(session_prefix, "  Peak Equity: $", DoubleToString(peak_equity, 2));
    Print(session_prefix, "  Current Drawdown: $", DoubleToString(drawdown, 2), " (", DoubleToString(drawdown_percent, 2), "%)");
    Print(session_prefix, "----------------------------------------");
    Print(session_prefix, "TRADES:");
    Print(session_prefix, "  Total: ", total_trades, " (Active: ", active_count, ")");
    Print(session_prefix, "  Wins: ", total_wins, " | Losses: ", total_losses);
    Print(session_prefix, "  Win Rate: ", DoubleToString(win_rate, 2), "%");
    Print(session_prefix, "  Longest Win Streak: ", longest_win_streak, " | Longest Loss Streak: ", longest_loss_streak);
    Print(session_prefix, "----------------------------------------");
    Print(session_prefix, "PERFORMANCE ($):");
    Print(session_prefix, "  Total Profit: $", DoubleToString(total_profit_dollars, 2));
    Print(session_prefix, "  Total Loss: $", DoubleToString(total_loss_dollars, 2));
    Print(session_prefix, "  Avg Win: $", DoubleToString(avg_win_dollars, 2), " | Avg Loss: $", DoubleToString(avg_loss_dollars, 2));
    Print(session_prefix, "  Profit Factor: ", DoubleToString(profit_factor_dollars, 2));
    Print(session_prefix, "----------------------------------------");
    
    // Find best/worst trading hours
    int best_hour = -1, worst_hour = -1;
    double best_hour_pnl = -999999.0, worst_hour_pnl = 999999.0;
    for(int h = 0; h < 24; h++)
    {
        if(hourly_trades[h] > 0)
        {
            if(hourly_pnl[h] > best_hour_pnl)
            {
                best_hour_pnl = hourly_pnl[h];
                best_hour = h;
            }
            if(hourly_pnl[h] < worst_hour_pnl)
            {
                worst_hour_pnl = hourly_pnl[h];
                worst_hour = h;
            }
        }
    }
    
    // Find best/worst trading weekdays
    int best_day = -1, worst_day = -1;
    double best_day_pnl = -999999.0, worst_day_pnl = 999999.0;
    string day_names[7] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
    for(int d = 0; d < 7; d++)
    {
        if(weekday_trades[d] > 0)
        {
            if(weekday_pnl[d] > best_day_pnl)
            {
                best_day_pnl = weekday_pnl[d];
                best_day = d;
            }
            if(weekday_pnl[d] < worst_day_pnl)
            {
                worst_day_pnl = weekday_pnl[d];
                worst_day = d;
            }
        }
    }
    
    Print(session_prefix, "TIME-BASED PERFORMANCE:");
    if(best_hour >= 0)
        Print(session_prefix, "  Best Hour: ", best_hour, ":00 ($", DoubleToString(best_hour_pnl, 2), " from ", hourly_trades[best_hour], " trades)");
    if(worst_hour >= 0)
        Print(session_prefix, "  Worst Hour: ", worst_hour, ":00 ($", DoubleToString(worst_hour_pnl, 2), " from ", hourly_trades[worst_hour], " trades)");
    if(best_day >= 0)
        Print(session_prefix, "  Best Day: ", day_names[best_day], " ($", DoubleToString(best_day_pnl, 2), " from ", weekday_trades[best_day], " trades)");
    if(worst_day >= 0)
        Print(session_prefix, "  Worst Day: ", day_names[worst_day], " ($", DoubleToString(worst_day_pnl, 2), " from ", weekday_trades[worst_day], " trades)");
    Print(session_prefix, "----------------------------------------");
    
    // Display session performance rankings
    string session_names[4] = {"Sydney", "Tokyo", "London", "New York"};
    
    // Create array of session indices sorted by P&L
    int session_indices[4] = {0, 1, 2, 3};
    
    // Simple bubble sort by P&L (descending)
    for(int i = 0; i < 3; i++)
    {
        for(int j = i + 1; j < 4; j++)
        {
            if(session_pnl[session_indices[j]] > session_pnl[session_indices[i]])
            {
                int temp = session_indices[i];
                session_indices[i] = session_indices[j];
                session_indices[j] = temp;
            }
        }
    }
    
    Print(session_prefix, "SESSION PERFORMANCE (UTC+2):");
    for(int i = 0; i < 4; i++)
    {
        int idx = session_indices[i];
        if(session_trades[idx] > 0)
        {
            double session_win_rate = (session_wins[idx] * 100.0) / session_trades[idx];
            string rank = (i == 0) ? "🥇" : (i == 1) ? "🥈" : (i == 2) ? "🥉" : "  ";
            Print(session_prefix, "  ", (i+1), ". ", session_names[idx], ": $", DoubleToString(session_pnl[idx], 2), 
                  " | ", session_trades[idx], " trades (", session_wins[idx], "W-", session_losses[idx], "L) | ",
                  DoubleToString(session_win_rate, 1), "% WR");

        }
    }
    Print(session_prefix, "========================================");
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set up indicator buffer
    SetIndexBuffer(0, AMA_Buffer, INDICATOR_DATA);
    ArraySetAsSeries(AMA_Buffer, true);
    
    // Set plot properties from inputs
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, AMA_Color);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, AMA_Width);
    
    // Create AMA indicator handle
    AMA_Handle = iAMA(_Symbol, _Period, AMA_Period, AMA_FastEMA, AMA_SlowEMA, 0, PRICE_CLOSE);
    if(AMA_Handle == INVALID_HANDLE)
        return(INIT_FAILED);
    
    // Initialize timeframe tracking
    current_timeframe = (ENUM_TIMEFRAMES)_Period;
    first_computation_done = false;
    
    // Generate unique session ID for log parsing (timestamp + symbol + timeframe)
    // This helps parser extract correct blocks when multiple tests run in parallel
    session_id = StringFormat("%s_%s_%d", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period), (int)TimeCurrent());
    session_prefix = StringFormat("[SESSION:%s] ", session_id);
    
    IndicatorSetString(INDICATOR_SHORTNAME, 
        StringFormat("Sim Trades (Lookback:%dW+%dD, MinBars:%d, AMA:%d)", 
        LookbackWeeks, LookbackDays, PatternBars, AMA_Period));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release AMA indicator handle
    if(AMA_Handle != INVALID_HANDLE)
        IndicatorRelease(AMA_Handle);
    
    // Clean up all indicator objects
    ObjectsDeleteAll(0, indicator_prefix);
}

//+------------------------------------------------------------------+
//| Check if a bar is the highest in a pattern (middle position)     |
//| Allows for two consecutive bars with same top value in middle    |
//+------------------------------------------------------------------+
bool IsMiddleHighPattern(const double &open[], const double &close[], int center_bar, int pattern_size, int rates_total, int &second_high_bar)
{
    // Calculate how many bars on each side
    int side_bars = (pattern_size - 1) / 2;
    
    // Check if we have enough bars on both sides
    if(center_bar - side_bars < 0 || center_bar + side_bars >= rates_total)
        return false;
    
    double center_body_top = GetBodyTop(open, close, center_bar);
    second_high_bar = -1;  // Initialize
    
    // Small epsilon for floating point comparison
    double epsilon = _Point * 0.1;
    
    // Check all bars in the pattern
    for(int i = center_bar - side_bars; i <= center_bar + side_bars; i++)
    {
        if(i == center_bar)
            continue;  // Skip center bar itself
        
        double bar_body_top = GetBodyTop(open, close, i);
        double diff = bar_body_top - center_body_top;
        
        // If any bar's body top is higher than center, not a valid pattern
        if(diff > epsilon)
            return false;
        
        // If bar has same body top as center (within epsilon tolerance)
        if(MathAbs(diff) <= epsilon)
        {
            // Allow only one adjacent bar with same top value
            if(i == center_bar - 1 || i == center_bar + 1)
            {
                if(second_high_bar == -1)
                    second_high_bar = i;  // Found the second high bar
                else
                    return false;  // More than 2 bars with same high - invalid
            }
            else
            {
                return false;  // Same height but not adjacent - invalid
            }
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if a bar is the lowest in a pattern (middle position)      |
//| Allows for two consecutive bars with same bottom value in middle |
//+------------------------------------------------------------------+
bool IsMiddleLowPattern(const double &open[], const double &close[], int center_bar, int pattern_size, int rates_total, int &second_low_bar)
{
    // Calculate how many bars on each side
    int side_bars = (pattern_size - 1) / 2;
    
    // Check if we have enough bars on both sides
    if(center_bar - side_bars < 0 || center_bar + side_bars >= rates_total)
        return false;
    
    double center_body_bottom = GetBodyBottom(open, close, center_bar);
    second_low_bar = -1;  // Initialize
    
    // Small epsilon for floating point comparison
    double epsilon = _Point * 0.1;
    
    // Check all bars in the pattern - center must have lowest body bottom
    for(int i = center_bar - side_bars; i <= center_bar + side_bars; i++)
    {
        if(i == center_bar)
            continue;  // Skip center bar itself
        
        double bar_body_bottom = GetBodyBottom(open, close, i);
        double diff = center_body_bottom - bar_body_bottom;  // Inverted: center should be lower
        
        // If any bar's body bottom is lower than center, not a valid pattern
        if(diff > epsilon)
            return false;
        
        // If bar has same body bottom as center (within epsilon tolerance)
        if(MathAbs(diff) <= epsilon)
        {
            // Allow only one adjacent bar with same bottom value
            if(i == center_bar - 1 || i == center_bar + 1)
            {
                if(second_low_bar == -1)
                    second_low_bar = i;  // Found the second low bar
                else
                    return false;  // More than 2 bars with same low - invalid
            }
            else
            {
                return false;  // Same height but not adjacent - invalid
            }
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if next bars have descending body tops with min distance   |
//+------------------------------------------------------------------+
bool HasDescendingTops(const double &open[], const double &close[], const int &spread[], 
                       int start_bar, int count, bool check_distance = false)
{
    // Make sure we have enough bars ahead
    if(start_bar < count)
        return false;
    
    // Check that each subsequent bar has lower body top than previous
    for(int i = 0; i < count; i++)
    {
        int current_bar = start_bar - i;      // Current bar
        int next_bar = start_bar - i - 1;     // Next bar (more recent)
        
        double current_top = GetBodyTop(open, close, current_bar);
        double next_top = GetBodyTop(open, close, next_bar);
        
        // Next bar's top should be lower than current bar's top
        if(next_top >= current_top)
            return false;  // Not descending
    }
    
    // Additional check: distance from start_bar to third bar (if requested)
    if(check_distance)
    {
        double start_top = GetBodyTop(open, close, start_bar);
        double third_bar_top = GetBodyTop(open, close, start_bar - 3);
        
        double distance = start_top - third_bar_top;  // Distance in price
        double min_distance = spread[start_bar] * _Point * 3;  // Minimum required distance
        
        if(distance <= min_distance)
            return false;  // Distance too small
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if next bars have ascending body bottoms with min distance |
//+------------------------------------------------------------------+
bool HasAscendingBottoms(const double &open[], const double &close[], const int &spread[], 
                         int start_bar, int count, bool check_distance = false)
{
    // Make sure we have enough bars ahead
    if(start_bar < count)
        return false;
    
    // Check that each subsequent bar has higher body bottom than previous
    for(int i = 0; i < count; i++)
    {
        int current_bar = start_bar - i;      // Current bar
        int next_bar = start_bar - i - 1;     // Next bar (more recent)
        
        double current_bottom = GetBodyBottom(open, close, current_bar);
        double next_bottom = GetBodyBottom(open, close, next_bar);
        
        // Next bar's bottom should be higher than current bar's bottom
        if(next_bottom <= current_bottom)
            return false;  // Not ascending
    }
    
    // Additional check: distance from start_bar to third bar (if requested)
    if(check_distance)
    {
        double start_bottom = GetBodyBottom(open, close, start_bar);
        double third_bar_bottom = GetBodyBottom(open, close, start_bar - 3);
        
        double distance = third_bar_bottom - start_bottom;  // Distance in price (inverted)
        double min_distance = spread[start_bar] * _Point * 3;  // Minimum required distance
        
        if(distance <= min_distance)
            return false;  // Distance too small
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // Check if we have enough bars
    if(rates_total < PatternBars)
        return(0);
    
    // Check if AMA indicator has calculated enough bars
    int ama_calculated = BarsCalculated(AMA_Handle);
    if(ama_calculated < rates_total)
        return(0);
    
    // Determine how many bars to copy
    int to_copy;
    if(prev_calculated > rates_total || prev_calculated <= 0)
        to_copy = rates_total;
    else
    {
        to_copy = rates_total - prev_calculated + 1;
    }
    
    // Copy AMA values to buffer
    if(CopyBuffer(AMA_Handle, 0, 0, to_copy, AMA_Buffer) <= 0)
        return(0);
    
    // Set arrays as series (index 0 is most recent)
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(spread, true);
    
    // Clear previous objects on first run
    if(prev_calculated == 0)
    {
        ObjectsDeleteAll(0, indicator_prefix);
        last_top_bar = -1;  // Reset tracking
        last_high_value = 0.0;  // Reset high/low tracking for flat trend filtering
        last_high_bar = -1;
        last_low_value = 0.0;
        last_low_bar = -1;
        trend_state = 0;     // Reset trend state
        validated_patterns_count = 0;    // Reset counters
        invalidated_patterns_count = 0;
        patterns_detected_count = 0;
        
        // Reset trade statistics
        ArrayResize(active_trades, 0);
        total_trades = 0;
        total_wins = 0;
        total_losses = 0;
        total_pips_won = 0.0;
        total_pips_lost = 0.0;
        prev_total_trades = 0;
        prev_total_wins = 0;
        prev_total_losses = 0;
        
        // Initialize money management
        current_equity = InitialDeposit;
        peak_equity = InitialDeposit;
        total_profit_dollars = 0.0;
        total_loss_dollars = 0.0;
        
        // Initialize equity history
        ArrayResize(equity_history, 0);
        
        // Clear old global variables for this symbol/timeframe to avoid stale data
        string var_prefix = StringFormat("simTrades_%s_%s_", _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
        int total_vars = GlobalVariablesTotal();
        for(int v = total_vars - 1; v >= 0; v--)
        {
            string var_name = GlobalVariableName(v);
            if(StringFind(var_name, var_prefix) == 0)  // Starts with our prefix
            {
                GlobalVariableDel(var_name);
            }
        }
        
        // Initialize streak tracking
        current_streak = 0;
        longest_win_streak = 0;
        longest_loss_streak = 0;
        
        // Initialize time-based tracking
        ArrayInitialize(hourly_pnl, 0.0);
        ArrayInitialize(hourly_trades, 0);
        ArrayInitialize(weekday_pnl, 0.0);
        ArrayInitialize(weekday_trades, 0);
        
        // Initialize session tracking
        ArrayInitialize(session_pnl, 0.0);
        ArrayInitialize(session_trades, 0);
        ArrayInitialize(session_wins, 0);
        ArrayInitialize(session_losses, 0);
        
        // Reset computation flag
        first_computation_done = false;
    }
    
    // Detect timeframe change
    ENUM_TIMEFRAMES detected_timeframe = (ENUM_TIMEFRAMES)_Period;
    bool timeframe_changed = (detected_timeframe != current_timeframe);
    
    if(timeframe_changed)
    {
        Print("Timeframe changed from ", EnumToString(current_timeframe), " to ", EnumToString(detected_timeframe));
        current_timeframe = detected_timeframe;
        first_computation_done = false;  // Reset on timeframe change
    }
    
    // Update trend state based on AMA BEFORE pattern scanning
    UpdateTrendState(spread);
    
    // Calculate side bars needed for pattern
    int side_bars = (PatternBars - 1) / 2;
    
    // Calculate time-based lookback
    int total_lookback_seconds = (LookbackWeeks * 7 + LookbackDays) * 24 * 60 * 60;
    datetime lookback_time = TimeCurrent() - total_lookback_seconds;
    
    // Find the bar index corresponding to lookback time
    int lookback_bar_index = iBarShift(_Symbol, _Period, lookback_time);
    if(lookback_bar_index < 0)
        lookback_bar_index = rates_total - 1;  // Use all available bars if time not found
    
    // Determine range to scan
    int start_idx = MathMin(lookback_bar_index, rates_total - side_bars - 1);
    int end_idx = side_bars;
    
    // If this is not the first run, only check recent bars
    if(prev_calculated > 0)
    {
        int new_bars = rates_total - prev_calculated;
        if(new_bars <= 0)
            return(rates_total);  // No new bars
        
        // Check new bars plus a small buffer
        start_idx = new_bars + side_bars + 5;
        if(start_idx > lookback_bar_index)
            start_idx = lookback_bar_index;
    }
    
    // Scan for middle high patterns
    for(int i = start_idx; i >= end_idx; i--)
    {
        // Skip if we're too close to the edges
        if(i < side_bars || i >= rates_total - side_bars)
            continue;
        
        // Skip if this bar was already detected as top_bar
        if(i == last_top_bar)
            continue;
        
        // Check if this bar forms a middle high pattern
        int second_high_bar = -1;
        if(IsMiddleHighPattern(open, close, i, PatternBars, rates_total, second_high_bar))
        {
            // Pattern detected - increment detection counter
            patterns_detected_count++;
            
            // Get trend at this specific bar
            int bar_trend = GetTrendAtBar(i, spread);
            
            // Optional: Filter SELL signals in UPTREND
            if(FilterOppositeSignals && bar_trend == 1)  // SELL signal in UPTREND
            {
                invalidated_patterns_count++;
                continue;  // Skip this pattern
            }
            
            // DOWNTREND VALIDATION: Check for 3 descending tops after the pattern
            // Also apply in FLAT trend to avoid marking small swings
            if(bar_trend == -1 || bar_trend == 0)  // Downtrend or Flat
            {
                // First check: Do we have descending tops?
                bool has_descending = HasDescendingTops(open, close, spread, i, 3, false);
                
                // Second check: Is distance sufficient?
                double start_top = GetBodyTop(open, close, i);
                double third_top = (i >= 3) ? GetBodyTop(open, close, i - 3) : 0;
                double distance = start_top - third_top;
                double min_distance = spread[i] * _Point * 3;
                bool distance_ok = (distance > min_distance);
                
                // Both conditions must be met
                if(!has_descending || !distance_ok)
                {
                    // Pattern invalid in downtrend/flat
                    invalidated_patterns_count++;
                    continue;  // Skip this pattern
                }
            }
            
            // Check if trading is allowed at this time
            if(!IsTradingTimeAllowed(time[i]))
            {
                invalidated_patterns_count++;
                continue;  // Skip this pattern - outside trading hours
            }
            
            // Find the bar with the HIGHEST HIGH across all pattern bars
            int half_size = PatternBars / 2;
            int pattern_start = i + half_size;
            int pattern_end = i - half_size;
            
            int arrow_bar = i;  // Default to center bar
            double max_high = high[i];
            
            // Loop through all bars in the pattern to find the highest high
            for(int j = pattern_start; j >= pattern_end && j >= 0; j--)
            {
                if(high[j] > max_high)
                {
                    max_high = high[j];
                    arrow_bar = j;
                }
            }
            
            // FLAT TREND FILTER: Avoid tight range entries
            // Skip SELL signals in flat markets where SL distance < 0.5 × distance to last low
            if(bar_trend == 0 && last_low_bar >= 0 && last_low_value > 0)
            {
                int entry_bar = i - 2;
                if(entry_bar >= 0)
                {
                    double sl_distance = max_high - close[entry_bar];
                    double distance_to_low = close[entry_bar] - last_low_value;
                    
                    if(distance_to_low > 0 && sl_distance < 0.5 * distance_to_low)
                    {
                        invalidated_patterns_count++;
                        continue;  // Skip this pattern
                    }
                }
            }
            
            // Calculate arrow position: bar high plus offset
            double arrow_price = high[arrow_bar] + (ArrowOffsetPoints * _Point);
            
            // Create unique arrow name based on bar time
            string arrow_name = indicator_prefix + "H_" + TimeToString(time[arrow_bar], TIME_DATE|TIME_MINUTES);
            
            // Check if arrow already exists
            if(ObjectFind(0, arrow_name) < 0)
            {
                // Create new down arrow above bar high (Sell entry)
                if(ObjectCreate(0, arrow_name, OBJ_ARROW, 0, time[arrow_bar], arrow_price))
                {
                    ObjectSetInteger(0, arrow_name, OBJPROP_ARROWCODE, 234);  // Down arrow
                    ObjectSetInteger(0, arrow_name, OBJPROP_COLOR, HighArrowColor);
                    ObjectSetInteger(0, arrow_name, OBJPROP_WIDTH, ArrowWidth);
                    ObjectSetInteger(0, arrow_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
                    
                    // Create SELL text label at the entry bar (where validation completes)
                    // Entry is confirmed at bar i-2 (third bar of validation sequence)
                    int entry_bar = i - 2;
                    if(entry_bar >= 0)
                    {
                        // Calculate SL: distance from arrow bar's high to entry bar's close
                        // SELL: Entry at BID (close)
                        double entry_price = close[entry_bar];  // BID
                        double sl_price = high[arrow_bar];      // Pattern extreme
                        double sl_distance_price = sl_price - entry_price;
                        int sl_points = (int)MathRound(sl_distance_price / _Point);
                        
                        // Calculate TP using configurable multiplier
                        double tp_price = entry_price - (TPMultiplier * sl_distance_price);
                        
                        // Format label as "SELL | SL_POINTS"
                        string label_text = "SELL | " + IntegerToString(sl_points);
                        
                        string sell_label = indicator_prefix + "sell_" + TimeToString(time[entry_bar], TIME_DATE|TIME_MINUTES);
                        if(ObjectFind(0, sell_label) < 0)
                        {
                            if(ObjectCreate(0, sell_label, OBJ_TEXT, 0, time[entry_bar], high[entry_bar]))
                            {
                                ObjectSetString(0, sell_label, OBJPROP_TEXT, label_text);
                                ObjectSetInteger(0, sell_label, OBJPROP_COLOR, clrBlack);
                                ObjectSetInteger(0, sell_label, OBJPROP_FONTSIZE, 10);
                                ObjectSetInteger(0, sell_label, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
                                
                                // Add trade to tracking
                                AddTrade(time[entry_bar], entry_price, sl_price, tp_price, -1);
                            }
                        }
                    }
                    
                    // Update last_top_bar to this bar
                    last_top_bar = arrow_bar;
                    
                    // Track this high for future flat trend filtering
                    last_high_value = max_high;
                    last_high_bar = arrow_bar;
                    
                    // Increment validated patterns counter
                    validated_patterns_count++;
                }
            }
        }
        
        // ========== INVERTED PATTERN: MIDDLE LOW ==========
        // Check if this bar forms a middle low pattern
        int second_low_bar = -1;
        if(IsMiddleLowPattern(open, close, i, PatternBars, rates_total, second_low_bar))
        {
            // Pattern detected - increment detection counter
            patterns_detected_count++;
            
            // Get trend at this specific bar
            int bar_trend = GetTrendAtBar(i, spread);
            
            // Optional: Filter BUY signals in DOWNTREND
            if(FilterOppositeSignals && bar_trend == -1)  // BUY signal in DOWNTREND
            {
                invalidated_patterns_count++;
                continue;  // Skip this pattern
            }
            
            // UPTREND VALIDATION: Check for 3 ascending bottoms after the pattern
            // Also apply in FLAT trend to avoid marking small swings
            if(bar_trend == 1 || bar_trend == 0)  // Uptrend or Flat
            {
                // First check: Do we have ascending bottoms?
                bool has_ascending = HasAscendingBottoms(open, close, spread, i, 3, false);
                
                // Second check: Is distance sufficient?
                double start_bottom = GetBodyBottom(open, close, i);
                double third_bottom = (i >= 3) ? GetBodyBottom(open, close, i - 3) : 0;
                double distance = third_bottom - start_bottom;  // Inverted: third should be higher
                double min_distance = spread[i] * _Point * 3;
                bool distance_ok = (distance > min_distance);
                
                // Both conditions must be met
                if(!has_ascending || !distance_ok)
                {
                    // Pattern invalid in uptrend/flat
                    invalidated_patterns_count++;
                    continue;  // Skip this pattern
                }
            }
            
            // Check if trading is allowed at this time
            if(!IsTradingTimeAllowed(time[i]))
            {
                invalidated_patterns_count++;
                continue;  // Skip this pattern - outside trading hours
            }
            
            // Find the bar with the LOWEST LOW across all pattern bars
            int half_size = PatternBars / 2;
            int pattern_start = i + half_size;
            int pattern_end = i - half_size;
            
            int arrow_bar = i;  // Default to center bar
            double min_low = low[i];
            
            // Loop through all bars in the pattern to find the lowest low
            for(int j = pattern_start; j >= pattern_end && j >= 0; j--)
            {
                if(low[j] < min_low)
                {
                    min_low = low[j];
                    arrow_bar = j;
                }
            }
            
            // FLAT TREND FILTER: Avoid tight range entries
            // Skip BUY signals in flat markets where SL distance < 0.5 × distance to last high
            if(bar_trend == 0 && last_high_bar >= 0 && last_high_value > 0)
            {
                int entry_bar = i - 2;
                if(entry_bar >= 0)
                {
                    double sl_distance = close[entry_bar] - min_low;
                    double distance_to_high = last_high_value - close[entry_bar];
                    
                    if(distance_to_high > 0 && sl_distance < 0.5 * distance_to_high)
                    {
                        invalidated_patterns_count++;
                        continue;  // Skip this pattern
                    }
                }
            }
            
            // Calculate arrow position: bar low minus offset
            double arrow_price = low[arrow_bar] - (ArrowOffsetPoints * _Point);
            
            // Create unique arrow name based on bar time
            string arrow_name = indicator_prefix + "L_" + TimeToString(time[arrow_bar], TIME_DATE|TIME_MINUTES);
            
            // Check if arrow already exists
            if(ObjectFind(0, arrow_name) < 0)
            {
                // Create new up arrow below bar low (Buy entry)
                if(ObjectCreate(0, arrow_name, OBJ_ARROW, 0, time[arrow_bar], arrow_price))
                {
                    ObjectSetInteger(0, arrow_name, OBJPROP_ARROWCODE, 233);  // Up arrow
                    ObjectSetInteger(0, arrow_name, OBJPROP_COLOR, LowArrowColor);
                    ObjectSetInteger(0, arrow_name, OBJPROP_WIDTH, ArrowWidth);
                    ObjectSetInteger(0, arrow_name, OBJPROP_ANCHOR, ANCHOR_TOP);
                    
                    // Create BUY text label at the entry bar (where validation completes)
                    // Entry is confirmed at bar i-2 (third bar of validation sequence)
                    int entry_bar = i - 2;
                    if(entry_bar >= 0)
                    {
                        // Calculate SL: distance from entry bar's close to arrow bar's low
                        // BUY: Entry at ASK (close + spread)
                        double entry_price = close[entry_bar] + (spread[entry_bar] * _Point);  // ASK
                        double sl_price = low[arrow_bar];       // Pattern extreme
                        double sl_distance_price = entry_price - sl_price;
                        int sl_points = (int)MathRound(sl_distance_price / _Point);
                        
                        // Calculate TP using configurable multiplier
                        double tp_price = entry_price + (TPMultiplier * sl_distance_price);
                        
                        // Format label as "BUY | SL_POINTS"
                        string label_text = "BUY | " + IntegerToString(sl_points);
                        
                        string buy_label = indicator_prefix + "buy_" + TimeToString(time[entry_bar], TIME_DATE|TIME_MINUTES);
                        if(ObjectFind(0, buy_label) < 0)
                        {
                            if(ObjectCreate(0, buy_label, OBJ_TEXT, 0, time[entry_bar], low[entry_bar]))
                            {
                                ObjectSetString(0, buy_label, OBJPROP_TEXT, label_text);
                                ObjectSetInteger(0, buy_label, OBJPROP_COLOR, clrBlack);
                                ObjectSetInteger(0, buy_label, OBJPROP_FONTSIZE, 10);
                                ObjectSetInteger(0, buy_label, OBJPROP_ANCHOR, ANCHOR_TOP);
                                
                                // Add trade to tracking
                                AddTrade(time[entry_bar], entry_price, sl_price, tp_price, 1);
                            }
                        }
                    }
                    
                    // Track this low for future flat trend filtering
                    last_low_value = min_low;
                    last_low_bar = arrow_bar;
                    
                    // Increment validated patterns counter
                    validated_patterns_count++;
                }
            }
        }
    }
    
    // Check active trades for TP/SL hits
    CheckActiveTrades(time, high, low, close, spread);
    
    // Print summary after first full computation or on timeframe change
    if(!first_computation_done && prev_calculated == 0)
    {
        // First computation just completed
        first_computation_done = true;
        Print(" ");
        Print("========== FIRST COMPUTATION COMPLETE ==========");
        PrintTradeSummary();
    }
    else if(timeframe_changed)
    {
        // Timeframe changed and recalculation complete
        first_computation_done = true;
        PrintTradeSummary();
    }
    
    // Display trend state and pattern statistics on chart
    DisplayTrendState();
    DisplayPatternStats();
    
    ChartRedraw(0);
    return(rates_total);
}
//+------------------------------------------------------------------+

