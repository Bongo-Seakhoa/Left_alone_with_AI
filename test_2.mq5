//+------------------------------------------------------------------+
//|             Adaptive Market Regime Trading System                |
//|                 © 2023 Advanced Trading Systems                  |
//|                           Version 2.1                            |
//+------------------------------------------------------------------+
#property copyright "© 2023 Advanced Trading Systems"
#property link      ""
#property version   "2.1"
#property strict

// Market regime classifications
enum ENUM_MARKET_REGIME {
   REGIME_TRENDING,          // Strong directional movement
   REGIME_RANGING,           // Sideways consolidation
   REGIME_VOLATILE,          // High volatility/unpredictable
   REGIME_BREAKOUT           // Pattern completion/range breach
};

// Volume significance classifications
enum ENUM_VOLUME_SIGNIFICANCE {
   VOL_LOW,                  // Below average volume
   VOL_NORMAL,               // Average volume
   VOL_HIGH,                 // Above average volume
   VOL_CLIMACTIC             // Extremely high volume (potential exhaustion)
};

//--- Input Parameters: Trading Intelligence
input string               IntelligenceSettings = "=== Market Intelligence Settings ===";
input int                  RegimeDetectionPeriod = 100;              // Data points for regime detection
input int                  VolumeLookbackPeriod = 20;                // Volume analysis period
input bool                 EnableAdaptiveParameters = true;          // Self-adjust parameters
input bool                 EnableMarketRegimeFilters = true;         // Filter trades by market regime
input bool                 EnableVolatilityNormalization = true;     // Adjust to changing volatility

//--- Input Parameters: Strategy Controls
input string               StrategySettings = "=== Strategy Controls ===";
input bool                 EnableTrendStrategy = true;               // Use trend-following strategy
input bool                 EnableRangeStrategy = true;               // Use range-trading strategy
input bool                 EnableBreakoutStrategy = true;            // Use breakout strategy
input bool                 EnableVolumeConfirmation = true;          // Require volume confirmation
input bool                 EnableCorrelationFiltering = true;        // Use correlation filtering
input bool                 EnableTrading = true;                     // Master switch for trading

//--- Input Parameters: Risk Management
input string               RiskSettings = "=== Risk Management Framework ===";
input double               AccountRiskPercent = 1.5;                 // % of account to risk per trade
input double               MaxDailyRiskPercent = 5.0;                // Maximum daily risk
input bool                 UsePositionSizing = true;                 // Adjust position size based on risk
input bool                 UseAdaptiveRisk = true;                   // Adjust risk based on win/loss
input bool                 UseAntiMartingale = true;                 // Increase size after wins
input double               MaxPositionSize = 3.0;                    // Maximum position size in lots
input double               MinPositionSize = 0.01;                   // Minimum position size in lots
input double               RiskRewardMinimum = 0.8;                  // Minimum reward:risk ratio
input int                  MaxOpenPositions = 3;                     // Maximum concurrent positions

//--- Input Parameters: Exit Strategy
input string               ExitSettings = "=== Exit Strategy Settings ===";
input bool                 UseVolatilityBasedSL = true;              // Set SL based on volatility
input double               VolatilityMultiplierSL = 2.0;             // ATR multiplier for stop loss
input double               VolatilityMultiplierTP = 3.0;             // ATR multiplier for take profit
input bool                 UseMultipleTargets = true;                // Use multiple profit targets
input bool                 EnablePartialClose = true;                // Allow partial profit taking
input double               PartialClosePercent = 50.0;               // % to close at first target
input bool                 UseAdaptiveTrailing = true;               // Dynamic trailing stop
input bool                 UseVolatilityExpansion = true;            // Adjust for volatility shifts
input bool                 UseProfitLock = true;                     // Lock in a percentage of profit
input double               ProfitLockPercent = 60.0;                 // % of profit to lock in
input bool                 UseBreakEven = true;                      // Enable breakeven
input double               BreakEvenActivationRatio = 0.5;           // TP ratio to activate breakeven
input bool                 UseTrailingStop = true;                   // Enable trailing stop
input double               TrailingStopActivation = 1.0;             // ATR multiple to activate trailing
input double               TrailingStopDistance = 1.5;               // ATR multiple for trailing distance
input double               PartialCloseTrigger = 1.5;                // ATR multiple to trigger partial close
input double               PartialCloseRatio = 50.0;                 // Ratio of position to close

//--- Input Parameters: Technical Indicators
input string               IndicatorSettings = "=== Technical Indicators ===";
input double               RSIOverbought = 70.0;                     // RSI overbought level
input double               RSIOversold = 30.0;                       // RSI oversold level
input int                  BreakoutPeriod = 20;                      // Lookback period for breakouts

//--- Input Parameters: Time Filters
input string               TimeFilterSettings = "=== Time Filters ===";
input bool                 EnableTimeFilter = false;                  // Apply time filtering
input int                  TradeSessionStartHour = 8;                // Session start (server time)
input int                  TradeSessionEndHour = 20;                 // Session end (server time)
input bool                 AvoidHighImpactNews = true;               // Avoid trading near news
input int                  NewsBufferMinutes = 30;                   // Minutes before/after news

//--- Input Parameters: Execution Settings
input string               ExecutionSettings = "=== Execution Settings ===";
input int                  OrderRetries = 3;                         // Retry failed orders
input int                  MaxSlippage = 20;                          // Maximum allowed slippage
input int                  MagicNumber = 20230921;                   // EA identifier
input bool                 EnableRandomTesting = false;              // Allow random trades for testing
input int                  RandomTradePercent = 20;                   // Percentage chance of random trade

// Global variables for system state
datetime LastBarTime = 0;
bool IsNewBar = false;
ENUM_MARKET_REGIME CurrentRegime = REGIME_RANGING;
ENUM_VOLUME_SIGNIFICANCE CurrentVolume = VOL_NORMAL;
double CurrentATR = 0;
double AverageATR = 0;
double AverageVolume = 0;
double DailyRiskUsed = 0;
double PipValue = 0;
double SystemQuality = 50.0;  // 0-100 scale for system performance
int ConsecutiveWins = 0;
int ConsecutiveLosses = 0;
bool NewsEventNearby = false;
int DigitMultiplier = 1;
double AdaptiveRiskMultiplier = 1.0;
int TotalTrades = 0;

// Arrays for adaptive analytics
double WinRates[4];          // Win rates for each regime
double ProfitFactors[4];     // Profit factors for each regime
double ExpectedValues[4];    // Expected values for each regime

// Handles for indicators
int ATRHandle;
int MACDHandle;
int RSIHandle;
int BollingerHandle;
int VolumeHandle;

// Order management
struct TradeResult {
   bool success;
   string message;
   ulong ticket;
   double executedPrice;
   datetime executionTime;
   double slippage;
};

// Performance tracking
struct SystemPerformance {
   int totalTrades;
   int winningTrades;
   int losingTrades;
   double grossProfit;
   double grossLoss;
   double largestWin;
   double largestLoss;
   double avgWin;
   double avgLoss;
   double profitFactor;
   double expectancy;
   double sharpeRatio;
   double drawdown;
   double maxDrawdown;
};

SystemPerformance Performance;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize time and account management
   LastBarTime = 0;
   DailyRiskUsed = 0;
   
   // Set multiplier for pip calculations
   DigitMultiplier = (_Digits == 3 || _Digits == 5) ? 10 : 1;
   
   // Calculate pip value for position sizing
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   PipValue = (tickValue / tickSize) * Point() * DigitMultiplier;
   
   // Initialize indicator handles
   ATRHandle = iATR(Symbol(), PERIOD_M15, 14);
   MACDHandle = iMACD(Symbol(), PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   RSIHandle = iRSI(Symbol(), PERIOD_M15, 14, PRICE_CLOSE);
   BollingerHandle = iBands(Symbol(), PERIOD_M15, 20, 2, 0, PRICE_CLOSE);
   
   // Verify indicator creation
   if(ATRHandle == INVALID_HANDLE || MACDHandle == INVALID_HANDLE || 
      RSIHandle == INVALID_HANDLE || BollingerHandle == INVALID_HANDLE) {
      Print("Error initializing indicators: ", GetLastError());
      return INIT_FAILED;
   }
   
   // Initialize adaptive analytics
   for(int i = 0; i < 4; i++) {
      WinRates[i] = 50.0;          // Start with neutral 50% win rate for each regime
      ProfitFactors[i] = 1.0;      // Start with breakeven profit factor
      ExpectedValues[i] = 0.0;     // Start with neutral expected value
   }
   
   // Load historical performance if available
   if(!LoadPerformanceData()) {
      // Initialize new performance record
      Performance.totalTrades = 0;
      Performance.winningTrades = 0;
      Performance.losingTrades = 0;
      Performance.grossProfit = 0;
      Performance.grossLoss = 0;
      Performance.largestWin = 0;
      Performance.largestLoss = 0;
      Performance.profitFactor = 1.0;
      Performance.expectancy = 0;
      Performance.sharpeRatio = 0;
      Performance.drawdown = 0;
      Performance.maxDrawdown = 0;
   }
   
   // Initialize volume analysis
   AnalyzeHistoricalVolume();
   
   // Detect current market regime
   DetectMarketRegime();
   
   // Log initialization
   Print("Adaptive Market Regime Trading System initialized on ", Symbol(), " with 15-minute timeframe");
   Print("Current market regime detected: ", EnumToString(CurrentRegime));
   Print("Current volume state: ", EnumToString(CurrentVolume));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(ATRHandle);
   IndicatorRelease(MACDHandle);
   IndicatorRelease(RSIHandle);
   IndicatorRelease(BollingerHandle);
   
   // Save performance data
   SavePerformanceData();
   
   // Display performance summary
   PrintPerformanceSummary();
   
   Print("Adaptive Market Regime Trading System deinitialized, reason: ", GetDeinitReasonText(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

   // Process only on new bar for the 15-minute timeframe
   if(!IsNewCandle(PERIOD_M15))
      return;
   
   // Update system state and analytics
   UpdateSystemState();
   
   // Check if trading is allowed
   if(!IsTradingAllowed())
      return;
      
   // Manage existing positions (trailing stops, partial close, etc.)
   ManageOpenPositions();
   
   // Check if we can open new positions
   if(CountOpenPositions() >= MaxOpenPositions || DailyRiskUsed >= MaxDailyRiskPercent)
      return;
   
   // Analyze market and execute trade strategy based on current regime
   switch(CurrentRegime) {
      case REGIME_TRENDING:
         if(EnableTrendStrategy) 
            ExecuteTrendStrategy();
         break;
         
      case REGIME_RANGING:
         if(EnableRangeStrategy)
            ExecuteRangeStrategy();
         break;
         
      case REGIME_VOLATILE:
         // Generally avoid trading in highly volatile markets
         // unless volatility breakout strategy is specifically enabled
         if(UseVolatilityExpansion)
            ExecuteVolatilityStrategy();
         break;
         
      case REGIME_BREAKOUT:
         if(EnableBreakoutStrategy)
            ExecuteBreakoutStrategy();
         break;
   }
   
   // Add random entries for testing if enabled
   if(EnableRandomTesting && MathRand() % 100 < RandomTradePercent) {
      ExecuteRandomTrade();
   }
}

// ADD THIS FUNCTION at the beginning of OnTick() to add logging about trading conditions
void LogTradingConditions()
{
   static datetime lastLogTime = 0;
   datetime currentTime = TimeCurrent();
   
   // Only log once per hour to avoid flooding
   if(currentTime - lastLogTime < 3600)
      return;
      
   lastLogTime = currentTime;
   
   Print("====== Trading Conditions Log ======");
   Print("Current Regime: ", EnumToString(CurrentRegime));
   Print("Current Volume: ", EnumToString(CurrentVolume));
   Print("Current ATR: ", CurrentATR);
   Print("Average ATR: ", AverageATR);
   Print("EnableTrading: ", EnableTrading);
   Print("Time Filter Passed: ", IsWithinTradingHours());
   
   // Check strategy conditions to see if signals are being generated
   double macd[], signal[], fastEMA[], slowEMA[];
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(signal, true);
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   
   CopyBuffer(MACDHandle, 0, 0, 3, macd);
   CopyBuffer(MACDHandle, 1, 0, 3, signal);
   
   int fastEMAHandle = iMA(Symbol(), PERIOD_M15, 8, 0, MODE_EMA, PRICE_CLOSE);
   int slowEMAHandle = iMA(Symbol(), PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   
   CopyBuffer(fastEMAHandle, 0, 0, 3, fastEMA);
   CopyBuffer(slowEMAHandle, 0, 0, 3, slowEMA);
   
   IndicatorRelease(fastEMAHandle);
   IndicatorRelease(slowEMAHandle);
   
   bool macdCrossUp = macd[1] < signal[1] && macd[0] >= signal[0];
   bool macdCrossDown = macd[1] > signal[1] && macd[0] <= signal[0];
   bool emaAlignBullish = fastEMA[0] > slowEMA[0];
   bool emaAlignBearish = fastEMA[0] < slowEMA[0];
   
   Print("MACD cross up: ", macdCrossUp);
   Print("MACD cross down: ", macdCrossDown);
   Print("EMA align bullish: ", emaAlignBullish);
   Print("EMA align bearish: ", emaAlignBearish);
   
   // Calculate sample risk-reward to see if it's an issue
   double buyRR = CalculateRiskRewardRatio(ORDER_TYPE_BUY);
   double sellRR = CalculateRiskRewardRatio(ORDER_TYPE_SELL);
   Print("Buy Risk-Reward: ", buyRR);
   Print("Sell Risk-Reward: ", sellRR);
   Print("Minimum Required: ", RiskRewardMinimum);
   
   // Calculate sample position size
   double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double stopLossLevel = entryPrice - (CurrentATR * VolatilityMultiplierSL);
   double posSize = CalculatePositionSize(entryPrice, stopLossLevel);
   Print("Sample Position Size: ", posSize);
   Print("Minimum Position Size: ", MinPositionSize);
   
   Print("======================================");
}


//+------------------------------------------------------------------+
//| Execute a random trade for testing purposes                      |
//+------------------------------------------------------------------+
void ExecuteRandomTrade()
{
   bool isBuy = (MathRand() % 2 == 0);
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double riskReward = CalculateRiskRewardRatio(orderType, 2.0, 3.0);
   
   if(riskReward >= RiskRewardMinimum) {
      ExecuteTradeOrder(orderType, "Random Test Trade", 2.0, 3.0);
   }
}

//+------------------------------------------------------------------+
//| Check for a new candle on specified timeframe                    |
//+------------------------------------------------------------------+
bool IsNewCandle(ENUM_TIMEFRAMES timeframe)
{
   static datetime last_time = 0;
   datetime current_time = iTime(Symbol(), timeframe, 0);
   
   if(current_time != last_time) {
      last_time = current_time;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update the system state with latest market data                  |
//+------------------------------------------------------------------+
void UpdateSystemState()
{
   // Update ATR for volatility measurement
   double atr[];
   ArraySetAsSeries(atr, true);
   CopyBuffer(ATRHandle, 0, 0, 1, atr);
   CurrentATR = atr[0];
   
   // Calculate average ATR
   static int atrCount = 0;
   if(atrCount < 20) {
      AverageATR = (AverageATR * atrCount + CurrentATR) / (atrCount + 1);
      atrCount++;
   } else {
      AverageATR = 0.95 * AverageATR + 0.05 * CurrentATR; // Exponential moving average
   }
   
   // Update volume analysis
   AnalyzeVolume();
   
   // Re-evaluate market regime periodically
   static int regimeBars = 0;
   if(regimeBars++ >= 10) { // Check every 10 bars for regime change
      DetectMarketRegime();
      regimeBars = 0;
   }
   
   // Check for nearby high-impact news events
   if(AvoidHighImpactNews)
      NewsEventNearby = CheckForNewsEvents();
   
   // Reset daily risk at the start of a new day
   static datetime lastDay = 0;
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   MqlDateTime lastDayStruct;
   TimeToStruct(lastDay, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      DailyRiskUsed = 0;
      lastDay = currentTime;
   }
   
   // Update adaptive risk multiplier
   if(UseAdaptiveRisk) {
      if(ConsecutiveWins > 2) {
         // Increase risk after consecutive wins (anti-martingale)
         AdaptiveRiskMultiplier = MathMin(1.5, 1.0 + (0.1 * ConsecutiveWins));
      }
      else if(ConsecutiveLosses > 1) {
         // Decrease risk after consecutive losses
         AdaptiveRiskMultiplier = MathMax(0.5, 1.0 - (0.1 * ConsecutiveLosses));
      }
      else {
         // Reset to baseline
         AdaptiveRiskMultiplier = 1.0;
      }
   }
}

//+------------------------------------------------------------------+
//| Analyze volume characteristics                                   |
//+------------------------------------------------------------------+
void AnalyzeVolume()
{
   // Get volume data
   long volumes[];
   ArraySetAsSeries(volumes, true);
   
   // Use real volume if available, otherwise tick volume
   bool hasRealVolume = false;
   long realVolumeFlag = 0;
   hasRealVolume = SymbolInfoInteger(Symbol(), ENUM_SYMBOL_INFO_INTEGER(SYMBOL_VOLUME_REAL), realVolumeFlag);
   
   if(hasRealVolume && realVolumeFlag > 0)
      CopyRealVolume(Symbol(), PERIOD_M15, 0, VolumeLookbackPeriod + 1, volumes);
   else
      CopyTickVolume(Symbol(), PERIOD_M15, 0, VolumeLookbackPeriod + 1, volumes);
   
   // Calculate average volume (excluding current bar)
   double avgVolume = 0;
   for(int i = 1; i <= VolumeLookbackPeriod; i++) {
      avgVolume += (double)volumes[i];
   }
   avgVolume /= VolumeLookbackPeriod;
   AverageVolume = avgVolume;
   
   // Determine volume significance - RELAXED THRESHOLDS
   double currentVolumeRatio = (double)volumes[0] / avgVolume;
   
   if(currentVolumeRatio <= 0.7) // Changed from 0.8
      CurrentVolume = VOL_LOW;
   else if(currentVolumeRatio <= 1.2) // Changed from 1.3
      CurrentVolume = VOL_NORMAL;
   else if(currentVolumeRatio <= 2.0) // Changed from 2.5
      CurrentVolume = VOL_HIGH;
   else
      CurrentVolume = VOL_CLIMACTIC;
}

//+------------------------------------------------------------------+
//| Analyze historical volume patterns                               |
//+------------------------------------------------------------------+
void AnalyzeHistoricalVolume()
{
   // Get longer-term volume data for pattern recognition
   long volumes[];
   ArraySetAsSeries(volumes, true);
   
   int lookback = 500; // Substantial history for volume pattern analysis
   
   // Use real volume if available, otherwise tick volume
   bool hasRealVolume = false;
   long realVolumeFlag = 0;
   hasRealVolume = SymbolInfoInteger(Symbol(), ENUM_SYMBOL_INFO_INTEGER(SYMBOL_VOLUME_REAL), realVolumeFlag);
   
   if(hasRealVolume && realVolumeFlag > 0)
      CopyRealVolume(Symbol(), PERIOD_M15, 0, lookback, volumes);
   else
      CopyTickVolume(Symbol(), PERIOD_M15, 0, lookback, volumes);
   
   // Calculate various volume metrics
   double avgVolume = 0, stdDev = 0;
   double maxVolume = 0, minVolume = DBL_MAX;
   
   // First pass - basic metrics
   for(int i = 0; i < lookback; i++) {
      avgVolume += (double)volumes[i];
      if(volumes[i] > maxVolume) maxVolume = (double)volumes[i];
      if(volumes[i] < minVolume) minVolume = (double)volumes[i];
   }
   avgVolume /= lookback;
   
   // Second pass - standard deviation
   for(int i = 0; i < lookback; i++) {
      stdDev += MathPow((double)volumes[i] - avgVolume, 2);
   }
   stdDev = MathSqrt(stdDev / lookback);
   
   // Identify volume patterns and thresholds
   double volumeVariability = stdDev / avgVolume;
   double climacticThreshold = avgVolume + (2.5 * stdDev);
   double lowVolumeThreshold = avgVolume - (0.5 * stdDev);
   
   // Analyze volume by day of week and hour
   double volumeByHour[24] = {0};
   double volumeByDay[7] = {0};
   int countByHour[24] = {0};
   int countByDay[7] = {0};
   
   datetime barTime;
   MqlDateTime timeStruct;
   
   for(int i = 0; i < lookback; i++) {
      barTime = iTime(Symbol(), PERIOD_M15, i);
      TimeToStruct(barTime, timeStruct);
      
      volumeByHour[timeStruct.hour] += (double)volumes[i];
      countByHour[timeStruct.hour]++;
      
      volumeByDay[timeStruct.day_of_week] += (double)volumes[i];
      countByDay[timeStruct.day_of_week]++;
   }
   
   // Calculate average volume by hour and day
   for(int i = 0; i < 24; i++) {
      if(countByHour[i] > 0)
         volumeByHour[i] /= countByHour[i];
   }
   
   for(int i = 0; i < 7; i++) {
      if(countByDay[i] > 0)
         volumeByDay[i] /= countByDay[i];
   }
   
   // Log volume analysis results
   Print("Volume Analysis Complete:");
   Print("Average Volume: ", avgVolume);
   Print("Volume Variability: ", volumeVariability);
   Print("Climactic Volume Threshold: ", climacticThreshold);
   Print("Low Volume Threshold: ", lowVolumeThreshold);
}

//+------------------------------------------------------------------+
//| Detect the current market regime                                 |
//+------------------------------------------------------------------+
void DetectMarketRegime()
{
   // Get price data
   double close[], high[], low[];
   double macd[], signal[], histogram[];
   double rsi[];
   double upperBand[], middleBand[], lowerBand[];
   
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(signal, true);
   ArraySetAsSeries(histogram, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(upperBand, true);
   ArraySetAsSeries(middleBand, true);
   ArraySetAsSeries(lowerBand, true);
   
   // Copy price data
   CopyClose(Symbol(), PERIOD_M15, 0, RegimeDetectionPeriod, close);
   CopyHigh(Symbol(), PERIOD_M15, 0, RegimeDetectionPeriod, high);
   CopyLow(Symbol(), PERIOD_M15, 0, RegimeDetectionPeriod, low);
   
   // Copy indicator data
   CopyBuffer(MACDHandle, 0, 0, RegimeDetectionPeriod, macd);
   CopyBuffer(MACDHandle, 1, 0, RegimeDetectionPeriod, signal);
   CopyBuffer(RSIHandle, 0, 0, RegimeDetectionPeriod, rsi);
   CopyBuffer(BollingerHandle, 0, 0, RegimeDetectionPeriod, upperBand);
   CopyBuffer(BollingerHandle, 1, 0, RegimeDetectionPeriod, middleBand);
   CopyBuffer(BollingerHandle, 2, 0, RegimeDetectionPeriod, lowerBand);
   
   // Calculate regime metrics
   double trendStrength = CalculateTrendStrength(close, macd, signal);
   double rangeStrength = CalculateRangeStrength(close, upperBand, lowerBand);
   double volatilityLevel = CalculateVolatilityLevel(high, low, close);
   double breakoutPotential = CalculateBreakoutPotential(close, upperBand, lowerBand, rsi);
   
   // Determine the dominant regime using a more balanced approach
   // Create a weighted score for each regime
   double trendScore = trendStrength * 1.0;
   double rangeScore = rangeStrength * 1.0;
   double volatilityScore = volatilityLevel * 0.8;
   double breakoutScore = breakoutPotential * 0.9;
   
   // Find the highest score
   double highestScore = MathMax(MathMax(trendScore, rangeScore), MathMax(volatilityScore, breakoutScore));
   
   // Require a minimum difference between highest and second highest to avoid frequent regime changes
   double minDifference = 5.0; // Minimum difference required
   
   if(highestScore == trendScore && trendScore > 55 && 
      trendScore - MathMax(MathMax(rangeScore, volatilityScore), breakoutScore) > minDifference) {
      CurrentRegime = REGIME_TRENDING;
   }
   else if(highestScore == rangeScore && rangeScore > 60 && 
           rangeScore - MathMax(MathMax(trendScore, volatilityScore), breakoutScore) > minDifference) {
      CurrentRegime = REGIME_RANGING;
   }
   else if(highestScore == volatilityScore && volatilityScore > 65 && 
           volatilityScore - MathMax(MathMax(trendScore, rangeScore), breakoutScore) > minDifference) {
      CurrentRegime = REGIME_VOLATILE;
   }
   else if(highestScore == breakoutScore && breakoutScore > 60 && 
           breakoutScore - MathMax(MathMax(trendScore, rangeScore), volatilityScore) > minDifference) {
      CurrentRegime = REGIME_BREAKOUT;
   }
   else {
      // If no clear winner, use a hybrid approach based on recent price action
      if(volatilityLevel > 70) {
         CurrentRegime = REGIME_VOLATILE;
      }
      else if(trendStrength > rangeStrength) {
         CurrentRegime = REGIME_TRENDING;
      }
      else {
         CurrentRegime = REGIME_RANGING;
      }
   }
   
   // Log regime detection
   Print("Market Regime Updated: ", EnumToString(CurrentRegime));
   Print("Trend Strength: ", trendStrength);
   Print("Range Strength: ", rangeStrength);
   Print("Volatility Level: ", volatilityLevel);
   Print("Breakout Potential: ", breakoutPotential);
}

//+------------------------------------------------------------------+
//| Calculate trend strength (0-100 scale) - Improved Version        |
//+------------------------------------------------------------------+
double CalculateTrendStrength(double &close[], double &macd[], double &signal[])
{
   // 1. Directional Movement Index (DMI) components
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   CopyHigh(Symbol(), PERIOD_M15, 0, 20, high);
   CopyLow(Symbol(), PERIOD_M15, 0, 20, low);
   
   double plusDM = 0, minusDM = 0, trueRange = 0;
   
   for(int i = 1; i < 15; i++) {
      double highDiff = high[i-1] - high[i];
      double lowDiff = low[i] - low[i-1];
      
      if(highDiff > 0 && highDiff > lowDiff)
         plusDM += highDiff;
      else if(lowDiff > 0 && lowDiff > highDiff)
         minusDM += lowDiff;
         
      double tr = MathMax(high[i-1], close[i]) - MathMin(low[i-1], close[i]);
      trueRange += tr;
   }
   
   double diPlus = (trueRange > 0) ? (plusDM / trueRange) * 100 : 0;
   double diMinus = (trueRange > 0) ? (minusDM / trueRange) * 100 : 0;
   double dx = (diPlus + diMinus > 0) ? (MathAbs(diPlus - diMinus) / (diPlus + diMinus)) * 100 : 0;
   
   // 2. Linear regression slope and R-squared
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
   int n = 20;
   
   for(int i = 0; i < n; i++) {
      sumX += i;
      sumY += close[i];
      sumXY += i * close[i];
      sumX2 += i * i;
      sumY2 += close[i] * close[i];
   }
   
   double slope = ((n * sumXY) - (sumX * sumY)) / ((n * sumX2) - (sumX * sumX));
   double intercept = (sumY - slope * sumX) / n;
   
   // Normalize slope to percentage of price
   double normalizedSlope = (slope * n) / close[0] * 100;
   double slopeScore = MathMin(100, MathAbs(normalizedSlope) * 10);
   
   // Calculate R-squared (goodness of fit)
   double regressionY, totalSS = 0, residualSS = 0;
   double meanY = sumY / n;
   
   for(int i = 0; i < n; i++) {
      regressionY = intercept + slope * i;
      residualSS += MathPow(close[i] - regressionY, 2);
      totalSS += MathPow(close[i] - meanY, 2);
   }
   
   double rSquared = (totalSS > 0) ? 1 - (residualSS / totalSS) : 0;
   double fitScore = rSquared * 100;
   
   // 3. MACD histogram consistency
   int consistentHistogram = 0;
   bool isPositive = macd[0] > signal[0];
   
   for(int i = 0; i < 10; i++) {
      if((isPositive && macd[i] > signal[i]) || (!isPositive && macd[i] < signal[i]))
         consistentHistogram++;
   }
   
   double macdScore = (consistentHistogram / 10.0) * 100;
   
   // 4. Price momentum
   double momentum = (close[0] - close[10]) / close[10] * 100;
   double momentumScore = MathMin(100, MathAbs(momentum) * 5);
   
   // 5. Moving average alignment
   double ema8[], ema21[], ema50[];
   ArraySetAsSeries(ema8, true);
   ArraySetAsSeries(ema21, true);
   ArraySetAsSeries(ema50, true);
   
   int ema8Handle = iMA(Symbol(), PERIOD_M15, 8, 0, MODE_EMA, PRICE_CLOSE);
   int ema21Handle = iMA(Symbol(), PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   int ema50Handle = iMA(Symbol(), PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   
   CopyBuffer(ema8Handle, 0, 0, 1, ema8);
   CopyBuffer(ema21Handle, 0, 0, 1, ema21);
   CopyBuffer(ema50Handle, 0, 0, 1, ema50);
   
   IndicatorRelease(ema8Handle);
   IndicatorRelease(ema21Handle);
   IndicatorRelease(ema50Handle);
   
   bool alignedUp = (ema8[0] > ema21[0] && ema21[0] > ema50[0]);
   bool alignedDown = (ema8[0] < ema21[0] && ema21[0] < ema50[0]);
   double alignmentScore = (alignedUp || alignedDown) ? 100 : 0;
   
   // Combine metrics with appropriate weighting
   double trendStrength = (dx * 0.2) + 
                         (slopeScore * 0.2) + 
                         (fitScore * 0.15) + 
                         (macdScore * 0.15) + 
                         (momentumScore * 0.15) + 
                         (alignmentScore * 0.15);
   
   return MathMin(100, trendStrength);
}

//+------------------------------------------------------------------+
//| Calculate range strength (0-100 scale) - Improved Version        |
//+------------------------------------------------------------------+
double CalculateRangeStrength(double &close[], double &upper[], double &lower[])
{
   // 1. Calculate volatility ratio (ATR/Range)
   double atr = 0;
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   CopyHigh(Symbol(), PERIOD_M15, 0, 20, high);
   CopyLow(Symbol(), PERIOD_M15, 0, 20, low);
   
   for(int i = 1; i < 15; i++) {
      double trueRange = MathMax(high[i-1], close[i]) - MathMin(low[i-1], close[i]);
      atr += trueRange;
   }
   atr /= 14;
   
   double bandWidth = upper[0] - lower[0];
   double volatilityRatio = atr / bandWidth;
   double volatilityScore = MathMin(100, 100 * MathExp(-5 * volatilityRatio)); // Exponential decay
   
   // 2. Price containment - percentage of prices inside bands
   int pricesWithinBands = 0;
   for(int i = 0; i < 20; i++) {
      if(close[i] < upper[i] * 0.995 && close[i] > lower[i] * 1.005)
         pricesWithinBands++;
   }
   double containmentScore = (pricesWithinBands / 20.0) * 100;
   
   // 3. Directional consistency - lower is better for ranging
   double direction = 0;
   for(int i = 1; i < 20; i++) {
      if(close[i] > close[i-1]) direction++;
      if(close[i] < close[i-1]) direction--;
   }
   double directionScore = 100 - MathMin(100, MathAbs(direction) * 5.26); // 19 bars * 5.26 = ~100
   
   // 4. Distance from middle band
   double avgDistFromMiddle = 0;
   for(int i = 0; i < 10; i++) {
      double middle = (upper[i] + lower[i]) / 2;
      avgDistFromMiddle += MathAbs(close[i] - middle) / middle;
   }
   avgDistFromMiddle = (avgDistFromMiddle / 10) * 100; // As percentage
   double middleScore = MathMax(0, 100 - avgDistFromMiddle * 10); // Further from middle = lower score
   
   // 5. Mean reversion tendency - specific measurement
   int reversals = 0;
   bool wasAboveMiddle = close[0] > (upper[0] + lower[0]) / 2;
   for(int i = 1; i < 20; i++) {
      bool isAboveMiddle = close[i] > (upper[i] + lower[i]) / 2;
      if(wasAboveMiddle != isAboveMiddle) {
         reversals++;
         wasAboveMiddle = isAboveMiddle;
      }
   }
   double reversalScore = MathMin(100, reversals * 10);
   
   // Combine with appropriate weighting
   double rangeStrength = (volatilityScore * 0.2) + 
                          (containmentScore * 0.3) + 
                          (directionScore * 0.2) + 
                          (middleScore * 0.1) + 
                          (reversalScore * 0.2);
   
   return MathMin(100, rangeStrength);
}

//+------------------------------------------------------------------+
//| Calculate volatility level (0-100 scale) - Improved Version      |
//+------------------------------------------------------------------+
double CalculateVolatilityLevel(double &high[], double &low[], double &close[])
{
   // 1. ATR as percentage of price
   double atr = 0;
   for(int i = 1; i < 14; i++) {
      double trueRange = MathMax(high[i-1], close[i]) - MathMin(low[i-1], close[i]);
      atr += trueRange;
   }
   atr /= 14;
   
   double atrPercent = (atr / close[0]) * 100;
   double atrScore = MathMin(100, atrPercent * 25); // Scale appropriately
   
   // 2. ATR rate of change (acceleration of volatility)
   double atrShort = 0, atrLong = 0;
   
   for(int i = 1; i < 8; i++) {
      double tr = MathMax(high[i-1], close[i]) - MathMin(low[i-1], close[i]);
      atrShort += tr;
   }
   atrShort /= 7;
   
   for(int i = 8; i < 22; i++) {
      double tr = MathMax(high[i-1], close[i]) - MathMin(low[i-1], close[i]);
      atrLong += tr;
   }
   atrLong /= 14;
   
   double atrRatio = (atrShort / atrLong);
   double atrChangeScore = MathMin(100, MathMax(0, (atrRatio - 0.8) * 100));
   
   // 3. Price gaps
   int significantGaps = 0;
   for(int i = 1; i < 20; i++) {
      double gap = MathAbs(close[i] - close[i-1]) / close[i] * 100;
      if(gap > 0.2) // 0.2% threshold for significant gap
         significantGaps++;
   }
   
   double gapScore = MathMin(100, significantGaps * 10);
   
   // 4. Candle size variability
   double avgCandleSize = 0;
   for(int i = 0; i < 20; i++) {
      avgCandleSize += (high[i] - low[i]);
   }
   avgCandleSize /= 20;
   
   double candleSizeVariability = 0;
   for(int i = 0; i < 20; i++) {
      candleSizeVariability += MathPow((high[i] - low[i]) - avgCandleSize, 2);
   }
   candleSizeVariability = MathSqrt(candleSizeVariability / 20) / avgCandleSize * 100;
   double variabilityScore = MathMin(100, candleSizeVariability);
   
   // 5. Bollinger Band width
   double upper[], lower[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   
   int bbHandle = iBands(Symbol(), PERIOD_M15, 20, 2, 0, PRICE_CLOSE);
   CopyBuffer(bbHandle, 0, 0, 1, upper);
   CopyBuffer(bbHandle, 2, 0, 1, lower);
   IndicatorRelease(bbHandle);
   
   double bbWidth = (upper[0] - lower[0]) / close[0] * 100;
   double bbWidthScore = MathMin(100, bbWidth * 10);
   
   // Combine metrics with appropriate weighting
   double volatilityLevel = (atrScore * 0.3) + 
                           (atrChangeScore * 0.2) + 
                           (gapScore * 0.15) + 
                           (variabilityScore * 0.15) + 
                           (bbWidthScore * 0.2);
   
   return MathMin(100, volatilityLevel);
}

//+------------------------------------------------------------------+
//| Calculate breakout potential (0-100 scale) - Robust Version      |
//+------------------------------------------------------------------+
double CalculateBreakoutPotential(double &close[], double &upper[], double &lower[], double &rsi[])
{
   // 1. Price proximity to band edges
   double distanceToUpper = (upper[0] - close[0]) / close[0] * 100;
   double distanceToLower = (close[0] - lower[0]) / close[0] * 100;
   double minDistance = MathMin(distanceToUpper, distanceToLower);
   
   // Use linear scaling instead of sigmoid to avoid potential issues
   double proximityScore = MathMax(0, 100 - minDistance * 20);
   
   // 2. Tick Volume analysis - using safer calculations
   long volumes[];
   ArraySetAsSeries(volumes, true);
   
   // Use only tick volume since that's all that's available
   if(CopyTickVolume(Symbol(), PERIOD_M15, 0, 10, volumes) <= 0) {
      // If we can't get volume data, use a default score
      Print("Warning: Could not copy tick volume data");
      return 50.0; // Return a neutral value
   }
   
   // Calculate volume change more safely
   double recentVol = 0.1; // Small non-zero value as safety
   double olderVol = 0.1; // Small non-zero value as safety
   
   for(int i = 0; i < 5 && i < ArraySize(volumes); i++) 
      recentVol += (double)volumes[i];
   
   for(int i = 5; i < 10 && i < ArraySize(volumes); i++) 
      olderVol += (double)volumes[i];
   
   // Safer calculation of volume acceleration
   double volRatio = (olderVol > 0.5) ? recentVol / olderVol : 1.0;
   double volAccel = (volRatio - 1.0) * 100;
   
   // Limit to reasonable bounds
   double volumeScore = MathMin(100, MathMax(0, 50 + volAccel * 2));
   
   // 3. Bollinger Band width - with safety checks
   double bandWidths[10];
   double avgMiddlePrice = 0;
   
   for(int i = 0; i < 10 && i < ArraySize(upper) && i < ArraySize(lower); i++) {
      avgMiddlePrice = (upper[i] + lower[i]) / 2;
      // Prevent division by zero
      if(avgMiddlePrice > 0)
         bandWidths[i] = (upper[i] - lower[i]) / avgMiddlePrice * 100;
      else
         bandWidths[i] = 0;
   }
   
   // Calculate band contraction with safety
   double currentWidth = MathMax(0.001, bandWidths[0]); // Ensure non-zero
   double avgPastWidth = 0;
   int validBars = 0;
   
   for(int i = 1; i < 10 && i < ArraySize(bandWidths); i++) {
      if(bandWidths[i] > 0) {
         avgPastWidth += bandWidths[i];
         validBars++;
      }
   }
   
   avgPastWidth = (validBars > 0) ? avgPastWidth / validBars : currentWidth;
   
   // Safe calculation of contraction
   double bandContraction = (avgPastWidth > 0 && currentWidth > 0) ? 
                           ((avgPastWidth / currentWidth) - 1.0) * 100 : 0;
   
   double squeezeScore = MathMin(100, MathMax(0, 50 + bandContraction));
   
   // 4. RSI - simple and robust
   double rsiScore = 0;
   
   // Check for valid RSI data
   if(ArraySize(rsi) > 5) {
      // RSI extremes
      if(rsi[0] > 70 || rsi[0] < 30) 
         rsiScore += 50;
      
      // RSI divergence from price (if we have enough data)
      if(ArraySize(close) > 5) {
         bool priceUp = close[0] > close[5];
         bool rsiUp = rsi[0] > rsi[5];
         
         // Divergence check: price up, RSI down or price down, RSI up
         if((priceUp && !rsiUp) || (!priceUp && rsiUp))
            rsiScore += 50;
      }
   }
   
   rsiScore = MathMin(100, rsiScore);
   
   // 5. Price range - more robust calculation
   double priceHigh[], priceLow[];
   ArraySetAsSeries(priceHigh, true);
   ArraySetAsSeries(priceLow, true);
   
   if(CopyHigh(Symbol(), PERIOD_M15, 0, 11, priceHigh) <= 0 || 
      CopyLow(Symbol(), PERIOD_M15, 0, 11, priceLow) <= 0) {
      // If we can't get price data, use a default score
      Print("Warning: Could not copy high/low price data");
      return 50.0; // Return a neutral value
   }
   
   // Find highest high and lowest low safely
   double highestHigh = priceHigh[0];
   double lowestLow = priceLow[0];
   
   for(int i = 1; i < ArraySize(priceHigh); i++) {
      if(priceHigh[i] > highestHigh) highestHigh = priceHigh[i];
   }
   
   for(int i = 1; i < ArraySize(priceLow); i++) {
      if(priceLow[i] < lowestLow) lowestLow = priceLow[i];
   }
   
   double priceRange = (close[0] > 0) ? ((highestHigh - lowestLow) / close[0] * 100) : 0;
   
   // Lower range means higher consolidation
   double consolidationScore = MathMax(0, 100 - priceRange * 5);
   
   // Combine scores with appropriate weighting
   double breakoutPotential = (proximityScore * 0.25) + 
                             (volumeScore * 0.20) + 
                             (squeezeScore * 0.25) + 
                             (rsiScore * 0.15) + 
                             (consolidationScore * 0.15);
   
   // Ensure result is positive before applying power function
   breakoutPotential = MathMax(0, breakoutPotential);
   
   // Power curve but with safety check
   if(breakoutPotential > 0)
      breakoutPotential = MathPow(breakoutPotential / 100, 1.2) * 100;
   
   // Final sanity check
   if(MathIsValidNumber(breakoutPotential))
      return MathMin(100, MathMax(0, breakoutPotential));
   else
      return 50.0; // Return neutral value if we get NaN
}

//+------------------------------------------------------------------+
//| Calculate linear regression slope                                |
//+------------------------------------------------------------------+
double CalculateLinearRegressionSlope(double &data[], int period)
{
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   
   for(int i = 0; i < period; i++) {
      sumX += i;
      sumY += data[i];
      sumXY += i * data[i];
      sumX2 += i * i;
   }
   
   double slope = (period * sumXY - sumX * sumY) / (period * sumX2 - sumX * sumX);
   return slope / data[0]; // Normalize by current price
}

//+------------------------------------------------------------------+
//| Calculate mean reversion score                                   |
//+------------------------------------------------------------------+
double CalculateMeanReversionScore(double &data[], int period)
{
   // Calculate simple moving average
   double sma = 0;
   for(int i = 0; i < period; i++) {
      sma += data[i];
   }
   sma /= period;
   
   // Calculate mean reversion tendency
   int reversions = 0;
   bool aboveMean = data[0] > sma;
   
   for(int i = 1; i < period; i++) {
      bool currentAboveMean = data[i] > sma;
      if(aboveMean != currentAboveMean) {
         reversions++;
         aboveMean = currentAboveMean;
      }
   }
   
   return (reversions / (double)period) * 100;
}

//+------------------------------------------------------------------+
//| Calculate consolidation score                                    |
//+------------------------------------------------------------------+
double CalculateConsolidationScore(double &data[], int period)
{
   double highest = data[ArrayMaximum(data, 0, period)];
   double lowest = data[ArrayMinimum(data, 0, period)];
   double range = (highest - lowest) / lowest * 100;
   
   // Narrower range indicates stronger consolidation
   double consolidationScore = MathMax(0, 100 - range * 10);
   
   return consolidationScore;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed based on all filters                 |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   // Check if automated trading is enabled
   if(!EnableTrading || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   
   // Check time filter
   if(EnableTimeFilter && !IsWithinTradingHours())
      return false;
   
   // Check news filter
   if(AvoidHighImpactNews && NewsEventNearby)
      return false;
   
   // MODIFIED: Check market regime filter - allow more regimes
   if(EnableMarketRegimeFilters) {
      // Only avoid extremely volatile markets
      if(CurrentRegime == REGIME_VOLATILE && !UseVolatilityExpansion && CurrentATR > 1.5 * AverageATR)
         return false;
   }
   
   // MODIFIED: Check volume filter - allow low volume in some cases
   if(EnableVolumeConfirmation && CurrentVolume == VOL_LOW) {
      // Allow low volume if we have strong signals in trend regime
      if(CurrentRegime != REGIME_TRENDING) // Only restrict in non-trending regimes
         return false;
   }
   
   // Check daily risk limit
   if(DailyRiskUsed >= MaxDailyRiskPercent)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within allowed trading hours            |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   // Check if weekend
   if(timeStruct.day_of_week == 0 || timeStruct.day_of_week == 6)
      return false;
   
   // Check trading session hours
   if(timeStruct.hour < TradeSessionStartHour || timeStruct.hour >= TradeSessionEndHour)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for nearby high-impact news events                         |
//+------------------------------------------------------------------+
bool CheckForNewsEvents()
{
   // This is a placeholder for an actual news calendar integration
   // In a real implementation, you would connect to a news feed API
   
   // For demonstration purposes, we'll return false
   // In a production system, this would check a real economic calendar
   return false;
}

//+------------------------------------------------------------------+
//| Count currently open positions for this EA                       |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Check if position belongs to this EA
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetString(POSITION_SYMBOL) == Symbol())
         count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Execute trend-following strategy                                 |
//+------------------------------------------------------------------+
void ExecuteTrendStrategy()
{
   // Get indicator data
   double macd[], signal[];
   double fastEMA[], slowEMA[];
   
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(signal, true);
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   
   // Copy MACD data
   CopyBuffer(MACDHandle, 0, 0, 3, macd);
   CopyBuffer(MACDHandle, 1, 0, 3, signal);
   
   // Get EMAs
   int fastEMAHandle = iMA(Symbol(), PERIOD_M15, 8, 0, MODE_EMA, PRICE_CLOSE);
   int slowEMAHandle = iMA(Symbol(), PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   
   CopyBuffer(fastEMAHandle, 0, 0, 3, fastEMA);
   CopyBuffer(slowEMAHandle, 0, 0, 3, slowEMA);
   
   IndicatorRelease(fastEMAHandle);
   IndicatorRelease(slowEMAHandle);
   
   // Check for trend signals
   bool bullishSignal = false;
   bool bearishSignal = false;
   
   // MACD crossover - more relaxed conditions
   bool macdCrossUp = macd[1] < signal[1] && macd[0] >= signal[0]; // Changed from strict > to >=
   bool macdCrossDown = macd[1] > signal[1] && macd[0] <= signal[0]; // Changed from strict < to <=
   
   // EMA alignment
   bool emaAlignBullish = fastEMA[0] > slowEMA[0];
   bool emaAlignBearish = fastEMA[0] < slowEMA[0];
   
   // Volume confirmation - accept normal volume too
   bool volumeConfirm = CurrentVolume >= VOL_NORMAL;
   
   // Generate signals
   if(macdCrossUp && emaAlignBullish && volumeConfirm) {
      bullishSignal = true;
   }
   else if(macdCrossDown && emaAlignBearish && volumeConfirm) {
      bearishSignal = true;
   }
   
   // Execute trades if signals are valid
   if(bullishSignal) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Trend Strategy - Bullish");
      }
   }
   else if(bearishSignal) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Trend Strategy - Bearish");
      }
   }
   
   // Add trend strength based signals for more trading opportunities
   double close[];
   ArraySetAsSeries(close, true);
   CopyClose(Symbol(), PERIOD_M15, 0, 5, close);
   
   double momentum = (close[0] - close[3]) / close[3] * 100; // 3-bar momentum
   
   // Check for strong momentum in the trend direction
   if(!bullishSignal && emaAlignBullish && momentum > 0.2 && volumeConfirm) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Trend Momentum - Bullish");
      }
   }
   else if(!bearishSignal && emaAlignBearish && momentum < -0.2 && volumeConfirm) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Trend Momentum - Bearish");
      }
   }
}

//+------------------------------------------------------------------+
//| Execute range trading strategy                                   |
//+------------------------------------------------------------------+
void ExecuteRangeStrategy()
{
   // Get Bollinger Bands data
   double upper[], middle[], lower[];
   double rsi[];
   
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(middle, true);
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(rsi, true);
   
   // Copy Bollinger Bands data
   CopyBuffer(BollingerHandle, 0, 0, 3, upper);
   CopyBuffer(BollingerHandle, 1, 0, 3, middle);
   CopyBuffer(BollingerHandle, 2, 0, 3, lower);
   
   // Copy RSI data
   CopyBuffer(RSIHandle, 0, 0, 3, rsi);
   
   // Get price data
   double close[];
   ArraySetAsSeries(close, true);
   CopyClose(Symbol(), PERIOD_M15, 0, 3, close);
   
   // Check for range signals
   bool buySignal = false;
   bool sellSignal = false;
   
   // Price near band edges - relaxed conditions
   bool nearLowerBand = close[0] < lower[0] * 1.02; // More relaxed - changed from 1.01 to 1.02
   bool nearUpperBand = close[0] > upper[0] * 0.98; // More relaxed - changed from 0.99 to 0.98
   
   // RSI confirmation - relaxed conditions
   bool rsiOversold = rsi[0] < RSIOversold + 5; // More relaxed - added 5 points
   bool rsiOverbought = rsi[0] > RSIOverbought - 5; // More relaxed - subtracted 5 points
   
   // Volume confirmation - accept normal volume
   bool volumeConfirm = CurrentVolume >= VOL_NORMAL;
   
   // Generate signals
   if(nearLowerBand && rsiOversold && volumeConfirm) {
      buySignal = true;
   }
   else if(nearUpperBand && rsiOverbought && volumeConfirm) {
      sellSignal = true;
   }
   
   // Also check for middle band bounce
   bool middleBandBounceBuy = close[0] > middle[0] && close[1] < middle[1] && rsi[0] < 50 && volumeConfirm;
   bool middleBandBounceSell = close[0] < middle[0] && close[1] > middle[1] && rsi[0] > 50 && volumeConfirm;
   
   // Execute trades if signals are valid
   if(buySignal) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Range Strategy - Support Bounce");
      }
   }
   else if(sellSignal) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Range Strategy - Resistance Rejection");
      }
   }
   
   // Add middle band bounce trades
   if(middleBandBounceBuy) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Range Strategy - Middle Band Bounce");
      }
   }
   else if(middleBandBounceSell) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Range Strategy - Middle Band Bounce");
      }
   }
}

//+------------------------------------------------------------------+
//| Execute volatility-based strategy                                |
//+------------------------------------------------------------------+
void ExecuteVolatilityStrategy()
{
   // This strategy is designed for high volatility environments
   // It uses wider stops and targets, and looks for strong momentum
   
   // Get price data
   double close[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   CopyClose(Symbol(), PERIOD_M15, 0, 10, close);
   CopyHigh(Symbol(), PERIOD_M15, 0, 10, high);
   CopyLow(Symbol(), PERIOD_M15, 0, 10, low);
   
   // Calculate momentum - relaxed threshold
   double momentum = (close[0] - close[5]) / close[5] * 100; // 5-bar momentum
   
   // Get RSI for confirmation
   double rsi[];
   ArraySetAsSeries(rsi, true);
   CopyBuffer(RSIHandle, 0, 0, 3, rsi);
   
   // Volume confirmation
   bool volumeConfirm = CurrentVolume >= VOL_NORMAL; // Changed from VOL_HIGH to VOL_NORMAL
   
   // Check for strong momentum signals
   bool strongBullish = momentum > 0.4 && volumeConfirm && rsi[0] > 45; // Relaxed from 0.5 to 0.4
   bool strongBearish = momentum < -0.4 && volumeConfirm && rsi[0] < 55; // Relaxed from -0.5 to -0.4
   
   // Execute trades with wider stops for volatility
   if(strongBullish) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY, 3.0, 4.5); // Wider SL/TP
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Volatility Strategy - Strong Bullish", 3.0, 4.5);
      }
   }
   else if(strongBearish) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL, 3.0, 4.5); // Wider SL/TP
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Volatility Strategy - Strong Bearish", 3.0, 4.5);
      }
   }
   
   // Add mean reversion trades
   bool extremeOverbought = rsi[0] > 75 && rsi[1] > 75 && volumeConfirm;
   bool extremeOversold = rsi[0] < 25 && rsi[1] < 25 && volumeConfirm;
   
   if(extremeOverbought) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL, 3.0, 4.5);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Volatility Strategy - Mean Reversion", 3.0, 4.5);
      }
   }
   else if(extremeOversold) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY, 3.0, 4.5);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Volatility Strategy - Mean Reversion", 3.0, 4.5);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute breakout strategy                                        |
//+------------------------------------------------------------------+
void ExecuteBreakoutStrategy()
{
   // Get price data
   double close[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   CopyClose(Symbol(), PERIOD_M15, 0, BreakoutPeriod + 1, close);
   CopyHigh(Symbol(), PERIOD_M15, 0, BreakoutPeriod + 1, high);
   CopyLow(Symbol(), PERIOD_M15, 0, BreakoutPeriod + 1, low);
   
   // Find recent high and low (excluding current bar)
   double recentHigh = high[ArrayMaximum(high, 1, BreakoutPeriod)];
   double recentLow = low[ArrayMinimum(low, 1, BreakoutPeriod)];
   
   // Check for breakouts - RELAXED CONDITIONS
   bool bullishBreakout = close[0] > recentHigh * 0.998; // Allow for slight variations
   bool bearishBreakout = close[0] < recentLow * 1.002; // Allow for slight variations
   
   // Volume confirmation is important but less restrictive
   bool volumeConfirm = CurrentVolume >= VOL_NORMAL; // Changed from VOL_HIGH to VOL_NORMAL
   
   // Execute trades if signals are valid
   if(bullishBreakout && volumeConfirm) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY, 2.0, 3.0);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Breakout Strategy - Bullish", 2.0, 3.0);
      }
   }
   else if(bearishBreakout && volumeConfirm) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL, 2.0, 3.0);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Breakout Strategy - Bearish", 2.0, 3.0);
      }
   }
   
   // Add range contraction breakout signals (often precedes major movements)
   double highRange = high[1] - low[1];
   double lowRange = 0;
   
   // Find the smallest range in recent bars
   for(int i = 2; i < 10; i++) {
      double range = high[i] - low[i];
      if(lowRange == 0 || range < lowRange)
         lowRange = range;
   }
   
   // Check for range expansion after contraction
   bool rangeContraction = highRange > lowRange * 1.5;
   double momentum = (close[0] - close[1]) / close[1] * 100;
   
   if(rangeContraction && momentum > 0.2 && volumeConfirm) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_BUY, 2.0, 3.0);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_BUY, "Breakout Strategy - Range Expansion", 2.0, 3.0);
      }
   }
   else if(rangeContraction && momentum < -0.2 && volumeConfirm) {
      double riskReward = CalculateRiskRewardRatio(ORDER_TYPE_SELL, 2.0, 3.0);
      if(riskReward >= RiskRewardMinimum) {
         ExecuteTradeOrder(ORDER_TYPE_SELL, "Breakout Strategy - Range Expansion", 2.0, 3.0);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate risk-reward ratio for potential trade                  |
//+------------------------------------------------------------------+
double CalculateRiskRewardRatio(ENUM_ORDER_TYPE orderType, double slMultiplier = 0, double tpMultiplier = 0)
{
   // Use default multipliers if not specified
   if(slMultiplier <= 0) slMultiplier = VolatilityMultiplierSL;
   if(tpMultiplier <= 0) tpMultiplier = VolatilityMultiplierTP;
   
   double entryPrice = (orderType == ORDER_TYPE_BUY) ? 
                        SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                        SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Calculate SL and TP distances based on ATR
   double stopLossDistance = CurrentATR * slMultiplier;
   double takeProfitDistance = CurrentATR * tpMultiplier;
   
   // Calculate SL and TP levels
   double stopLossLevel = (orderType == ORDER_TYPE_BUY) ? 
                           entryPrice - stopLossDistance : 
                           entryPrice + stopLossDistance;
   
   double takeProfitLevel = (orderType == ORDER_TYPE_BUY) ? 
                             entryPrice + takeProfitDistance : 
                             entryPrice - takeProfitDistance;
   
   // Calculate risk-reward ratio
   double risk = MathAbs(entryPrice - stopLossLevel);
   double reward = MathAbs(entryPrice - takeProfitLevel);
   
   return reward / risk;
}

//+------------------------------------------------------------------+
//| Execute trade order with proper risk management                  |
//+------------------------------------------------------------------+
TradeResult ExecuteTradeOrder(ENUM_ORDER_TYPE orderType, string comment, double slMultiplier = 0, double tpMultiplier = 0)
{
   TradeResult result;
   result.success = false;
   
   // Use default multipliers if not specified
   if(slMultiplier <= 0) slMultiplier = VolatilityMultiplierSL;
   if(tpMultiplier <= 0) tpMultiplier = VolatilityMultiplierTP;
   
   // Get entry price
   double entryPrice = (orderType == ORDER_TYPE_BUY) ? 
                        SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                        SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Calculate SL and TP distances based on ATR
   double stopLossDistance = CurrentATR * slMultiplier;
   double takeProfitDistance = CurrentATR * tpMultiplier;
   
   // Calculate SL and TP levels
   double stopLossLevel = (orderType == ORDER_TYPE_BUY) ? 
                           entryPrice - stopLossDistance : 
                           entryPrice + stopLossDistance;
   
   double takeProfitLevel = (orderType == ORDER_TYPE_BUY) ? 
                             entryPrice + takeProfitDistance : 
                             entryPrice - takeProfitDistance;
   
   // Calculate position size based on risk
   double positionSize = CalculatePositionSize(entryPrice, stopLossLevel);
   
   // Check if position size is valid
   if(positionSize < MinPositionSize) {
      result.message = "Position size too small";
      return result;
   }
   
   if(positionSize > MaxPositionSize) {
      positionSize = MaxPositionSize;
   }
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult tradeResult = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = NormalizeDouble(positionSize, 2);
   request.type = orderType;
   request.price = entryPrice;
   request.sl = NormalizeDouble(stopLossLevel, _Digits);
   request.tp = NormalizeDouble(takeProfitLevel, _Digits);
   request.deviation = MaxSlippage;
   request.magic = MagicNumber;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;
   
   // Execute the trade
   bool orderSent = false;
   for(int attempts = 0; attempts < OrderRetries; attempts++) {
      orderSent = OrderSend(request, tradeResult);
      
      if(orderSent && tradeResult.retcode == TRADE_RETCODE_DONE) {
         break;
      }
      
      // Wait briefly before retry
      Sleep(100);
   }
   
   // Process result
   if(orderSent && tradeResult.retcode == TRADE_RETCODE_DONE) {
      result.success = true;
      result.ticket = tradeResult.order;
      result.executedPrice = tradeResult.price;
      result.executionTime = TimeCurrent();
      result.message = "Order executed successfully";
      
      // Update risk tracking
      double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (AccountRiskPercent / 100.0);
      DailyRiskUsed += AccountRiskPercent;
      
      // Update performance tracking
      TotalTrades++;
      
      Print("Trade executed: ", EnumToString(orderType), " at ", entryPrice, 
            ", SL: ", stopLossLevel, ", TP: ", takeProfitLevel, 
            ", Size: ", positionSize, " lots");
   }
   else {
      result.message = "Order failed: " + IntegerToString(tradeResult.retcode);
      Print("Order failed: ", GetLastError(), ", Retcode: ", tradeResult.retcode);
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk parameters                 |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLossLevel)
{
   // Calculate risk amount in account currency
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (AccountRiskPercent / 100.0) * AdaptiveRiskMultiplier;
   
   // Calculate risk in pips
   double pipsRisk = MathAbs(entryPrice - stopLossLevel) / Point() / DigitMultiplier;
   
   // Handle zero or extremely small pip risk to avoid division by zero
   if(pipsRisk < 0.1) {
      pipsRisk = 0.1; // Minimum pip risk to avoid division by zero
   }
   
   // Calculate position size
   double positionSize = riskAmount / (pipsRisk * PipValue);
   
   // Normalize to lot step
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   positionSize = MathFloor(positionSize / lotStep) * lotStep;
   
   return NormalizeDouble(positionSize, 2);
}

//+------------------------------------------------------------------+
//| Manage open positions (trailing stops, partial close, etc.)      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      // Check if position belongs to this EA
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || 
         PositionGetString(POSITION_SYMBOL) != Symbol())
         continue;
      
      // Get position details
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double stopLoss = PositionGetDouble(POSITION_SL);
      double takeProfit = PositionGetDouble(POSITION_TP);
      double positionSize = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Calculate profit in pips
      double profitPips = (positionType == POSITION_TYPE_BUY) ? 
                           (currentPrice - openPrice) / Point() / DigitMultiplier : 
                           (openPrice - currentPrice) / Point() / DigitMultiplier;
      
      // Calculate distance to TP in pips
      double tpDistance = (takeProfit > 0) ? 
                           MathAbs(takeProfit - openPrice) / Point() / DigitMultiplier : 0;
      
      // Apply breakeven when profit reaches threshold
      if(UseBreakEven && stopLoss != openPrice) {
         double breakEvenThreshold = tpDistance * BreakEvenActivationRatio;
         
         if(profitPips >= breakEvenThreshold) {
            // Move stop loss to breakeven plus a small buffer
            double newSL = openPrice + (positionType == POSITION_TYPE_BUY ? 1 : -1) * 5 * Point() * DigitMultiplier;
            ModifyPosition(ticket, newSL, takeProfit);
         }
      }
      
      // Apply trailing stop
      if(UseTrailingStop) {
         double trailingActivation = CurrentATR * TrailingStopActivation;
         double trailingDistance = CurrentATR * TrailingStopDistance;
         
         if(profitPips * Point() * DigitMultiplier >= trailingActivation) {
            double newSL = 0;
            
            if(positionType == POSITION_TYPE_BUY) {
               newSL = currentPrice - trailingDistance;
               if(newSL > stopLoss)
                  ModifyPosition(ticket, newSL, takeProfit);
            }
            else {
               newSL = currentPrice + trailingDistance;
               if(stopLoss == 0 || newSL < stopLoss)
                  ModifyPosition(ticket, newSL, takeProfit);
            }
         }
      }
      
      // Apply partial close
      if(EnablePartialClose && positionSize > MinPositionSize * 2) {
         double partialCloseThreshold = tpDistance * PartialCloseTrigger / VolatilityMultiplierTP;
         
         if(profitPips >= partialCloseThreshold) {
            // Check if position has not been partially closed yet
            string posComment = PositionGetString(POSITION_COMMENT);
            if(StringFind(posComment, "Partial Close") < 0) {
               // Close part of the position
               double closeVolume = positionSize * PartialCloseRatio / 100.0;
               // Ensure the remaining position won't be below minimum
               if(positionSize - closeVolume >= MinPositionSize) {
                  ClosePartialPosition(ticket, closeVolume);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify existing position's SL and TP                             |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double sl, double tp)
{
   // Check if we need to modify position - only modify if the new SL/TP is different
   if(!PositionSelectByTicket(ticket))
      return false;
      
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   
   // Skip if no changes needed
   if(MathAbs(currentSL - sl) < Point() && MathAbs(currentTP - tp) < Point())
      return true; // No modification needed
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = Symbol();
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE) {
      Print("Position modified: Ticket ", ticket, ", New SL: ", sl, ", New TP: ", tp);
      return true;
   }
   else {
      Print("Failed to modify position: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Close part of an existing position                               |
//+------------------------------------------------------------------+
bool ClosePartialPosition(ulong ticket, double volume)
{
   if(!PositionSelectByTicket(ticket))
      return false;
      
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = Symbol();
   request.volume = NormalizeDouble(volume, 2);
   request.deviation = MaxSlippage;
   request.magic = MagicNumber;
   request.comment = "Partial Close";
   
   // Set order type opposite to position type
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      request.type = ORDER_TYPE_SELL;
   else
      request.type = ORDER_TYPE_BUY;
   
   // Set price based on current bid/ask
   request.price = (request.type == ORDER_TYPE_BUY) ? 
                    SymbolInfoDouble(Symbol(), SYMBOL_ASK) : 
                    SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE) {
      Print("Partial close executed: Ticket ", ticket, ", Volume: ", volume);
      return true;
   }
   else {
      Print("Failed to partially close position: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Save performance data to file                                    |
//+------------------------------------------------------------------+
bool SavePerformanceData()
{
   string fileName = "AMRTS_Performance_" + Symbol() + ".dat";
   int fileHandle = FileOpen(fileName, FILE_WRITE|FILE_BIN);
   
   if(fileHandle == INVALID_HANDLE) {
      Print("Failed to open file for writing: ", GetLastError());
      return false;
   }
   
   // Write performance data
   FileWriteInteger(fileHandle, Performance.totalTrades);
   FileWriteInteger(fileHandle, Performance.winningTrades);
   FileWriteInteger(fileHandle, Performance.losingTrades);
   FileWriteDouble(fileHandle, Performance.grossProfit);
   FileWriteDouble(fileHandle, Performance.grossLoss);
   FileWriteDouble(fileHandle, Performance.largestWin);
   FileWriteDouble(fileHandle, Performance.largestLoss);
   FileWriteDouble(fileHandle, Performance.avgWin);
   FileWriteDouble(fileHandle, Performance.avgLoss);
   FileWriteDouble(fileHandle, Performance.profitFactor);
   FileWriteDouble(fileHandle, Performance.expectancy);
   FileWriteDouble(fileHandle, Performance.sharpeRatio);
   FileWriteDouble(fileHandle, Performance.drawdown);
   FileWriteDouble(fileHandle, Performance.maxDrawdown);
   
   // Write regime-specific data
   for(int i = 0; i < 4; i++) {
      FileWriteDouble(fileHandle, WinRates[i]);
      FileWriteDouble(fileHandle, ProfitFactors[i]);
      FileWriteDouble(fileHandle, ExpectedValues[i]);
   }
   
   FileClose(fileHandle);
   return true;
}

//+------------------------------------------------------------------+
//| Load performance data from file                                  |
//+------------------------------------------------------------------+
bool LoadPerformanceData()
{
   string fileName = "AMRTS_Performance_" + Symbol() + ".dat";
   
   if(!FileIsExist(fileName))
      return false;
      
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_BIN);
   
   if(fileHandle == INVALID_HANDLE) {
      Print("Failed to open file for reading: ", GetLastError());
      return false;
   }
   
   // Read performance data
   Performance.totalTrades = FileReadInteger(fileHandle);
   Performance.winningTrades = FileReadInteger(fileHandle);
   Performance.losingTrades = FileReadInteger(fileHandle);
   Performance.grossProfit = FileReadDouble(fileHandle);
   Performance.grossLoss = FileReadDouble(fileHandle);
   Performance.largestWin = FileReadDouble(fileHandle);
   Performance.largestLoss = FileReadDouble(fileHandle);
   Performance.avgWin = FileReadDouble(fileHandle);
   Performance.avgLoss = FileReadDouble(fileHandle);
   Performance.profitFactor = FileReadDouble(fileHandle);
   Performance.expectancy = FileReadDouble(fileHandle);
   Performance.sharpeRatio = FileReadDouble(fileHandle);
   Performance.drawdown = FileReadDouble(fileHandle);
   Performance.maxDrawdown = FileReadDouble(fileHandle);
   
   // Read regime-specific data
   for(int i = 0; i < 4; i++) {
      WinRates[i] = FileReadDouble(fileHandle);
      ProfitFactors[i] = FileReadDouble(fileHandle);
      ExpectedValues[i] = FileReadDouble(fileHandle);
   }
   
   FileClose(fileHandle);
   return true;
}

//+------------------------------------------------------------------+
//| Print performance summary                                        |
//+------------------------------------------------------------------+
void PrintPerformanceSummary()
{
   Print("=== AMRTS Performance Summary ===");
   Print("Total Trades: ", Performance.totalTrades);
   Print("Winning Trades: ", Performance.winningTrades, " (", 
         Performance.totalTrades > 0 ? DoubleToString(100.0 * Performance.winningTrades / Performance.totalTrades, 1) : "0", "%)");
   Print("Gross Profit: ", DoubleToString(Performance.grossProfit, 2));
   Print("Gross Loss: ", DoubleToString(Performance.grossLoss, 2));
   Print("Net Profit: ", DoubleToString(Performance.grossProfit + Performance.grossLoss, 2));
   Print("Profit Factor: ", DoubleToString(Performance.profitFactor, 2));
   Print("Expected Value: ", DoubleToString(Performance.expectancy, 2));
   Print("Maximum Drawdown: ", DoubleToString(Performance.maxDrawdown, 2), "%");
   
   Print("=== Regime Performance ===");
   Print("Trending Market - Win Rate: ", DoubleToString(WinRates[REGIME_TRENDING], 1), 
         "%, Profit Factor: ", DoubleToString(ProfitFactors[REGIME_TRENDING], 2));
   Print("Ranging Market - Win Rate: ", DoubleToString(WinRates[REGIME_RANGING], 1), 
         "%, Profit Factor: ", DoubleToString(ProfitFactors[REGIME_RANGING], 2));
   Print("Volatile Market - Win Rate: ", DoubleToString(WinRates[REGIME_VOLATILE], 1), 
         "%, Profit Factor: ", DoubleToString(ProfitFactors[REGIME_VOLATILE], 2));
   Print("Breakout Market - Win Rate: ", DoubleToString(WinRates[REGIME_BREAKOUT], 1), 
         "%, Profit Factor: ", DoubleToString(ProfitFactors[REGIME_BREAKOUT], 2));
}

//+------------------------------------------------------------------+
//| Update performance metrics after trade closure                   |
//+------------------------------------------------------------------+
void UpdatePerformanceMetrics(double profit, ENUM_MARKET_REGIME regime)
{
   // Update overall performance
   Performance.totalTrades++;
   
   if(profit > 0) {
      Performance.winningTrades++;
      Performance.grossProfit += profit;
      
      if(profit > Performance.largestWin)
         Performance.largestWin = profit;
         
      ConsecutiveWins++;
      ConsecutiveLosses = 0;
   }
   else {
      Performance.losingTrades++;
      Performance.grossLoss += profit; // profit is negative here
      
      if(profit < Performance.largestLoss)
         Performance.largestLoss = profit;
         
      ConsecutiveWins = 0;
      ConsecutiveLosses++;
   }
   
   // Update average win/loss
   if(Performance.winningTrades > 0)
      Performance.avgWin = Performance.grossProfit / Performance.winningTrades;
      
   if(Performance.losingTrades > 0)
      Performance.avgLoss = Performance.grossLoss / Performance.losingTrades;
   
   // Update profit factor
   if(Performance.grossLoss != 0)
      Performance.profitFactor = MathAbs(Performance.grossProfit / Performance.grossLoss);
   else
      Performance.profitFactor = (Performance.grossProfit > 0) ? 999.0 : 0.0;
   
   // Update expectancy
   double winRate = (double)Performance.winningTrades / Performance.totalTrades;
   Performance.expectancy = (winRate * Performance.avgWin) + ((1 - winRate) * Performance.avgLoss);
   
   // Update regime-specific metrics
   int regimeIndex = (int)regime;
   
   // Calculate win rate for this regime
   static int regimeTrades[4] = {0, 0, 0, 0};
   static int regimeWins[4] = {0, 0, 0, 0};
   static double regimeProfit[4] = {0, 0, 0, 0};
   static double regimeLoss[4] = {0, 0, 0, 0};
   
   regimeTrades[regimeIndex]++;
   if(profit > 0) {
      regimeWins[regimeIndex]++;
      regimeProfit[regimeIndex] += profit;
   }
   else {
      regimeLoss[regimeIndex] += profit; // profit is negative
   }
   
   // Update regime win rates
   WinRates[regimeIndex] = (regimeTrades[regimeIndex] > 0) ? 
                           100.0 * regimeWins[regimeIndex] / regimeTrades[regimeIndex] : 0;
   
   // Update regime profit factors
   ProfitFactors[regimeIndex] = (regimeLoss[regimeIndex] != 0) ? 
                               MathAbs(regimeProfit[regimeIndex] / regimeLoss[regimeIndex]) : 
                               (regimeProfit[regimeIndex] > 0 ? 999.0 : 0.0);
   
   // Update regime expected values
   double regimeWinRate = (regimeTrades[regimeIndex] > 0) ? 
                          (double)regimeWins[regimeIndex] / regimeTrades[regimeIndex] : 0;
   double regimeAvgWin = (regimeWins[regimeIndex] > 0) ? 
                         regimeProfit[regimeIndex] / regimeWins[regimeIndex] : 0;
   double regimeAvgLoss = (regimeTrades[regimeIndex] - regimeWins[regimeIndex] > 0) ? 
                          regimeLoss[regimeIndex] / (regimeTrades[regimeIndex] - regimeWins[regimeIndex]) : 0;
   
   ExpectedValues[regimeIndex] = (regimeWinRate * regimeAvgWin) + ((1 - regimeWinRate) * regimeAvgLoss);
   
   // Save updated performance data
   SavePerformanceData();
}

//+------------------------------------------------------------------+
//| Get text description of deinitialization reason                  |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
   switch(reason) {
      case REASON_PROGRAM:     return "Program called ExpertRemove()";
      case REASON_REMOVE:      return "Expert removed from chart";
      case REASON_RECOMPILE:   return "Expert recompiled";
      case REASON_CHARTCHANGE: return "Symbol or timeframe changed";
      case REASON_CHARTCLOSE:  return "Chart closed";
      case REASON_PARAMETERS:  return "Parameters changed";
      case REASON_ACCOUNT:     return "Another account activated";
      case REASON_TEMPLATE:    return "New template applied";
      case REASON_INITFAILED:  return "OnInit() returned non-zero value";
      case REASON_CLOSE:       return "Terminal closed";
      default:                 return "Unknown reason: " + IntegerToString(reason);
   }
}

//+------------------------------------------------------------------+
//| OnTrade event handler                                            |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Process trade events to update performance metrics
   static int lastTradeCount = 0;
   int currentTradeCount = HistoryDealsTotal();
   
   if(currentTradeCount <= lastTradeCount)
      return;
      
   // Process new history deals
   for(int i = lastTradeCount; i < currentTradeCount; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;
      
      // Check if deal belongs to this EA
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;
         
      // Check if deal is a position close
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         
         // Update performance metrics
         UpdatePerformanceMetrics(profit, CurrentRegime);
      }
   }
   
   lastTradeCount = currentTradeCount;
}

//+------------------------------------------------------------------+
//| Function to get custom trade statistics                          |
//+------------------------------------------------------------------+
void GetTradeStatistics()
{
   // Reset statistics
   int totalTrades = 0;
   int winningTrades = 0;
   int losingTrades = 0;
   double grossProfit = 0;
   double grossLoss = 0;
   double largestWin = 0;
   double largestLoss = 0;
   
   // Get history for the last 3 months
   datetime startTime = TimeCurrent() - 60 * 60 * 24 * 90; // Last 90 days
   
   // Select history deals
   HistorySelect(startTime, TimeCurrent());
   
   // Analyze all deals
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;
      
      // Check if deal belongs to this EA
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
         continue;
         
      // Check if deal is a position close
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         totalTrades++;
         
         if(profit > 0) {
            winningTrades++;
            grossProfit += profit;
            
            if(profit > largestWin)
               largestWin = profit;
         }
         else {
            losingTrades++;
            grossLoss += profit; // profit is negative
            
            if(profit < largestLoss)
               largestLoss = profit;
         }
      }
   }
   
   // Update performance metrics
   Performance.totalTrades = totalTrades;
   Performance.winningTrades = winningTrades;
   Performance.losingTrades = losingTrades;
   Performance.grossProfit = grossProfit;
   Performance.grossLoss = grossLoss;
   Performance.largestWin = largestWin;
   Performance.largestLoss = largestLoss;
   
   // Calculate derived metrics
   if(winningTrades > 0)
      Performance.avgWin = grossProfit / winningTrades;
      
   if(losingTrades > 0)
      Performance.avgLoss = grossLoss / losingTrades;
      
   if(grossLoss != 0)
      Performance.profitFactor = MathAbs(grossProfit / grossLoss);
   else
      Performance.profitFactor = (grossProfit > 0) ? 999.0 : 0.0;
      
   if(totalTrades > 0) {
      double winRate = (double)winningTrades / totalTrades;
      Performance.expectancy = (winRate * Performance.avgWin) + ((1 - winRate) * Performance.avgLoss);
   }
   
   // Save updated performance data
   SavePerformanceData();
}

//+------------------------------------------------------------------+
//| Calculate drawdown and related metrics                           |
//+------------------------------------------------------------------+
void CalculateDrawdown()
{
   // This function would calculate current and maximum drawdown
   // using equity history data
   // For simplicity, we'll just use a placeholder
   Performance.drawdown = 0;
   Performance.maxDrawdown = 0;
   
   // Get equity history and calculate drawdown
   // This would involve tracking peak equity and calculating
   // percentage drops from peak to trough
}