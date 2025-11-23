//+------------------------------------------------------------------+
//|                                                   AutoTrade.mq5   |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.mql5.com"
#property version   "3.00"
#property strict
#property description "Combined EA: Auto Trade on Signal + 3-Step Partial Close"

//+------------------------------------------------------------------+
//| Input Parameters - Auto Trade Section                            |
//+------------------------------------------------------------------+
input group "=== AUTO TRADE SETTINGS ==="
input bool   EnableAutoTrade = false;      // Enable Auto Trading (default: OFF for safety)
input double RiskPercent = 1.0;            // Risk percentage of equity
input double TPMultiplier = 2.0;           // Take Profit multiplier (TP = SL × Multiplier)
input int    MagicNumber = 2025111802;     // Magic number for this EA
input string TradeComment = "AutoTrade";   // Comment for trades
input int    Slippage = 10;                // Maximum slippage in points

// Signal prefix - DO NOT CHANGE (must match PatternEntrySignals indicator)
const string SignalPrefix = "PatternEntrySignals_";

//+------------------------------------------------------------------+
//| Input Parameters - Partial Close Section                         |
//+------------------------------------------------------------------+
enum PartialCloseStrategy
{
   STRATEGY_NO_PARTIAL = 0,      // No Partial Close (Full TP/SL only)
   STRATEGY_2_STEPS = 1,          // 2-Step: 50% at 50% TP + BE
   STRATEGY_3_STEPS = 2,          // 3-Step Progressive: 1/3 at 40%, 1/3 at 80%, trail at 100%
   STRATEGY_STEP_LADDER = 3       // Step Ladder: At 90% progress, move both SL & TP by step distance
};

input group "=== PARTIAL CLOSE SETTINGS ==="
input bool   EnablePartialClose = true;    // Enable Partial Close Logic (default: ON)
input PartialCloseStrategy Strategy = STRATEGY_3_STEPS; // Partial Close Strategy
input ulong  InpTicket = 0;                // 0=Auto (all positions on chart's symbol), or specific ticket
input bool   DebugPrint = true;            // Print logs to Experts tab

//+------------------------------------------------------------------+
//| Global Variables - Auto Trade Section                            |
//+------------------------------------------------------------------+
datetime lastBarTime = 0;                  // Time of the last processed bar
MqlTick lastTick;                          // Last tick information
MqlTradeRequest request;                   // Trade request structure
MqlTradeResult result;                     // Trade result structure

//+------------------------------------------------------------------+
//| Global Variables - Partial Close Section                         |
//+------------------------------------------------------------------+
struct PositionState
{
   ulong   ticket;
   bool    step1_done;
   bool    step2_done;
   bool    step3_done;
   double  originalVolume;     // Store original volume for accurate calculations
   double  originalOpenPrice;  // Store original open price
   double  originalSL;         // Store original SL (for trailing calculations)
   double  originalTP;         // Store original TP
};

PositionState positions[]; // Array to track multiple positions
ulong skippedLowVolumeTickets[]; // Array to track positions with too low volume (to avoid spam)

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize last bar time to current bar time
   lastBarTime = iTime(_Symbol, _Period, 0);
   
   Print("=== AutoTrade EA Initialized ===");
   Print("Auto Trade: ", EnableAutoTrade ? "ENABLED" : "DISABLED");
   Print("Partial Close: ", EnablePartialClose ? "ENABLED" : "DISABLED");
   
   if(EnableAutoTrade)
   {
      Print("Risk per trade: ", RiskPercent, "%");
      Print("TP Multiplier: ", TPMultiplier, " (RRR 1:", TPMultiplier, ")");
      Print("Symbol: ", _Symbol);
      Print("Period: ", EnumToString(_Period));
      Print("Signal Prefix: ", SignalPrefix);
   }
   
   if(EnablePartialClose)
   {
      string strategyName;
      if(Strategy == STRATEGY_NO_PARTIAL)
         strategyName = "No Partial Close (Full TP/SL only)";
      else if(Strategy == STRATEGY_2_STEPS)
         strategyName = "2-Step (50% at 50% TP + BE)";
      else if(Strategy == STRATEGY_STEP_LADDER)
         strategyName = "Step Ladder (At 90% progress, move SL & TP by step distance)";
      else if(Strategy == STRATEGY_3_STEPS)
         strategyName = "3-Step Progressive";
      
      Print("Partial Close Strategy: ", strategyName);
      Print("Partial Close Mode: ", (InpTicket == 0) ? "AUTO (All positions)" : "Specific Ticket: " + IntegerToString(InpTicket));
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("AutoTrade EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // PART 1: Auto Trade Logic (if enabled)
   if(EnableAutoTrade)
   {
      ProcessAutoTrade();
   }
   
   // PART 2: Partial Close Logic (if enabled)
   if(EnablePartialClose)
   {
      ProcessPartialClose();
   }
}

//+------------------------------------------------------------------+
//| Process Auto Trade Logic                                         |
//+------------------------------------------------------------------+
void ProcessAutoTrade()
{
   // Get current bar time
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   // Check if a new bar has formed (previous bar closed)
   if(currentBarTime != lastBarTime)
   {
      // Check for buy or sell signals on the closed bar
      datetime closedBarTime = lastBarTime;  // Time of the bar that just closed
      
      // Check for BUY signal (lowercase "buy_" to match indicator)
      string buySignalName = SignalPrefix + "buy_" + TimeToString(closedBarTime, TIME_DATE|TIME_MINUTES);
      bool hasBuySignal = (ObjectFind(0, buySignalName) >= 0);
      
      // Check for SELL signal (lowercase "sell_" to match indicator)
      string sellSignalName = SignalPrefix + "sell_" + TimeToString(closedBarTime, TIME_DATE|TIME_MINUTES);
      bool hasSellSignal = (ObjectFind(0, sellSignalName) >= 0);
      
      // Update last bar time
      lastBarTime = currentBarTime;
      
      // Execute trades based on signals
      if(hasBuySignal)
      {
         if(DebugPrint) Print("[AutoTrade] BUY signal detected on closed bar!");
         int slPoints = ExtractSLFromSignal(buySignalName);
         OpenBuyPosition(slPoints);
      }
      else if(hasSellSignal)
      {
         if(DebugPrint) Print("[AutoTrade] SELL signal detected on closed bar!");
         int slPoints = ExtractSLFromSignal(sellSignalName);
         OpenSellPosition(slPoints);
      }
   }
}

//+------------------------------------------------------------------+
//| Process Partial Close Logic                                      |
//+------------------------------------------------------------------+
void ProcessPartialClose()
{
   // Clean up closed positions from tracking array
   CleanupClosedPositions();
   
   // Build list of positions to manage
   ManagePositionsList();
   
   // Process each tracked position with selected strategy
   for(int i = 0; i < ArraySize(positions); i++)
   {
      if(Strategy == STRATEGY_NO_PARTIAL)
         continue;  // Skip partial close processing - let position hit full TP/SL
      else if(Strategy == STRATEGY_2_STEPS)
         ProcessPosition_2Step(positions[i].ticket);
      else if(Strategy == STRATEGY_STEP_LADDER)
         ProcessPosition_StepLadder(positions[i].ticket);
      else if(Strategy == STRATEGY_3_STEPS)
         ProcessPosition_3Step(positions[i].ticket);
   }
}

//+------------------------------------------------------------------+
//| Extract SL distance (in points) from signal label                |
//+------------------------------------------------------------------+
int ExtractSLFromSignal(string signalName)
{
   // Get the label text from the signal object
   string labelText = ObjectGetString(0, signalName, OBJPROP_TEXT);
   
   if(labelText == "")
   {
      if(DebugPrint) Print("[WARN] Could not read label text from signal: ", signalName);
      return 0;
   }
   
   // Label format: "BUY | 120" or "SELL | 150"
   // Extract the number after the "|" separator
   int separatorPos = StringFind(labelText, "|");
   if(separatorPos < 0)
   {
      if(DebugPrint) Print("[WARN] Invalid label format (no separator): ", labelText);
      return 0;
   }
   
   // Get substring after "|" and trim spaces
   string slString = StringSubstr(labelText, separatorPos + 1);
   StringTrimLeft(slString);
   StringTrimRight(slString);
   
   // Convert to integer
   int slPoints = (int)StringToInteger(slString);
   
   if(DebugPrint) Print("[AutoTrade] Extracted SL from signal: ", slPoints, " points (from label: ", labelText, ")");
   
   return slPoints;
}

//+------------------------------------------------------------------+
//| Open Buy Position Function                                        |
//+------------------------------------------------------------------+
void OpenBuyPosition(int slPointsFromSignal = 0)
{
   // Get current price information
   if(!SymbolInfoTick(_Symbol, lastTick))
   {
      Print("[ERROR] Error getting current tick: ", GetLastError());
      return;
   }
   
   // Current Ask price (buy at market)
   double entryPrice = lastTick.ask;
   
   // Calculate Stop Loss
   double stopLoss;
   double slDistance;
   
   if(slPointsFromSignal > 0)
   {
      // Use SL distance from signal (in points)
      slDistance = slPointsFromSignal * _Point;
      stopLoss = entryPrice - slDistance;
      if(DebugPrint) Print("[AutoTrade] Using SL from signal: ", slPointsFromSignal, " points");
   }
   else
   {
      // Fallback: Use the low of the previous closed bar (index 1)
      double barLow = iLow(_Symbol, _Period, 1);
      stopLoss = barLow;
      slDistance = entryPrice - stopLoss;
      if(DebugPrint) Print("[AutoTrade] Using bar low for SL (signal had no SL data)");
   }
   
   if(slDistance <= 0)
   {
      Print("[ERROR] Invalid SL distance. Entry: ", entryPrice, " SL: ", stopLoss);
      return;
   }
   
   // Take Profit is TPMultiplier × SL distance (configurable)
   double tpDistance = slDistance * TPMultiplier;
   double takeProfit = entryPrice + tpDistance;
   
   // Normalize SL and TP prices
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   // Calculate lot size based on risk percentage
   double lotSize = CalculateLotSize(entryPrice, stopLoss);
   
   if(lotSize <= 0)
   {
      Print("[ERROR] Invalid lot size calculated: ", lotSize);
      return;
   }
   
   // Get symbol properties
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize lot size to comply with broker requirements
   lotSize = NormalizeLotSize(lotSize, minLot, maxLot, lotStep);
   
   if(DebugPrint)
   {
      Print("[AutoTrade] Opening BUY position:");
      Print("  Entry Price: ", entryPrice);
      Print("  Stop Loss: ", stopLoss, " (Distance: ", slDistance, " points)");
      Print("  Take Profit: ", takeProfit, " (Distance: ", tpDistance, " points)");
      Print("  Lot Size: ", lotSize);
      Print("  Risk: ", RiskPercent, "% of equity (", AccountInfoDouble(ACCOUNT_EQUITY), ")");
   }
   
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
      Print("[ERROR] OrderSend failed. Error: ", GetLastError());
      Print("Result code: ", result.retcode, " - ", result.comment);
      
      // Try IOC filling type if FOK failed
      request.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(request, result))
      {
         Print("[ERROR] OrderSend failed again with IOC. Error: ", GetLastError());
         return;
      }
   }
   
   // Check result
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("[OK] Buy order executed successfully!");
      Print("  Order Ticket: ", result.order);
      Print("  Deal Ticket: ", result.deal);
      Print("  Volume: ", result.volume);
      Print("  Price: ", result.price);
   }
   else
   {
      Print("[ERROR] Order execution failed. Return code: ", result.retcode);
      Print("Comment: ", result.comment);
   }
}

//+------------------------------------------------------------------+
//| Open Sell Position Function                                       |
//+------------------------------------------------------------------+
void OpenSellPosition(int slPointsFromSignal = 0)
{
   // Get current price information
   if(!SymbolInfoTick(_Symbol, lastTick))
   {
      Print("[ERROR] Error getting current tick: ", GetLastError());
      return;
   }
   
   // Current Bid price (sell at market)
   double entryPrice = lastTick.bid;
   
   // Calculate Stop Loss
   double stopLoss;
   double slDistance;
   
   if(slPointsFromSignal > 0)
   {
      // Use SL distance from signal (in points)
      slDistance = slPointsFromSignal * _Point;
      stopLoss = entryPrice + slDistance;
      if(DebugPrint) Print("[AutoTrade] Using SL from signal: ", slPointsFromSignal, " points");
   }
   else
   {
      // Fallback: Use the high of the previous closed bar (index 1)
      double barHigh = iHigh(_Symbol, _Period, 1);
      stopLoss = barHigh;
      slDistance = stopLoss - entryPrice;
      if(DebugPrint) Print("[AutoTrade] Using bar high for SL (signal had no SL data)");
   }
   
   if(slDistance <= 0)
   {
      Print("[ERROR] Invalid SL distance. Entry: ", entryPrice, " SL: ", stopLoss);
      return;
   }
   
   // Take Profit is TPMultiplier × SL distance (configurable)
   double tpDistance = slDistance * TPMultiplier;
   double takeProfit = entryPrice - tpDistance;
   
   // Normalize SL and TP prices
   stopLoss = NormalizeDouble(stopLoss, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);
   
   // Calculate lot size based on risk percentage
   double lotSize = CalculateLotSize(entryPrice, stopLoss);
   
   if(lotSize <= 0)
   {
      Print("[ERROR] Invalid lot size calculated: ", lotSize);
      return;
   }
   
   // Get symbol properties
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize lot size to comply with broker requirements
   lotSize = NormalizeLotSize(lotSize, minLot, maxLot, lotStep);
   
   if(DebugPrint)
   {
      Print("[AutoTrade] Opening SELL position:");
      Print("  Entry Price: ", entryPrice);
      Print("  Stop Loss: ", stopLoss, " (Distance: ", slDistance, " points)");
      Print("  Take Profit: ", takeProfit, " (Distance: ", tpDistance, " points)");
      Print("  Lot Size: ", lotSize);
      Print("  Risk: ", RiskPercent, "% of equity (", AccountInfoDouble(ACCOUNT_EQUITY), ")");
   }
   
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
      Print("[ERROR] OrderSend failed. Error: ", GetLastError());
      Print("Result code: ", result.retcode, " - ", result.comment);
      
      // Try IOC filling type if FOK failed
      request.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(request, result))
      {
         Print("[ERROR] OrderSend failed again with IOC. Error: ", GetLastError());
         return;
      }
   }
   
   // Check result
   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      Print("[OK] Sell order executed successfully!");
      Print("  Order Ticket: ", result.order);
      Print("  Deal Ticket: ", result.deal);
      Print("  Volume: ", result.volume);
      Print("  Price: ", result.price);
   }
   else
   {
      Print("[ERROR] Order execution failed. Return code: ", result.retcode);
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
      Print("[ERROR] SL distance is zero or negative");
      return 0;
   }
   
   // Get tick value and size
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize <= 0 || tickValue <= 0)
   {
      Print("[ERROR] Invalid tick size or tick value");
      return 0;
   }
   
   // Calculate number of ticks in SL distance
   double slTicks = slDistance / tickSize;
   
   // Calculate money lost per lot for this SL distance
   double moneyPerLot = slTicks * tickValue;
   
   if(moneyPerLot <= 0)
   {
      Print("[ERROR] Money per lot is zero or negative");
      return 0;
   }
   
   // Calculate lot size
   double lotSize = riskAmount / moneyPerLot;
   
   if(DebugPrint)
   {
      Print("[AutoTrade] Lot calculation:");
      Print("  Equity: ", equity);
      Print("  Risk Amount: ", riskAmount);
      Print("  SL Distance: ", slDistance);
      Print("  Ticks in SL: ", slTicks);
      Print("  Money per lot: ", moneyPerLot);
      Print("  Calculated lots: ", lotSize);
   }
   
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
//| Manage the list of positions to track                            |
//+------------------------------------------------------------------+
void ManagePositionsList()
{
   string symbolFilter = Symbol(); // Chart symbol
   int totalPositions = PositionsTotal();
   
   // Build list based on input mode
   if(InpTicket == 0)
   {
      // Auto mode: track all positions on chart's symbol
      for(int i = 0; i < totalPositions; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == symbolFilter)
            {
               if(!IsPositionTracked(ticket))
               {
                  AddPositionToTrack(ticket);
               }
            }
         }
      }
   }
   else
   {
      // Specific ticket mode
      if(!IsPositionTracked(InpTicket))
      {
         AddPositionToTrack(InpTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if position is already being tracked                       |
//+------------------------------------------------------------------+
bool IsPositionTracked(ulong ticket)
{
   for(int i = 0; i < ArraySize(positions); i++)
   {
      if(positions[i].ticket == ticket) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if position is in skipped low volume list                  |
//+------------------------------------------------------------------+
bool IsPositionSkipped(ulong ticket)
{
   for(int i = 0; i < ArraySize(skippedLowVolumeTickets); i++)
   {
      if(skippedLowVolumeTickets[i] == ticket) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add position to skipped low volume list                          |
//+------------------------------------------------------------------+
void AddToSkippedList(ulong ticket)
{
   int size = ArraySize(skippedLowVolumeTickets);
   ArrayResize(skippedLowVolumeTickets, size + 1);
   skippedLowVolumeTickets[size] = ticket;
}

//+------------------------------------------------------------------+
//| Add position to tracking array                                   |
//+------------------------------------------------------------------+
void AddPositionToTrack(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   int size = ArraySize(positions);
   ArrayResize(positions, size + 1);
   positions[size].ticket = ticket;
   positions[size].step1_done = false;
   positions[size].step2_done = false;
   positions[size].step3_done = false;
   positions[size].originalVolume = PositionGetDouble(POSITION_VOLUME);
   positions[size].originalOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   positions[size].originalSL = PositionGetDouble(POSITION_SL);
   positions[size].originalTP = PositionGetDouble(POSITION_TP);
   string positionType = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";

   if(DebugPrint) Print("[PartialClose] Added ", positionType, " position ", ticket, " to tracking (VOL: ", 
                      DoubleToString(positions[size].originalVolume, 2), "| OP: ",
                      DoubleToString(positions[size].originalOpenPrice, 5), "| SL: ",
                      DoubleToString(positions[size].originalSL, 5), "| TP: ",
                      DoubleToString(positions[size].originalTP, 5), ")");
}

//+------------------------------------------------------------------+
//| Clean up positions that no longer exist                          |
//+------------------------------------------------------------------+
void CleanupClosedPositions()
{
   for(int i = ArraySize(positions) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(positions[i].ticket))
      {
         if(DebugPrint) Print("[PartialClose] Removing closed position ", positions[i].ticket, " from tracking");
         RemovePositionFromArray(i);
      }
   }
   
   // Also cleanup skipped low volume positions that have closed
   for(int i = ArraySize(skippedLowVolumeTickets) - 1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(skippedLowVolumeTickets[i]))
      {
         RemoveFromSkippedList(i);
      }
   }
}

//+------------------------------------------------------------------+
//| Remove position from array by index                              |
//+------------------------------------------------------------------+
void RemovePositionFromArray(int index)
{
   int size = ArraySize(positions);
   if(index >= size) return;
   
   // Shift elements
   for(int i = index; i < size - 1; i++)
   {
      positions[i] = positions[i + 1];
   }
   ArrayResize(positions, size - 1);
}

//+------------------------------------------------------------------+
//| Remove position from skipped list by index                       |
//+------------------------------------------------------------------+
void RemoveFromSkippedList(int index)
{
   int size = ArraySize(skippedLowVolumeTickets);
   if(index >= size) return;
   
   // Shift elements
   for(int i = index; i < size - 1; i++)
   {
      skippedLowVolumeTickets[i] = skippedLowVolumeTickets[i + 1];
   }
   ArrayResize(skippedLowVolumeTickets, size - 1);
}

//+------------------------------------------------------------------+
//| Get position state index from tracking array                     |
//+------------------------------------------------------------------+
int GetPositionStateIndex(ulong ticket)
{
   for(int i = 0; i < ArraySize(positions); i++)
   {
      if(positions[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Process a single position - 2-Step Strategy                      |
//+------------------------------------------------------------------+
void ProcessPosition_2Step(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   long type       = PositionGetInteger(POSITION_TYPE);
   double openPrice= PositionGetDouble(POSITION_PRICE_OPEN);
   double tpPrice  = PositionGetDouble(POSITION_TP);
   double volume   = PositionGetDouble(POSITION_VOLUME);
   string symbol   = PositionGetString(POSITION_SYMBOL);
   double bid      = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tpPrice == 0 || tickSize <= 0 || volume <= 0) return;
   
   // Safety check: verify position volume is reasonable (SYMBOL_VOLUME_MIN * 2)
   if(volume < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN) * 2)
   {
      if(!IsPositionSkipped(ticket))
      {
         if(DebugPrint) Print("[PartialClose-2Step] Position ", ticket, " volume (", DoubleToString(volume,2), 
                             ") below minimum *2. Skipping permanently.");
         AddToSkippedList(ticket);
      }
      return;
   }

   // Get position state index
   int stateIdx = GetPositionStateIndex(ticket);
   if(stateIdx < 0) return;

   // Use original values for calculations
   double originalVolume = positions[stateIdx].originalVolume;
   double originalOpenPrice = positions[stateIdx].originalOpenPrice;
   double originalTP = positions[stateIdx].originalTP;
   
   double range = MathAbs(originalTP - originalOpenPrice);
   double level1 = (type == POSITION_TYPE_BUY) ? originalOpenPrice + range/2.0 : originalOpenPrice - range/2.0;
   double price = (type == POSITION_TYPE_BUY) ? bid : ask;

   // STEP 1: Close 50% of volume at 50% TP and move SL to BE
   if(!positions[stateIdx].step1_done)
   {
      bool trigger1 = (type == POSITION_TYPE_BUY && price >= level1) ||
                      (type == POSITION_TYPE_SELL && price <= level1);
      if(trigger1)
      {
         double closeLots = NormalizeVolume(originalVolume/2.0, symbol);
         double volumeBefore = volume;
         if(PartialCloseMT5(symbol, type, closeLots))
         {
            if(VerifyPartialClose(ticket, volumeBefore, closeLots))
            {
               double newSL = originalOpenPrice; // Move SL to breakeven
               if(ModifyPositionSLTP(ticket, newSL, originalTP))
               {
                  positions[stateIdx].step1_done = true;
                  if(DebugPrint)
                     Print("[PartialClose-2Step] [", ticket, "] Closed 50% (", DoubleToString(closeLots,2),
                           " lots) at 50% TP, SL->BE (", DoubleToString(newSL,5), ")");
               }
            }
            else
            {
               if(DebugPrint) Print("[WARN] [", ticket, "] 2-Step: Volume verification failed - retrying");
            }
         }
      }
   }

   // Step 2 is simply letting the remaining 50% run to TP or BE SL
   // No additional action needed - marking as done for consistency
   if(positions[stateIdx].step1_done && !positions[stateIdx].step2_done)
   {
      positions[stateIdx].step2_done = true;
   }
}

//+------------------------------------------------------------------+
//| Process a single position - 2-Step + Trailing Strategy          |
//+------------------------------------------------------------------+
void ProcessPosition_StepLadder(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   long type       = PositionGetInteger(POSITION_TYPE);
   double openPrice= PositionGetDouble(POSITION_PRICE_OPEN);
   double slPrice  = PositionGetDouble(POSITION_SL);
   double tpPrice  = PositionGetDouble(POSITION_TP);
   double volume   = PositionGetDouble(POSITION_VOLUME);
   string symbol   = PositionGetString(POSITION_SYMBOL);
   double bid      = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tpPrice == 0 || tickSize <= 0 || volume <= 0) return;
   
   // Get position state index
   int stateIdx = GetPositionStateIndex(ticket);
   if(stateIdx < 0) return;

   // Use original values for calculations
   double originalSL = positions[stateIdx].originalSL;
   double originalOpenPrice = positions[stateIdx].originalOpenPrice;
   
   // Calculate step distance (SL to BE distance, kept constant)
   double stepDistance = MathAbs(originalSL - originalOpenPrice);
   
   // Current price for checking
   double price = (type == POSITION_TYPE_BUY) ? bid : ask;
   
   // Calculate current SL-TP range
   double range = MathAbs(tpPrice - slPrice);
   
   if(type == POSITION_TYPE_BUY)
   {
      // Calculate 90% progress point: SL + 90% of (TP - SL)
      double trigger_price = slPrice + 0.9 * range;
      
      // Check if price reached 90% of the way to TP
      if(price >= trigger_price)
      {
         // Move both SL and TP up by stepDistance
         double newSL = slPrice + stepDistance;
         double newTP = tpPrice + stepDistance;
         
         newSL = NormalizeDouble(newSL, _Digits);
         newTP = NormalizeDouble(newTP, _Digits);
         
         if(ModifyPositionSLTP(ticket, newSL, newTP))
         {
            if(DebugPrint)
               Print("[StepLadder] [", ticket, "] Ladder stepped UP: SL ", DoubleToString(slPrice,5),
                     " -> ", DoubleToString(newSL,5), " | TP ", DoubleToString(tpPrice,5),
                     " -> ", DoubleToString(newTP,5));
         }
      }
   }
   else  // SELL
   {
      // Calculate 90% progress point: SL - 90% of (SL - TP)
      double trigger_price = slPrice - 0.9 * range;
      
      // Check if price reached 90% of the way to TP
      if(price <= trigger_price)
      {
         // Move both SL and TP down by stepDistance
         double newSL = slPrice - stepDistance;
         double newTP = tpPrice - stepDistance;
         
         newSL = NormalizeDouble(newSL, _Digits);
         newTP = NormalizeDouble(newTP, _Digits);
         
         if(ModifyPositionSLTP(ticket, newSL, newTP))
         {
            if(DebugPrint)
               Print("[StepLadder] [", ticket, "] Ladder stepped DOWN: SL ", DoubleToString(slPrice,5),
                     " -> ", DoubleToString(newSL,5), " | TP ", DoubleToString(tpPrice,5),
                     " -> ", DoubleToString(newTP,5));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Process a single position - 3-Step Strategy                      |
//+------------------------------------------------------------------+
void ProcessPosition_3Step(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   long type       = PositionGetInteger(POSITION_TYPE);
   double openPrice= PositionGetDouble(POSITION_PRICE_OPEN);
   double tpPrice  = PositionGetDouble(POSITION_TP);
   double volume   = PositionGetDouble(POSITION_VOLUME);
   string symbol   = PositionGetString(POSITION_SYMBOL);
   double bid      = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tpPrice == 0 || tickSize <= 0 || volume <= 0) return;
   
   // Additional safety check: verify position volume is reasonable (SYMBOL_VOLUME_MIN * 3)
   if(volume < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN) * 3)
   {
      // Only print warning once per position, then track it to avoid spam
      if(!IsPositionSkipped(ticket))
      {
         if(DebugPrint) Print("[PartialClose] Position ", ticket, " volume (", DoubleToString(volume,2), 
                             ") below minimum *3. Skipping permanently.");
         AddToSkippedList(ticket);
      }
      return;
   }

   // Get position state index
   int stateIdx = GetPositionStateIndex(ticket);
   if(stateIdx < 0) return;

   // Use original values for calculations (not current reduced values)
   double originalVolume = positions[stateIdx].originalVolume;
   double originalOpenPrice = positions[stateIdx].originalOpenPrice;
   double originalTP = positions[stateIdx].originalTP;
   
   double range = MathAbs(originalTP - originalOpenPrice);
   double level1 = (type == POSITION_TYPE_BUY) ? originalOpenPrice + range/2.5 : originalOpenPrice - range/2.5;
   double level2 = (type == POSITION_TYPE_BUY) ? originalOpenPrice + 2.0*range/2.5 : originalOpenPrice - 2.0*range/2.5;
   double level3 = originalTP;
   double price = (type == POSITION_TYPE_BUY) ? bid : ask;

   // STEP 1: Close 1/3 of ORIGINAL volume
   if(!positions[stateIdx].step1_done)
   {
      bool trigger1 = (type == POSITION_TYPE_BUY && price >= level1) ||
                      (type == POSITION_TYPE_SELL && price <= level1);
      if(trigger1)
      {
         double closeLots = NormalizeVolume(originalVolume/3.0, symbol);
         double volumeBefore = volume;
         if(PartialCloseMT5(symbol, type, closeLots))
         {
            if(VerifyPartialClose(ticket, volumeBefore, closeLots))
            {
               positions[stateIdx].step1_done = true;
               if(DebugPrint)
                  Print("[PartialClose] [", ticket, "] Step 1: Closed 1/3 of original (", DoubleToString(closeLots,2),
                        " lots) at ", DoubleToString(level1,5));
            }
            else
            {
               if(DebugPrint) Print("[WARN] [", ticket, "] Step 1: Volume verification failed - retrying");
            }
         }
      }
   }

   // STEP 2: Close 1/3 of ORIGINAL volume, SL -> BE, TP -> +1.25 range
   if(positions[stateIdx].step1_done && !positions[stateIdx].step2_done)
   {
      bool trigger2 = (type == POSITION_TYPE_BUY && price >= level2) ||
                      (type == POSITION_TYPE_SELL && price <= level2);
      if(trigger2)
      {
         double closeLots = NormalizeVolume(originalVolume/3.0, symbol);
         double volumeBefore = volume; // Current volume after Step 1
         if(PartialCloseMT5(symbol, type, closeLots))
         {
            if(VerifyPartialClose(ticket, volumeBefore, closeLots))
            {
               double newSL = originalOpenPrice;
               double newTP = (type == POSITION_TYPE_BUY) ? originalOpenPrice + range*1.25
                                                          : originalOpenPrice - range*1.25;
               if(ModifyPositionSLTP(ticket, newSL, newTP))
               {
                  positions[stateIdx].step2_done = true;
                  if(DebugPrint)
                     Print("[PartialClose] [", ticket, "] Step 2: Closed 1/3 of original (", DoubleToString(closeLots,2),
                           " lots), SL->BE (", DoubleToString(newSL,5), "), TP extended to ", DoubleToString(newTP,5));
               }
            }
            else
            {
               if(DebugPrint) Print("[WARN] [", ticket, "] Step 2: Volume verification failed - retrying");
            }
         }
      }
   }

   // STEP 3: Move SL 80% of range when original TP is hit (keep TP at 1.25x from Step 2)
   if(positions[stateIdx].step2_done && !positions[stateIdx].step3_done)
   {
      bool trigger3 = (type == POSITION_TYPE_BUY && price >= level3) ||
                      (type == POSITION_TYPE_SELL && price <= level3);
      if(trigger3)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? originalOpenPrice + range/1.25
                                                   : originalOpenPrice - range/1.25;
         double currentTP = PositionGetDouble(POSITION_TP); // Keep TP at 1.25x from Step 2
         if(ModifyPositionSLTP(ticket, newSL, currentTP))
         {
            positions[stateIdx].step3_done = true;
            if(DebugPrint)
               Print("[PartialClose] [", ticket, "] Step 3: Price hit original TP(",
               DoubleToString(level3,5), "), SL moved to 80% of range: ",
               DoubleToString(newSL,5), ", TP kept at 1.25x: ", DoubleToString(currentTP,5));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Partial close using opposite order                                |
//+------------------------------------------------------------------+
bool PartialCloseMT5(string symbol, long type, double lots)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   // Use the already-selected position instead of searching
   ulong positionTicket = PositionGetInteger(POSITION_TICKET);
   
   if(positionTicket == 0)
   {
      if(DebugPrint) Print("[ERROR] No position found for symbol: ", symbol);
      return false;
   }

   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol,SYMBOL_BID)
                                              : SymbolInfoDouble(symbol,SYMBOL_ASK);

   req.action    = TRADE_ACTION_DEAL;
   req.position  = positionTicket;  // CRITICAL: This links to existing position
   req.symbol    = symbol;
   req.volume    = lots;
   req.type      = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = price;
   req.deviation = 10;
   req.magic     = 0;
   req.comment   = "3-Step Partial Close";

   if(!OrderSend(req, res))
   {
      if(DebugPrint) Print("[ERROR] Partial close failed: ", GetLastError(), " | Code: ", res.retcode);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Modify SL/TP of existing position                                  |
//+------------------------------------------------------------------+
bool ModifyPositionSLTP(ulong ticket, double newSL, double newTP)
{
   if(!PositionSelectByTicket(ticket)) return false;
   string symbol = PositionGetString(POSITION_SYMBOL);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);

   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = symbol;
   req.position = ticket;
   req.sl       = NormalizeDouble((newSL != 0) ? newSL : currentSL, (int)digits);
   req.tp       = NormalizeDouble((newTP != 0) ? newTP : currentTP, (int)digits);

   // Check if values actually changed
   if(req.sl == currentSL && req.tp == currentTP)
   {
      if(DebugPrint) Print("[PartialClose] No SL/TP changes needed");
      return true;
   }

   if(!OrderSend(req, res))
   {
      if(DebugPrint) Print("[WARN] Failed to modify SL/TP: ", GetLastError(), " | Code: ", res.retcode);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Verify partial close was successful                              |
//+------------------------------------------------------------------+
bool VerifyPartialClose(ulong ticket, double volumeBefore, double closeLots)
{
   Sleep(100); // Small delay to allow position update
   
   if(!PositionSelectByTicket(ticket))
   {
      if(DebugPrint) Print("[WARN] Position no longer exists after partial close - verification failed");
      return false;
   }
   
   double volumeAfter = PositionGetDouble(POSITION_VOLUME);
   double expectedVolume = volumeBefore - closeLots;
   double tolerance = 0.01; // Allow small floating point differences
   
   if(MathAbs(volumeAfter - expectedVolume) > tolerance)
   {
      if(DebugPrint) Print("[WARN] Volume mismatch! Expected: ", DoubleToString(expectedVolume, 2),
                          ", Actual: ", DoubleToString(volumeAfter, 2),
                          ", Closed: ", DoubleToString(closeLots, 2));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Normalize volume helper                                          |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots, string sym)
{
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   
   if(minLot <= 0 || lotStep <= 0) return lots; // Safety check
   
   lots = MathMin(lots, maxLot);
   double normalized = MathFloor(lots / lotStep) * lotStep;
   normalized = MathMax(normalized, minLot);
   
   return NormalizeDouble(normalized, 2);
}
//+------------------------------------------------------------------+

