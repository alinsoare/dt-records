//+------------------------------------------------------------------+
//|                                            SimTradesEquity.mq5 |
//|                      Displays equity curve from simTrades.mq5   |
//+------------------------------------------------------------------+
#property copyright "DT Records"
#property link      ""
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2

//--- plot Equity
#property indicator_label1  "Equity"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- plot Peak Equity
#property indicator_label2  "Peak"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLimeGreen
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Input parameters
input double InitialEquity = 10000.0;  // Initial Equity ($)
input double ScalePadding = 10.0;      // Scale padding (%)
input bool ShowStats = false;           // Show statistics on chart

//--- Indicator buffers
double Equity_Buffer[];
double PeakEquity_Buffer[];

//--- Cached equity data (persists between OnCalculate calls)
struct EquitySnapshot
{
    datetime bar_time;
    double equity;
    double peak;
};
EquitySnapshot equity_cache[];
bool cache_loaded = false;

//+------------------------------------------------------------------+
//| Load equity snapshots from global variables into cache          |
//+------------------------------------------------------------------+
void LoadEquityCache()
{
    ArrayResize(equity_cache, 0);
    
    // Scan all global variables for our symbol/timeframe
    string var_prefix = StringFormat("simTrades_%s_%s_equity_", 
                                     _Symbol, 
                                     EnumToString((ENUM_TIMEFRAMES)_Period));
    
    int total_vars = GlobalVariablesTotal();
    for(int v = 0; v < total_vars; v++)
    {
        string var_name = GlobalVariableName(v);
        
        // Check if this is an equity variable for our symbol/timeframe
        if(StringFind(var_name, var_prefix) == 0)
        {
            // Extract the timestamp from variable name
            int time_start = StringLen(var_prefix);
            string time_str = StringSubstr(var_name, time_start);
            datetime bar_time = StringToTime(time_str);
            
            // Read equity and peak values
            double eq_value = GlobalVariableGet(var_name);
            
            string peak_var_name = StringFormat("simTrades_%s_%s_peak_%s", 
                                               _Symbol, 
                                               EnumToString((ENUM_TIMEFRAMES)_Period),
                                               time_str);
            double peak_value = InitialEquity;
            if(GlobalVariableCheck(peak_var_name))
                peak_value = GlobalVariableGet(peak_var_name);
            
            // Add to cache
            int size = ArraySize(equity_cache);
            ArrayResize(equity_cache, size + 1);
            equity_cache[size].bar_time = bar_time;
            equity_cache[size].equity = eq_value;
            equity_cache[size].peak = peak_value;
        }
    }
    
    cache_loaded = true;
    
    // Calculate min/max equity values for fixed scaling
    if(ArraySize(equity_cache) > 0)
    {
        double min_equity = InitialEquity;
        double max_equity = InitialEquity;
        
        for(int i = 0; i < ArraySize(equity_cache); i++)
        {
            if(equity_cache[i].equity < min_equity)
                min_equity = equity_cache[i].equity;
            if(equity_cache[i].equity > max_equity)
                max_equity = equity_cache[i].equity;
            if(equity_cache[i].peak > max_equity)
                max_equity = equity_cache[i].peak;
        }
        
        // Add padding to min/max
        double range = max_equity - min_equity;
        if(range < 100.0)  // Minimum range for better visualization
            range = 100.0;
        
        double padding = range * (ScalePadding / 100.0);
        double scale_min = min_equity - padding;
        double scale_max = max_equity + padding;
        
        // Ensure minimum is not negative
        if(scale_min < 0)
            scale_min = 0;
        
        // Set indicator scale
        IndicatorSetDouble(INDICATOR_MINIMUM, scale_min);
        IndicatorSetDouble(INDICATOR_MAXIMUM, scale_max);
    }
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Set buffers
    SetIndexBuffer(0, Equity_Buffer, INDICATOR_DATA);
    SetIndexBuffer(1, PeakEquity_Buffer, INDICATOR_DATA);
    
    ArraySetAsSeries(Equity_Buffer, true);
    ArraySetAsSeries(PeakEquity_Buffer, true);
    
    //--- Set plot properties
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
    
    //--- Set indicator name
    IndicatorSetString(INDICATOR_SHORTNAME, "simTrades Equity Curve");
    
    //--- Set indicator digits
    IndicatorSetInteger(INDICATOR_DIGITS, 2);
    
    //--- Reset cache flag
    cache_loaded = false;
    
    return(INIT_SUCCEEDED);
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
    //--- Set arrays as series
    ArraySetAsSeries(time, true);
    
    // Load cache on first run or periodically to catch new data
    static datetime last_cache_update = 0;
    datetime current_time = TimeCurrent();
    
    // Refresh cache: immediately on first run, then every 5 seconds, or when new bars appear
    bool should_refresh = !cache_loaded || prev_calculated == 0 || 
                          current_time - last_cache_update > 5 ||
                          rates_total != prev_calculated;
    
    if(should_refresh)
    {
        LoadEquityCache();
        last_cache_update = current_time;
    }
    
    // Initialize or update buffers
    if(prev_calculated == 0)
    {
        // First calculation - initialize all bars
        for(int i = 0; i < rates_total; i++)
        {
            Equity_Buffer[i] = InitialEquity;
            PeakEquity_Buffer[i] = InitialEquity;
        }
    }
    
    // Fill buffers from cached data
    double last_equity = InitialEquity;
    double last_peak = InitialEquity;
    
    // Process from oldest to newest bar (forward fill)
    for(int i = rates_total - 1; i >= 0; i--)
    {
        // Look for this bar's time in the cache
        bool found = false;
        for(int c = 0; c < ArraySize(equity_cache); c++)
        {
            if(equity_cache[c].bar_time == time[i])
            {
                last_equity = equity_cache[c].equity;
                // Peak must be monotonically non-decreasing (always >= previous peak)
                last_peak = MathMax(last_peak, equity_cache[c].peak);
                found = true;
                break;
            }
        }
        
        // Ensure peak is always >= current equity (safety check)
        if(last_equity > last_peak)
            last_peak = last_equity;
        
        // Set buffer values (forward fill from last known equity)
        Equity_Buffer[i] = last_equity;
        PeakEquity_Buffer[i] = last_peak;
    }
    
    // Display current equity stats (use bar 0 values)
    double current_equity = Equity_Buffer[0];
    double current_peak = PeakEquity_Buffer[0];
    double total_pnl = current_equity - InitialEquity;
    double total_pnl_pct = (InitialEquity > 0) ? (total_pnl / InitialEquity * 100.0) : 0.0;
    double current_dd = current_peak - current_equity;
    double current_dd_pct = (current_peak > 0) ? (current_dd / current_peak * 100.0) : 0.0;
    
    // Calculate min/max from cache for display
    double min_equity = InitialEquity;
    double max_equity = InitialEquity;
    for(int i = 0; i < ArraySize(equity_cache); i++)
    {
        if(equity_cache[i].equity < min_equity)
            min_equity = equity_cache[i].equity;
        if(equity_cache[i].peak > max_equity)
            max_equity = equity_cache[i].peak;
    }
    double max_dd = max_equity - min_equity;
    double max_dd_pct = (max_equity > 0) ? (max_dd / max_equity * 100.0) : 0.0;
    
    // Display statistics if enabled
    if(ShowStats)
    {
        string stats = "═══ SIMTRADES EQUITY CURVE ═══\n";
        stats += StringFormat("Initial:  $%s\n", DoubleToString(InitialEquity, 2));
        stats += StringFormat("Current:  $%s\n", DoubleToString(current_equity, 2));
        stats += StringFormat("Peak:     $%s\n", DoubleToString(current_peak, 2));
        stats += StringFormat("Low:      $%s\n", DoubleToString(min_equity, 2));
        stats += "\n";
        stats += StringFormat("P&L:      $%s (%.2f%%)\n", 
                             DoubleToString(total_pnl, 2), total_pnl_pct);
        stats += StringFormat("Curr DD:  $%s (%.2f%%)\n", 
                             DoubleToString(current_dd, 2), current_dd_pct);
        stats += StringFormat("Max DD:   $%s (%.2f%%)\n", 
                             DoubleToString(max_dd, 2), max_dd_pct);
        stats += StringFormat("Snapshots: %d", ArraySize(equity_cache));
        
        Comment(stats);
    }
    
    //--- Return value of prev_calculated for next call
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Deinitialization function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Comment("");  // Clear comment
    cache_loaded = false;
    ArrayResize(equity_cache, 0);
}
//+------------------------------------------------------------------+

