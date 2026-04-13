//+------------------------------------------------------------------+
//|                                                     EAVolPB.mq5   |
//|                                          Nahuel H. Scarpelli      |
//|            Expert Advisor - Volume Pullback Strategy (MT5)         |
//+------------------------------------------------------------------+
#property copyright "Nahuel H. Scarpelli"
#property version   "1.40"
#property description "EA basado en pullback con confirmacion de volumen."
#property description "Usa EMA8, SMA30, SMA200, SMA500 y analisis de volumen/precio."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Parametros de entrada                                             |
//+------------------------------------------------------------------+
input group "=== Medias Moviles ==="
input int      InpEMA_Period     = 8;       // Periodo EMA
input int      InpSMA30_Period   = 30;      // Periodo SMA (filtro tendencia 1)
input int      InpSMA200_Period  = 200;     // Periodo SMA (filtro tendencia 2)
input int      InpSMA500_Period  = 500;     // Periodo SMA (filtro tendencia 3)

input group "=== Estrategia ==="
input int      InpMinCandles     = 2;       // Min. velas encima/debajo de EMA (2 o 3)
input double   InpBigBodyRatio   = 1.2;     // Ratio cuerpo grande vs promedio
input double   InpSmallBodyRatio = 0.85;    // Ratio cuerpo pequeno vs promedio
input int      InpLookbackBars   = 100;     // Barras de busqueda hacia atras
input bool     InpUseSMA200      = true;    // Usar SMA200 como filtro de tendencia
input bool     InpUseSMA500      = false;   // Usar SMA500 como filtro de tendencia
input bool     InpReqVolConfirm  = false;   // Exigir confirmacion de volumen (paso 6)
input bool     InpDebugMode      = true;    // Imprimir por que se rechazan senales

input group "=== Gestion de Riesgo ==="
input double   InpLotSize        = 0.1;     // Tamano de lote
input double   InpPartialPct     = 50.0;    // Porcentaje cierre parcial
input int      InpPartialTP      = 20;      // Take Profit parcial (pips)
input int      InpTrailingStop   = 20;      // Trailing Stop (pips)
input int      InpSL_Buffer      = 2;       // Buffer SL debajo/encima swing (pips)
input int      InpMaxSL_Pips     = 25;      // SL maximo permitido en pips (0=sin limite)

input group "=== General ==="
input ulong    InpMagicNumber    = 2025;    // Numero magico
input int      InpSlippage       = 10;      // Slippage (puntos)

//+------------------------------------------------------------------+
//| Variables globales                                                |
//+------------------------------------------------------------------+
CTrade g_trade;
int    g_hEMA8   = INVALID_HANDLE;
int    g_hSMA30  = INVALID_HANDLE;
int    g_hSMA200 = INVALID_HANDLE;
int    g_hSMA500 = INVALID_HANDLE;
ulong  g_posTicket   = 0;
bool   g_partialDone = false;

//+------------------------------------------------------------------+
//| Inicializacion                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_hEMA8   = iMA(_Symbol, PERIOD_CURRENT, InpEMA_Period,    0, MODE_EMA, PRICE_CLOSE);
   g_hSMA30  = iMA(_Symbol, PERIOD_CURRENT, InpSMA30_Period,  0, MODE_SMA, PRICE_CLOSE);
   g_hSMA200 = iMA(_Symbol, PERIOD_CURRENT, InpSMA200_Period, 0, MODE_SMA, PRICE_CLOSE);
   g_hSMA500 = iMA(_Symbol, PERIOD_CURRENT, InpSMA500_Period, 0, MODE_SMA, PRICE_CLOSE);

   if(g_hEMA8 == INVALID_HANDLE || g_hSMA30 == INVALID_HANDLE ||
      g_hSMA200 == INVALID_HANDLE || g_hSMA500 == INVALID_HANDLE)
   {
      Print("Error: no se pudieron crear los handles de indicadores");
      return(INIT_FAILED);
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);

   // Auto-detectar tipo de filling soportado por el broker
   long fillPolicy = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillPolicy & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillPolicy & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_posTicket   = 0;
   g_partialDone = false;

   Print("EAVolPB v1.40 inicializado | ", _Symbol, " | ", EnumToString(Period()),
         " | MaxSL=", InpMaxSL_Pips, "p | TP=", InpPartialTP, "p | Trail=", InpTrailingStop, "p | BE=auto");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Desinicializacion                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_hEMA8   != INVALID_HANDLE) IndicatorRelease(g_hEMA8);
   if(g_hSMA30  != INVALID_HANDLE) IndicatorRelease(g_hSMA30);
   if(g_hSMA200 != INVALID_HANDLE) IndicatorRelease(g_hSMA200);
   if(g_hSMA500 != INVALID_HANDLE) IndicatorRelease(g_hSMA500);
}

//+------------------------------------------------------------------+
//| Funcion principal por tick                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Gestionar posiciones abiertas en cada tick
   ManagePartialClose();
   ManageTrailingStop();

   // Solo buscar senales en nueva barra
   static datetime s_lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar == s_lastBar)
      return;
   s_lastBar = curBar;

   // Si ya hay posicion abierta, no buscar mas senales
   if(HasPosition())
      return;

   // Reset de estado
   g_posTicket   = 0;
   g_partialDone = false;

   // Buscar senal de compra
   double sl = 0;
   if(CheckBuySignal(sl))
   {
      ExecuteBuy(sl);
      return;
   }

   // Buscar senal de venta
   if(CheckSellSignal(sl))
   {
      ExecuteSell(sl);
      return;
   }
}

//+------------------------------------------------------------------+
//|                        UTILIDADES                                 |
//+------------------------------------------------------------------+

// Convertir pips a precio segun digitos del simbolo
double PipsToPrice(int pips)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? pips * _Point * 10 : pips * _Point;
}

// Calcular cuerpo promedio de N velas desde startBar
double CalcAverageBody(const MqlRates &rates[], int startBar, int count)
{
   double sum = 0;
   int n = 0;
   int total = ArraySize(rates);
   for(int i = startBar; i < startBar + count && i < total; i++)
   {
      sum += MathAbs(rates[i].close - rates[i].open);
      n++;
   }
   return (n > 0) ? sum / n : 0;
}

// Verificar si hay posicion abierta del EA
bool HasPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
      return true;
   }
   return false;
}

// Obtener ticket de la posicion abierta del EA
ulong GetPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
      return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| SENAL DE COMPRA                                                   |
//| Secuencia:                                                        |
//|   1) N+ velas por encima de EMA8 sin tocarla (tendencia alcista)  |
//|   2) N+ velas por debajo de EMA8 sin tocarla (pullback)           |
//|   3) Divergencia de volumen: vela grande + bajo vol, luego        |
//|      vela chica + alto vol (acumulacion)                          |
//|   4) Precio cierra por encima de SMA30                            |
//|   5) Precio cierra por encima de SMA200 y SMA500                  |
//|   6) Confirmacion: vela con volumen >= vol de referencia          |
//|   7) COMPRA                                                       |
//+------------------------------------------------------------------+
bool CheckBuySignal(double &sl)
{
   int maxBars = InpLookbackBars;

   double ema8[], sma30[], sma200[], sma500[];
   MqlRates rates[];
   ArraySetAsSeries(ema8, true);
   ArraySetAsSeries(sma30, true);
   ArraySetAsSeries(sma200, true);
   ArraySetAsSeries(sma500, true);
   ArraySetAsSeries(rates, true);

   if(CopyBuffer(g_hEMA8,   0, 0, maxBars, ema8)   < maxBars) return false;
   if(CopyBuffer(g_hSMA30,  0, 0, maxBars, sma30)  < maxBars) return false;
   if(CopyBuffer(g_hSMA200, 0, 0, maxBars, sma200) < maxBars) return false;
   if(CopyBuffer(g_hSMA500, 0, 0, maxBars, sma500) < maxBars) return false;
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, maxBars, rates)   < maxBars) return false;

   //--- FILTRO RAPIDO: bar 1 (ultima cerrada) por encima de EMA8 + SMA30 [+ SMA200 + SMA500 opcionales]
   if(rates[1].close <= ema8[1])
   { if(InpDebugMode) Print("BUY REJECT | Bar1 close=",rates[1].close," <= EMA8=",ema8[1]); return false; }
   if(rates[1].close <= sma30[1])
   { if(InpDebugMode) Print("BUY REJECT | Bar1 close=",rates[1].close," <= SMA30=",sma30[1]); return false; }
   if(InpUseSMA200 && rates[1].close <= sma200[1])
   { if(InpDebugMode) Print("BUY REJECT | Bar1 close=",rates[1].close," <= SMA200=",sma200[1]); return false; }
   if(InpUseSMA500 && rates[1].close <= sma500[1])
   { if(InpDebugMode) Print("BUY REJECT | Bar1 close=",rates[1].close," <= SMA500=",sma500[1]); return false; }

   //--- PASO 2: Encontrar pullback (cierres por debajo de EMA8)
   int pullbackEnd = -1;
   for(int i = 2; i < maxBars - 1; i++)
   {
      if(rates[i].close < ema8[i])
      {
         pullbackEnd = i;
         break;
      }
   }
   if(pullbackEnd < 0)
   { if(InpDebugMode) Print("BUY REJECT | No se encontro pullback debajo de EMA8"); return false; }

   int pullbackStart = pullbackEnd;
   int pullbackCount = 0;
   double lowestLow = DBL_MAX;

   for(int i = pullbackEnd; i < maxBars - 1; i++)
   {
      if(rates[i].close < ema8[i])
      {
         pullbackCount++;
         if(rates[i].low < lowestLow) lowestLow = rates[i].low;
         pullbackStart = i;
      }
      else
         break;
   }
   if(pullbackCount < InpMinCandles)
   { if(InpDebugMode) Print("BUY REJECT | Pullback insuficiente: ",pullbackCount," < ",InpMinCandles); return false; }

   //--- PASO 1: Verificar tendencia alcista antes del pullback (cierres por encima de EMA8)
   int aboveCount = 0;
   for(int i = pullbackStart + 1; i < maxBars - 1; i++)
   {
      if(rates[i].close > ema8[i])
         aboveCount++;
      else
         break;
   }
   if(aboveCount < InpMinCandles)
   { if(InpDebugMode) Print("BUY REJECT | Tendencia insuficiente: ",aboveCount," < ",InpMinCandles); return false; }

   //--- PASO 3: Divergencia de volumen
   //    Vela2 (mas vieja): cuerpo GRANDE, volumen BAJO
   //    Vela1 (mas nueva):  cuerpo CHICO, volumen ALTO
   int bodyBars = (int)MathMin(20, maxBars - pullbackEnd - 1);
   double avgBody = CalcAverageBody(rates, pullbackEnd, bodyBars);
   if(avgBody <= 0) return false;

   bool volSignalFound = false;
   double refVolume = 0;
   int vela2Bar = -1, vela1Bar = -1;

   for(int i = 2; i <= pullbackStart && i < maxBars - 2; i++)
   {
      double bodyOlder = MathAbs(rates[i + 1].close - rates[i + 1].open);
      double bodyNewer = MathAbs(rates[i].close     - rates[i].open);
      long   volOlder  = rates[i + 1].tick_volume;
      long   volNewer  = rates[i].tick_volume;

      if(bodyOlder >= avgBody * InpBigBodyRatio  &&
         bodyNewer <= avgBody * InpSmallBodyRatio &&
         volNewer > volOlder)
      {
         volSignalFound = true;
         refVolume = (double)volNewer;
         vela2Bar  = i + 1;
         vela1Bar  = i;
         break;
      }
   }
   if(!volSignalFound)
   { if(InpDebugMode) Print("BUY REJECT | No se encontro divergencia de volumen (avgBody=",avgBody,")"); return false; }

   //--- PASO 6: Confirmacion de volumen (opcional, configurable)
   if(InpReqVolConfirm)
   {
      bool volConfirmed = false;
      for(int i = 1; i <= vela2Bar; i++)
      {
         if(i == vela1Bar || i == vela2Bar) continue;
         if((double)rates[i].tick_volume >= refVolume)
         {
            volConfirmed = true;
            break;
         }
      }
      if(!volConfirmed)
      { if(InpDebugMode) Print("BUY REJECT | Sin confirmacion de volumen adicional"); return false; }
   }

   //--- TODAS LAS CONDICIONES SE CUMPLEN - Calcular SL
   sl = NormalizeDouble(lowestLow - PipsToPrice(InpSL_Buffer),
                        (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   //--- Verificar distancia maxima del SL
   if(InpMaxSL_Pips > 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slDist = (ask - sl) / PipsToPrice(1);
      if(slDist > InpMaxSL_Pips)
      {
         if(InpDebugMode) Print("BUY REJECT | SL demasiado lejano: ",DoubleToString(slDist,1)," pips > max ",InpMaxSL_Pips);
         return false;
      }
   }

   Print("BUY SIGNAL | SL=", sl, " | SwingLow=", lowestLow,
         " | Pullback=", pullbackCount, "b | Tendencia=", aboveCount, "b | AvgBody=", avgBody);
   return true;
}

//+------------------------------------------------------------------+
//| SENAL DE VENTA (espejo de la compra)                              |
//| Secuencia:                                                        |
//|   1) N+ velas por debajo de EMA8 sin tocarla (tendencia bajista)  |
//|   2) N+ velas por encima de EMA8 sin tocarla (pullback alcista)   |
//|   3) Divergencia de volumen (distribucion)                        |
//|   4) Precio cierra por debajo de SMA30                            |
//|   5) Precio cierra por debajo de SMA200 y SMA500                  |
//|   6) Confirmacion de volumen                                      |
//|   7) VENTA                                                        |
//+------------------------------------------------------------------+
bool CheckSellSignal(double &sl)
{
   int maxBars = InpLookbackBars;

   double ema8[], sma30[], sma200[], sma500[];
   MqlRates rates[];
   ArraySetAsSeries(ema8, true);
   ArraySetAsSeries(sma30, true);
   ArraySetAsSeries(sma200, true);
   ArraySetAsSeries(sma500, true);
   ArraySetAsSeries(rates, true);

   if(CopyBuffer(g_hEMA8,   0, 0, maxBars, ema8)   < maxBars) return false;
   if(CopyBuffer(g_hSMA30,  0, 0, maxBars, sma30)  < maxBars) return false;
   if(CopyBuffer(g_hSMA200, 0, 0, maxBars, sma200) < maxBars) return false;
   if(CopyBuffer(g_hSMA500, 0, 0, maxBars, sma500) < maxBars) return false;
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, maxBars, rates)   < maxBars) return false;

   //--- FILTRO RAPIDO: bar 1 por debajo de EMA8 + SMA30 [+ SMA200 + SMA500 opcionales]
   if(rates[1].close >= ema8[1])
   { if(InpDebugMode) Print("SELL REJECT | Bar1 close=",rates[1].close," >= EMA8=",ema8[1]); return false; }
   if(rates[1].close >= sma30[1])
   { if(InpDebugMode) Print("SELL REJECT | Bar1 close=",rates[1].close," >= SMA30=",sma30[1]); return false; }
   if(InpUseSMA200 && rates[1].close >= sma200[1])
   { if(InpDebugMode) Print("SELL REJECT | Bar1 close=",rates[1].close," >= SMA200=",sma200[1]); return false; }
   if(InpUseSMA500 && rates[1].close >= sma500[1])
   { if(InpDebugMode) Print("SELL REJECT | Bar1 close=",rates[1].close," >= SMA500=",sma500[1]); return false; }

   //--- PASO 2: Encontrar pullback alcista (cierres por encima de EMA8)
   int pullbackEnd = -1;
   for(int i = 2; i < maxBars - 1; i++)
   {
      if(rates[i].close > ema8[i])
      {
         pullbackEnd = i;
         break;
      }
   }
   if(pullbackEnd < 0)
   { if(InpDebugMode) Print("SELL REJECT | No se encontro pullback encima de EMA8"); return false; }

   int pullbackStart = pullbackEnd;
   int pullbackCount = 0;
   double highestHigh = 0;

   for(int i = pullbackEnd; i < maxBars - 1; i++)
   {
      if(rates[i].close > ema8[i])
      {
         pullbackCount++;
         if(rates[i].high > highestHigh) highestHigh = rates[i].high;
         pullbackStart = i;
      }
      else
         break;
   }
   if(pullbackCount < InpMinCandles)
   { if(InpDebugMode) Print("SELL REJECT | Pullback insuficiente: ",pullbackCount," < ",InpMinCandles); return false; }

   //--- PASO 1: Verificar tendencia bajista antes del pullback (cierres por debajo de EMA8)
   int belowCount = 0;
   for(int i = pullbackStart + 1; i < maxBars - 1; i++)
   {
      if(rates[i].close < ema8[i])
         belowCount++;
      else
         break;
   }
   if(belowCount < InpMinCandles)
   { if(InpDebugMode) Print("SELL REJECT | Tendencia bajista insuficiente: ",belowCount," < ",InpMinCandles); return false; }

   //--- PASO 3: Divergencia de volumen (distribucion)
   int bodyBars = (int)MathMin(20, maxBars - pullbackEnd - 1);
   double avgBody = CalcAverageBody(rates, pullbackEnd, bodyBars);
   if(avgBody <= 0) return false;

   bool volSignalFound = false;
   double refVolume = 0;
   int vela2Bar = -1, vela1Bar = -1;

   for(int i = 2; i <= pullbackStart && i < maxBars - 2; i++)
   {
      double bodyOlder = MathAbs(rates[i + 1].close - rates[i + 1].open);
      double bodyNewer = MathAbs(rates[i].close     - rates[i].open);
      long   volOlder  = rates[i + 1].tick_volume;
      long   volNewer  = rates[i].tick_volume;

      if(bodyOlder >= avgBody * InpBigBodyRatio  &&
         bodyNewer <= avgBody * InpSmallBodyRatio &&
         volNewer > volOlder)
      {
         volSignalFound = true;
         refVolume = (double)volNewer;
         vela2Bar  = i + 1;
         vela1Bar  = i;
         break;
      }
   }
   if(!volSignalFound)
   { if(InpDebugMode) Print("SELL REJECT | No se encontro divergencia de volumen (avgBody=",avgBody,")"); return false; }

   //--- PASO 6: Confirmacion de volumen (opcional, configurable)
   if(InpReqVolConfirm)
   {
      bool volConfirmed = false;
      for(int i = 1; i <= vela2Bar; i++)
      {
         if(i == vela1Bar || i == vela2Bar) continue;
         if((double)rates[i].tick_volume >= refVolume)
         {
            volConfirmed = true;
            break;
         }
      }
      if(!volConfirmed)
      { if(InpDebugMode) Print("SELL REJECT | Sin confirmacion de volumen adicional"); return false; }
   }

   //--- SENAL CONFIRMADA
   sl = NormalizeDouble(highestHigh + PipsToPrice(InpSL_Buffer),
                        (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   //--- Verificar distancia maxima del SL
   if(InpMaxSL_Pips > 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slDist = (sl - bid) / PipsToPrice(1);
      if(slDist > InpMaxSL_Pips)
      {
         if(InpDebugMode) Print("SELL REJECT | SL demasiado lejano: ",DoubleToString(slDist,1)," pips > max ",InpMaxSL_Pips);
         return false;
      }
   }

   Print("SELL SIGNAL | SL=", sl, " | SwingHigh=", highestHigh,
         " | Pullback=", pullbackCount, "b | Tendencia=", belowCount, "b | AvgBody=", avgBody);
   return true;
}

//+------------------------------------------------------------------+
//|                    EJECUCION DE ORDENES                           |
//+------------------------------------------------------------------+
void ExecuteBuy(double sl)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   ask = NormalizeDouble(ask, digits);

   if(g_trade.Buy(InpLotSize, _Symbol, ask, sl, 0, "EAVolPB BUY"))
   {
      g_posTicket   = g_trade.ResultOrder();
      g_partialDone = false;
      Print("COMPRA abierta | Ticket=", g_posTicket, " | Precio=", ask, " | SL=", sl);
   }
   else
      Print("Error COMPRA: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
}

void ExecuteSell(double sl)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   bid = NormalizeDouble(bid, digits);

   if(g_trade.Sell(InpLotSize, _Symbol, bid, sl, 0, "EAVolPB SELL"))
   {
      g_posTicket   = g_trade.ResultOrder();
      g_partialDone = false;
      Print("VENTA abierta | Ticket=", g_posTicket, " | Precio=", bid, " | SL=", sl);
   }
   else
      Print("Error VENTA: ", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//|                  GESTION DE POSICIONES                            |
//+------------------------------------------------------------------+

// Cierre parcial al alcanzar TP parcial
void ManagePartialClose()
{
   if(g_partialDone) return;

   ulong ticket = GetPositionTicket();
   if(ticket == 0) return;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume    = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double tpDist = PipsToPrice(InpPartialTP);
   bool tpReached = false;

   if(posType == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid >= openPrice + tpDist) tpReached = true;
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= openPrice - tpDist) tpReached = true;
   }

   if(!tpReached) return;

   double partialVol = NormalizeDouble(volume * InpPartialPct / 100.0, 2);
   double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // Ajustar al step de volumen del broker
   partialVol = MathFloor(partialVol / stepVol) * stepVol;

   if(partialVol >= minVol && (volume - partialVol) >= minVol)
   {
      if(g_trade.PositionClosePartial(ticket, partialVol))
      {
         g_partialDone = true;
         Print("CIERRE PARCIAL | Cerrado=", partialVol, " | Restante=", volume - partialVol);
      }
      else
         Print("Error cierre parcial: ", g_trade.ResultRetcode());
   }
   else
      g_partialDone = true; // Lote muy chico para partir, activar trailing igual
}

// Trailing stop con breakeven automatico tras cierre parcial
void ManageTrailingStop()
{
   if(!g_partialDone) return;

   ulong ticket = GetPositionTicket();
   if(ticket == 0) return;

   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double trailDist = PipsToPrice(InpTrailingStop);
   // Breakeven = entry + 1 pip buffer (nunca puede perder despues del parcial)
   double beBuffer = PipsToPrice(1);

   if(posType == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double beLevel = NormalizeDouble(openPrice + beBuffer, digits);
      double trailSL = NormalizeDouble(bid - trailDist, digits);
      // Usar el mayor entre breakeven y trailing
      double newSL = MathMax(beLevel, trailSL);
      if(newSL > currentSL + _Point)
         g_trade.PositionModify(ticket, newSL, currentTP);
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double beLevel = NormalizeDouble(openPrice - beBuffer, digits);
      double trailSL = NormalizeDouble(ask + trailDist, digits);
      // Usar el menor entre breakeven y trailing
      double newSL = MathMin(beLevel, trailSL);
      if(currentSL == 0 || newSL < currentSL - _Point)
         g_trade.PositionModify(ticket, newSL, currentTP);
   }
}
//+------------------------------------------------------------------+
