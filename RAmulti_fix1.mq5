//+------------------------------------------------------------------+
//|                                             SR_MultiTF_Trader.mq5 |
//|                                             Copyright 2023        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property link      ""
#property version   "1.00"
#property strict

// Include necessary libraries
#include <Trade\Trade.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Arrays\Array.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

// Magic number for this EA
#define MAGIC_NUMBER 20231215

// Global constants
#define MAX_ZONES 100
#define MAX_BARS_HISTORY 5000

// Enumerations
enum ENUM_TRADE_SCENARIO {
   SCENARIO_BOUNCE,
   SCENARIO_BREAKOUT,
   SCENARIO_NONE
};

enum ENUM_MARKET_REGIME {
   REGIME_TRENDING,
   REGIME_RANGING,
   REGIME_NEUTRAL
};

// Input parameters - SR Zone Detection
input group "Support and Resistance Detection"
input int      Zone_MinimumTouches      = 2;            // Minimum touches for valid zone
input double   Zone_ThicknessPips       = 20;           // Zone thickness in pips
input double   Zone_MinimumScore        = 5;            // Minimum strength score (1-10)
input bool     Zone_UseWeeklyLevels     = true;         // Include weekly levels in analysis
input int      Zone_MaxLookbackYears    = 5;            // Years of historical data to analyze
input double   Zone_NearbyZoneMergeDistance = 30;       // Distance to merge nearby zones (pips)

// Input parameters - Trading Settings
input group "Trading Settings"
input bool     Trade_EnableBounces      = true;         // Enable bounce trades
input bool     Trade_EnableBreakouts    = true;         // Enable breakout trades
input double   Trade_BouncesMinScore    = 7;            // Min score for bounce trades
input double   Trade_BreakoutsMinScore  = 5;            // Min score for breakout trades
input double   Trade_ADXThreshold       = 25;           // ADX threshold for trend confirmation
input double   Trade_RiskPercent        = 1.0;          // Risk per trade (% of balance)
input double   Trade_RewardRatio        = 2.0;          // Reward-to-risk ratio
input bool     Trade_UseTrailingStop    = true;         // Use trailing stop
input int      Trade_TrailingActivation = 30;           // Pips profit to activate trailing


// Input parameters - Timeframes
input group "Timeframe Settings"
input bool     UseCustomTimeframes     = false;         // Use custom timeframes
input ENUM_TIMEFRAMES TimeframeZones    = PERIOD_D1;    // Timeframe for zone detection
input ENUM_TIMEFRAMES TimeframeConfirm  = PERIOD_H4;    // Timeframe for confirmation
input ENUM_TIMEFRAMES TimeframeEntry    = PERIOD_M15;   // Timeframe for entry signals

// Structure to represent S/R zones
struct SRZone {
   double       upperBound;             // Upper price of zone
   double       lowerBound;             // Lower price of zone
   datetime     firstTouch;             // First time zone was touched
   datetime     lastTouch;              // Last time zone was touched
   int          touchCount;             // Number of times zone was touched
   double       strength;               // Strength score (1-10)
   bool         isSupport;              // true = support, false = resistance
   bool         isBroken;               // Has zone been broken recently
   double       volumeAtFormation;      // Volume when zone was formed
   int          testedCountD1;          // Test count on D1
   int          testedCountH4;          // Test count on H4
   bool         isValid;                // Is zone still valid
   string       id;                     // Unique identifier for zone
   
   // Constructor
   SRZone() {
      touchCount = 0;
      strength = 0;
      isSupport = false;
      isBroken = false;
      isValid = true;
      testedCountD1 = 0;
      testedCountH4 = 0;
      id = "";
   }
};

//+------------------------------------------------------------------+
//| Structure to hold pattern detection result                       |
//+------------------------------------------------------------------+
struct PatternResult {
   bool     detected;       // Pattern detected
   string   patternName;    // Name of the pattern
   double   reliability;    // Pattern reliability score (0-10)
   datetime time;           // Time of pattern completion
   
   PatternResult() {
      detected = false;
      patternName = "";
      reliability = 0;
      time = 0;
   }
};

// Global variables
CTrade         trade;                    // Trade object
CSymbolInfo    symbolInfo;               // Symbol information
CAccountInfo   accountInfo;              // Account information
SRZone         zones[];                  // Array of S/R zones
bool Trade_RequireVolumeConfirmation = false; // Default to false since volume data is unreliable
int            zoneCount = 0;            // Count of identified zones
datetime       lastD1BarTime = 0;        // Last D1 bar time processed
datetime       lastH4BarTime = 0;        // Last H4 bar time processed
datetime       lastM15BarTime = 0;       // Last M15 bar time processed
bool           isInitialized = false;    // Flag to indicate if zones are initialized
double         pipSize;                  // Value of 1 pip for current symbol
int            barsPerDay;               // Number of bars per day for entry timeframe

// Indicator handles
int            adxHandle;                // ADX indicator handle
int            rsiHandle;                // RSI indicator handle
int            bbandsHandle;             // Bollinger Bands handle
int            atrHandle;                // ATR handle

//+------------------------------------------------------------------+
//| OnInit function with improved initialization                     |
//+------------------------------------------------------------------+
int OnInit() {
   // Set up trade object
   trade.SetExpertMagicNumber(MAGIC_NUMBER);
   trade.SetDeviationInPoints(10); // Allow 1 pip slippage
   trade.SetTypeFilling(ORDER_FILLING_FOK); // Fill or Kill order type
   trade.SetMarginMode();
   trade.LogLevel(LOG_LEVEL_ERRORS); // Only log errors
   
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol)) {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
   }
   
   // Calculate pip size
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   pipSize = (digits == 3 || digits == 5) ? 0.0001 : 0.01;
   
   // Calculate bars per day for entry timeframe
   barsPerDay = (int)(24 * 60 / PeriodSeconds(TimeframeEntry));
   
   // Initialize indicators
   adxHandle = iADX(_Symbol, TimeframeConfirm, 14);
   rsiHandle = iRSI(_Symbol, TimeframeConfirm, 14, PRICE_CLOSE);
   bbandsHandle = iBands(_Symbol, TimeframeConfirm, 20, 2, 0, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, TimeframeConfirm, 14);
   
   if(adxHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || 
      bbandsHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) {
      Print("Error initializing indicators: ", GetLastError());
      return INIT_FAILED;
   }
   
   // Initialize S/R zones array
   ArrayResize(zones, MAX_ZONES);
   
   // Initialize zones on EA start
   if(!isInitialized) {
      if(!InitializeSRZones()) {
         Print("Failed to initialize S/R zones");
         return INIT_FAILED;
      }
      isInitialized = true;
   }
   
   // Add input parameter for volume confirmation
   Trade_RequireVolumeConfirmation = false; // Default to false since volume data is unreliable
   
   Print("EA initialized successfully. Discovered ", zoneCount, " S/R zones");
   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Clean up indicator handles
   IndicatorRelease(adxHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(bbandsHandle);
   IndicatorRelease(atrHandle);
   
   // Remove all chart objects created by EA
   ObjectsDeleteAll(0, "SR_Zone_");
   ObjectsDeleteAll(0, "SR_Label_");
   ObjectsDeleteAll(0, "Pattern_");
   ObjectsDeleteAll(0, "Arrow_");
   
   Print("EA deinitialized. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Check for new bars on all relevant timeframes
   if(!CheckNewBars()) return;
   
   // Update S/R zones if necessary
   UpdateZones();
   
   // Display zones on chart
   if(MQLInfoInteger(MQL_VISUAL_MODE)) DisplayZonesOnChart();
   
   // Scan for candlestick patterns
   ScanForPatterns();
   
   // Check for trade conditions
   CheckTradeConditions();
   
   // Manage existing positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Check if new bars have formed on relevant timeframes             |
//+------------------------------------------------------------------+
bool CheckNewBars() {
   bool newBars = false;
   
   // Check D1 timeframe for new bar
   datetime currentD1Time = iTime(_Symbol, TimeframeZones, 0);
   if(currentD1Time != lastD1BarTime) {
      lastD1BarTime = currentD1Time;
      newBars = true;
   }
   
   // Check H4 timeframe for new bar
   datetime currentH4Time = iTime(_Symbol, TimeframeConfirm, 0);
   if(currentH4Time != lastH4BarTime) {
      lastH4BarTime = currentH4Time;
      newBars = true;
   }
   
   // Check M15 timeframe for new bar (for entry signals)
   datetime currentM15Time = iTime(_Symbol, TimeframeEntry, 0);
   if(currentM15Time != lastM15BarTime) {
      lastM15BarTime = currentM15Time;
      newBars = true;
   }
   
   return newBars;
}

//+------------------------------------------------------------------+
//| Initialize Support and Resistance Zones                          |
//+------------------------------------------------------------------+
bool InitializeSRZones() {
   Print("Initializing S/R zones...");
   
   // Calculate how many bars we need to analyze
   int barsNeeded = Zone_MaxLookbackYears * 365; // Approximate D1 bars for years
   
   // Check available history
   if(Bars(_Symbol, TimeframeZones) < barsNeeded) {
      Print("Not enough historical data available. Needed: ", barsNeeded, ", Available: ", Bars(_Symbol, TimeframeZones));
      barsNeeded = Bars(_Symbol, TimeframeZones) - 10; // Use what's available minus safety margin
   }
   
   // Get historical data
   MqlRates rates[];
   if(CopyRates(_Symbol, TimeframeZones, 0, barsNeeded, rates) != barsNeeded) {
      Print("Error copying historical data: ", GetLastError());
      return false;
   }
   
   // Detect potential zones using zigzag approach
   int pivotPoints = IdentifyPivotPoints(rates, barsNeeded);
   
   // Calculate strength scores and validate zones
   CalculateZoneStrengths();
   
   // Merge nearby zones
   MergeNearbySRZones();
   
   // Sort zones by strength
   SortZonesByStrength();
   
   Print("S/R Zones initialized. Identified ", zoneCount, " valid zones.");
   return true;
}

//+------------------------------------------------------------------+
//| Identify pivot points for potential S/R zones                    |
//+------------------------------------------------------------------+
int IdentifyPivotPoints(MqlRates &rates[], int barsCount) {
   int pivotCount = 0;
   double zigzagThreshold = Zone_ThicknessPips * pipSize; // Convert pips to price
   
   zoneCount = 0; // Reset zone count
   
   // Find swing highs and lows
   for(int i = 2; i < barsCount - 2; i++) {
      // Check for swing high
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high && 
         rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high) {
         
         // Check if we already have a nearby resistance zone
         bool existingZone = false;
         for(int j = 0; j < zoneCount; j++) {
            if(!zones[j].isSupport && 
               MathAbs(zones[j].upperBound - rates[i].high) < zigzagThreshold) {
               // Update existing zone
               zones[j].touchCount++;
               zones[j].lastTouch = rates[i].time;
               existingZone = true;
               break;
            }
         }
         
         // Create new zone if no existing one
         if(!existingZone && zoneCount < MAX_ZONES) {
            zones[zoneCount].upperBound = rates[i].high + zigzagThreshold/2;
            zones[zoneCount].lowerBound = rates[i].high - zigzagThreshold/2;
            zones[zoneCount].firstTouch = rates[i].time;
            zones[zoneCount].lastTouch = rates[i].time;
            zones[zoneCount].touchCount = 1;
            zones[zoneCount].isSupport = false; // Resistance
            zones[zoneCount].id = "R_" + IntegerToString(zoneCount);
            zones[zoneCount].volumeAtFormation = (double)rates[i].tick_volume;
            zoneCount++;
            pivotCount++;
         }
      }
      
      // Check for swing low
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low && 
         rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low) {
         
         // Check if we already have a nearby support zone
         bool existingZone = false;
         for(int j = 0; j < zoneCount; j++) {
            if(zones[j].isSupport && 
               MathAbs(zones[j].lowerBound - rates[i].low) < zigzagThreshold) {
               // Update existing zone
               zones[j].touchCount++;
               zones[j].lastTouch = rates[i].time;
               existingZone = true;
               break;
            }
         }
         
         // Create new zone if no existing one
         if(!existingZone && zoneCount < MAX_ZONES) {
            zones[zoneCount].upperBound = rates[i].low + zigzagThreshold/2;
            zones[zoneCount].lowerBound = rates[i].low - zigzagThreshold/2;
            zones[zoneCount].firstTouch = rates[i].time;
            zones[zoneCount].lastTouch = rates[i].time;
            zones[zoneCount].touchCount = 1;
            zones[zoneCount].isSupport = true; // Support
            zones[zoneCount].id = "S_" + IntegerToString(zoneCount);
            zones[zoneCount].volumeAtFormation = (double)rates[i].tick_volume;
            zoneCount++;
            pivotCount++;
         }
      }
   }
   
   return pivotCount;
}

//+------------------------------------------------------------------+
//| Calculate strength scores for all zones                          |
//+------------------------------------------------------------------+
void CalculateZoneStrengths() {
   // Get average volume for normalization
   double avgVolume = CalculateAverageVolume(TimeframeZones, 1000);
   
   // Calculate current time for age calculations
   datetime currentTime = TimeCurrent();
   
   for(int i = 0; i < zoneCount; i++) {
      double score = 0.0;
      
      // Factor 1: Number of touches (max +5)
      score += MathMin(zones[i].touchCount, 5);
      
      // Factor 2: Recent vs. old (age factor, max +2)
      double ageInDays = (double)(currentTime - zones[i].firstTouch) / (60 * 60 * 24);
      double ageFactor = 0;
      
      if(ageInDays <= 30) ageFactor = 2.0; // Very recent zone
      else if(ageInDays <= 90) ageFactor = 1.5; // Recent zone
      else if(ageInDays <= 180) ageFactor = 1.0; // Medium-aged zone
      else if(ageInDays <= 365) ageFactor = 0.5; // Older zone
      // Oldest zones get 0
      
      score += ageFactor;
      
      // Factor 3: Volume at formation relative to average (max +1.5)
      double volumeRatio = zones[i].volumeAtFormation / avgVolume;
      if(volumeRatio > 2.0) score += 1.5;
      else if(volumeRatio > 1.5) score += 1.0;
      else if(volumeRatio > 1.0) score += 0.5;
      
      // Factor 4: Multi-timeframe confluence (max +1.5)
      if(CheckZoneVisibleOnMultipleTimeframes(i)) {
         score += 1.5;
      }
      
      // Set final strength score
      zones[i].strength = score;
      
      // Validate zone based on minimum criteria
      zones[i].isValid = (zones[i].touchCount >= Zone_MinimumTouches && 
                         zones[i].strength >= Zone_MinimumScore);
   }
}

//+------------------------------------------------------------------+
//| Check if zone is visible on multiple timeframes                  |
//+------------------------------------------------------------------+
bool CheckZoneVisibleOnMultipleTimeframes(int zoneIndex) {
   // This is a simplified method - a more sophisticated implementation
   // would check for actual pivots on higher timeframes
   
   if(!Zone_UseWeeklyLevels) return false;
   
   double zonePrice = zones[zoneIndex].isSupport ? 
                     zones[zoneIndex].lowerBound : 
                     zones[zoneIndex].upperBound;
   
   // Get some weekly data
   MqlRates weeklyRates[];
   if(CopyRates(_Symbol, PERIOD_W1, 0, 50, weeklyRates) < 50) {
      return false;
   }
   
   // Check if our zone aligns with weekly highs/lows
   for(int i = 0; i < 50; i++) {
      // For support zones, check weekly lows
      if(zones[zoneIndex].isSupport) {
         if(MathAbs(weeklyRates[i].low - zonePrice) < Zone_ThicknessPips * pipSize) {
            return true;
         }
      }
      // For resistance zones, check weekly highs
      else {
         if(MathAbs(weeklyRates[i].high - zonePrice) < Zone_ThicknessPips * pipSize) {
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Merge nearby S/R zones to avoid duplication                      |
//+------------------------------------------------------------------+
void MergeNearbySRZones() {
   double mergeDistance = Zone_NearbyZoneMergeDistance * pipSize;
   
   for(int i = 0; i < zoneCount; i++) {
      if(!zones[i].isValid) continue;
      
      for(int j = i + 1; j < zoneCount; j++) {
         if(!zones[j].isValid) continue;
         
         // Only merge zones of the same type (support with support, resistance with resistance)
         if(zones[i].isSupport != zones[j].isSupport) continue;
         
         // Check if zones are close enough to merge
         bool shouldMerge = false;
         
         if(zones[i].isSupport) {
            // For support zones, check if lower bounds are close
            if(MathAbs(zones[i].lowerBound - zones[j].lowerBound) < mergeDistance) {
               shouldMerge = true;
            }
         } else {
            // For resistance zones, check if upper bounds are close
            if(MathAbs(zones[i].upperBound - zones[j].upperBound) < mergeDistance) {
               shouldMerge = true;
            }
         }
         
         if(shouldMerge) {
            // Merge zones - keep the stronger one and enhance its properties
            if(zones[i].strength >= zones[j].strength) {
               // Merge j into i
               zones[i].touchCount += zones[j].touchCount;
               zones[i].firstTouch = MathMin(zones[i].firstTouch, zones[j].firstTouch);
               zones[i].lastTouch = MathMax(zones[i].lastTouch, zones[j].lastTouch);
               zones[i].strength = MathMax(zones[i].strength, zones[j].strength) + 0.5; // Bonus for merged zone
               
               // Invalidate the weaker zone
               zones[j].isValid = false;
            } else {
               // Merge i into j
               zones[j].touchCount += zones[i].touchCount;
               zones[j].firstTouch = MathMin(zones[i].firstTouch, zones[j].firstTouch);
               zones[j].lastTouch = MathMax(zones[i].lastTouch, zones[j].lastTouch);
               zones[j].strength = MathMax(zones[i].strength, zones[j].strength) + 0.5; // Bonus for merged zone
               
               // Invalidate the weaker zone
               zones[i].isValid = false;
               break; // Break since i is now invalid
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Sort zones by strength (descending)                              |
//+------------------------------------------------------------------+
void SortZonesByStrength() {
   // Simple bubble sort
   for(int i = 0; i < zoneCount - 1; i++) {
      for(int j = 0; j < zoneCount - i - 1; j++) {
         if(zones[j].strength < zones[j + 1].strength) {
            // Swap zones
            SRZone temp = zones[j];
            zones[j] = zones[j + 1];
            zones[j + 1] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modified CalculateAverageVolume function to handle volume errors |
//+------------------------------------------------------------------+
double CalculateAverageVolume(ENUM_TIMEFRAMES timeframe, int bars) {
   long volume[];
   if(CopyTickVolume(_Symbol, timeframe, 0, bars, volume) != bars) {
      Print("Warning: Error copying volume data: ", GetLastError());
      return 1.0; // Default value
   }
   
   double sum = 0;
   for(int i = 0; i < bars; i++) {
      sum += (double)volume[i];
   }
   
   return sum / bars;
}

//+------------------------------------------------------------------+
//| Update zones with recent price action                            |
//+------------------------------------------------------------------+
void UpdateZones() {
   // This function updates zone status based on recent price action
   // It checks if zones have been broken or retested
   
   // Get recent price data
   MqlRates ratesD1[];
   if(CopyRates(_Symbol, TimeframeZones, 0, 10, ratesD1) != 10) {
      Print("Error copying D1 rates for zone update: ", GetLastError());
      return;
   }
   
   // Check each zone
   for(int i = 0; i < zoneCount; i++) {
      if(!zones[i].isValid) continue;
      
      // Check if zone has been broken
      if(!zones[i].isBroken) {
         if(zones[i].isSupport) {
            // Support zone is broken if price closes below it
            if(ratesD1[0].close < zones[i].lowerBound) {
               zones[i].isBroken = true;
            }
         } else {
            // Resistance zone is broken if price closes above it
            if(ratesD1[0].close > zones[i].upperBound) {
               zones[i].isBroken = true;
            }
         }
      } else {
         // Check if broken zone has been retested (role reversal)
         if(zones[i].isSupport) {
            // Former support now resistance
            if(ratesD1[0].high > zones[i].upperBound && ratesD1[0].close < zones[i].upperBound) {
               // Retested as resistance
               zones[i].isSupport = false; // Change role
               zones[i].isBroken = false;  // Reset broken status
               zones[i].touchCount++;      // Increment touch count
               zones[i].lastTouch = ratesD1[0].time;
            }
         } else {
            // Former resistance now support
            if(ratesD1[0].low < zones[i].lowerBound && ratesD1[0].close > zones[i].lowerBound) {
               // Retested as support
               zones[i].isSupport = true;  // Change role
               zones[i].isBroken = false;  // Reset broken status
               zones[i].touchCount++;      // Increment touch count
               zones[i].lastTouch = ratesD1[0].time;
            }
         }
      }
      
      // Check for new tests of the zone
      if(!zones[i].isBroken) {
         if(zones[i].isSupport) {
            // Price tested support zone
            if(ratesD1[0].low <= zones[i].upperBound && ratesD1[0].low >= zones[i].lowerBound) {
               zones[i].touchCount++;
               zones[i].lastTouch = ratesD1[0].time;
               zones[i].testedCountD1++;
            }
         } else {
            // Price tested resistance zone
            if(ratesD1[0].high >= zones[i].lowerBound && ratesD1[0].high <= zones[i].upperBound) {
               zones[i].touchCount++;
               zones[i].lastTouch = ratesD1[0].time;
               zones[i].testedCountD1++;
            }
         }
      }
   }
   
   // Recalculate zone strengths after updates
   CalculateZoneStrengths();
}

//+------------------------------------------------------------------+
//| Display zones on chart                                           |
//+------------------------------------------------------------------+
void DisplayZonesOnChart() {
   // Clear previous zone objects
   ObjectsDeleteAll(0, "SR_Zone_");
   ObjectsDeleteAll(0, "SR_Label_");
   
   // Display only valid zones
   for(int i = 0; i < zoneCount; i++) {
      if(!zones[i].isValid) continue;
      
      // Determine zone color based on type and strength
      color zoneColor;
      if(zones[i].isSupport) {
         // Support zones - green with varying intensity
         int intensity = (int)(zones[i].strength * 25); // 0-250
         intensity = MathMin(intensity, 250);
         zoneColor = clrGreen; // Base color for support
      } else {
         // Resistance zones - red with varying intensity
         int intensity = (int)(zones[i].strength * 25); // 0-250
         intensity = MathMin(intensity, 250);
         zoneColor = clrRed; // Base color for resistance
      }
      
      // Create zone rectangle
      string zoneName = "SR_Zone_" + zones[i].id;
      ObjectCreate(0, zoneName, OBJ_RECTANGLE, 0, zones[i].firstTouch, zones[i].upperBound, 
                  TimeCurrent() + 60*60*24, zones[i].lowerBound); // Extend to future
      
      ObjectSetInteger(0, zoneName, OBJPROP_COLOR, zoneColor);
      ObjectSetInteger(0, zoneName, OBJPROP_FILL, true);
      ObjectSetInteger(0, zoneName, OBJPROP_BACK, true);
      ObjectSetInteger(0, zoneName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, zoneName, OBJPROP_STYLE, STYLE_SOLID);
      
      // Add label with zone info
      string labelName = "SR_Label_" + zones[i].id;
      string labelText = StringFormat("%s: %.2f (%.1f)", 
                                     zones[i].isSupport ? "S" : "R", 
                                     zones[i].isSupport ? zones[i].lowerBound : zones[i].upperBound,
                                     zones[i].strength);
      
      ObjectCreate(0, labelName, OBJ_TEXT, 0, zones[i].lastTouch, 
                  zones[i].isSupport ? zones[i].lowerBound - 10*pipSize : zones[i].upperBound + 10*pipSize);
      ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, zoneColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
   }
   
   // Refresh chart
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Modified CheckTradeConditions function to handle volume errors   |
//+------------------------------------------------------------------+
void CheckTradeConditions() {
   // Don't check for new trades if we already have open positions for this symbol
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER) {
            // Already have a position on this symbol
            return;
         }
      }
   }
   
   // Ensure symbol info is updated
   symbolInfo.Refresh();
   symbolInfo.RefreshRates();
   
   // Get current price data
   double currentPrice = symbolInfo.Bid();
   
   // Get indicator data for confirmation
   double adx[], rsi[], upperBand[], middleBand[], lowerBand[], atr[];
   
   bool indicatorsValid = true;
   
   if(CopyBuffer(adxHandle, 0, 0, 3, adx) != 3 ||
      CopyBuffer(rsiHandle, 0, 0, 3, rsi) != 3 ||
      CopyBuffer(bbandsHandle, 0, 0, 3, upperBand) != 3 ||
      CopyBuffer(bbandsHandle, 1, 0, 3, middleBand) != 3 ||
      CopyBuffer(bbandsHandle, 2, 0, 3, lowerBand) != 3 ||
      CopyBuffer(atrHandle, 0, 0, 3, atr) != 3) {
      Print("Error copying indicator data: ", GetLastError());
      indicatorsValid = false;
   }
   
   // Get recent price action
   MqlRates ratesEntry[];
   if(CopyRates(_Symbol, TimeframeEntry, 0, 5, ratesEntry) != 5) {
      Print("Error copying entry timeframe rates: ", GetLastError());
      return;
   }
   
   // Check each zone for potential trade setups
   for(int i = 0; i < zoneCount; i++) {
      if(!zones[i].isValid || zones[i].isBroken) continue;
      
      // Check for bounce scenario
      if(Trade_EnableBounces && zones[i].strength >= Trade_BouncesMinScore) {
         // Skip volume check if we couldn't get indicator data
         if(!indicatorsValid || ShouldTradeBounce(i, ratesEntry, adx[0], rsi[0])) {
            ExecuteBounceTrade(i, currentPrice, indicatorsValid ? atr[0] : 0.001);
            return; // Execute only one trade at a time
         }
      }
      
      // Check for breakout scenario
      if(Trade_EnableBreakouts && zones[i].strength >= Trade_BreakoutsMinScore) {
         // Skip volume check if we couldn't get indicator data
         if(!indicatorsValid || ShouldTradeBreakout(i, ratesEntry, adx[0])) {
            ExecuteBreakoutTrade(i, currentPrice, indicatorsValid ? atr[0] : 0.001);
            return; // Execute only one trade at a time
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for bounce trade scenario                                  |
//+------------------------------------------------------------------+
ENUM_TRADE_SCENARIO CheckBounceScenario(int zoneIndex, double currentPrice, MqlRates &rates[], double adxValue, double rsiValue) {
   // For bounce trades, we want:
   // 1. Price approaching or touching the zone
   // 2. Confirmation of rejection (pin bar, engulfing, etc.)
   // 3. Momentum indicators supporting the bounce
   
   // Check if price is near the zone
   bool priceNearZone = false;
   
   if(zones[zoneIndex].isSupport) {
      // For support, price should be approaching from above
      if(currentPrice <= zones[zoneIndex].upperBound + 10*pipSize && 
         currentPrice >= zones[zoneIndex].lowerBound - 5*pipSize) {
         priceNearZone = true;
      }
   } else {
      // For resistance, price should be approaching from below
      if(currentPrice >= zones[zoneIndex].lowerBound - 10*pipSize && 
         currentPrice <= zones[zoneIndex].upperBound + 5*pipSize) {
         priceNearZone = true;
      }
   }
   
   if(!priceNearZone) return SCENARIO_NONE;
   
   // Check for rejection candle patterns
   bool hasRejectionPattern = false;
   
   if(zones[zoneIndex].isSupport) {
      // Look for bullish patterns at support
      
      // Pin bar (hammer)
      if(rates[1].close > rates[1].open && // Bullish candle
         rates[1].high - rates[1].close < (rates[1].open - rates[1].low) * 0.5 && // Small upper wick
         rates[1].open - rates[1].low > (rates[1].high - rates[1].low) * 0.6) { // Long lower wick
         hasRejectionPattern = true;
      }
      
      // Bullish engulfing
      if(rates[1].close > rates[1].open && // Current bullish
         rates[2].close < rates[2].open && // Previous bearish
         rates[1].close > rates[2].open && // Current close above previous open
         rates[1].open < rates[2].close) { // Current open below previous close
         hasRejectionPattern = true;
      }
      
      // RSI oversold and turning up
      if(rsiValue < 30 && rsiValue > 20) {
         hasRejectionPattern = true;
      }
   } else {
      // Look for bearish patterns at resistance
      
      // Pin bar (shooting star)
      if(rates[1].close < rates[1].open && // Bearish candle
         rates[1].open - rates[1].low < (rates[1].high - rates[1].close) * 0.5 && // Small lower wick
         rates[1].high - rates[1].open > (rates[1].high - rates[1].low) * 0.6) { // Long upper wick
         hasRejectionPattern = true;
      }
      
      // Bearish engulfing
      if(rates[1].close < rates[1].open && // Current bearish
         rates[2].close > rates[2].open && // Previous bullish
         rates[1].close < rates[2].open && // Current close below previous open
         rates[1].open > rates[2].close) { // Current open above previous close
         hasRejectionPattern = true;
      }
      
      // RSI overbought and turning down
      if(rsiValue > 70 && rsiValue < 80) {
         hasRejectionPattern = true;
      }
   }
   
   if(!hasRejectionPattern) return SCENARIO_NONE;
   
   // Additional confirmation: ADX should not be too high (not strong trend)
   if(adxValue > 40) return SCENARIO_NONE; // Too strong trend, might break through
   
   return SCENARIO_BOUNCE;
}

//+------------------------------------------------------------------+
//| Check for breakout trade scenario                                |
//+------------------------------------------------------------------+
ENUM_TRADE_SCENARIO CheckBreakoutScenario(int zoneIndex, double currentPrice, MqlRates &rates[], double adxValue) {
   // For breakout trades, we want:
   // 1. Price breaking through the zone
   // 2. Strong momentum in breakout direction
   // 3. Confirmation of breakout (close beyond zone)
   
   // Check if price has broken the zone
   bool hasBreakout = false;
   
   if(zones[zoneIndex].isSupport) {
      // For support breakout, price should close below the zone
      if(rates[1].close < zones[zoneIndex].lowerBound && 
         rates[2].low > zones[zoneIndex].lowerBound) { // Previous candle was above
         hasBreakout = true;
      }
   } else {
      // For resistance breakout, price should close above the zone
      if(rates[1].close > zones[zoneIndex].upperBound && 
         rates[2].high < zones[zoneIndex].upperBound) { // Previous candle was below
         hasBreakout = true;
      }
   }
   
   if(!hasBreakout) return SCENARIO_NONE;
   
   // Check for strong momentum (ADX)
   if(adxValue < Trade_ADXThreshold) return SCENARIO_NONE; // Not enough momentum
   
   // Try to check volume, but don't fail if volume data is unavailable
   bool volumeConfirmation = true; // Default to true if we can't check volume
   
   long volume[];
   if(CopyTickVolume(_Symbol, TimeframeEntry, 0, 5, volume) == 5) {
      // Volume should increase on breakout
      if(volume[1] <= volume[2]) {
         volumeConfirmation = false;
      }
   }
   
   // If volume confirmation is required but failed, exit
   if(!volumeConfirmation && Trade_RequireVolumeConfirmation) {
      return SCENARIO_NONE;
   }
   
   // Check for pullback after breakout (for better entry)
   bool hasPullback = false;
   
   if(zones[zoneIndex].isSupport) {
      // For broken support, look for pullback up to test the level
      if(rates[0].high > zones[zoneIndex].lowerBound && rates[0].close < zones[zoneIndex].lowerBound) {
         hasPullback = true;
      }
   } else {
      // For broken resistance, look for pullback down to test the level
      if(rates[0].low < zones[zoneIndex].upperBound && rates[0].close > zones[zoneIndex].upperBound) {
         hasPullback = true;
      }
   }
   
   // We prefer to have a pullback, but it's not mandatory
   if(!hasPullback && rates[0].time > rates[1].time + 4*PeriodSeconds(TimeframeEntry)) {
      // If enough time has passed without pullback, we might miss the move
      return SCENARIO_NONE;
   }
   
   return SCENARIO_BREAKOUT;
}

//+------------------------------------------------------------------+
//| Fixed ExecuteBounceTrade function with proper SL/TP calculation  |
//+------------------------------------------------------------------+
void ExecuteBounceTrade(int zoneIndex, double currentPrice, double atr) {
   // First check if we already have an open position
   if(PositionsTotal() > 0) {
      for(int i = 0; i < PositionsTotal(); i++) {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER) {
               // Already have a position on this symbol
               Print("Skip trade - position already exists for ", _Symbol);
               return;
            }
         }
      }
   }
   
   // Get necessary symbol info for stop loss calculation
   double minStopLevel = symbolInfo.StopsLevel() * symbolInfo.Point();
   double askPrice = symbolInfo.Ask();
   double bidPrice = symbolInfo.Bid();
   double spread = askPrice - bidPrice;
   
   // Calculate position size, stop loss, and take profit
   double stopLoss, takeProfit;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * Trade_RiskPercent / 100.0;
   
   if(zones[zoneIndex].isSupport) {
      // Long trade from support
      // Stop loss should be below support zone with buffer
      stopLoss = zones[zoneIndex].lowerBound - atr * 0.5;
      
      // Ensure minimum stop distance
      if(askPrice - stopLoss < minStopLevel + spread) {
         stopLoss = askPrice - (minStopLevel + spread + 5 * pipSize);
      }
      
      // Take profit based on risk:reward ratio
      takeProfit = askPrice + (askPrice - stopLoss) * Trade_RewardRatio;
      
      // Calculate position size based on risk
      double riskPips = (askPrice - stopLoss) / pipSize;
      double positionSize = CalculatePositionSize(riskAmount, riskPips);
      
      // Execute buy order
      if(positionSize >= symbolInfo.LotsMin()) {
         Print("Attempting buy: Entry=", askPrice, " SL=", stopLoss, " TP=", takeProfit, " Risk=", Trade_RiskPercent, "% Lot=", positionSize);
         if(trade.Buy(positionSize, _Symbol, 0, stopLoss, takeProfit, "Bounce_Support_" + zones[zoneIndex].id)) {
            Print("Bounce trade executed: BUY at support zone ", zones[zoneIndex].id, 
                  " Entry: ", askPrice, " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", positionSize);
         } else {
            Print("Error executing bounce trade: ", GetLastError(), " (", trade.ResultRetcode(), ")");
         }
      } else {
         Print("Calculated position size too small: ", positionSize, " minimum: ", symbolInfo.LotsMin());
      }
   } else {
      // Short trade from resistance
      // Stop loss should be above resistance zone with buffer
      stopLoss = zones[zoneIndex].upperBound + atr * 0.5;
      
      // Ensure minimum stop distance
      if(stopLoss - bidPrice < minStopLevel + spread) {
         stopLoss = bidPrice + (minStopLevel + spread + 5 * pipSize);
      }
      
      // Take profit based on risk:reward ratio
      takeProfit = bidPrice - (stopLoss - bidPrice) * Trade_RewardRatio;
      
      // Calculate position size based on risk
      double riskPips = (stopLoss - bidPrice) / pipSize;
      double positionSize = CalculatePositionSize(riskAmount, riskPips);
      
      // Execute sell order
      if(positionSize >= symbolInfo.LotsMin()) {
         Print("Attempting sell: Entry=", bidPrice, " SL=", stopLoss, " TP=", takeProfit, " Risk=", Trade_RiskPercent, "% Lot=", positionSize);
         if(trade.Sell(positionSize, _Symbol, 0, stopLoss, takeProfit, "Bounce_Resistance_" + zones[zoneIndex].id)) {
            Print("Bounce trade executed: SELL at resistance zone ", zones[zoneIndex].id, 
                  " Entry: ", bidPrice, " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", positionSize);
         } else {
            Print("Error executing bounce trade: ", GetLastError(), " (", trade.ResultRetcode(), ")");
         }
      } else {
         Print("Calculated position size too small: ", positionSize, " minimum: ", symbolInfo.LotsMin());
      }
   }
}

//+------------------------------------------------------------------+
//| Fixed ExecuteBreakoutTrade function with proper SL/TP calculation|
//+------------------------------------------------------------------+
void ExecuteBreakoutTrade(int zoneIndex, double currentPrice, double atr) {
   // First check if we already have an open position
   if(PositionsTotal() > 0) {
      for(int i = 0; i < PositionsTotal(); i++) {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MAGIC_NUMBER) {
               // Already have a position on this symbol
               Print("Skip trade - position already exists for ", _Symbol);
               return;
            }
         }
      }
   }
   
   // Get necessary symbol info for stop loss calculation
   double minStopLevel = symbolInfo.StopsLevel() * symbolInfo.Point();
   double askPrice = symbolInfo.Ask();
   double bidPrice = symbolInfo.Bid();
   double spread = askPrice - bidPrice;
   
   // Calculate position size, stop loss, and take profit
   double stopLoss, takeProfit;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * Trade_RiskPercent / 100.0;
   
   if(zones[zoneIndex].isSupport) {
      // Short trade on support breakout
      // Stop loss should be above broken support zone with buffer
      stopLoss = zones[zoneIndex].upperBound + atr * 0.5;
      
      // Ensure minimum stop distance
      if(stopLoss - bidPrice < minStopLevel + spread) {
         stopLoss = bidPrice + (minStopLevel + spread + 5 * pipSize);
      }
      
      // Take profit based on risk:reward ratio
      takeProfit = bidPrice - (stopLoss - bidPrice) * Trade_RewardRatio;
      
      // Calculate position size based on risk
      double riskPips = (stopLoss - bidPrice) / pipSize;
      double positionSize = CalculatePositionSize(riskAmount, riskPips);
      
      // Execute sell order
      if(positionSize >= symbolInfo.LotsMin()) {
         Print("Attempting breakout sell: Entry=", bidPrice, " SL=", stopLoss, " TP=", takeProfit, " Risk=", Trade_RiskPercent, "% Lot=", positionSize);
         if(trade.Sell(positionSize, _Symbol, 0, stopLoss, takeProfit, "Breakout_Support_" + zones[zoneIndex].id)) {
            Print("Breakout trade executed: SELL on support breakout ", zones[zoneIndex].id, 
                  " Entry: ", bidPrice, " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", positionSize);
                  
            // Mark zone as broken
            zones[zoneIndex].isBroken = true;
         } else {
            Print("Error executing breakout trade: ", GetLastError(), " (", trade.ResultRetcode(), ")");
         }
      } else {
         Print("Calculated position size too small: ", positionSize, " minimum: ", symbolInfo.LotsMin());
      }
   } else {
      // Long trade on resistance breakout
      // Stop loss should be below broken resistance zone with buffer
      stopLoss = zones[zoneIndex].lowerBound - atr * 0.5;
      
      // Ensure minimum stop distance
      if(askPrice - stopLoss < minStopLevel + spread) {
         stopLoss = askPrice - (minStopLevel + spread + 5 * pipSize);
      }
      
      // Take profit based on risk:reward ratio
      takeProfit = askPrice + (askPrice - stopLoss) * Trade_RewardRatio;
      
      // Calculate position size based on risk
      double riskPips = (askPrice - stopLoss) / pipSize;
      double positionSize = CalculatePositionSize(riskAmount, riskPips);
      
      // Execute buy order
      if(positionSize >= symbolInfo.LotsMin()) {
         Print("Attempting breakout buy: Entry=", askPrice, " SL=", stopLoss, " TP=", takeProfit, " Risk=", Trade_RiskPercent, "% Lot=", positionSize);
         if(trade.Buy(positionSize, _Symbol, 0, stopLoss, takeProfit, "Breakout_Resistance_" + zones[zoneIndex].id)) {
            Print("Breakout trade executed: BUY on resistance breakout ", zones[zoneIndex].id, 
                  " Entry: ", askPrice, " SL: ", stopLoss, " TP: ", takeProfit, " Lot: ", positionSize);
                  
            // Mark zone as broken
            zones[zoneIndex].isBroken = true;
         } else {
            Print("Error executing breakout trade: ", GetLastError(), " (", trade.ResultRetcode(), ")");
         }
      } else {
         Print("Calculated position size too small: ", positionSize, " minimum: ", symbolInfo.LotsMin());
      }
   }
}

//+------------------------------------------------------------------+
//| Improved position size calculation with proper lot handling      |
//+------------------------------------------------------------------+
double CalculatePositionSize(double riskAmount, double stopLossPips) {
   // Ensure we have valid inputs
   if(stopLossPips <= 0 || riskAmount <= 0) {
      Print("Invalid inputs for position sizing: Risk=", riskAmount, " SL Pips=", stopLossPips);
      return symbolInfo.LotsMin();
   }
   
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();
   double lotStep = symbolInfo.LotsStep();
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   
   // Calculate value per pip
   double valuePerPip = tickValue * (pipSize / tickSize);
   
   // Calculate position size based on risk and stop loss
   double positionSize = riskAmount / (stopLossPips * valuePerPip);
   
   // Round down to the nearest lot step
   positionSize = MathFloor(positionSize / lotStep) * lotStep;
   
   // Ensure minimum and maximum lot size
   positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
   
   return positionSize;
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions() {
   // Loop through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket)) {
         // Check if this position belongs to our EA
         if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER) continue;
         
         // Get position details
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double stopLoss = PositionGetDouble(POSITION_SL);
         double takeProfit = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Check if trailing stop should be activated
         if(Trade_UseTrailingStop) {
            double profitPips;
            
            if(posType == POSITION_TYPE_BUY) {
               profitPips = (currentPrice - openPrice) / pipSize;
            } else {
               profitPips = (openPrice - currentPrice) / pipSize;
            }
            
            // If profit exceeds activation threshold, apply trailing stop
            if(profitPips >= Trade_TrailingActivation) {
               ApplyTrailingStop(ticket, openPrice, currentPrice, stopLoss, posType);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply trailing stop to position                                  |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, double openPrice, double currentPrice, 
                      double currentSL, ENUM_POSITION_TYPE posType) {
   double newSL;
   
   if(posType == POSITION_TYPE_BUY) {
      // For long positions, trail below current price
      newSL = currentPrice - Trade_TrailingActivation * pipSize;
      
      // Only move stop loss up, never down
      if(newSL <= currentSL) return;
   } else {
      // For short positions, trail above current price
      newSL = currentPrice + Trade_TrailingActivation * pipSize;
      
      // Only move stop loss down, never up
      if(newSL >= currentSL) return;
   }
   
   // Modify the position with new stop loss
   if(!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP))) {
      Print("Error modifying trailing stop: ", GetLastError());
   } else {
      Print("Trailing stop updated for ticket #", ticket, " New SL: ", newSL);
   }
}

//+------------------------------------------------------------------+
//| Custom function for strategy tester optimization                 |
//+------------------------------------------------------------------+
double OnTester() {
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   double trades = TesterStatistics(STAT_TRADES);
   
   // Custom scoring formula prioritizing consistent performance with low drawdown
   double score = 0;
   
   // Avoid division by zero
   if(drawdown < 0.1) drawdown = 0.1;
   
   // Basic score components
   if(profitFactor > 1.0) score += profitFactor * 5;
   if(sharpeRatio > 0) score += sharpeRatio * 10;
   
   // Penalize high drawdown
   score -= drawdown / 10;
   
   // Reward higher number of trades (for statistical significance)
   if(trades > 30) score += MathLog(trades) * 2;
   
   // Reward positive expected payoff
   if(expectedPayoff > 0) score += expectedPayoff;
   
   return score;
}

//+------------------------------------------------------------------+
//| Error handling function                                          |
//+------------------------------------------------------------------+
void HandleError(int errorCode, string operation) {
   string errorDesc = "";
   
   switch(errorCode) {
      case 0: // ERR_NO_ERROR
         return; // No error
      case 4051: // ERR_INVALID_STOPS
         errorDesc = "Invalid stops";
         break;
      case 4107: // ERR_INVALID_TRADE_PARAMETERS
         errorDesc = "Invalid trade parameters";
         break;
      case 4106: // ERR_INVALID_VOLUME
         errorDesc = "Invalid trade volume";
         break;
      case 10019: // ERR_NOT_ENOUGH_MONEY
         errorDesc = "Not enough money";
         break;
      case 4109: // ERR_TRADE_DISABLED
         errorDesc = "Trading disabled";
         break;
      default:
         errorDesc = "Error code " + IntegerToString(errorCode);
         break;
   }
   
   Print("Error during ", operation, ": ", errorDesc);
}

//+------------------------------------------------------------------+
//| Determine market regime (trending/ranging)                       |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetermineMarketRegime() {
   double adx[];
   if(CopyBuffer(adxHandle, 0, 0, 20, adx) != 20) {
      Print("Error copying ADX data: ", GetLastError());
      return REGIME_NEUTRAL; // Default
   }
   
   // Calculate average ADX
   double avgADX = 0;
   for(int i = 0; i < 14; i++) {
      avgADX += adx[i];
   }
   avgADX /= 14;
   
   // Determine regime
   if(avgADX > 30) return REGIME_TRENDING;
   if(avgADX < 20) return REGIME_RANGING;
   return REGIME_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Check for bullish candlestick patterns                           |
//+------------------------------------------------------------------+
PatternResult CheckBullishPatterns(MqlRates &rates[], int startIdx, SRZone &nearZone) {
   PatternResult result;
   
   // Calculate candle properties for easy reference
   double bodySize1 = MathAbs(rates[startIdx].close - rates[startIdx].open);
   double upperWick1 = rates[startIdx].high - MathMax(rates[startIdx].close, rates[startIdx].open);
   double lowerWick1 = MathMin(rates[startIdx].close, rates[startIdx].open) - rates[startIdx].low;
   double totalSize1 = rates[startIdx].high - rates[startIdx].low;
   
   double bodySize2 = (startIdx+1 < ArraySize(rates)) ? MathAbs(rates[startIdx+1].close - rates[startIdx+1].open) : 0;
   double upperWick2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].high - MathMax(rates[startIdx+1].close, rates[startIdx+1].open) : 0;
   double lowerWick2 = (startIdx+1 < ArraySize(rates)) ? MathMin(rates[startIdx+1].close, rates[startIdx+1].open) - rates[startIdx+1].low : 0;
   double totalSize2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].high - rates[startIdx+1].low : 0;
   
   // For three-candle patterns
   double bodySize3 = (startIdx+2 < ArraySize(rates)) ? MathAbs(rates[startIdx+2].close - rates[startIdx+2].open) : 0;
   double upperWick3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].high - MathMax(rates[startIdx+2].close, rates[startIdx+2].open) : 0;
   double lowerWick3 = (startIdx+2 < ArraySize(rates)) ? MathMin(rates[startIdx+2].close, rates[startIdx+2].open) - rates[startIdx+2].low : 0;
   double totalSize3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].high - rates[startIdx+2].low : 0;
   
   bool isBullish1 = rates[startIdx].close > rates[startIdx].open;
   bool isBearish1 = rates[startIdx].close < rates[startIdx].open;
   bool isBullish2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].close > rates[startIdx+1].open : false;
   bool isBearish2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].close < rates[startIdx+1].open : false;
   bool isBullish3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].close > rates[startIdx+2].open : false;
   bool isBearish3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].close < rates[startIdx+2].open : false;
   
   // Base reliability - will be modified by pattern specifics
   double reliability = 5.0;
   
   // Enhanced reliability if pattern is at a support/resistance zone
   if(nearZone.isValid) {
      reliability += nearZone.strength / 2;
      
      // Even better if it's at support for bullish pattern
      if(nearZone.isSupport) reliability += 1.0;
   }
   
   // Check for single-candle patterns
   
   // 1. Hammer/Bullish Pin Bar (high reliability at support)
   if(isBullish1 && 
      lowerWick1 > bodySize1 * 2 && 
      lowerWick1 > upperWick1 * 3 && 
      lowerWick1 > totalSize1 * 0.6) {
      
      result.detected = true;
      result.patternName = "Hammer";
      // Higher reliability for true hammers
      result.reliability = reliability + 2 + (lowerWick1 / totalSize1) * 2;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 2. Bullish Marubozu (strong bullish signal)
   if(isBullish1 && 
      bodySize1 > totalSize1 * 0.9 && 
      upperWick1 < totalSize1 * 0.05 && 
      lowerWick1 < totalSize1 * 0.05) {
      
      result.detected = true;
      result.patternName = "Bullish Marubozu";
      result.reliability = reliability + 1.5 + (bodySize1 / totalSize1) * 3;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 3. Bullish Inverted Hammer
   if(isBullish1 && 
      upperWick1 > bodySize1 * 2 && 
      upperWick1 > lowerWick1 * 3 && 
      upperWick1 > totalSize1 * 0.6) {
      
      result.detected = true;
      result.patternName = "Inverted Hammer";
      // Lower reliability for inverted hammers than regular hammers
      result.reliability = reliability + 0.5 + (upperWick1 / totalSize1) * 1.5;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 4. Dragonfly Doji (strong reversal signal at support)
   if(MathAbs(rates[startIdx].open - rates[startIdx].close) < totalSize1 * 0.05 && 
      lowerWick1 > totalSize1 * 0.7 && 
      upperWick1 < totalSize1 * 0.05) {
      
      result.detected = true;
      result.patternName = "Dragonfly Doji";
      result.reliability = reliability + 2.5 + (lowerWick1 / totalSize1) * 2;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // Check for two-candle patterns
   if(startIdx+1 >= ArraySize(rates)) return result; // Not enough candles
   
   // 5. Bullish Engulfing (strong reversal signal)
   if(isBullish1 && isBearish2 && 
      rates[startIdx].close > rates[startIdx+1].open && 
      rates[startIdx].open < rates[startIdx+1].close) {
      
      // Calculate engulfing quality
      double engulfSize = (rates[startIdx].close - rates[startIdx].open) / (rates[startIdx+1].open - rates[startIdx+1].close);
      
      result.detected = true;
      result.patternName = "Bullish Engulfing";
      // Higher reliability for larger engulfing
      result.reliability = reliability + 2 + (engulfSize > 1.5 ? 1.5 : engulfSize - 1);
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 6. Tweezer Bottom (reversal signal at support)
   if(MathAbs(rates[startIdx].low - rates[startIdx+1].low) < totalSize1 * 0.1 && 
      isBearish2 && isBullish1) {
      
      result.detected = true;
      result.patternName = "Tweezer Bottom";
      result.reliability = reliability + 1.5;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 7. Bullish Harami (reversal signal)
   if(isBullish1 && isBearish2 && 
      rates[startIdx].high < rates[startIdx+1].open && 
      rates[startIdx].low > rates[startIdx+1].close && 
      bodySize1 < bodySize2 * 0.6) {
      
      result.detected = true;
      result.patternName = "Bullish Harami";
      result.reliability = reliability + 1.0;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 8. Piercing Line Pattern
   if(isBullish1 && isBearish2 && 
      rates[startIdx].open < rates[startIdx+1].close && 
      rates[startIdx].close > rates[startIdx+1].close + bodySize2 * 0.5 && 
      rates[startIdx].close < rates[startIdx+1].open) {
      
      result.detected = true;
      result.patternName = "Piercing Line";
      result.reliability = reliability + 1.5 + (rates[startIdx].close - rates[startIdx+1].close) / bodySize2;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // Check for three-candle patterns
   if(startIdx+2 >= ArraySize(rates)) return result; // Not enough candles
   
   // 9. Morning Star
   if(isBullish1 && 
      bodySize2 < bodySize1 * 0.5 && bodySize2 < bodySize3 * 0.5 && // Small middle candle
      isBearish3 && // First candle bearish
      rates[startIdx].close > rates[startIdx+2].close + bodySize3 * 0.5) { // Closed above midpoint of first candle
      
      result.detected = true;
      result.patternName = "Morning Star";
      result.reliability = reliability + 2.5;
      if(bodySize2 < totalSize2 * 0.1) { // If middle candle is a doji
         result.patternName = "Morning Doji Star";
         result.reliability += 0.5;
      }
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 10. Three White Soldiers
   if(isBullish1 && isBullish2 && isBullish3 && 
      rates[startIdx].close > rates[startIdx+1].close && 
      rates[startIdx+1].close > rates[startIdx+2].close && 
      rates[startIdx].open > rates[startIdx+1].open && 
      rates[startIdx+1].open > rates[startIdx+2].open && 
      upperWick1 < bodySize1 * 0.15 && 
      upperWick2 < bodySize2 * 0.15 && 
      upperWick3 < bodySize3 * 0.15) {
      
      result.detected = true;
      result.patternName = "Three White Soldiers";
      result.reliability = reliability + 3.0;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 11. Bullish Abandoned Baby
   if(isBullish1 && 
      MathAbs(rates[startIdx+1].close - rates[startIdx+1].open) < totalSize2 * 0.1 && // Doji in middle
      rates[startIdx+1].low > rates[startIdx].high && // Gap up from doji
      rates[startIdx+1].low > rates[startIdx+2].high && // Gap down to doji
      isBearish3) {
      
      result.detected = true;
      result.patternName = "Bullish Abandoned Baby";
      result.reliability = reliability + 4.0; // Very reliable pattern
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 12. Three Inside Up
   if(isBullish1 && isBullish2 && isBearish3 && 
      rates[startIdx+1].high < rates[startIdx+2].open && 
      rates[startIdx+1].low > rates[startIdx+2].close && 
      rates[startIdx].close > rates[startIdx+2].open) {
      
      result.detected = true;
      result.patternName = "Three Inside Up";
      result.reliability = reliability + 2.0;
      result.time = rates[startIdx].time;
      return result;
   }
   
   return result; // No pattern detected
}

//+------------------------------------------------------------------+
//| Check for bearish candlestick patterns                           |
//+------------------------------------------------------------------+
PatternResult CheckBearishPatterns(MqlRates &rates[], int startIdx, SRZone &nearZone) {
   PatternResult result;
   
   // Calculate candle properties for easy reference
   double bodySize1 = MathAbs(rates[startIdx].close - rates[startIdx].open);
   double upperWick1 = rates[startIdx].high - MathMax(rates[startIdx].close, rates[startIdx].open);
   double lowerWick1 = MathMin(rates[startIdx].close, rates[startIdx].open) - rates[startIdx].low;
   double totalSize1 = rates[startIdx].high - rates[startIdx].low;
   
   double bodySize2 = (startIdx+1 < ArraySize(rates)) ? MathAbs(rates[startIdx+1].close - rates[startIdx+1].open) : 0;
   double upperWick2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].high - MathMax(rates[startIdx+1].close, rates[startIdx+1].open) : 0;
   double lowerWick2 = (startIdx+1 < ArraySize(rates)) ? MathMin(rates[startIdx+1].close, rates[startIdx+1].open) - rates[startIdx+1].low : 0;
   double totalSize2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].high - rates[startIdx+1].low : 0;
   
   // For three-candle patterns
   double bodySize3 = (startIdx+2 < ArraySize(rates)) ? MathAbs(rates[startIdx+2].close - rates[startIdx+2].open) : 0;
   double upperWick3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].high - MathMax(rates[startIdx+2].close, rates[startIdx+2].open) : 0;
   double lowerWick3 = (startIdx+2 < ArraySize(rates)) ? MathMin(rates[startIdx+2].close, rates[startIdx+2].open) - rates[startIdx+2].low : 0;
   double totalSize3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].high - rates[startIdx+2].low : 0;
   
   bool isBullish1 = rates[startIdx].close > rates[startIdx].open;
   bool isBearish1 = rates[startIdx].close < rates[startIdx].open;
   bool isBullish2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].close > rates[startIdx+1].open : false;
   bool isBearish2 = (startIdx+1 < ArraySize(rates)) ? rates[startIdx+1].close < rates[startIdx+1].open : false;
   bool isBullish3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].close > rates[startIdx+2].open : false;
   bool isBearish3 = (startIdx+2 < ArraySize(rates)) ? rates[startIdx+2].close < rates[startIdx+2].open : false;
   
   // Base reliability - will be modified by pattern specifics
   double reliability = 5.0;
   
   // Enhanced reliability if pattern is at a support/resistance zone
   if(nearZone.isValid) {
      reliability += nearZone.strength / 2;
      
      // Even better if it's at resistance for bearish pattern
      if(!nearZone.isSupport) reliability += 1.0;
   }
   
   // Check for single-candle patterns
   
   // 1. Shooting Star/Bearish Pin Bar (high reliability at resistance)
   if(isBearish1 && 
      upperWick1 > bodySize1 * 2 && 
      upperWick1 > lowerWick1 * 3 && 
      upperWick1 > totalSize1 * 0.6) {
      
      result.detected = true;
      result.patternName = "Shooting Star";
      // Higher reliability for true shooting stars
      result.reliability = reliability + 2 + (upperWick1 / totalSize1) * 2;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 2. Bearish Marubozu (strong bearish signal)
   if(isBearish1 && 
      bodySize1 > totalSize1 * 0.9 && 
      upperWick1 < totalSize1 * 0.05 && 
      lowerWick1 < totalSize1 * 0.05) {
      
      result.detected = true;
      result.patternName = "Bearish Marubozu";
      result.reliability = reliability + 1.5 + (bodySize1 / totalSize1) * 3;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 3. Hanging Man
   if(isBearish1 && 
      lowerWick1 > bodySize1 * 2 && 
      lowerWick1 > upperWick1 * 3 && 
      lowerWick1 > totalSize1 * 0.6) {
      
      result.detected = true;
      result.patternName = "Hanging Man";
      result.reliability = reliability + 0.5 + (lowerWick1 / totalSize1) * 1.5;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 4. Gravestone Doji (strong reversal signal at resistance)
   if(MathAbs(rates[startIdx].open - rates[startIdx].close) < totalSize1 * 0.05 && 
      upperWick1 > totalSize1 * 0.7 && 
      lowerWick1 < totalSize1 * 0.05) {
      
      result.detected = true;
      result.patternName = "Gravestone Doji";
      result.reliability = reliability + 2.5 + (upperWick1 / totalSize1) * 2;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // Check for two-candle patterns
   if(startIdx+1 >= ArraySize(rates)) return result; // Not enough candles
   
   // 5. Bearish Engulfing (strong reversal signal)
   if(isBearish1 && isBullish2 && 
      rates[startIdx].close < rates[startIdx+1].open && 
      rates[startIdx].open > rates[startIdx+1].close) {
      
      // Calculate engulfing quality
      double engulfSize = (rates[startIdx].open - rates[startIdx].close) / (rates[startIdx+1].close - rates[startIdx+1].open);
      
      result.detected = true;
      result.patternName = "Bearish Engulfing";
      // Higher reliability for larger engulfing
      result.reliability = reliability + 2 + (engulfSize > 1.5 ? 1.5 : engulfSize - 1);
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 6. Tweezer Top (reversal signal at resistance)
   if(MathAbs(rates[startIdx].high - rates[startIdx+1].high) < totalSize1 * 0.1 && 
      isBullish2 && isBearish1) {
      
      result.detected = true;
      result.patternName = "Tweezer Top";
      result.reliability = reliability + 1.5;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 7. Bearish Harami (reversal signal)
   if(isBearish1 && isBullish2 && 
      rates[startIdx].high < rates[startIdx+1].close && 
      rates[startIdx].low > rates[startIdx+1].open && 
      bodySize1 < bodySize2 * 0.6) {
      
      result.detected = true;
      result.patternName = "Bearish Harami";
      result.reliability = reliability + 1.0;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 8. Dark Cloud Cover
   if(isBearish1 && isBullish2 && 
      rates[startIdx].open > rates[startIdx+1].close && 
      rates[startIdx].close < rates[startIdx+1].open - bodySize2 * 0.5 && 
      rates[startIdx].close > rates[startIdx+1].close) {
      
      result.detected = true;
      result.patternName = "Dark Cloud Cover";
      result.reliability = reliability + 1.5 + (rates[startIdx+1].open - rates[startIdx].close) / bodySize2;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // Check for three-candle patterns
   if(startIdx+2 >= ArraySize(rates)) return result; // Not enough candles
   
   // 9. Evening Star
   if(isBearish1 && 
      bodySize2 < bodySize1 * 0.5 && bodySize2 < bodySize3 * 0.5 && // Small middle candle
      isBullish3 && // First candle bullish
      rates[startIdx].close < rates[startIdx+2].close - bodySize3 * 0.5) { // Closed below midpoint of first candle
      
      result.detected = true;
      result.patternName = "Evening Star";
      result.reliability = reliability + 2.5;
      if(bodySize2 < totalSize2 * 0.1) { // If middle candle is a doji
         result.patternName = "Evening Doji Star";
         result.reliability += 0.5;
      }
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 10. Three Black Crows
   if(isBearish1 && isBearish2 && isBearish3 && 
      rates[startIdx].close < rates[startIdx+1].close && 
      rates[startIdx+1].close < rates[startIdx+2].close && 
      rates[startIdx].open < rates[startIdx+1].open && 
      rates[startIdx+1].open < rates[startIdx+2].open && 
      lowerWick1 < bodySize1 * 0.15 && 
      lowerWick2 < bodySize2 * 0.15 && 
      lowerWick3 < bodySize3 * 0.15) {
      
      result.detected = true;
      result.patternName = "Three Black Crows";
      result.reliability = reliability + 3.0;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 11. Bearish Abandoned Baby
   if(isBearish1 && 
      MathAbs(rates[startIdx+1].close - rates[startIdx+1].open) < totalSize2 * 0.1 && // Doji in middle
      rates[startIdx+1].high < rates[startIdx].low && // Gap down from doji
      rates[startIdx+1].high < rates[startIdx+2].low && // Gap up to doji
      isBullish3) {
      
      result.detected = true;
      result.patternName = "Bearish Abandoned Baby";
      result.reliability = reliability + 4.0; // Very reliable pattern
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 12. Three Inside Down
   if(isBearish1 && isBearish2 && isBullish3 && 
      rates[startIdx+1].high < rates[startIdx+2].close && 
      rates[startIdx+1].low > rates[startIdx+2].open && 
      rates[startIdx].close < rates[startIdx+2].open) {
      
      result.detected = true;
      result.patternName = "Three Inside Down";
      result.reliability = reliability + 2.0;
      result.time = rates[startIdx].time;
      return result;
   }
   
   // 13. Bearish Belt Hold
   if(isBearish1 && 
      rates[startIdx].open == rates[startIdx].high && // Open at high
      bodySize1 > totalSize1 * 0.8 && // Large bearish body
      lowerWick1 < totalSize1 * 0.1) { // Small or no lower wick
      
      result.detected = true;
      result.patternName = "Bearish Belt Hold";
      result.reliability = reliability + 1.5;
      result.time = rates[startIdx].time;
      return result;
   }
   
   return result; // No pattern detected
}

//+------------------------------------------------------------------+
//| Find the nearest S/R zone to a price level                       |
//+------------------------------------------------------------------+
SRZone FindNearestZone(double price, bool lookForSupport) {
   SRZone emptyZone; // Default return if no zone found
   double minDistance = DBL_MAX;
   int nearestIdx = -1;
   
   for(int i = 0; i < zoneCount; i++) {
      if(!zones[i].isValid) continue;
      if(zones[i].isSupport != lookForSupport) continue;
      
      double zonePrice = lookForSupport ? zones[i].upperBound : zones[i].lowerBound;
      double distance = MathAbs(price - zonePrice);
      
      if(distance < minDistance) {
         minDistance = distance;
         nearestIdx = i;
      }
   }
   
   // If a zone was found and it's within a reasonable distance
   if(nearestIdx >= 0 && minDistance < 100 * pipSize) {
      return zones[nearestIdx];
   }
   
   return emptyZone;
}

//+------------------------------------------------------------------+
//| Check for candlestick patterns at current price                  |
//+------------------------------------------------------------------+
PatternResult CheckForPatterns(MqlRates &rates[], int startIdx = 0) {
   // Make sure we have enough candles
   if(ArraySize(rates) < 3 || startIdx >= ArraySize(rates) - 2) {
      PatternResult emptyResult;
      return emptyResult;
   }
   
   // Find nearest support and resistance zones
   double currentPrice = rates[startIdx].close;
   SRZone nearestSupport = FindNearestZone(currentPrice, true);
   SRZone nearestResistance = FindNearestZone(currentPrice, false);
   
   // Determine which zone is closer
   SRZone nearestZone;
   if(nearestSupport.isValid && nearestResistance.isValid) {
      double distToSupport = MathAbs(currentPrice - nearestSupport.upperBound);
      double distToResistance = MathAbs(currentPrice - nearestResistance.lowerBound);
      
      nearestZone = (distToSupport < distToResistance) ? nearestSupport : nearestResistance;
   } else if(nearestSupport.isValid) {
      nearestZone = nearestSupport;
   } else if(nearestResistance.isValid) {
      nearestZone = nearestResistance;
   }
   
   // Check for bullish patterns
   PatternResult bullishResult = CheckBullishPatterns(rates, startIdx, nearestZone);
   
   // Check for bearish patterns
   PatternResult bearishResult = CheckBearishPatterns(rates, startIdx, nearestZone);
   
   // Return the pattern with higher reliability
   if(bullishResult.detected && bearishResult.detected) {
      return (bullishResult.reliability > bearishResult.reliability) ? bullishResult : bearishResult;
   } else if(bullishResult.detected) {
      return bullishResult;
   } else if(bearishResult.detected) {
      return bearishResult;
   }
   
   // No pattern detected
   PatternResult emptyResult;
   return emptyResult;
}

//+------------------------------------------------------------------+
//| Determine if a pattern is bullish or bearish                     |
//+------------------------------------------------------------------+
bool IsPatternBullish(string patternName) {
   string bullishPatterns[] = {
      "Hammer", "Bullish Marubozu", "Inverted Hammer", "Dragonfly Doji",
      "Bullish Engulfing", "Tweezer Bottom", "Bullish Harami", "Piercing Line",
      "Morning Star", "Morning Doji Star", "Three White Soldiers", 
      "Bullish Abandoned Baby", "Three Inside Up"
   };
   
   for(int i = 0; i < ArraySize(bullishPatterns); i++) {
      if(patternName == bullishPatterns[i]) return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Integrate pattern detection into trade decision                  |
//+------------------------------------------------------------------+
bool ShouldTradeBounce(int zoneIndex, MqlRates &rates[], double adxValue, double rsiValue) {
   // Get pattern at current price
   PatternResult pattern = CheckForPatterns(rates);
   
   // If no pattern detected, use simpler criteria
   if(!pattern.detected) {
      // Use the original bounce criteria
      return CheckBounceScenario(zoneIndex, SymbolInfoDouble(_Symbol, SYMBOL_BID), rates, adxValue, rsiValue) == SCENARIO_BOUNCE;
   }
   
   // Pattern detected - check if it aligns with the zone
   bool patternAligned = false;
   
   if(zones[zoneIndex].isSupport && IsPatternBullish(pattern.patternName)) {
      // Bullish pattern at support - aligned
      patternAligned = true;
   } else if(!zones[zoneIndex].isSupport && !IsPatternBullish(pattern.patternName)) {
      // Bearish pattern at resistance - aligned
      patternAligned = true;
   }
   
   // Consider pattern reliability
   if(patternAligned && pattern.reliability >= 6.0) {
      // High reliability pattern that aligns with zone - strong signal
      return true;
   } else if(patternAligned && pattern.reliability >= 4.0) {
      // Medium reliability pattern - check additional confirmation
      if(zones[zoneIndex].isSupport && rsiValue < 40) return true;
      if(!zones[zoneIndex].isSupport && rsiValue > 60) return true;
   }
   
   // Fall back to original criteria if pattern doesn't provide clear signal
   return CheckBounceScenario(zoneIndex, SymbolInfoDouble(_Symbol, SYMBOL_BID), rates, adxValue, rsiValue) == SCENARIO_BOUNCE;
}

//+------------------------------------------------------------------+
//| Integrate pattern detection into breakout decision               |
//+------------------------------------------------------------------+
bool ShouldTradeBreakout(int zoneIndex, MqlRates &rates[], double adxValue) {
   // Get pattern at current price
   PatternResult pattern = CheckForPatterns(rates);
   
   // If no pattern detected, use simpler criteria
   if(!pattern.detected) {
      // Use the original breakout criteria
      return CheckBreakoutScenario(zoneIndex, SymbolInfoDouble(_Symbol, SYMBOL_BID), rates, adxValue) == SCENARIO_BREAKOUT;
   }
   
   // Pattern detected - check if it aligns with breakout direction
   bool patternAligned = false;
   
   if(zones[zoneIndex].isSupport && !IsPatternBullish(pattern.patternName)) {
      // Bearish pattern breaking support - aligned
      patternAligned = true;
   } else if(!zones[zoneIndex].isSupport && IsPatternBullish(pattern.patternName)) {
      // Bullish pattern breaking resistance - aligned
      patternAligned = true;
   }
   
   // Consider pattern reliability for breakouts
   if(patternAligned && pattern.reliability >= 6.5) {
      // High reliability pattern that aligns with breakout direction - strong signal
      return true;
   } else if(patternAligned && pattern.reliability >= 5.0 && adxValue > Trade_ADXThreshold) {
      // Medium reliability pattern with strong trend - good breakout signal
      return true;
   }
   
   // Fall back to original criteria if pattern doesn't provide clear signal
   return CheckBreakoutScenario(zoneIndex, SymbolInfoDouble(_Symbol, SYMBOL_BID), rates, adxValue) == SCENARIO_BREAKOUT;
}

//+------------------------------------------------------------------+
//| Draw pattern on chart for visual confirmation                    |
//+------------------------------------------------------------------+
void DrawPatternOnChart(PatternResult &pattern, MqlRates &rates[], int startIdx) {
   if(!pattern.detected || !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   
   string objectName = "Pattern_" + TimeToString(pattern.time) + "_" + pattern.patternName;
   
   // Delete existing object if it exists
   ObjectDelete(0, objectName);
   
   // Create text object
   ObjectCreate(0, objectName, OBJ_TEXT, 0, rates[startIdx].time, rates[startIdx].high + 20*pipSize);
   ObjectSetString(0, objectName, OBJPROP_TEXT, pattern.patternName);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, IsPatternBullish(pattern.patternName) ? clrGreen : clrRed);
   ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 8);
   
   // Create arrow
   string arrowName = "Arrow_" + objectName;
   ObjectCreate(0, arrowName, OBJ_ARROW, 0, rates[startIdx].time, 
               IsPatternBullish(pattern.patternName) ? rates[startIdx].low - 10*pipSize : rates[startIdx].high + 10*pipSize);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 
                   IsPatternBullish(pattern.patternName) ? 217 : 218); // Up/down arrows
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, 
                   IsPatternBullish(pattern.patternName) ? clrGreen : clrRed);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   
   // Draw pattern-specific visualization
   if(StringFind(pattern.patternName, "Engulfing") >= 0) {
      // Highlight the engulfing candles
      string rect1 = "Rect1_" + objectName;
      string rect2 = "Rect2_" + objectName;
      
      ObjectCreate(0, rect1, OBJ_RECTANGLE, 0, 
                  rates[startIdx].time, MathMax(rates[startIdx].open, rates[startIdx].close),
                  rates[startIdx].time + PeriodSeconds(Period())*0.8, MathMin(rates[startIdx].open, rates[startIdx].close));
      
      ObjectCreate(0, rect2, OBJ_RECTANGLE, 0, 
                  rates[startIdx+1].time, MathMax(rates[startIdx+1].open, rates[startIdx+1].close),
                  rates[startIdx+1].time + PeriodSeconds(Period())*0.8, MathMin(rates[startIdx+1].open, rates[startIdx+1].close));
      
      ObjectSetInteger(0, rect1, OBJPROP_COLOR, IsPatternBullish(pattern.patternName) ? clrGreen : clrRed);
      ObjectSetInteger(0, rect2, OBJPROP_COLOR, IsPatternBullish(pattern.patternName) ? clrRed : clrGreen);
      ObjectSetInteger(0, rect1, OBJPROP_FILL, true);
      ObjectSetInteger(0, rect2, OBJPROP_FILL, true);
      ObjectSetInteger(0, rect1, OBJPROP_BACK, true);
      ObjectSetInteger(0, rect2, OBJPROP_BACK, true);
   }
   else if(StringFind(pattern.patternName, "Star") >= 0) {
      // Highlight the three candles of the star pattern
      for(int i=0; i<3; i++) {
         string rectName = "Star_" + IntegerToString(i) + "_" + objectName;
         
         ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, 
                     rates[startIdx+i].time, MathMax(rates[startIdx+i].open, rates[startIdx+i].close),
                     rates[startIdx+i].time + PeriodSeconds(Period())*0.8, MathMin(rates[startIdx+i].open, rates[startIdx+i].close));
         
         color candleColor = (rates[startIdx+i].close > rates[startIdx+i].open) ? clrGreen : clrRed;
         ObjectSetInteger(0, rectName, OBJPROP_COLOR, candleColor);
         ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
         ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      }
   }
   else if(StringFind(pattern.patternName, "Doji") >= 0) {
      // Highlight the doji
      string dojiLine = "DojiLine_" + objectName;
      
      ObjectCreate(0, dojiLine, OBJ_TREND, 0, 
                  rates[startIdx].time, rates[startIdx].low,
                  rates[startIdx].time, rates[startIdx].high);
      
      ObjectSetInteger(0, dojiLine, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, dojiLine, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, dojiLine, OBJPROP_RAY_RIGHT, false);
   }
   
   // Add reliability indicator
   string reliabilityName = "Reliability_" + objectName;
   ObjectCreate(0, reliabilityName, OBJ_TEXT, 0, 
               rates[startIdx].time, rates[startIdx].high + 30*pipSize);
   ObjectSetString(0, reliabilityName, OBJPROP_TEXT, 
                  StringFormat("Reliability: %.1f/10", pattern.reliability));
   ObjectSetInteger(0, reliabilityName, OBJPROP_COLOR, pattern.reliability >= 7.0 ? clrLime : 
                                                      pattern.reliability >= 5.0 ? clrYellow : clrOrange);
   ObjectSetInteger(0, reliabilityName, OBJPROP_FONTSIZE, 8);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Modified ScanForPatterns function to handle volume errors        |
//+------------------------------------------------------------------+
void ScanForPatterns() {
   // Get rates for each timeframe
   MqlRates ratesM15[];
   MqlRates ratesH4[];
   MqlRates ratesD1[];
   
   bool ratesValid = true;
   
   if(CopyRates(_Symbol, TimeframeEntry, 0, 10, ratesM15) != 10 ||
      CopyRates(_Symbol, TimeframeConfirm, 0, 10, ratesH4) != 10 ||
      CopyRates(_Symbol, TimeframeZones, 0, 10, ratesD1) != 10) {
      Print("Error copying rates for pattern scanning: ", GetLastError());
      ratesValid = false;
   }
   
   if(!ratesValid) return;
   
   // Check for patterns on each timeframe
   PatternResult patternM15 = CheckForPatterns(ratesM15);
   PatternResult patternH4 = CheckForPatterns(ratesH4);
   PatternResult patternD1 = CheckForPatterns(ratesD1);
   
   // Draw patterns if detected
   if(patternM15.detected) {
      DrawPatternOnChart(patternM15, ratesM15, 0);
      Print("M15 Pattern detected: ", patternM15.patternName, " (Reliability: ", 
            DoubleToString(patternM15.reliability, 1), ")");
   }
   
   if(patternH4.detected) {
      DrawPatternOnChart(patternH4, ratesH4, 0);
      Print("H4 Pattern detected: ", patternH4.patternName, " (Reliability: ", 
            DoubleToString(patternH4.reliability, 1), ")");
   }
   
   if(patternD1.detected) {
      DrawPatternOnChart(patternD1, ratesD1, 0);
      Print("D1 Pattern detected: ", patternD1.patternName, " (Reliability: ", 
            DoubleToString(patternD1.reliability, 1), ")");
   }
   
   // Check for multi-timeframe confluence
   if(patternM15.detected && patternH4.detected) {
      bool sameDirection = (IsPatternBullish(patternM15.patternName) == IsPatternBullish(patternH4.patternName));
      
      if(sameDirection) {
         string direction = IsPatternBullish(patternM15.patternName) ? "BULLISH" : "BEARISH";
         Print("STRONG SIGNAL: Multi-timeframe confluence - ", direction, " patterns on M15 and H4");
         
         // Create alert object
         if(MQLInfoInteger(MQL_VISUAL_MODE)) {
            string alertName = "MTF_Alert_" + TimeToString(TimeCurrent());
            ObjectCreate(0, alertName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
            ObjectSetInteger(0, alertName, OBJPROP_XDISTANCE, 50);
            ObjectSetInteger(0, alertName, OBJPROP_YDISTANCE, 50);
            ObjectSetInteger(0, alertName, OBJPROP_XSIZE, 200);
            ObjectSetInteger(0, alertName, OBJPROP_YSIZE, 30);
            ObjectSetInteger(0, alertName, OBJPROP_BGCOLOR, direction == "BULLISH" ? clrGreen : clrRed);
            ObjectSetInteger(0, alertName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetString(0, alertName, OBJPROP_TEXT, "MTF " + direction + " SIGNAL");
            ObjectSetInteger(0, alertName, OBJPROP_FONTSIZE, 10);
         }
      }
   }
}
