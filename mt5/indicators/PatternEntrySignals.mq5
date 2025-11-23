//+------------------------------------------------------------------+
//|                                      Middle High Pattern Indicator |
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
#property indicator_width1  1

// Input parameters
input int BarsLookback = 200;          // Bars lookback from current bar
int PatternBars = 5;
color HighArrowColor = clrRed;   // High pattern arrow color (Red Down = Sell entry)
color LowArrowColor = clrLime;   // Low pattern arrow color (Green Up = Buy entry)
int ArrowWidth = 1;              // Arrow width
int ArrowOffsetPoints = 15;      // Arrow offset from high/low in points

// AMA (Adaptive Moving Average) parameters
int AMA_Period = 10;             // AMA Period
int AMA_FastEMA = 10;            // Fast EMA Period
int AMA_SlowEMA = 200;           // Slow EMA Period
color AMA_Color = clrBlue;       // AMA Line Color
int AMA_Width = 1;               // AMA Line Width
input double TrendSpreadMultiplier = 1.5;  // Spread multiplier for trend threshold

// Signal filtering
input bool FilterOppositeSignals = true;  // Filter opposite trend signals (SELL in uptrend, BUY in downtrend)

// Debug settings
input bool DebugMode = false;          // Enable debug logs

// Trading hours
input int TradingStartHour = 3;         // Trading start hour (0-23)
input int TradingEndHour = 22;          // Trading end hour (0-23)
input bool TradeOnMonday = true;        // Trade on Monday
input bool TradeOnTuesday = true;       // Trade on Tuesday
input bool TradeOnWednesday = true;     // Trade on Wednesday
input bool TradeOnThursday = true;      // Trade on Thursday
input bool TradeOnFriday = true;        // Trade on Friday

// Indicator prefix for object names
string indicator_prefix = "PatternEntrySignals_";

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
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    if(DebugMode)
    {
        Print("PatternEntrySignals | ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period), 
              " | FilterOpposite: ", FilterOppositeSignals ? "ON" : "OFF",
              " | Hours: ", TradingStartHour, ":00-", TradingEndHour, ":00");
    }
    
    // Set up indicator buffer
    SetIndexBuffer(0, AMA_Buffer, INDICATOR_DATA);
    ArraySetAsSeries(AMA_Buffer, true);
    
    // Set plot properties from inputs
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, AMA_Color);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, AMA_Width);
    
    // Create AMA indicator handle
    AMA_Handle = iAMA(_Symbol, _Period, AMA_Period, AMA_FastEMA, AMA_SlowEMA, 0, PRICE_CLOSE);
    if(AMA_Handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create AMA handle");
        return(INIT_FAILED);
    }
    
    IndicatorSetString(INDICATOR_SHORTNAME, 
        StringFormat("Middle High Pattern (Lookback:%d, AMA:%d)", 
        BarsLookback, AMA_Period));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get Uninit Reason Text                                           |
//+------------------------------------------------------------------+
string getUninitReasonText(int reasonCode)
{
    string text = "";
    switch(reasonCode)
    {
        case REASON_PROGRAM:     text = "Program closed"; break;
        case REASON_REMOVE:      text = "Removed from chart"; break;
        case REASON_RECOMPILE:   text = "Recompiled"; break;
        case REASON_CHARTCHANGE: text = "Chart symbol/period changed"; break;
        case REASON_CHARTCLOSE:  text = "Chart closed"; break;
        case REASON_PARAMETERS:  text = "Input parameters changed"; break;
        case REASON_ACCOUNT:     text = "Account changed"; break;
        case REASON_TEMPLATE:    text = "Template applied"; break;
        case REASON_INITFAILED:  text = "Initialization failed"; break;
        case REASON_CLOSE:       text = "Terminal closed"; break;
        default:                 text = "Unknown reason"; break;
    }
    return text;
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
bool IsPatternEntrySignals(const double &open[], const double &close[], int center_bar, int pattern_size, int rates_total, int &second_high_bar)
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
    }
    
    // Update trend state based on AMA BEFORE pattern scanning
    UpdateTrendState(spread);
    
    // Calculate side bars needed for pattern
    int side_bars = (PatternBars - 1) / 2;
    
    // Determine range to scan
    int start_idx = MathMin(BarsLookback, rates_total - side_bars - 1);
    int end_idx = side_bars;
    
    // If this is not the first run, only check recent bars
    if(prev_calculated > 0)
    {
        int new_bars = rates_total - prev_calculated;
        if(new_bars <= 0)
            return(rates_total);  // No new bars
        
        // Check new bars plus a small buffer
        start_idx = new_bars + side_bars + 5;
        if(start_idx > BarsLookback)
            start_idx = BarsLookback;
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
        
        // Check if trading is allowed at this time
        if(!IsTradingTimeAllowed(time[i]))
        {
            invalidated_patterns_count++;
            continue;  // Skip this pattern - outside trading hours
        }
        
        // Check if this bar forms a middle high pattern
        int second_high_bar = -1;
        if(IsPatternEntrySignals(open, close, i, PatternBars, rates_total, second_high_bar))
        {
            // Pattern detected - increment detection counter
            patterns_detected_count++;
            
            // Get body top for this bar
            double body_top = GetBodyTop(open, close, i);
            
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
                        double sl_distance_price = high[arrow_bar] - close[entry_bar];
                        int sl_points = (int)MathRound(sl_distance_price / _Point);
                        
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
                    
                    if(DebugMode)
                    {
                        string trend_text = bar_trend == 1 ? "UP" : bar_trend == -1 ? "DN" : "FL";
                        Print("SELL | Bar ", arrow_bar, " | ", trend_text, " | Valid: ", validated_patterns_count);
                    }
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
            
            // Get body bottom for this bar
            double body_bottom = GetBodyBottom(open, close, i);
            
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
                        double sl_distance_price = close[entry_bar] - low[arrow_bar];
                        int sl_points = (int)MathRound(sl_distance_price / _Point);
                        
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
                            }
                        }
                    }
                    
                    // Increment validated patterns counter
                    validated_patterns_count++;
                    
                    // Track this low for future flat trend filtering
                    last_low_value = min_low;
                    last_low_bar = arrow_bar;
                    
                    if(DebugMode)
                    {
                        string trend_text = bar_trend == 1 ? "UP" : bar_trend == -1 ? "DN" : "FL";
                        Print("BUY  | Bar ", arrow_bar, " | ", trend_text, " | Valid: ", validated_patterns_count);
                    }
                }
            }
        }
    }
    
    // Display trend state and pattern statistics on chart
    DisplayTrendState();
    DisplayPatternStats();
    
    ChartRedraw(0);
    return(rates_total);
}
//+------------------------------------------------------------------+

