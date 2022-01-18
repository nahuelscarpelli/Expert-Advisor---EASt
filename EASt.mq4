//+------------------------------------------------------------------+
//|                                                         EASt.mq4 |
//|                                         Nahuel H. Scarpelli 2016 |
//|                                                     Somos2SR.com |
//+------------------------------------------------------------------+
#property copyright "Nahuel H. Scarpelli 2016"
#property link      "Somos2SR.com"
#property version   "1.00"
#property strict

//--- Parametros de entrada
input int      PeriodosK=5;
input int      PeriodosD=3;
input int      Slowing=3;
input int      StopLost=10;
input int      MagicNumber=2016;
input int      Contratos=1;//Automatizado seria int Contratos=CantidadPortafolio/MarketInfo(NULL,MODE_MARGINREQUIRED)
input int      StMax=60;
input int      StMin=40;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
 
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
Condicion1();
Condicion2();
Condicion3();
ComparacionPrecios();
CierreOrden();
AlertaCierreOrden();
  }
//+------------------------------------------------------------------+
//                  FUNCION PRIMERA CONDICION
//+------------------------------------------------------------------+

bool Condicion1() //Funcion de la 1er condicion Estocastico mayor a 80
{
 
double A=0;
double St1=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,1);//Valor principal estocastico vela 1
double St2=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,2);//Valor principal estocastico vela 2
double St3=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,3);//Valor principal estocastico vela 3  

if(St2>StMax && St2>St1 && St2>St3)

A=Bid;

return(true);

}

//+------------------------------------------------------------------+
//                  FUNCION SEGUNDA CONDICION
//+------------------------------------------------------------------+

bool Condicion2() //Funcion de la 2da condicion Estocastico menor a 20
{

while(Condicion2()==true)
{
double B=0;
double St4=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,1);//Valor principal estocastico vela 1
double St5=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,2);//Valor principal estocastico vela 2
double St6=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,3);//Valor principal estocastico vela 3  

if(St5<StMin && St5<St4 && St5<St6)

B=Bid;

return(true);
}
return(true);
}

//+------------------------------------------------------------------+
//                  FUNCION TERCERA CONDICION
//+------------------------------------------------------------------+

bool Condicion3() //Funcion de la 3ra condicion Estocastico Mayor a 80 pero menor St2
{

while(Condicion3()==true)
{
double C=0;
double St7=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,1);//Valor principal estocastico vela 1
double St8=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,2);//Valor principal estocastico vela 2
double St9=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,3);//Valor principal estocastico vela 3  

if(St8>StMax && St8<St7 && St8<St9 && St8<St2) //ERROR SE CORREGIRA CUANDO ARME EL CONCATENADO EN OnTick

C=Bid;

return(true);
}
return(true);
}

//+------------------------------------------------------------------+
//                  FUNCION CUARTA CONDICION y COMPRA
//+------------------------------------------------------------------+

bool ComparacionPrecios() //Comparacion de los 3 precios capturados, si se cumple orden de VENTA!
{
if(A>B && C>A)

int Ticket=OrderSend(NULL,OP_SELL,Contratos,Bid,10,0,0,NULL,MagicNumber,0,clrNONE);

return(true);
}

//+------------------------------------------------------------------+
//                  FUNCION CERRADO DE ORDEN
//+------------------------------------------------------------------+

bool CierreOrden()
{

while(CierreOrden()==true)
{
double M1,M2,S1,S2;

M1=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,1);
M2=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_MAIN,2);
S1=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_SIGNAL,1);
S2=iStochastic(NULL,0,PeriodosK,PeriodosD,Slowing,MODE_SMA,0,MODE_SIGNAL,2);

if(M2<S2 && M1>=S1)

bool OC=OrderClose(Ticket,0,Bid,0,clrNONE);

return(true);
}
return(true);
}

//+------------------------------------------------------------------+
//                 FUNCION ALERTA CERRADO DE ORDEN
//+------------------------------------------------------------------+

bool AlertaCierreOrden()
{
if(OC==true)Alert("Orden ",Ticket," Cerrada");  //Alerta de cierre de orden, para proximamente programar Pips ganados.
return(true);
}

