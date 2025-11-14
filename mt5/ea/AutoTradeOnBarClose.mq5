//+------------------------------------------------------------------+
//|                                              AutoTradeOnBarClose.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

// Input parameters
input double RiskPercent = 1.0;        // Risk percentage of equity (default 1%)
input int MagicNumber = 2025111402;        // Magic number for this EA
input string TradeComment = "SignalTrade"; // Comment for trades
input int Slippage = 10;               // Maximum slippage in points
input string SignalPrefix = "EntrySignal_"; // Prefix for signal objects from indicator

// Global variables
datetime lastBarTime = 0;              // Time of the last processed bar
MqlTick lastTick;                      // Last tick information
MqlTradeRequest request;               // Trade request structure
MqlTradeResult result;                 // Trade result structure

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize last bar time to current bar time
   lastBarTime = iTime(_Symbol, _Period, 0);
   
   Print("BuyOnBarClose EA initialized successfully");
   Print("Risk per trade: ", RiskPercent, "%");
   Print("Symbol: ", _Symbol);
   Print("Period: ", EnumToString(_Period));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("BuyOnBarClose EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Get current bar time
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   // Check if a new bar has formed (previous bar closed)
   if(currentBarTime != lastBarTime)
   {
      Print("New bar detected. Previous bar closed at: ", TimeToString(lastBarTime));
      
      // Check for buy or sell signals on the closed bar
      datetime closedBarTime = lastBarTime;  // Time of the bar that just closed
      
      // Check for BUY signal
      string buySignalName = SignalPrefix + "BUY_" + TimeToString(closedBarTime, TIME_DATE|TIME_MINUTES);
      bool hasBuySignal = (ObjectFind(0, buySignalName) >= 0);
      
      // Check for SELL signal
      string sellSignalName = SignalPrefix + "SELL_" + TimeToString(closedBarTime, TIME_DATE|TIME_MINUTES);
      bool hasSellSignal = (ObjectFind(0, sellSignalName) >= 0);
      
      // Update last bar time
      lastBarTime = currentBarTime;
      
      // Execute trades based on signals
      if(hasBuySignal)
      {
         Print("BUY signal detected on closed bar!");
         OpenBuyPosition();
      }
      else if(hasSellSignal)
      {
         Print("SELL signal detected on closed bar!");
         OpenSellPosition();
      }
      else
      {
         Print("No entry signals detected on closed bar.");
      }
   }
}

//+------------------------------------------------------------------+
//| Open Buy Position Function                                        |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   // Get the low of the previous closed bar (index 1)
   double barLow = iLow(_Symbol, _Period, 1);
   
   // Get current price information
   if(!SymbolInfoTick(_Symbol, lastTick))
   {
      Print("Error getting current tick: ", GetLastError());
      return;
   }
   
   // Current Ask price (buy at market)
   double entryPrice = lastTick.ask;
   
   // Stop Loss is the low of the previous bar
   double stopLoss = barLow;
   
   // Calculate SL distance in price
   double slDistance = entryPrice - stopLoss;
   
   if(slDistance <= 0)
   {
      Print("Invalid SL distance. Entry: ", entryPrice, " SL: ", stopLoss);
      return;
   }
   
   // Take Profit is 2x the SL distance
   double tpDistance = slDistance * 2;
   double takeProfit = entryPrice + tpDistance;
   
   // Normalize SL and TP prices
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   // Calculate lot size based on risk percentage
   double lotSize = CalculateLotSize(entryPrice, stopLoss);
   
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated: ", lotSize);
      return;
   }
   
   // Get symbol properties
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize lot size to comply with broker requirements
   lotSize = NormalizeLotSize(lotSize, minLot, maxLot, lotStep);
   
   Print("Opening BUY position:");
   Print("  Entry Price: ", entryPrice);
   Print("  Stop Loss: ", stopLoss, " (Distance: ", slDistance, " points)");
   Print("  Take Profit: ", takeProfit, " (Distance: ", tpDistance, " points)");
   Print("  Lot Size: ", lotSize);
   Print("  Risk: ", RiskPercent, "% of equity (", AccountInfoDouble(ACCOUNT_EQUITY), ")");
   
   // Prepare trade request
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;          // Immediate order execution
   request.symbol = _Symbol;                     // Symbol
   request.volume = lotSize;                     // Volume in lots
   request.type = ORDER_TYPE_BUY;               // Buy order
   request.price = entryPrice;                   // Entry price (Ask)
   request.sl = stopLoss;                        // Stop Loss
   request.tp = takeProfit;                      // Take Profit
   request.deviation = Slippage;                 // Allowed slippage
   request.magic = MagicNumber;                  // Magic number
   request.comment = TradeComment;               // Order comment
   request.type_filling = ORDER_FILLING_FOK;     // Fill or Kill
   
   // Send trade request
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed. Error: ", GetLastError());
      Print("Result code: ", result.retcode, " - ", result.comment);
      
      // Try IOC filling type if FOK failed
      request.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(request, result))
      {
         Print("OrderSend failed again with IOC. Error: ", GetLastError());
         return;
      }
   }
   
   // Check result
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("Buy order executed successfully!");
      Print("  Order Ticket: ", result.order);
      Print("  Deal Ticket: ", result.deal);
      Print("  Volume: ", result.volume);
      Print("  Price: ", result.price);
   }
   else
   {
      Print("Order execution failed. Return code: ", result.retcode);
      Print("Comment: ", result.comment);
   }
}

//+------------------------------------------------------------------+
//| Open Sell Position Function                                       |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   // Get the high of the previous closed bar (index 1)
   double barHigh = iHigh(_Symbol, _Period, 1);
   
   // Get current price information
   if(!SymbolInfoTick(_Symbol, lastTick))
   {
      Print("Error getting current tick: ", GetLastError());
      return;
   }
   
   // Current Bid price (sell at market)
   double entryPrice = lastTick.bid;
   
   // Stop Loss is the high of the previous bar
   double stopLoss = barHigh;
   
   // Calculate SL distance in price
   double slDistance = stopLoss - entryPrice;
   
   if(slDistance <= 0)
   {
      Print("Invalid SL distance. Entry: ", entryPrice, " SL: ", stopLoss);
      return;
   }
   
   // Take Profit is 2x the SL distance
   double tpDistance = slDistance * 2;
   double takeProfit = entryPrice - tpDistance;
   
   // Normalize SL and TP prices
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   // Calculate lot size based on risk percentage
   double lotSize = CalculateLotSize(entryPrice, stopLoss);
   
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated: ", lotSize);
      return;
   }
   
   // Get symbol properties
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize lot size to comply with broker requirements
   lotSize = NormalizeLotSize(lotSize, minLot, maxLot, lotStep);
   
   Print("Opening SELL position:");
   Print("  Entry Price: ", entryPrice);
   Print("  Stop Loss: ", stopLoss, " (Distance: ", slDistance, " points)");
   Print("  Take Profit: ", takeProfit, " (Distance: ", tpDistance, " points)");
   Print("  Lot Size: ", lotSize);
   Print("  Risk: ", RiskPercent, "% of equity (", AccountInfoDouble(ACCOUNT_EQUITY), ")");
   
   // Prepare trade request
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;          // Immediate order execution
   request.symbol = _Symbol;                     // Symbol
   request.volume = lotSize;                     // Volume in lots
   request.type = ORDER_TYPE_SELL;              // Sell order
   request.price = entryPrice;                   // Entry price (Bid)
   request.sl = stopLoss;                        // Stop Loss
   request.tp = takeProfit;                      // Take Profit
   request.deviation = Slippage;                 // Allowed slippage
   request.magic = MagicNumber;                  // Magic number
   request.comment = TradeComment;               // Order comment
   request.type_filling = ORDER_FILLING_FOK;     // Fill or Kill
   
   // Send trade request
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed. Error: ", GetLastError());
      Print("Result code: ", result.retcode, " - ", result.comment);
      
      // Try IOC filling type if FOK failed
      request.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(request, result))
      {
         Print("OrderSend failed again with IOC. Error: ", GetLastError());
         return;
      }
   }
   
   // Check result
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("Sell order executed successfully!");
      Print("  Order Ticket: ", result.order);
      Print("  Deal Ticket: ", result.deal);
      Print("  Volume: ", result.volume);
      Print("  Price: ", result.price);
   }
   else
   {
      Print("Order execution failed. Return code: ", result.retcode);
      Print("Comment: ", result.comment);
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk Percentage                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   // Get account equity
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Calculate risk amount in account currency
   double riskAmount = equity * (RiskPercent / 100.0);
   
   // Calculate SL distance in price
   double slDistance = MathAbs(entryPrice - stopLoss);
   
   if(slDistance <= 0)
   {
      Print("Error: SL distance is zero or negative");
      return 0;
   }
   
   // Get tick value and size
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize <= 0 || tickValue <= 0)
   {
      Print("Error: Invalid tick size or tick value");
      return 0;
   }
   
   // Calculate number of ticks in SL distance
   double slTicks = slDistance / tickSize;
   
   // Calculate money lost per lot for this SL distance
   double moneyPerLot = slTicks * tickValue;
   
   if(moneyPerLot <= 0)
   {
      Print("Error: Money per lot is zero or negative");
      return 0;
   }
   
   // Calculate lot size
   double lotSize = riskAmount / moneyPerLot;
   
   Print("Lot calculation:");
   Print("  Equity: ", equity);
   Print("  Risk Amount: ", riskAmount);
   Print("  SL Distance: ", slDistance);
   Print("  Ticks in SL: ", slTicks);
   Print("  Money per lot: ", moneyPerLot);
   Print("  Calculated lots: ", lotSize);
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Normalize Lot Size                                                |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots, double minLot, double maxLot, double lotStep)
{
   // Round to nearest lot step
   lots = MathFloor(lots / lotStep) * lotStep;
   
   // Ensure within min/max bounds
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;
   
   // Get lot digits for normalization
   double lotDigits = 2;
   if(lotStep >= 1.0)
      lotDigits = 0;
   else if(lotStep >= 0.1)
      lotDigits = 1;
   else if(lotStep >= 0.01)
      lotDigits = 2;
   else
      lotDigits = 3;
   
   lots = NormalizeDouble(lots, (int)lotDigits);
   
   return lots;
}

//+------------------------------------------------------------------+

