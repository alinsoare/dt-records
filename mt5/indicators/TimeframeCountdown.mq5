//+------------------------------------------------------------------+
//|                                         TimeframeCountdown.mq5   |
//|                                                                  |
//|                        Displays countdown to next candle close   |
//+------------------------------------------------------------------+
#property copyright "Custom Indicator"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//--- Input parameters
input color TextColor = clrBlack;           // Text color
input int FontSize = 12;                    // Font size
input string FontName = "Arial Bold";       // Font name
input ENUM_BASE_CORNER Corner = CORNER_LEFT_LOWER;  // Corner for label
input int XDistance = 10;                   // Horizontal distance from corner
input int YDistance = 30;                   // Vertical distance from corner
input bool ShowSeconds = true;              // Show seconds
input bool ShowMilliseconds = false;        // Show milliseconds

//--- Global variables
string labelName = "TimeframeCountdown";
string labelName2 = "CandlePoints";
int currentBarIndex = 0;  // Track which bar to display

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create text label for countdown
   if(ObjectFind(0, labelName) < 0)
   {
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
   }
   
   //--- Set label properties
   ObjectSetInteger(0, labelName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, XDistance);
   ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, YDistance);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, labelName, OBJPROP_FONT, FontName);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
   
   //--- Create text label for candle points
   if(ObjectFind(0, labelName2) < 0)
   {
      ObjectCreate(0, labelName2, OBJ_LABEL, 0, 0, 0);
   }
   
   //--- Set second label properties (positioned below first label)
   ObjectSetInteger(0, labelName2, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, labelName2, OBJPROP_XDISTANCE, XDistance);
   ObjectSetInteger(0, labelName2, OBJPROP_YDISTANCE, YDistance + FontSize + 5);
   ObjectSetInteger(0, labelName2, OBJPROP_COLOR, TextColor);
   ObjectSetInteger(0, labelName2, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, labelName2, OBJPROP_FONT, FontName);
   ObjectSetInteger(0, labelName2, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, labelName2, OBJPROP_HIDDEN, true);
   
   //--- Enable timer
   EventSetTimer(1);
   
   //--- Enable mouse move events to track cursor position
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Kill timer
   EventKillTimer();
   
   //--- Delete labels
   ObjectDelete(0, labelName);
   ObjectDelete(0, labelName2);
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
   //--- Update countdown
   UpdateCountdown();
   
   //--- Return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Update countdown
   UpdateCountdown();
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   //--- Mouse move event
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      //--- Get mouse coordinates
      int x = (int)lparam;
      int y = (int)dparam;
      
      //--- Convert screen coordinates to time and price
      datetime time;
      double price;
      int window;
      
      if(ChartXYToTimePrice(0, x, y, window, time, price))
      {
         //--- Find the bar index for this time
         int barIndex = iBarShift(_Symbol, _Period, time);
         if(barIndex >= 0)
         {
            currentBarIndex = barIndex;
            UpdateCountdown();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update countdown display                                         |
//+------------------------------------------------------------------+
void UpdateCountdown()
{
   //--- Get current time and timeframe
   datetime currentTime = TimeCurrent();
   ENUM_TIMEFRAMES period = Period();
   
   //--- Get period in seconds
   int periodSeconds = PeriodSeconds(period);
   
   //--- Calculate seconds since period start
   int secondsSinceStart = (int)(currentTime % periodSeconds);
   
   //--- Calculate remaining seconds
   int remainingSeconds = periodSeconds - secondsSinceStart;
   
   //--- Format countdown string
   string countdownText = FormatCountdown(remainingSeconds, periodSeconds);
   
   //--- Update countdown label
   ObjectSetString(0, labelName, OBJPROP_TEXT, countdownText);
   
   //--- Get candle data for the candle at cursor position (or current candle)
   double open = iOpen(_Symbol, _Period, currentBarIndex);
   double close = iClose(_Symbol, _Period, currentBarIndex);
   
   //--- Calculate points difference (Close - Open)
   double pointsDiff = close - open;
   double candlePoints = pointsDiff / _Point;
   
   //--- Format candle points string
   string candleText = "";
   if(currentBarIndex > 0)
      candleText += "Bar[" + IntegerToString(currentBarIndex) + "] ";
   else
      candleText += "Current ";
   
   candleText += "Candle: ";
   if(candlePoints >= 0)
      candleText += "+";
   candleText += IntegerToString((int)candlePoints) + " pts";
   
   if(candlePoints >= 0)
      candleText += " (Bullish)";
   else
      candleText += " (Bearish)";
   
   //--- Update candle points label
   ObjectSetString(0, labelName2, OBJPROP_TEXT, candleText);
   
   //--- Refresh chart
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Format countdown time                                            |
//+------------------------------------------------------------------+
string FormatCountdown(int remainingSeconds, int totalSeconds)
{
   string result = "";
   
   //--- Calculate time components
   int hours = remainingSeconds / 3600;
   int minutes = (remainingSeconds % 3600) / 60;
   int seconds = remainingSeconds % 60;
   
   //--- Get timeframe name
   string tfName = GetTimeframeName();
   
   //--- Build countdown string
   result = tfName + " | ";
   
   if(hours > 0)
   {
      result += IntegerToString(hours) + "h ";
   }
   
   if(minutes > 0 || hours > 0)
   {
      result += StringFormat("%02d", minutes) + "m ";
   }
   
   if(ShowSeconds)
   {
      result += StringFormat("%02d", seconds) + "s";
   }
   
   //--- Add progress bar
   int barLength = 20;
   int filledBars = (int)((totalSeconds - remainingSeconds) * barLength / totalSeconds);
   
   result += " [";
   for(int i = 0; i < barLength; i++)
   {
      if(i < filledBars)
         result += "█";
      else
         result += "░";
   }
   result += "]";
   
   return result;
}

//+------------------------------------------------------------------+
//| Get timeframe name                                               |
//+------------------------------------------------------------------+
string GetTimeframeName()
{
   ENUM_TIMEFRAMES period = Period();
   
   switch(period)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "TF";
   }
}
//+------------------------------------------------------------------+

