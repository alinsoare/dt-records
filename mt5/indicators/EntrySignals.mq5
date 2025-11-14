//+------------------------------------------------------------------+
//|                                                 EntrySignals.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   0

// MA buffers used for calculations only (not plotted)
// EMA 20, EMA 100, SMA 200

// Input parameters
input int lookback_period = 10;           // Lookback Period
input int start_hour = 9;                 // Trading Start Hour
input int end_hour = 23;                  // Trading End Hour

// Constants
#define ARROW_OFFSET_POINTS 5

// Indicator buffers
double HighMA[];
double MediumMA[];
double LowMA[];

// Indicator handles
int handle_high_ma;
int handle_medium_ma;
int handle_low_ma;

// Global variables
string indicator_prefix = "EntrySignal_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set indicator buffers
    SetIndexBuffer(0, HighMA, INDICATOR_DATA);
    SetIndexBuffer(1, MediumMA, INDICATOR_DATA);
    SetIndexBuffer(2, LowMA, INDICATOR_DATA);
    
    // Create indicator handles
    handle_high_ma = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
    handle_medium_ma = iMA(_Symbol, _Period, 100, 0, MODE_EMA, PRICE_CLOSE);
    handle_low_ma = iMA(_Symbol, _Period, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    if(handle_high_ma == INVALID_HANDLE || handle_medium_ma == INVALID_HANDLE || 
       handle_low_ma == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles");
        return(INIT_FAILED);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(handle_high_ma != INVALID_HANDLE) IndicatorRelease(handle_high_ma);
    if(handle_medium_ma != INVALID_HANDLE) IndicatorRelease(handle_medium_ma);
    if(handle_low_ma != INVALID_HANDLE) IndicatorRelease(handle_low_ma);
    
    // Delete all arrow objects created by this indicator
    ObjectsDeleteAll(0, indicator_prefix, 0, OBJ_ARROW);
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
    if(rates_total < 200) return(0);  // Not enough data
    
    // Only process on new bar to improve performance
    static datetime last_time = 0;
    if(time[0] == last_time) return(rates_total);
    last_time = time[0];
    
    // Get MA data - only copy what we need
    int bars_needed = MathMin(2000, rates_total);
    if(CopyBuffer(handle_high_ma, 0, 0, bars_needed, HighMA) <= 0) return(0);
    if(CopyBuffer(handle_medium_ma, 0, 0, bars_needed, MediumMA) <= 0) return(0);
    if(CopyBuffer(handle_low_ma, 0, 0, bars_needed, LowMA) <= 0) return(0);
    
    // Set arrays as series - CRITICAL: arrays must be indexed from most recent
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(HighMA, true);
    ArraySetAsSeries(MediumMA, true);
    ArraySetAsSeries(LowMA, true);
    
    // Main calculation loop - only process last 2000 bars
    int limit = MathMin(2000, rates_total - 200);
    
    for(int idx = 0; idx < limit; idx++)
    {
        // Time filter
        MqlDateTime dt;
        TimeToStruct(time[idx], dt);
        bool valid_trading_hours = (dt.hour >= start_hour && dt.hour < end_hour);
        
        if(!valid_trading_hours) continue;
        
        // Skip if not enough history for lookback
        if(idx + lookback_period >= limit) continue;
        
        // Check medium_ma above low_ma for lookback period - simplified
        bool medium_ma_above_low_ma = true;
        bool medium_ma_below_low_ma = true;
        
        for(int j = 0; j < lookback_period; j++)
        {
            if(MediumMA[idx + j] <= LowMA[idx + j]) medium_ma_above_low_ma = false;
            if(MediumMA[idx + j] >= LowMA[idx + j]) medium_ma_below_low_ma = false;
        }
        
        // Crossover/Crossunder detection
        bool x_over_high = (close[idx] > HighMA[idx] && close[idx + 1] <= HighMA[idx + 1]);
        bool x_under_high = (close[idx] < HighMA[idx] && close[idx + 1] >= HighMA[idx + 1]);
        
        // Uptrend condition
        bool uptrend = medium_ma_above_low_ma && 
                      HighMA[idx] > MediumMA[idx] && 
                      MediumMA[idx] > LowMA[idx] && 
                      (MediumMA[idx] - MediumMA[idx + 1]) > 0;
        
        // Downtrend condition
        bool downtrend = medium_ma_below_low_ma && 
                        HighMA[idx] < MediumMA[idx] && 
                        MediumMA[idx] < LowMA[idx] && 
                        (MediumMA[idx] - MediumMA[idx + 1]) < 0;
        
        // Buy condition
        bool base_buy_condition = x_over_high && uptrend && (close[idx] > open[idx]);
        
        // Check for recent buy signals in the lookback period
        bool no_recent_buy = true;
        for(int j = 1; j <= lookback_period && (idx - j) >= 0; j++)
        {
            string check_name = indicator_prefix + "BUY_" + TimeToString(time[idx - j], TIME_DATE|TIME_MINUTES);
            if(ObjectFind(0, check_name) >= 0)
            {
                no_recent_buy = false;
                break;
            }
        }
        
        if(base_buy_condition && no_recent_buy)
        {
            // Create BUY arrow (up triangle) below candle low
            string obj_name = indicator_prefix + "BUY_" + TimeToString(time[idx], TIME_DATE|TIME_MINUTES);
            ObjectDelete(0, obj_name);
            
            // Position arrow below the bar low with fixed point offset
            double arrow_price = low[idx] - ARROW_OFFSET_POINTS * _Point;
            if(ObjectCreate(0, obj_name, OBJ_ARROW, 0, time[idx], arrow_price))
            {
                ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrBlue);
                ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 233);  // Up Triangle
            }
            
            // Send alert only on most recent bar
            if(idx == 0)
                Alert("BUY signal on ", _Symbol, " at ", TimeToString(time[idx]));
        }
        
        // Sell condition
        bool base_sell_condition = x_under_high && downtrend && (close[idx] < open[idx]);
        
        // Check for recent sell signals in the lookback period
        bool no_recent_sell = true;
        for(int j = 1; j <= lookback_period && (idx - j) >= 0; j++)
        {
            string check_name = indicator_prefix + "SELL_" + TimeToString(time[idx - j], TIME_DATE|TIME_MINUTES);
            if(ObjectFind(0, check_name) >= 0)
            {
                no_recent_sell = false;
                break;
            }
        }
        
        if(base_sell_condition && no_recent_sell)
        {
            // Create SELL arrow (down triangle) above candle high
            string obj_name = indicator_prefix + "SELL_" + TimeToString(time[idx], TIME_DATE|TIME_MINUTES);
            ObjectDelete(0, obj_name);
            
            // Position arrow above the bar high with fixed point offset
            double arrow_price = high[idx] + ARROW_OFFSET_POINTS * _Point;
            if(ObjectCreate(0, obj_name, OBJ_ARROW, 0, time[idx], arrow_price))
            {
                ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrOrange);
                ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 234);  // Down Triangle
                ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);  // Anchor at arrow tip
            }
            
            // Send alert only on most recent bar
            if(idx == 0)
                Alert("SELL signal on ", _Symbol, " at ", TimeToString(time[idx]));
        }
    }
    
    ChartRedraw(0);  // Redraw chart once after all calculations
    return(rates_total);
}
//+------------------------------------------------------------------+