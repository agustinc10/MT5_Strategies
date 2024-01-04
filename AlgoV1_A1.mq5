//+------------------------------------------------------------------+
//|                                               AlgoVictor_ac3.mq5 |
//|                                                   Agustin_202312 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, MetaQuotes Ltd."
#property link      "https://www.youtube.com/watch?v=h8lZCEpiFOI&list=PLGjfbI-PZyHW4fWaAYrSo4gRpCGNPH-ae&index=3"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>    // Include MQL trade object functions
CTrade   trade;               // Declare Trade as an object of the CTrade class in the stack  
#include "RiskCalc.mqh"
//+------------------------------------------------------------------+
//| Input variables                                                  |
//+------------------------------------------------------------------+

input group "==== General Inputs ===="
input int                  InpMagicNumber  = 2000001;       // Unique identifier for this expert advisor for EA not get confused between each other
input string               InpTradeComment = __FILE__;      // Optional comment for trades
//input ENUM_APPLIED_PRICE   InpAppliedPrice = PRICE_CLOSE;   // Applied price for indicators

input group "==== Risk Mode ===="
enum LOT_MODE_ENUM {
   LOT_MODE_FIXED,                     // fixed lots
   LOT_MODE_MONEY,                     // lots based on money
   LOT_MODE_PCT_ACCOUNT                // lots based on % of account   
};
input LOT_MODE_ENUM InpLotMode = LOT_MODE_FIXED; // lot mode
input double        InpLots    = 0.10;           // lots / money / percent

input double AtrProfitMulti    = 4.0;   // ATR Profit Multiple
input double AtrLossMulti      = 1.0;   // ATR Loss Multiple
input bool InpStopLossTrailing = true; // trailing stop loss?

input double puntos_entrada = 0;        // puntos de desfasaje en Entrada
input double puntos_salida  = 0;        // puntos de desfasaje en Salida

input group "==== Indicator Inputs ===="
input ENUM_TIMEFRAMES InpTF1 = PERIOD_CURRENT;   // Timeframe base
input ENUM_TIMEFRAMES InpTF2 = PERIOD_H4;        // Timeframe mayor

input int InpFastMA          = 5;     // fast period Base
input int InpMidMA           = 10;    // mid period Base
input int InpSlowMA          = 20;    // slow period Base
input int InpFastMA_tf2      = 10;    // fast period Mayor
input int InpSlowMA_tf2      = 20;    // slow period Mayor
input double InpERlimit      = 0.3;   // ER value

input group "==== Order Mangement===="
input int InpOrderTimer      = 15;    // Minutes for Order cancelation 

input group "==== Range Inputs ===="
input int InpRangeStart     = 120;     // range start time in minutes (after midnight). (ex: 600min is 10am)
input int InpRangeDuration  = 1140;    // range duration in minutes (ex: 120min = 2hs)
input int InpRangeClose     = 1290;    // range close time in minutes (ex: 1200min = 20hs) (-1 = off)

input group "==== Day of week filter ===="
input bool InpMonday    = true;        // range on Monday
input bool InpTuesday   = true;        // range on Tuesday
input bool InpWednesday = true;        // range on Wednesday
input bool InpThursday  = true;        // range on Thursday
input bool InpFriday    = true;        // range on Friday

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
// Get indicator values 
int fast_MA_Handle;
int mid_MA_Handle;
int slow_MA_Handle;
int fast_MAtf2_Handle;
int slow_MAtf2_Handle;
int AtrHandle;
int AtrPeriod = 14;     // ATR Period
int ERPeriod  = 10;     // Efficiency Ratio Period

double fast_MA_Buffer[];    // to receive/store the indicator values, define a dynamic array
double mid_MA_Buffer[];  
double slow_MA_Buffer[];
double fast_MAtf2_Buffer[];
double slow_MAtf2_Buffer[];
double AtrBuffer[];

double Open[];
double High[];
double Low[];
double Close[];

double AtrCurrent;

// "All the variables for the range we'll put them together in a structure"
struct RANGE_STRUCT
{
   datetime start_time;    // start of the range
   datetime end_time;      // end of the range
   datetime close_time;    // close time (where we will close the trades)
   //double high;            // high of the range             
   //double low;             // low of the range
   bool f_entry;           // flag if we are in the range 
   //bool f_high_breakout;   // flag if a high breakout occurred
   //bool f_low_breakout;    // flag if a low breakout occurred
   
   // "define a constructor for the structue, and here we just predifine our variables"
   RANGE_STRUCT(): start_time(0), end_time(0), close_time(0), f_entry(false) {};
};

RANGE_STRUCT range;
MqlTick prevTick, lastTick;

ENUM_ORDER_TYPE OrderType;
static datetime TimeLastTickProcessed; // Stores the last time a tick was processed based off candle opens

double ENTRY = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
// OnInit gets called every time the EA is started

int OnInit(){ 
    
   if (!CheckInputs()) return INIT_PARAMETERS_INCORRECT; // check correct input from user
   
   trade.SetExpertMagicNumber(InpMagicNumber);           // set magicnumber
   
   if (!SetHandles()) return INIT_FAILED;                // set handles 
  
   ArraySetAsSeries(fast_MA_Buffer,true);             // With SetAsSeries the index starts from 0 in the current bar, n for the oldest bar
   ArraySetAsSeries(mid_MA_Buffer,true);              // If it is NOT SetAsSeries, the oldest bar is 0 and the current bar is n   
   ArraySetAsSeries(slow_MA_Buffer,true);  
   ArraySetAsSeries(fast_MAtf2_Buffer,true);  
   ArraySetAsSeries(slow_MAtf2_Buffer,true);  
   ArraySetAsSeries(AtrBuffer,true);
   ArraySetAsSeries(Open,true);
   ArraySetAsSeries(High,true);
   ArraySetAsSeries(Low,true);
   ArraySetAsSeries(Close,true);
   
   // Calculate new range if input changes -- "if parameters change we want to calculate a new range" 
   // -> this is to be able to change the range after the EA is already in the chart with a range calculated
   // we should only do this if there is no position open   
   if (_UninitReason == REASON_PARAMETERS && CountOpenPosition() == 0) CalculateRange();                            
   DrawObjects();    // If we change timeframes, I want the objects to appear in the new timeframe
   
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
// This function is called only once, "when the EA is unloaded from the chart"
void OnDeinit(const int reason){
   
   if (fast_MA_Handle    != INVALID_HANDLE) { IndicatorRelease(fast_MA_Handle); }
   if (mid_MA_Handle     != INVALID_HANDLE) { IndicatorRelease(mid_MA_Handle); }   
   if (slow_MA_Handle    != INVALID_HANDLE) { IndicatorRelease(slow_MA_Handle); }
   if (fast_MAtf2_Handle != INVALID_HANDLE) { IndicatorRelease(fast_MAtf2_Handle); }
   if (slow_MAtf2_Handle != INVALID_HANDLE) { IndicatorRelease(slow_MAtf2_Handle); } 
   if (AtrHandle         != INVALID_HANDLE) { IndicatorRelease(AtrHandle); }
    
   Print("Handles released");
   Comment("");
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
// This function is called every time there is a new price
void OnTick(){
         
   copy_buffers();
          
   flagtendencia();       
             
   // Print ("### Valor de Efficiency Ratio= ", ER(RequiredOHLC));
   
   // Quick check if trading is possible
   if (!IsTradeAllowed()) return;      
   // Also exit if the market may be closed
   // https://youtu.be/GejPtodJow
   if( !IsMarketOpen(_Symbol, TimeCurrent())) return;

   // Checks for new candle   
   bool IsNewCandle = false;
   if (TimeLastTickProcessed != iTime(_Symbol, _Period, 0))
   {
      IsNewCandle = true;
      TimeLastTickProcessed = iTime(_Symbol, _Period, 0); //Variable updates every time a bar opens    
   }
   
   // If there is a new candle, delete old orders
   // I only run the code if it is a new candle (instead of only a new tick)
   if (IsNewCandle == true) DeleteOrders();
      
   
   // Close orders if old
   // DeleteOrdersByTimer();
   
   // Get current tick
   prevTick = lastTick;
   SymbolInfoTick(_Symbol, lastTick); 
   
   // Close positions if out of RangeClose
   if(lastTick.time >= range.start_time && lastTick.time < range.end_time)
      range.f_entry = true; // set flag (we know we had a tick in the range)
      else range.f_entry = false;
    
   if (InpRangeClose >= 0 && lastTick.time >= range.close_time) {
      if(!ClosePositions()) return;
      else Print ("Close because out of range");
   }  
     
   // Close positions and orders
   ClosePositions(POSITION_TYPE_BUY);   
   ClosePositions(POSITION_TYPE_SELL);   
   DeleteOrders (ORDER_TYPE_BUY_STOP);
   DeleteOrders (ORDER_TYPE_SELL_STOP);

   // Calculate new range if...
   if (((InpRangeClose >= 0 && lastTick.time >= range.close_time)                     // close time reached
      || (range.end_time == 0)                                                        // range not calculated yet
      || (range.end_time != 0 && lastTick.time > range.end_time && !range.f_entry))   // there was a range calculated but no tick inside
      && (CountOpenPosition() == 0))
   {
      CalculateRange();      
   }
   
   double mylots;
   // Open position
   createorder(mylots);
   // update stop loss
   UpdateStopLoss();   
   
   //to display the values on the screen
   //comments();
              
}

//+------------------------------------------------------------------+
//| COMMENTS |||||||||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    

void comments(){
   Comment("BASE   Fast MA   /   Mid MA   /   Slow MA\n",
           "[1]:   ", NormalizeDouble(fast_MA_Buffer[1], _Digits), "   /   ", NormalizeDouble(mid_MA_Buffer[1], _Digits), "   /   ", NormalizeDouble(slow_MA_Buffer[1], _Digits),"\n",
           "[2]:   ", NormalizeDouble(fast_MA_Buffer[2], _Digits), "   /   ", NormalizeDouble(mid_MA_Buffer[2], _Digits), "   /   ", NormalizeDouble(slow_MA_Buffer[2], _Digits),"\n\n",
           "MAYOR   Fast MA   /   Slow MA\n",
           "[1]:   ", NormalizeDouble(fast_MAtf2_Buffer[1], _Digits), "   /   ", NormalizeDouble(slow_MAtf2_Buffer[1], _Digits),"\n",
           "[2]:   ", NormalizeDouble(fast_MAtf2_Buffer[2], _Digits), "   /   ", NormalizeDouble(slow_MAtf2_Buffer[2], _Digits),"\n\n",
           "       Open   /   High   /   Low   /   Close\n",
           "[1]:   ", NormalizeDouble(Open[1], _Digits), "   /   ", NormalizeDouble(High[1], _Digits), "   /   ", NormalizeDouble(Low[1], _Digits), "   /   ", NormalizeDouble(Close[1], _Digits),"\n",
           "[2]:   ", NormalizeDouble(Open[2], _Digits), "   /   ", NormalizeDouble(High[2], _Digits), "   /   ", NormalizeDouble(Low[2], _Digits), "   /   ", NormalizeDouble(Close[2], _Digits),"\n\n",
           "       ATR\n", 
           "[1]:   ", NormalizeDouble(AtrBuffer[1], _Digits), "\n",
           "[2]:   ", NormalizeDouble(AtrBuffer[2], _Digits), "\n\n"
           "Open Positions: ", CountOpenPosition(), "\n",
           "Range Flag:     ", range.f_entry, "\n",
           "Eff. Ratio:     ", ER(ERPeriod), "\n",
           "Tendencia:      ", flagtendencia(), "\n");
}

//+------------------------------------------------------------------+
//| CHECK INPUTS |||||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+
 
bool CheckInputs() {
   // check for correct input from user
   if (InpMagicNumber <= 0)                                                   { Alert ("Magicnumber <= 0"); return false; }
   if (InpLotMode == LOT_MODE_FIXED && (InpLots <= 0 || InpLots > 5))         { Alert ("Lots <= 0 or > 5"); return false; }
   if (InpLotMode == LOT_MODE_MONEY && (InpLots <= 0 || InpLots > 500))       { Alert ("Money <= 0 or > 500"); return false; }
   if (InpLotMode == LOT_MODE_PCT_ACCOUNT && (InpLots <= 0 || InpLots > 2))   { Alert ("Percent <= 0 or > 2"); return false; }   
   /*if ((InpLotMode == LOT_MODE_MONEY || InpLotMode == LOT_MODE_PCT_ACCOUNT) && InpStopLoss == 0){ Alert ("Selected lot mode needs a stop loss"); return false; }        
   if (InpStopLoss < 0 || InpStopLoss > 1000){ Alert ("Stop Loss <= 0 or > 1000"); eturn false; }   
   if (InpTakeProfit < 0 || InpTakeProfit > 1000){ Alert ("Take profit <= 0 or > 1000"); return false; }
   */
   if (InpRangeClose < 0 && AtrLossMulti == 0)           { Alert ("Both close time and stop loss are off"); return false; }   
   if (InpRangeStart < 0 || InpRangeStart >= 1440)       { Alert ("Range start < 0 or >= 1440"); return false; }   
   if (InpRangeDuration < 0 || InpRangeDuration >= 1440) { Alert ("Range duration < 0 or >= 1440"); return false; } 
   
   // Start + Duration puede ser > a un día, entonces uso el % para comparar que el cierre no coincida   
   if (InpRangeClose < -1 || InpRangeClose >= 1440 || (InpRangeStart + InpRangeDuration) % 1440 == InpRangeClose){ 
      Alert ("Range close < 0 or >= 1440 or end time == close time");
      return false;
   }
   if (InpMonday + InpTuesday + InpWednesday + InpThursday + InpFriday == 0){ Alert ("Range is prohibited on all days of the week"); return false; }   
   
   if (InpFastMA <= 0)     { Alert("Fast MA <= 0"); return false;}
   if (InpMidMA <= 0)      { Alert("Mid MA <= 0");  return false;}
   if (InpSlowMA <= 0)     { Alert("Slow MA <= 0"); return false;}
   if (InpFastMA_tf2 <= 0) { Alert("Fast MA_tf2 <= 0"); return false;}   
   if (InpSlowMA_tf2 <= 0) { Alert("Slow MA_tf2 <= 0"); return false;}
    
   if (InpSlowMA <= InpMidMA || InpMidMA <= InpFastMA)   { Alert("Fast MA >= Mid MA  or Mid MA >= Slow MA"); return false; }
   if (InpSlowMA_tf2 <= InpFastMA_tf2 )                  { Alert("Fast MA_tf2 >= Slow MA_tf2"); return false; }
   
   if (AtrLossMulti <= 0)     { Alert("AtrLossMulti <= 0"); return false;}
   if (AtrProfitMulti <= 0)   { Alert("AtrProfitMulti <= 0");  return false;}
   
   return true;
}

//+------------------------------------------------------------------+
//| SET HANNDLES |||||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    
 
bool SetHandles() {
   // set Handles only once in the OnInit function and check if function failed
   fast_MA_Handle = iMA(_Symbol,InpTF1, InpFastMA,0,MODE_SMA,PRICE_CLOSE);
   if (fast_MA_Handle == INVALID_HANDLE) { Alert("Failed to create Fast MA Handle"); return false; }

   mid_MA_Handle = iMA(_Symbol,InpTF1, InpMidMA,0,MODE_SMA,PRICE_CLOSE);
   if (mid_MA_Handle == INVALID_HANDLE) { Alert("Failed to create Mid MA Handle"); return false; }

   slow_MA_Handle = iMA(_Symbol,InpTF1, InpSlowMA,0,MODE_SMA,PRICE_CLOSE);
   if (slow_MA_Handle == INVALID_HANDLE) { Alert("Failed to create Slow MA Handle"); return false; }

   fast_MAtf2_Handle = iMA(_Symbol,InpTF2, InpFastMA_tf2,0,MODE_SMA,PRICE_CLOSE);
   if (fast_MAtf2_Handle == INVALID_HANDLE) { Alert("Failed to create Fast MA_tf2 Handle"); return false; }

   slow_MAtf2_Handle = iMA(_Symbol,InpTF2, InpSlowMA_tf2,0,MODE_SMA,PRICE_CLOSE);
   if (slow_MAtf2_Handle == INVALID_HANDLE) { Alert("Failed to create Slow MA_tf2 Handle"); return false; }
   
   AtrHandle= iATR(_Symbol,InpTF1, AtrPeriod);
   if (slow_MAtf2_Handle == INVALID_HANDLE) { Alert("Failed to create HandleAtr"); return false; }     
   
   return true;   
}   

//+------------------------------------------------------------------+
//| COPY BUFFERS |||||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    
 
void copy_buffers(){   

   // Set symbol string and indicator buffers
   const int StartCandle      = 0;
   const int RequiredCandles  = 5; // How many candles are required to be stored in Expert - [current confirmed, not confirmed] if StartCandle=0
   int RequiredOHLC     = ERPeriod + 1;
   const int Index            = 0; 
   
   
   //Get indicator values
   int values = CopyBuffer(slow_MA_Handle, Index, StartCandle, RequiredCandles, slow_MA_Buffer);  
   if (values!= RequiredCandles){ Print("Not enough data for slow_MA"); return;}

   values = CopyBuffer(mid_MA_Handle, Index, StartCandle, RequiredCandles, mid_MA_Buffer);  
   // if (values != RequiredCandles){ Print("Not enough data for mid_MA"); return;}

   values = CopyBuffer(fast_MA_Handle, Index, StartCandle, RequiredCandles, fast_MA_Buffer);   
   // if (values!= RequiredCandles){ Print("Not enough data for fast_MA"); return;}   
   
   values = CopyBuffer(slow_MAtf2_Handle, Index, StartCandle, RequiredCandles, slow_MAtf2_Buffer);  
   if (values!= RequiredCandles){ Print("Not enough data for slow_MAtf2"); return;}

   values = CopyBuffer(fast_MAtf2_Handle, Index, StartCandle, RequiredCandles, fast_MAtf2_Buffer);  
   // if (values!= RequiredCandles){ Print("Not enough data for fast_MAtf2"); return;}
      
   values = CopyBuffer(AtrHandle, Index, StartCandle, RequiredCandles, AtrBuffer);  
   if (values!= RequiredCandles){ Print("Not enough data for ATR"); return;}
   AtrCurrent = NormalizeDouble(AtrBuffer[1], _Digits);
   // Print("ATR: ", AtrCurrent);

   values = CopyClose(_Symbol, InpTF1, StartCandle, RequiredOHLC, Close);
   if (values!= RequiredOHLC){ Print("Not enough data for Close"); return;}
   values = CopyOpen(_Symbol, InpTF1, StartCandle, RequiredOHLC, Open);
   // if (values!= RequiredOHLC){ Print("Not enough data for Open"); return;}   
   values = CopyHigh(_Symbol, InpTF1, StartCandle, RequiredCandles, High);
   // if (values!= RequiredOHLC){ Print("Not enough data for High"); return;}
   values = CopyLow(_Symbol, InpTF1, StartCandle, RequiredCandles, Low);
   // if (values!= RequiredOHLC){ Print("Not enough data for Low"); return;}   
}

//+------------------------------------------------------------------+
//| Custom function - GET POSITION TICKET ||||||||||||||||||||||||||||
//+------------------------------------------------------------------+ 
bool GetPosTicket(int i, ulong ticket){      
   if (ticket <= 0) { Print ("ERROR_ac: Failed to get position ticket!"); return false; }
   if (!PositionSelectByTicket(ticket)) { Print ("ERROR_ac: Failed to select position by ticket"); return false; } // "I like to selectPosition again (...) This updates the position data so we make sure we get a fresh position data"
   long magicnumber;
   if (!PositionGetInteger(POSITION_MAGIC, magicnumber)) { Print ("ERROR_ac: Failed to get position magicnumber"); return false; } // Gets the value of POSITION_MAGIC and puts it in magicnumber
   if (magicnumber == InpMagicNumber)
      return true;
   return true;
}

//+------------------------------------------------------------------+
//| Custom function - GET ORDER TICKET ||||||||||||||||||||||||||||
//+------------------------------------------------------------------+ 
bool GetOrTicket(int i, ulong ticket){      
   if (ticket <= 0) { Print ("ERROR_ac: Failed to get order ticket!"); return false; }
   if (!OrderSelect(ticket)) { Print ("ERROR_ac: Failed to select order by ticket"); return false; } // "I like to selectPosition again (...) This updates the position data so we make sure we get a fresh position data"
   long magicnumber;
   if (!OrderGetInteger(ORDER_MAGIC, magicnumber)) { Print ("ERROR_ac: Failed to get order magicnumber"); return false; } // Gets the value of POSITION_MAGIC and puts it in magicnumber
   if (magicnumber == InpMagicNumber)
      return true;
   return true;
}
         
//+------------------------------------------------------------------+
//| Custom function - COUNT POSITIONS ||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+ 
int CountOpenPosition()
{
   int counter = 0;
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);   // Select position
      if(GetPosTicket(i, ticket)) counter++;  
   }
   return counter;
}

//+------------------------------------------------------------------+
//| Custom function - COUNT OPEN ORDERS ||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+ 
int CountOpenOrders()
{
   int counter = 0;
   int total = OrdersTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if (ticket <= 0) { Print ("ERROR_ac: Failed to get order ticket"); return -1; }
      if(GetOrTicket(i, ticket)) counter++;      
   }
   return counter;
}

//+------------------------------------------------------------------+
//| Custom function - CLOSE POSITIONS ||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    

bool ClosePositions() // ENUM_POSITION_TYPE positiontype
{
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)      // Important to count down to close positions. Counting up can lead to leave positions open
   {
      if( total != PositionsTotal()) { total = PositionsTotal(); i = total; continue; }     // Check that during the loop no new positions were opened (by another EA for example)
      ulong ticket = PositionGetTicket(i);   // Select position
      if (GetPosTicket(i, ticket)){
         trade.PositionClose(ticket);
         if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
         {
            Print ("ERROR_ac: Failed to close position. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
            return false;     
         }        
      }      
   }
   return true;
}
 
/////////////////////////////////////////////////
bool ClosePositions(ENUM_POSITION_TYPE positiontype) // ENUM_POSITION_TYPE positiontype
{
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)      // Important to count down to close positions. Counting up can lead to leave positions open
   {
      if( total != PositionsTotal()) { total = PositionsTotal(); i = total; continue; }     // Check that during the loop no new positions were opened (by another EA for example)
      ulong ticket = PositionGetTicket(i);   // Select position
      if (GetPosTicket(i, ticket) ){
         if (PositionGetDouble(POSITION_PROFIT) > 0){
            if (PositionGetInteger(POSITION_TYPE) == positiontype 
               && positiontype == POSITION_TYPE_BUY
               && fast_MA_Buffer[1] < mid_MA_Buffer[1]               
               && Close[1] < Open[1]){ 
               trade.PositionClose(ticket);
               if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
               {
                  Print ("ERROR_ac: Failed to close position. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
                  return false;     
               }
               Print ("Close position in profit with SMA crossover and opposite candle");
            }
            if (PositionGetInteger(POSITION_TYPE) == positiontype 
               && positiontype == POSITION_TYPE_SELL
               && fast_MA_Buffer[1] > mid_MA_Buffer[1]
               && Close[1] > Open[1]){ 
               trade.PositionClose(ticket);
               if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
               {
                  Print ("ERROR_ac: Failed to close position. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
                  return false;     
               }
               Print ("Close position in profit with SMA crossover and opposite candle");               
            }
         }
      }
      
   }
   return true;
}

//+------------------------------------------------------------------+
//| Custom function - CALCULATE LOTS |||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+  

//https://www.youtube.com/watch?v=UFFTlc0Ysy4&list=PLGjfbI-PZyHW4fWaAYrSo4gRpCGNPH-ae&index=10
bool CalculateLots(double slDistance, double &mylots)      // Pass lots as a reference (&) so we can modify it inside the function
{
   mylots = 0.0;
   if(InpLotMode == LOT_MODE_FIXED) {
      mylots = InpLots;
   }   
   else
   {
      string symbol      = _Symbol;
      double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);         // https://www.mql5.com/en/articles/2555#invalid_lot
              
      // Calculate risk based off entry and stop loss level by pips
      double Riskpercent = InpLotMode == LOT_MODE_MONEY ? InpLots / AccountInfoDouble(ACCOUNT_EQUITY) : InpLots * 0.01;
      double RiskAmount  = InpLotMode == LOT_MODE_MONEY ? InpLots : AccountInfoDouble(ACCOUNT_EQUITY) * InpLots * 0.01;

      double lots = NormalizeDouble(PercentRiskLots(symbol, Riskpercent, slDistance ), 2);
      
      mylots = (int)MathFloor(lots/volume_step) * volume_step;
                         
   }   
   // check calculated lots
   string desc;
   if (!CheckVolumeValue(mylots, desc)) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| CREATE ORDERS ||||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+

void createorder(double &mylots){
   // Check general conditions
   static datetime openTime = 0;
   if (IsNewOrderAllowed() && CountOpenPosition() == 0 && range.f_entry == true && ER(ERPeriod) >= InpERlimit && CountOpenOrders() == 0) { 
      //if (openTime != iTime(_Symbol,PERIOD_CURRENT,0)) {
         double sldistance = MathMax(AtrCurrent * AtrLossMulti, 100 * _Point);   // SL es como mínimo 10 pips
         
         string symbol = _Symbol;
         int digits    = _Digits;
         // check BUY conditions   
         if (openorder() == "buy"){
           // openTime = iTime(_Symbol,PERIOD_CURRENT,0);
            double price = High[1] + puntos_entrada*_Point;
            ENTRY = price;
            // double price  = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
            double sl    = NormalizeDouble(Low[1] - sldistance - puntos_salida*_Point, digits);
            sldistance   = NormalizeDouble(MathAbs(price - sl), digits);
            double tp    = NormalizeDouble(price + sldistance * AtrProfitMulti - puntos_salida*_Point, digits);

            if (!CalculateLots(sldistance, mylots)) return;

            if (!Checkstoplevels(sldistance, sldistance * AtrProfitMulti - puntos_salida*_Point)) return;                                             
            if (!CheckMoneyForTrade(symbol, mylots, ORDER_TYPE_BUY)) return;
            
            // OrderType = ORDER_TYPE_BUY_STOP;              
            // trade.PositionOpen(_Symbol, OrderType, mylots,price,sl,tp,"BUY SMA ordenadas");   // No funciona por algún motivo
            
            if (// High[0] < price &&                                                                  // Si en la misma vela se cerró una posición anterior, cuando se activa la nueva orden puede pasar que la vela ya haya pasado el precio de entrada
                                                                                                 // Para ser más flexible, podría usar el lastTick en vez del High        
               price > lastTick.ask) {                                                        // No puedo colocar la orden si el precio stop no está encima del ask.
               //DeleteOrders();                                                                   
               trade.BuyStop(mylots, price, symbol, sl, tp, ORDER_TIME_GTC, 0, "Orden BUY");
               /*PrintFormat("BUY_STOP ORDER - price = %f, sl = %f, tp = %f, ER = %f, ATR = %f",
                        price, sl, tp, ER(ERPeriod), AtrCurrent);
               */
            }
         } else
         
         // check SELL conditions
         if (openorder() == "sell"){
           // openTime = iTime(_Symbol,PERIOD_CURRENT,0); 
            double price = Low[1] - puntos_entrada*_Point;   //double bid   = SymbolInfoDouble(_Symbol,SYMBOL_BID);
            ENTRY = price;
            // double price  = SymbolInfoDouble(_Symbol,SYMBOL_BID);            
            double sl    = NormalizeDouble(High[1] + sldistance + puntos_salida*_Point, digits);
            sldistance   = NormalizeDouble(MathAbs(price - sl), digits);
            double tp    = NormalizeDouble(price - sldistance * AtrProfitMulti + puntos_salida*_Point,digits);

            if (!CalculateLots(sldistance, mylots)) return;

            if (!Checkstoplevels(sldistance, sldistance * AtrProfitMulti+ puntos_salida*_Point)) return;                                             
            if (!CheckMoneyForTrade(symbol, mylots, ORDER_TYPE_SELL)) return;         
            
            // OrderType = ORDER_TYPE_SELL_STOP;        
            //trade.PositionOpen(_Symbol, OrderType,mylots,price,sl,tp,"SELL SMA ordenadas");      
            if (//Low[0] > price && 
               price < lastTick.bid){
               //DeleteOrders();
               trade.SellStop(mylots, price, symbol, sl, tp, ORDER_TIME_GTC, 0, "Orden SELL");
               /*PrintFormat("SELL_STOP ORDER - price = %f, sl = %f, tp = %f, ER = %f, ATR = %f",
                  price, sl, tp, ER(ERPeriod), AtrCurrent);  
               */
            }
         }
      //}
   }
}

//+------------------------------------------------------------------+
//| Custom function - UPDATE STOP LOSS |||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    

void UpdateStopLoss()
{
   // return if no stop loss or fixed stop loss
   if (AtrLossMulti == 0 || !InpStopLossTrailing) return;
   int digits = _Digits;
   // loop through open positions
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (GetPosTicket(i, ticket)){    
         // get type of position
         long type;
         if (!PositionGetInteger(POSITION_TYPE, type)) { Print ("ERROR_ac: Failed to get position type"); return; }
         // get current sl and tp
         double currSL, currTP;
         if (!PositionGetDouble(POSITION_SL, currSL)) { Print ("ERROR_ac: Failed to get position stop loss"); return; }
         if (!PositionGetDouble(POSITION_TP, currTP)) { Print ("ERROR_ac: Failed to get position take profit"); return; }
        
         // calculate stop loss
         double ProfitCurr, entry;         
         if (!PositionGetDouble(POSITION_PRICE_OPEN, entry)) { Print ("ERROR_ac: Failed to get position entry price"); return; }
         double currPrice = type == POSITION_TYPE_BUY ? lastTick.bid : lastTick.ask;
         int n            = type == POSITION_TYPE_BUY ? 1 : -1;        
         
         entry = NormalizeDouble(ENTRY, digits);

         ProfitCurr = NormalizeDouble(MathAbs(currPrice - entry), digits);
                 
         //if (ProfitCurr <= MathAbs(entry - currSL)) return;
         if (ProfitCurr < NormalizeDouble(MathAbs(entry - currSL), digits)) return;
         
         double newSL1 = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), digits);
         double newSL2 = type == POSITION_TYPE_BUY ? NormalizeDouble(mid_MA_Buffer[3] - puntos_salida * _Point, digits) : NormalizeDouble(mid_MA_Buffer[3] + puntos_salida * _Point, digits);        
         double newSL  = 0; 
         if (type == POSITION_TYPE_BUY)
            newSL = newSL1 >= newSL2 ? newSL1 : newSL2;
         if (type == POSITION_TYPE_SELL)
            newSL = newSL1 <= newSL2 ? newSL1 : newSL2;
                
         // if we modify the position with the same SL value, we get an error, so we have to check if newSL != currSL
         // check if new stop loss is closer to current price than existing stop loss
         if ((newSL * n) <= (currSL*n) || NormalizeDouble(MathAbs(newSL - currSL), digits) < _Point){
            //Print("No new stop loss needed");
            continue;
         }
         
         if ((newSL * n) >= (currPrice * n)){                              // Si el precio retrocedió pasando la MA[3], no puedo modificar el SL
            Print("Can't modify SL because price crossed possible NewSL");
            continue; 
         }
         
         if (!Checkstoplevels(NormalizeDouble(MathAbs(currPrice - newSL), digits), NormalizeDouble(MathAbs(currPrice - currTP), digits))) return;         
         
         // modify position with new stop loss
         if(!trade.PositionModify(ticket, newSL, currTP)) {
            Print("ERROR_ac: Failed to modify position, ticket: ", (string) ticket, " / currSL: ", (string) currSL, 
                  " / newSL: ", (string) newSL, " / currTP: ", (string) currTP,
                  " / bid: ", (string) lastTick.bid, " / ask: ", (string) lastTick.ask);                         
            return;
         }         

      }                    
   }      
}


//+------------------------------------------------------------------+
//| Custom function - CALCULATE TIME RANGE |||||||||||||||||||||||||||
//+------------------------------------------------------------------+    

void CalculateRange()
{
   // Reset all range variables 
   range.start_time        = 0;
   range.end_time          = 0;
   range.close_time        = 0;
   range.f_entry           = false; 

   // calculate range start time
   int time_cycle = 86400;                                                                   // seconds in a day
   range.start_time = (lastTick.time - (lastTick.time % time_cycle)) + InpRangeStart * 60;   // calculates the start of each day and sums the InpRangeStart
   // for loop to shift the start time to the next working day (skipping saturday and sunday)
   for (int i = 0; i < 8; i++)                                                               
   {
      MqlDateTime tmp;                          // The date type structure contains eight fields of the int type
      TimeToStruct (range.start_time, tmp);     // Converts a value of datetime type (number of seconds since 01.01.1970) into a structure variable MqlDateTime.
      int dow = tmp.day_of_week;
      if (lastTick.time >= range.start_time || dow == 6 || dow == 0 
         || (dow == 1 && !InpMonday) || (dow == 2 && !InpTuesday) || (dow == 3 && !InpWednesday) || (dow == 4 && !InpThursday) || (dow == 5 && !InpFriday))
         range.start_time += time_cycle;       
   }
   
   // calculate range end time
   range.end_time = range.start_time + InpRangeDuration * 60; // If the range end goes to another day and that day is weekend, we have to shift it to monday
   for (int i = 0; i < 2; i++)
   {
      MqlDateTime tmp;                        // The date type structure contains eight fields of the int type
      TimeToStruct (range.end_time, tmp);     // Converts a value of datetime type (number of seconds since 01.01.1970) into a structure variable MqlDateTime.
      int dow = tmp.day_of_week;
      if (dow == 6 || dow == 0)
         range.end_time += time_cycle;       
   }

   // calculate range close
   if(InpRangeClose >= 0)
   {
      range.close_time = (range.end_time - (range.end_time % time_cycle)) + InpRangeClose * 60;   // calculates the close of each day and sums the InpRangeClose
      for (int i = 0; i < 3; i++)
      {
         MqlDateTime tmp;                        // The date type structure contains eight fields of the int type
         TimeToStruct (range.close_time, tmp);     // Converts a value of datetime type (number of seconds since 01.01.1970) into a structure variable MqlDateTime.
         int dow = tmp.day_of_week;
         if (range.close_time <= range.end_time || dow == 6 || dow == 0)
            range.close_time += time_cycle;       
      }
   }
   // draw object
   DrawObjects();
} 


//+------------------------------------------------------------------+
//| Custom function - DRAW OBJECTS |||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    

void DrawObjects()
{
   // start time
   ObjectDelete(NULL, "range start");     // We always want to draw a new start time
   if (range.start_time > 0)               // Check if there is a start time calculated
   {
      ObjectCreate(NULL, "range start", OBJ_VLINE, 0, range.start_time, 0);         // Create a vertical line in the current chart named "range start" at range.start_time
      ObjectSetString(NULL, "range start", OBJPROP_TOOLTIP, "start of the range \n" + TimeToString(range.start_time, TIME_DATE|TIME_MINUTES));  // Set description for the object
      ObjectSetInteger(NULL, "range start", OBJPROP_COLOR, clrBlue);                // Change Color
      ObjectSetInteger(NULL, "range start", OBJPROP_WIDTH, 2);                      // Change width of drawing
      ObjectSetInteger(NULL, "range start", OBJPROP_BACK, true);                    // Set object to background                 
   }
   
   // end time
   ObjectDelete(NULL, "range end");     // We always want to draw a new end time
   if (range.end_time > 0)               // Check if there is a end time calculated
   {
      ObjectCreate(NULL, "range end", OBJ_VLINE, 0, range.end_time, 0);           // Create a vertical line in the current chart named "range end" at range.end_time
      ObjectSetString(NULL, "range end", OBJPROP_TOOLTIP, "end of the range \n" + TimeToString(range.end_time, TIME_DATE|TIME_MINUTES));  // Set description for the object
      ObjectSetInteger(NULL, "range end", OBJPROP_COLOR, clrBlue);                // Change Color
      ObjectSetInteger(NULL, "range end", OBJPROP_WIDTH, 2);                      // Change width of drawing
      ObjectSetInteger(NULL, "range end", OBJPROP_BACK, true);                    // Set object to background                 
   }   

   // close time
   ObjectDelete(NULL, "range close");     // We always want to draw a new close time
   if (range.close_time > 0)               // Check if there is a close time calculated
   {
      ObjectCreate(NULL, "range close", OBJ_VLINE, 0, range.close_time, 0);         // Create a vertical line in the current chart named "range close" at range.close_time
      ObjectSetString(NULL, "range close", OBJPROP_TOOLTIP, "close of the range \n" + TimeToString(range.close_time, TIME_DATE|TIME_MINUTES));  // Set description for the object
      ObjectSetInteger(NULL, "range close", OBJPROP_COLOR, clrRed);                 // Change Color
      ObjectSetInteger(NULL, "range close", OBJPROP_WIDTH, 2);                      // Change width of drawing
      ObjectSetInteger(NULL, "range close", OBJPROP_BACK, true);                    // Set object to background                 
   }   

   // refresh chart
   ChartRedraw();
   
} 

//+------------------------------------------------------------------+
//| Custom function - KAUFMAN EFFICIENCY RATIO |||||||||||||||||||||||
//+------------------------------------------------------------------+    

//Calculo del Kaufman Efficiency Ratio, voy a hacerlo para 10 velas
//ER= abs(close[1] - open[10])/ sumatoria de diferencias de close y open de todas las velas entre 1 y 10
double ER (int erperiod){ 
   double NumEF = 0;
   double DenEF = 0;
   NumEF = MathAbs(Close[1] - Open[erperiod]);
   for (int i = 1; i < (erperiod + 1); i++){
      DenEF += MathAbs(Close[i] - Open[i]);
   }
   return NormalizeDouble(NumEF/DenEF,_Digits);
}

//+------------------------------------------------------------------+
//| CHECK TENDENCIA ||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+

int flagtendencia(){
   static int FlagTendencia = 0;
   if (fast_MAtf2_Buffer[1] > slow_MAtf2_Buffer[1]
      && fast_MAtf2_Buffer[2] > slow_MAtf2_Buffer[2]
      && fast_MAtf2_Buffer[1] > fast_MAtf2_Buffer[2]){
      FlagTendencia = 1;                                     // Set Flag de tendencia alcista
   }

   if (fast_MAtf2_Buffer[1] < slow_MAtf2_Buffer[1]
      && fast_MAtf2_Buffer[2] < slow_MAtf2_Buffer[2]
      && fast_MAtf2_Buffer[1] < fast_MAtf2_Buffer[2]){
      FlagTendencia = -1;                                    // Set Flag de tendencia bajista
   }   
   
   if (FlagTendencia == 1 && fast_MAtf2_Buffer[1] < slow_MAtf2_Buffer[1]) {
      FlagTendencia = 0;                                    // Reset Tendencia
      }      

   if (FlagTendencia == -1 && fast_MAtf2_Buffer[1] > slow_MAtf2_Buffer[1]) {
      FlagTendencia = 0;                                    // Reset Tendencia
      }   
   return FlagTendencia;
}
//+------------------------------------------------------------------+
//| CONDICIONES BUY & SELL |||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+

string openorder(){

   // check BUY conditions   
   if(flagtendencia() == 1                               // Flag Tendencia positiva
      && fast_MA_Buffer[1] > mid_MA_Buffer[1] 
      && mid_MA_Buffer[1] > slow_MA_Buffer[1]          // MA 15min ordenadas
      && Close[1] < Open[1])                           // Vela trigger contra tendencia
         return "buy"; 
           
   else // check SELL conditions 
   if(flagtendencia() == -1                               // Flag Tendencia negativa
      && fast_MA_Buffer[1] < mid_MA_Buffer[1] 
      && mid_MA_Buffer[1] < slow_MA_Buffer[1] 
      && Close[1] > Open[1]) 
         return "sell";
   else
      return "no order";
}

//+------------------------------------------------------------------+
//| Custom function - DELETE ORDERS ||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+    

bool DeleteOrders()
{
   int total = OrdersTotal();
   for (int i = total - 1; i >= 0; i--)      // Important to count down to close positions. Counting up can lead to leave positions open
   {
      if( total != OrdersTotal()) { total = OrdersTotal(); i = total; continue; }     // Check that during the loop no new positions were opened (by another EA for example)
      ulong ticket = OrderGetTicket(i);   // Select position
      if (GetOrTicket(i, ticket)){
         trade.OrderDelete(ticket);
         if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
         {
            Print ("ERROR_ac: Failed to delete order. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
            return false;     
         }
      }
      
   }
   return true;
}
////////////////////////////////////////////
bool DeleteOrders(ENUM_ORDER_TYPE ordertype)
{
   int total = OrdersTotal();
   for (int i = total - 1; i >= 0; i--)      // Important to count down to close positions. Counting up can lead to leave positions open
   {
      if( total != OrdersTotal()) { total = OrdersTotal(); i = total; continue; }     // Check that during the loop no new positions were opened (by another EA for example)
      ulong ticket = OrderGetTicket(i);   // Select position
      if (GetOrTicket(i, ticket)){
         if (OrderGetInteger(ORDER_TYPE) == ordertype && ordertype== ORDER_TYPE_BUY_STOP){
            if (fast_MA_Buffer[1] <= mid_MA_Buffer[1] || mid_MA_Buffer[1] <= slow_MA_Buffer[1]){ 
               trade.OrderDelete(ticket);
               if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
               {
                  Print ("ERROR_ac: Failed to delete order. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
                  return false;     
               }
            }
         }
         if (OrderGetInteger(ORDER_TYPE) == ordertype && ordertype== ORDER_TYPE_SELL_STOP){
            if (fast_MA_Buffer[1] >= mid_MA_Buffer[1] || mid_MA_Buffer[1] >= slow_MA_Buffer[1]){ 
               trade.OrderDelete(ticket);
               if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
               {
                  Print ("ERROR_ac: Failed to delete order. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
                  return false;     
               }
            }
         }
      }      
   }
   return true;
}

//+------------------------------------------------------------------+
//| ORDER TIMER ||||||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+
//Llamo a la funcion que cierra ordenes pendientes segun la hora
void DeleteOrdersByTimer()   
{
   int total = OrdersTotal();
   for (int i = total - 1; i >= 0; i--)      // Important to count down to close positions. Counting up can lead to leave positions open
   {
      if( total != OrdersTotal()) { total = OrdersTotal(); i = total; continue; }     // Check that during the loop no new positions were opened (by another EA for example)
      ulong ticket = OrderGetTicket(i);   // Select position
      if (GetOrTicket(i, ticket)){
         //pido la fecha y hora de apertura
         datetime OrderOpenTime = (datetime) OrderGetInteger(ORDER_TIME_SETUP);
         //creo estructura
         MqlDateTime MyOpenTime;   
         //Convierto la hora de apertura a esta esctructura
         TimeToStruct(OrderOpenTime,MyOpenTime);
         int OpenMinutes = MyOpenTime.hour * 60 + MyOpenTime.min;
         
         //pido la hora local
         datetime LocalTime = TimeLocal();
         //Creo estructura
         MqlDateTime MyLocalTime;
         //Convierto la hora local a esta esctructura
         TimeToStruct(LocalTime, MyLocalTime);
         //pido la hora y minutos local 
         int CurrentMinutes = MyLocalTime.hour * 60 + MyLocalTime.min;
         
         //Ahora puedo calcular la diferencia de enteros.
         int Difference = CurrentMinutes - OpenMinutes;
      
         /*      
         Print ("### OrderTicket: ", ticket);
         Print ("### OrderOpenTime: ",OrderOpenTime);
         Print ("### LocalTime: ",LocalTime);
         Print ("### Difference: ",Difference);
         */
               
         if (MathAbs(Difference) >= InpOrderTimer) {
            trade.OrderDelete(ticket);
            if (trade.ResultRetcode() != TRADE_RETCODE_DONE)   // To check the result of the operation, to make sure we closed the position correctly
            {
               Print ("ERROR_ac: Failed to delete order by time. Result " + (string)trade.ResultRetcode() + ":" + trade.ResultRetcodeDescription());
               return;     
            }
            Print ("### Cierro orden por expiracion de tiempo: ", ticket);
         }
      }
   }
   return;         
}         

//+------------------------------------------------------------------+
//||||||||||||||||||||||||| GENERAL CHECKS||||||||||||||||||||||||||||
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check Stop Levels                                                |
//+------------------------------------------------------------------+  
// check for stop level (some brokers have a stop level so you cannot set the sl too close to the current price)
bool Checkstoplevels(double sldistance, double tpdistance){
   long level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if (level != 0 && sldistance <= level * _Point) {
      Print("ERROR_ac: Failed to place sl because it is inside stop level");
      return false;                                                        // return para que salga de la función y no cree la orden sin sl o sin tp 
   }
   if (level != 0 && tpdistance <= level * _Point) {
      Print("ERROR_ac: Failed to place tp because it is inside stop level");
      return false;
   }
   return true;
}        
//+------------------------------------------------------------------+
//| Check if Enough Money                                            |
//+------------------------------------------------------------------+  
  
bool CheckMoneyForTrade(string symb,double lots,ENUM_ORDER_TYPE type)
  {
//--- Getting the opening price
   MqlTick mqltick;
   SymbolInfoTick(symb,mqltick);
   double price=mqltick.ask;
   if(type==ORDER_TYPE_SELL)
      price=mqltick.bid;
//--- values of the required and free margin
   double margin,free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   //--- call of the checking function
   if(!OrderCalcMargin(type,symb,lots,price,margin))
     {
      //--- something went wrong, report and return false
      Print("ERROR_ac: Error in ",__FUNCTION__," code=",GetLastError());
      return(false);
     }
   //--- if there are insufficient funds to perform the operation
   if(margin>free_margin)
     {
      //--- report the error and return false
      Print("ERROR_ac: Not enough money for ",EnumToString(type)," ",lots," ",symb," Error code=",GetLastError());
      return(false);
     }
//--- checking successful
   return(true);
  } 


//+------------------------------------------------------------------+
//| Check the correctness of the order volume                        |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume,string &description)
  {
//--- minimal allowed volume for trade operations
   double min_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(volume<min_volume)
     {
      description=StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
     }
//--- maximal allowed volume of trade operations
   double max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(volume>max_volume)
     {
      description=StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
     }
//--- get minimal step of volume changing
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);

   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001)
     {
      description=StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                               volume_step,ratio*volume_step);
      return(false);
     }
   description="Correct volume value";
   return(true);
  }

  
//+------------------------------------------------------------------+
//| Check if another order can be placed                             |
//+------------------------------------------------------------------+
bool IsNewOrderAllowed()
  {
//--- get the number of pending orders allowed on the account
   int max_allowed_orders=(int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);

//--- if there is no limitation, return true; you can send an order
   if(max_allowed_orders==0) return(true);

//--- if we passed to this line, then there is a limitation; find out how many orders are already placed
   int orders=OrdersTotal();

//--- return the result of comparing
   return(orders<max_allowed_orders);
  }
  
//+------------------------------------------------------------------+
//| IS TRADE ALLOWED? ||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+

// Check 4 things. The functions are int thar correspond to true/false so I convert it to bool
bool IsTradeAllowed() {
   return ( (bool)MQLInfoInteger     (MQL_TRADE_ALLOWED)       // Trading allowed in input dialog
         && (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)  // Trading allowed in terminal
         && (bool)AccountInfoInteger (ACCOUNT_TRADE_ALLOWED)   // Is account able to trade,
         && (bool)AccountInfoInteger (ACCOUNT_TRADE_EXPERT)    // Is account able to auto trade
         ); 
}        
         
//+------------------------------------------------------------------+
//| IS MARKET OPEN |||||||||||||||||||||||||||||||||||||||||||||||||||
//+------------------------------------------------------------------+

bool IsMarketOpen() { return IsMarketOpen(_Symbol, TimeCurrent());}
bool IsMarketOpen(datetime time) { return IsMarketOpen(_Symbol, time); }
bool IsMarketOpen(string symbol, datetime time) {

	static string lastSymbol = "";
	static bool isOpen = false;
	static datetime sessionStart = 0;
	static datetime sessionEnd = 0;

	if (lastSymbol==symbol && sessionEnd>sessionStart) {
		if ( (isOpen && time>=sessionStart && time<=sessionEnd)
		      || (!isOpen && time>sessionStart && time<sessionEnd) ) return isOpen;
	}
		
	lastSymbol = symbol;

	MqlDateTime mtime;
	TimeToStruct(time, mtime);
	datetime seconds = mtime.hour*3600+mtime.min*60+mtime.sec;
	
	mtime.hour = 0;
	mtime.min = 0;
	mtime.sec = 0;
	datetime dayStart = StructToTime(mtime);
	datetime dayEnd = dayStart + 86400;
	
	datetime fromTime;
	datetime toTime;
	
	sessionStart = dayStart;
	sessionEnd = dayEnd;
	
	for(int session = 0;;session++) {
	
		if (!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)mtime.day_of_week, session, fromTime, toTime)) {
			sessionEnd = dayEnd;
			isOpen = false;
			return isOpen;
		}
		
		if (seconds<fromTime) { // not inside a session
			sessionEnd = dayStart + fromTime;
			isOpen = false;
			return isOpen;
		}
		
		if (seconds>toTime) { // maybe a later session
			sessionStart = dayStart + toTime;
			continue;
		}
		
		// at this point must be inside a session
		sessionStart = dayStart + fromTime;
		sessionEnd = dayStart + toTime;
		isOpen = true;
		return isOpen;

	}
	
	return false;
	
}
          