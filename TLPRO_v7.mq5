//+------------------------------------------------------------------+
//| TLPRO_7.mq5                                                      |
//| ex TrendlineStatsCollector_PRO_01_v1.07.mq5                      |
//| Copyright 2025, ProfitPickers - vitoiacobellis.it                |
//| https://www.vitoiacobellis.it                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, ProfitPickers - vitoiacobellis.it"
#property link      "https://www.vitoiacobellis.it"
#property version   "1.06"
#property strict
#property description "EA di analisi trendline macro-micro, delta e dashboard statistica."



#include <ChartObjects/ChartObjectsLines.mqh>
#include <Trade/Trade.mqh>

#include "../Include/CTrendlineAnalyzer.mqh"
#include "../Include/MovingAverages.mqh"


#include "../Include/CStrategyParamsManager.mqh"
#include "../Include/AuditParamsCheck.mqh"

#include "../Include/CTradeExecutor.mqh"
#include "../Include/CTradeDecisionManager.mqh"
#include "../Include/CVolumeManager.mqh"

#include "../Include/CTrackCounterDashboard.mqh"
#include "../Include/CTrackCounterDrawer.mqh"

#include "../Include/AuditCheck.mqh"
#include "../Include/CAuditCheck.mqh"




// === [GLOB] Variabili di tempo e intervalli ===
datetime last_extra_update = 0;
int extra_interval_sec = 300;

// === [GRAFICO] Etichette per trendline (LEFT / RIGHT) ===
string labels_left[6]  = { "MICRO", "MACRO", "EXTRA", "UPTrend", "DOWNtrend", "SUPPORT" };
string labels_right[6] = { "Delta Mac-Mic", "Delta Mac-Ext", "Delta Ext-Mic", "DIST", "MAXpick", "MINpick" };

// === [TREND INDEX] Valori indicizzati per logica strategica ===
int left_vals[6], right_vals[6];
double indexMicro, indexMacro, indexExtra;

// === [OGGETTI CORE] Trade, Parametri, Esecuzione ===
CTrade trade;




CVolumeManager        trade_volume;
CVolumeManager volumeManager;

CStrategyParamsManager strategyParams;
CStrategyParamsManager paramsManager;
//CTrendlineAnalyzer trendAnalyzer;

// === [STRATEGIE DECISIONALI] ===
CTradeDecisionManager decision;
CTradeExecutor executor;


// === [TRACKING VISIVO] ===
CTrackCounterDrawer trackDrawer;
CTrackCounterDashboard trackCounter;

// === [AUDIT] ===
AuditCheck audit;





//==============================//
// ORIGINE DATI E TRENDLINE     //
//==============================//
input group "bypass_filter per abilitare audit anche in Strategy Tester"
input bool bypass_main_filter = false;  // 🔓 Esegui Audit anche nel Strategy Tester


//==============================//
// ORIGINE DATI E TRENDLINE     //
//==============================//
input group "ORIGINE DATI E TRENDLINE"
input ENUM_TLBaseCalc TL_CalcBase = TL_CLOSE;
input int TL_MA_Period = 14;

input group "Trendline Settings"
input int micro_bars = 10;
input int macro_bars = 50;
input int extra_bars = 300;
input int count_window = 20;

//==============================//
//      MODALITA' LOG           //
//==============================//
input bool debug_strategy = true; // Attiva o disattiva la modalità di log [DEBUG]



//==============================//
// FILTRI E NORMALIZZAZIONE     //
//==============================//
input group "Filtri Volatilità e Volume"
input bool enable_auto_normalizer = true;
input double min_volatility_pips = 50;
input double min_volume_tick_avg = 100;


//==============================//
// ⚙️ SOGLIE INDEX RENDLINE   I //
//==============================//
input group "Soglie Globali - Regolazione sensibilità strategie"
input double REMOVED_MIN_INDEX_BUY  = 1000.0;   // Soglia minima INDEX per BUY
input double REMOVED_MAX_INDEX_SELL = -1000.0;  // Soglia massima INDEX per SELL



//==============================//
// ⚙️ SOGLIE GLOBALI - DELTA / ANGOLI //
//==============================//
input group "Soglie Globali - Regolazione sensibilità strategie"

// Soglia di compressione tra micro e macro trendline (Strategia 1)
input double delta_mm_s1 = 0.5;     // Diff. ang. max ° micro VS macro TL attiva compressione

// Soglia di compressione tra macro e extra trendline (Strategia 1)
input double delta_me_s1 = 0.5;     // Diff. ang. max ° macro VS extra TL attiva compressione


// Soglia di compressione tra extra e micro trendline (Strategia 1)
input double delta_em_s1 = 0.5;     // Diff. ang. max ° extra VS micro TL attiva compressione


// Soglia pendenza trendline extra per attivazione strategia 3
input double angle_thresh_ext = 25.0;   // Pendenza min ° trendline EXTRA attiva condizioni retracement

// Soglia pendenza combinata micro e macro per strategia 3
input double angle_thresh_micmac = 15.0; // Pendenza min ° richiesta a micro e macro TL per rilevare trend diretto

// Delta minimo tra macro ed extra per validare lo scenario di ritracciamento (Strategia 3)
input double delta_min_retracement = 0.3;  // Differenza angolare minima ° macro Vs extra attiva retracement

// Distanza massima tra prezzo e TL extra per ritracciamento valido (Strategia 3)
input double max_dist_retracement = 200.0; // Massima distanza in punti tra prezzo e TL extra x evento significativo

input group "🎯������ "
input double s1_equity_tp_buy = 10.0;
input double s2_equity_tp_buy = 10.0;
input double s3_equity_tp_buy = 10.0;
input group "🎯������ "
input int s1_max_positions_buy = 1;
input int s2_max_positions_buy = 1;
input int s3_max_positions_buy = 1;
input group "🎯������ "
input int s1_min_spacing_buy = 10;
input int s2_min_spacing_buy = 10;
input int s3_min_spacing_buy = 10;

input group "🎯������ "





//==============================//
// 🎯 STRATEGIA 1
//==============================//
input group "🎯 Strategia 1 - Parametri Generali 🎯 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1"
input bool     enable_s1                   = true;        // Attiva o disattiva la Strategia 1 (logica su soglie positive)
input bool     invert_strategy_1           = false;       // Inverte la logica BUY/SELL per test contrarian
input int      magic_strategy_1            = 110001;      // Numero magico univoco per la Strategia 1
input int      sl_pips_s1                  = 40;          // Stop Loss in pips per ogni ordine S1
input int      tp_pips_s1                  = 60;          // Take Profit in pips per ogni ordine S1
input int      trendline_bars_s1           = 20;          // Numero barre da considerare per costruzione trendline S1
input double   equity_tp_s1                = 10.0;        // Profitto cumulativo per chiusura ordini di S1
input int      max_positions_s1            = 3;           // Numero massimo di posizioni contemporanee per S1
input double   min_spacing_s1              = 5.0;         // Spaziatura minima tra ordini S1
input double   trail_pips_s1               = 10.0;        // Trailing Stop in pips per ordini di S1

input double tp_s1 = 40;
input double sl_s1 = 20;
input int magic_s1 = 70011;
input bool invert_strategy_s1 = false;
input int trailing_s1 = 10;
input int bars_s1 = 60;
input bool use_buy_s1 = true;
input bool use_sell_s1 = false;


//------------------------------//
// 🟢 Strategia 1 - BUY Trigger
//------------------------------//
input group "🟢 Strategia 1 - BUY Settings"
input bool     s1_use_buy                  = true;        // Abilita il lato BUY per Strategia 1
input double   angle_thresh_extra_s1_buy   = 30.0;        // Pendenza minima positiva della trendline EXTRA
input double   angle_thresh_macro_s1_buy   = 25.0;        // Pendenza minima positiva della trendline MACRO
input double   angle_thresh_micro_s1_buy   = 20.0;        // Pendenza minima positiva della trendline MICRO
input double   velocity_min_micro_s1_buy   = 0.5;
input double   price_dist_extra_s1_buy     = 100.0;       // Distanza minima tra prezzo e trendline EXTRA (BUY)
input double   delta_tl_s1_buy             = 10.0;        // Differenza angolare tra le 3 TL per validazione BUY
input double   index_s1_buy                = 0.8;         // Valore minimo dell’indice combinato per attivare BUY 

//------------------------------//
// 🔴 Strategia 1 - SELL Trigger
//------------------------------//
input group "🔴 Strategia 1 - SELL Settings"
input bool     s1_use_sell                 = true;        // Abilita il lato SELL per Strategia 1
input double   angle_thresh_extra_s1_sell  = -30.0;       // Pendenza minima negativa della trendline EXTRA
input double   angle_thresh_macro_s1_sell  = -25.0;       // Pendenza minima negativa della trendline MACRO
input double   angle_thresh_micro_s1_sell  = -20.0;       // Pendenza minima negativa della trendline MICRO
input double   velocity_min_micro_s1       = 0.8;
input double   price_dist_extra_s1_sell    = 100.0;       // Distanza minima tra prezzo e trendline EXTRA (SELL)
input double   delta_tl_s1_sell            = 10.0;        // Differenza angolare tra le 3 TL per validazione SELL
input double   index_s1_sell               = 0.8;         // Valore minimo dell’indice combinato per attivare SELL


//==============================//
// 🎯 STRATEGIA 2
//==============================//
input group "🎯 Strategia 2 - Parametri Generali 🎯 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2"
input bool   enable_s2           = true;        // Attiva o disattiva la Strategia 2 (logica su soglie negative)
input bool   invert_strategy_2           = false;       // Inverte la logica BUY/SELL per test contrarian
input int    magic_strategy_2            = 110002;      // Numero magico univoco per la Strategia 2
input int    sl_pips_s2                  = 40;          // Stop Loss in pips per ogni ordine S2
input int    tp_pips_s2                  = 60;          // Take Profit in pips per ogni ordine S2
input int    trendline_bars_s2           = 20;          // Numero barre da considerare per costruzione trendline S2
input double equity_tp_s2                = 10.0;        // Profitto cumulativo per chiusura ordini di S2
input int    max_positions_s2            = 3;           // Numero massimo di posizioni contemporanee per S2
input double min_spacing_s2              = 5.0;         // Spaziatura minima tra ordini S2
input double trail_pips_s2               = 10.0;        // Trailing Stop in pips per ordini di S2



input double tp_s2 = 40;
input double sl_s2 = 20;
input int magic_s2 = 70011;
input bool invert_strategy_s2 = false;
input int trailing_s2 = 10;
input int bars_s2 = 60;
input bool use_buy_s2 = true;
input bool use_sell_s2 = false;



//------------------------------//
// 🟢 Strategia 2 - BUY Trigger
//------------------------------//
input group "🟢 Strategia 2 - BUY Settings"
input bool   s2_use_buy                  = true;        // Abilita il lato BUY per Strategia 2
input double angle_thresh_extra_s2_buy  = 30.0;         // Pendenza minima positiva della trendline EXTRA
input double angle_thresh_macro_s2_buy  = 25.0;         // Pendenza minima positiva della trendline MACRO
input double angle_thresh_micro_s2_buy  = 20.0;         // Pendenza minima positiva della trendline MICRO
input double velocity_min_micro_s2_buy = 0.5;
input double price_dist_extra_s2_buy    = 100.0;        // Distanza minima tra prezzo e trendline EXTRA (BUY)
input double delta_tl_s2_buy            = 10.0;         // Differenza angolare tra le 3 TL per validazione BUY
input double index_s2_buy               = 0.8;          // Valore minimo dell’indice combinato per attivare BUY 

//------------------------------//
// 🔴 Strategia 2 - SELL Trigger
//------------------------------//
input group "🔴 Strategia 2 - SELL Settings"
input bool   s2_use_sell                 = true;        // Abilita il lato SELL per Strategia 2
input double angle_thresh_extra_s2_sell = -30.0;        // Pendenza minima negativa della trendline EXTRA
input double angle_thresh_macro_s2_sell = -25.0;        // Pendenza minima negativa della trendline MACRO
input double angle_thresh_micro_s2_sell = -20.0;        // Pendenza minima negativa della trendline MICRO
input double velocity_min_micro_s2       = 0.8;
input double price_dist_extra_s2_sell   = 100.0;        // Distanza minima tra prezzo e trendline EXTRA (SELL)
input double delta_tl_s2_sell           = 10.0;         // Differenza angolare tra le 3 TL per validazione SELL
input double index_s2_sell              = 0.8;          // Valore minimo dell’indice combinato per attivare SELL




//==============================//
// 🎯 STRATEGIA 3
//==============================//
input group "🎯 Strategia 3 - Parametri Generali 🎯 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3"
input bool   enable_s3           = true;        // Attiva o disattiva la Strategia 3 (blocco TP se eccesso positivo)
input bool   invert_strategy_3           = false;       // Inverte la logica BUY/SELL per test contrarian
input int    magic_strategy_3            = 110003;      // Numero magico univoco per la Strategia 3
input int    sl_pips_s3                  = 40;          // Stop Loss in pips per ogni ordine S3
input int    tp_pips_s3                  = 60;          // Take Profit in pips per ogni ordine S3
input int    trendline_bars_s3           = 20;          // Numero barre da considerare per costruzione trendline S3
input double equity_tp_s3                = 10.0;        // Profitto cumulativo per chiusura ordini di S3
input int    max_positions_s3            = 3;           // Numero massimo di posizioni contemporanee per S3
input double min_spacing_s3              = 5.0;         // Spaziatura minima tra ordini S3
input double trail_pips_s3               = 10.0;        // Trailing Stop in pips per ordini di S3

input double tp_s3 = 40;
input double sl_s3 = 20;
input int magic_s3 = 70011;
input bool invert_strategy_s3 = false;
input int trailing_s3 = 10;
input int bars_s3 = 60;
input bool use_buy_s3 = true;
input bool use_sell_s3 = false;







//------------------------------//
// 🟢 Strategia 3 - BUY Trigger
//------------------------------//
input group "🟢 Strategia 3 - BUY Settings"
input bool   s3_use_buy                  = true;        // Abilita il lato BUY per Strategia 3
input double angle_thresh_extra_s3_buy  = 30.0;         // Pendenza minima positiva della trendline EXTRA
input double angle_thresh_macro_s3_buy  = 25.0;         // Pendenza minima positiva della trendline MACRO
input double angle_thresh_micro_s3_buy  = 20.0;         // Pendenza minima positiva della trendline MICRO
input double velocity_min_micro_s3_buy = 0.5;
input double price_dist_extra_s3_buy    = 100.0;        // Distanza minima tra prezzo e trendline EXTRA (BUY)
input double delta_tl_s3_buy            = 10.0;         // Differenza angolare tra le 3 TL per validazione BUY
input double index_s3_buy               = 0.8;          // Valore minimo dell’indice combinato per attivare BUY 

//------------------------------//
// 🔴 Strategia 3 - SELL Trigger
//------------------------------//
input group "🔴 Strategia 3 - SELL Settings"
input bool   s3_use_sell                 = true;        // Abilita il lato SELL per Strategia 3
input double angle_thresh_extra_s3_sell = -30.0;        // Pendenza minima negativa della trendline EXTRA
input double angle_thresh_macro_s3_sell = -25.0;        // Pendenza minima negativa della trendline MACRO
input double angle_thresh_micro_s3_sell = -20.0;        // Pendenza minima negativa della trendline MICRO
input double   velocity_min_micro_s3       = 0.8;
input double price_dist_extra_s3_sell   = 100.0;        // Distanza minima tra prezzo e trendline EXTRA (SELL)
input double delta_tl_s3_sell           = 10.0;         // Differenza angolare tra le 3 TL per validazione SELL
input double index_s3_sell              = 0.8;          // Valore minimo dell’indice combinato per attivare SELL

//------------------------------//
// 🔴 Strategia 4 - 
//------------------------------//

input group "🧠 Strategia 4 - Parametri Generali 🧠 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4"
input bool     enable_s4           = true;        // Attiva o disattiva la Strategia 4 (logica su soglie negative - blocco TP)
input bool     invert_strategy_4           = false;       // Inverte la logica BUY/SELL per test contrarian
input int      magic_strategy_4            = 110004;      // Numero magico univoco per la Strategia 4
input int      sl_pips_s4                  = 40;          // Stop Loss in pips per ogni ordine S4
input int      tp_pips_s4                  = 60;          // Take Profit in pips per ogni ordine S4
input int      trendline_bars_s4           = 20;          // Numero barre da considerare per costruzione trendline S4
input double   equity_tp_s4                = 10.0;        // Profitto cumulativo per chiusura ordini di S4
input int      max_positions_s4            = 3;           // Numero massimo di posizioni contemporanee per S4
input double   min_spacing_s4              = 5.0;         // Spaziatura minima tra ordini S4
input double   trail_pips_s4               = 10.0;        // Trailing Stop in pips per ordini di S4
input double   angle_thresh_extra_s4       = 30.0;        // Pendenza soglia EXTRA (media)
input double   angle_thresh_macro_s4       = 25.0;        // Pendenza soglia MACRO (media)
input double   angle_thresh_micro_s4       = 20.0;        // Pendenza soglia MICRO (media)
input double   min_dist_extra_s4           = 100.0;       // Distanza min tra prezzo e TL EXTRA

input double tp_s4 = 40;
input double sl_s4 = 20;
input int magic_s4 = 70011;
input bool invert_strategy_s4 = false;
input int trailing_s4 = 10;
input int bars_s4 = 60;
input bool use_buy_s4 = true;
input bool use_sell_s4 = false;





//------------------------------//
// 🟢 Strategia 4 - BUY Trigger
//------------------------------//
input group "🟢 Strategia 4 - BUY Settings"
input bool     s4_use_buy                  = true;        // Abilita il lato BUY per Strategia 4
input double   angle_thresh_extra_s4_buy   = 30.0;        // Pendenza minima positiva della trendline EXTRA
input double   angle_thresh_macro_s4_buy   = 25.0;        // Pendenza minima positiva della trendline MACRO
input double   angle_thresh_micro_s4_buy   = 20.0;        // Pendenza minima positiva della trendline MICRO
input double velocity_min_micro_s4_buy = 0.5;
input double   price_dist_extra_s4_buy     = 100.0;       // Distanza minima tra prezzo e trendline EXTRA (BUY)
input double   delta_tl_s4_buy             = 10.0;        // Differenza angolare tra le 3 TL per validazione BUY
input double   index_s4_buy                = 0.8;         // Valore minimo dell’indice combinato per attivare BUY (blocco TP)
input double   s4_equity_tp_buy            = 10.0;        // Equity TP lato BUY (S4)
input int      s4_max_positions_buy        = 3;           // Max posizioni BUY S4
input double   s4_min_spacing_buy          = 5.0;         // Spaziatura minima BUY S4


//------------------------------//
// 🔴 Strategia 4 - SELL Trigger
//------------------------------//
input group "🔴 Strategia 4 - SELL Settings"
input bool     s4_use_sell                 = true;        // Abilita il lato SELL per Strategia 4
input double   angle_thresh_extra_s4_sell  = -30.0;       // Pendenza minima negativa della trendline EXTRA
input double   angle_thresh_macro_s4_sell  = -25.0;       // Pendenza minima negativa della trendline MACRO
input double   angle_thresh_micro_s4_sell  = -20.0;       // Pendenza minima negativa della trendline MICRO
input double   velocity_min_micro_s4       = 0.8;
input double   price_dist_extra_s4_sell    = 100.0;       // Distanza minima tra prezzo e trendline EXTRA (SELL)
input double   delta_tl_s4_sell            = 10.0;        // Differenza angolare tra le 3 TL per validazione SELL
input double   index_s4_sell               = 0.8;         // Valore minimo dell’indice combinato per attivare SELL (blocco TP)
input double   s4_equity_tp_sell           = 10.0;        // Equity TP lato SELL (S4)
input int      s4_max_positions_sell       = 3;           // Max posizioni SELL S4
input double   s4_min_spacing_sell         = 5.0;         // Spaziatura minima SELL S4

//==============================//
// ⚠️ GESTIONE RISCHIO E TRAILING
//==============================//

//--- 📉 Parametri di rischio e SL/TP di base
input group "⚖️ Gestione Rischio"
input double inp_base_volume          = 0.01;   // Lotto iniziale base
input double inp_max_volume           = 0.1;    // Volume massimo consentito
input double inp_initial_capital      = 1000.0; // Capitale di riferimento per il calcolo dinamico
input int    inp_sl_pips              = 30;     // SL di base usato in fallback (in pips)
input int    inp_tp_pips              = 50;     // TP di base usato in fallback (in pips)

//--- 💡 Strategia di volume dinamico
input group "📊 Strategia Volume"
input ENUM_LOT_STRATEGY inp_lot_strategy = FIXED_LOT; // FIXED_LOT, MARTINGALE, SUMMING ecc.
input double inp_increment_index     = 0.1;    // Incremento percentuale (per strategie dinamiche)
input double inp_martingale_mult     = 2.0;    // Moltiplicatore martingala (se usata)
input double inp_sum_increment       = 0.01;   // Lotto fisso da sommare (se strategia SUMMING)
input bool   inp_use_volume_reset    = true;   // Azzeramento lotto dopo recupero perdita
input double inp_reset_trigger_percent = 10.0; // Soglia % di profitto che azzera (soft reset)

//--- 🔁 Trailing dinamico su momentum
input group "📉 Trailing Dinamico"
input double inp_spike_threshold_points = 300; // Spike massimo tollerato nella candela corrente
input double inp_profit_trigger_points = 200;  // Profitto minimo richiesto prima di attivare trailing
input double inp_trail_pips            = 50;   // Valore base del trailing (modificato dal momentum)
input double inp_momentum_base         = 30;   // Base normalizzata del momentum per scaling
input double inp_momentum_min_factor   = 1.0;  // Fattore minimo sul trailing
input double inp_momentum_max_factor   = 3.0;  // Fattore massimo sul trailing

//--- 🏷️ Etichetta generale del sistema
input string inp_label = "TrendlinePRO";       // Prefisso comune per etichette di trade e log




//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   paramsManager.InitFromInputs();
   Print("✅ Inizializzazione completata con successo.");
   return INIT_SUCCEEDED;
}




void OnDeinit(const int reason) {
    for(int i = 0; i < 6; i++) {
        ObjectDelete(0, "LabelLeft" + IntegerToString(i));
        ObjectDelete(0, "LabelRight" + IntegerToString(i));
    }
    for(int i = 0; i < 3; i++)
        ObjectDelete(0, "Trendline" + IntegerToString(i));
        
    ObjectDelete(0, "VolumeOverlay");
    ObjectDelete(0, "LabelLeft_Lengths");  // ✅ Etichetta extra dashboard vecchia
}





bool IsMarketFavorable()
{
   
   
   
   if (!enable_auto_normalizer)
      return true;

   double volatility = (iHigh(_Symbol, _Period, 1) - iLow(_Symbol, _Period, 1)) / _Point;
   double avg_volume = (double)iVolume(_Symbol, _Period, 1); // cast esplicito corretto

   if (volatility < min_volatility_pips)
   {
      Print("📉 [Filtro Mercato] Volatilità insufficiente: ", volatility, "pips < ", min_volatility_pips);
      return false;
   }

   if (avg_volume < min_volume_tick_avg)
   {
      Print("📉 [Filtro Mercato] Volume insufficiente: ", avg_volume, " < ", min_volume_tick_avg);
      return false;
   }

   return true;
}

#define OBJPROP_TIME1  8
#define OBJPROP_TIME2  9


   
   
datetime ObjectGetTimeByValue(long chart_id, string name, int prop_id)
{
   long val = 0;
   if (!ObjectGetInteger(chart_id, name, (ENUM_OBJECT_PROPERTY_INTEGER)prop_id, 0, val))
      return 0;

   return (datetime)val;
}   
  
  
   
string FormatStrategyLabel(string strategyCode, string direction, int magic)
{
   return StringFormat("%s %s #%d", strategyCode, direction, magic);
}


// Funzione unica per log

void LogOrderPreview(string strategyCode, string direction, int magic)
{
   string label = FormatStrategyLabel(strategyCode, direction, magic);
   Print("[INFO] Opening ", label);
}



double CalculateTrendlineVelocity(string name) {
   long t1_raw, t2_raw;
   if (!ObjectGetInteger(0, name, OBJPROP_TIME, 0, t1_raw) ||
       !ObjectGetInteger(0, name, OBJPROP_TIME, 1, t2_raw))
       return 0.0;

   datetime t1 = (datetime)t1_raw;
   datetime t2 = (datetime)t2_raw;

   double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);

   double delta_price = MathAbs(p2 - p1);
   double delta_time  = (double)(t2 - t1) / 60.0;

   if (delta_time == 0.0) return 0.0;
   return delta_price / delta_time / _Point;
}




void OnTick()
{
   // === PARAMETRI STRATEGICI CENTRALIZZATI ===
     StrategyInputParams s1 = paramsManager.GetS1();
     StrategyInputParams s2 = paramsManager.GetS2();
     StrategyInputParams s3 = paramsManager.GetS3();
     StrategyInputParams s4 = paramsManager.GetS4();

   // === STRATEGIA 1: BUY Contrarian ===
   if(s1.active && !executor.HasOpenTrade(s1.magic))
   {
      bool isBuy = true;
      if(decision.CheckContrarianCumulative(isBuy,
            s1.angle_micro, s1.angle_macro, s1.angle_extra,
            s1.vel, s1.dist,
            s1.angle_macro_thresh,
            s1.angle_extra_thresh,
            s1.angle_micro_limit,
            s1.vel_min, s1.dist_min))
      {
         double lot = trade_volume.CalculateLot();
         executor.OpenBuy(lot, s1.sl_pips, s1.tp_pips, s1.magic, s1.label_prefix + "_BUY");
         Print("✅ [S1] BUY APERTA - ", s1.label_prefix);
      }
   }

   // === STRATEGIA 2: SELL se S1 era attiva ===
   if(s2.active && !executor.HasOpenTrade(s2.magic))
   {
      bool isBuy = false;
      if(decision.CheckContrarianCumulative(isBuy,
            s2.angle_micro, s2.angle_macro, s2.angle_extra,
            s2.vel, s2.dist,
            s2.angle_macro_thresh,
            s2.angle_extra_thresh,
            s2.angle_micro_limit,
            s2.vel_min, s2.dist_min))
      {
         // executor.CloseAllByMagic(s1.magic); // Chiudi S1
         double lot = trade_volume.CalculateLot();
         executor.OpenSell(lot, s2.sl_pips, s2.tp_pips, s2.magic, s2.label_prefix + "_SELL");
         Print("✅ [S2] SELL APERTA (chiusa S1) - ", s2.label_prefix);
      }
   }

   // === STRATEGIA 3: SELL Contrarian ===
   if(s3.active && !executor.HasOpenTrade(s3.magic))
   {
      bool isBuy = false;
      if(decision.CheckContrarianCumulative(isBuy,
            s3.angle_micro, s3.angle_macro, s3.angle_extra,
            s3.vel, s3.dist,
            s3.angle_macro_thresh,
            s3.angle_extra_thresh,
            s3.angle_micro_limit,
            s3.vel_min, s3.dist_min))
      {
         double lot = trade_volume.CalculateLot();
         executor.OpenSell(lot, s3.sl_pips, s3.tp_pips, s3.magic, s3.label_prefix + "_SELL");
         Print("✅ [S3] SELL APERTA - ", s3.label_prefix);
      }
   }

   // === STRATEGIA 4: BUY se S3 era attiva ===
   if(s4.active && !executor.HasOpenTrade(s4.magic))
   {
      bool isBuy = true;
      if(decision.CheckContrarianCumulative(isBuy,
            s4.angle_micro, s4.angle_macro, s4.angle_extra,
            s4.vel, s4.dist,
            s4.angle_macro_thresh,
            s4.angle_extra_thresh,
            s4.angle_micro_limit,
            s4.vel_min, s4.dist_min))
      {
         // executor.CloseAllByMagic(s3.magic); // Chiudi S3
         double lot = trade_volume.CalculateLot();
         executor.OpenBuy(lot, s4.sl_pips, s4.tp_pips, s4.magic, s4.label_prefix + "_BUY");
         Print("✅ [S4] BUY APERTA (chiusa S3) - ", s4.label_prefix);
      }
   }
}






bool CheckContrarianAuto(bool isBuy,
                         double angleMicro, double angleMacro, double angleExtra,
                         double distancePriceToExtra,
                         double idxMicro, double idxMacro, double idxExtra,
                         double thresholdDistanceBUY, double thresholdDistanceSELL,
                         double minIndexBuy, double maxIndexSell)
{
   if (isBuy)
   {
      return (
         angleMicro > 0 && angleMacro > 0 && angleExtra > 0 &&
         distancePriceToExtra > thresholdDistanceBUY &&
         idxMicro > minIndexBuy &&
         idxMacro > minIndexBuy &&
         idxExtra > minIndexBuy
      );
   }
   else
   {
      return (
         angleMicro < 0 && angleMacro < 0 && angleExtra < 0 &&
         distancePriceToExtra < thresholdDistanceSELL &&
         idxMicro < maxIndexSell &&
         idxMacro < maxIndexSell &&
         idxExtra < maxIndexSell
      );
   }
}
   

void ClosePositionByMagic(int magic) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      if (PositionGetTicket(i) == 0) continue;
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if ((int)PositionGetInteger(POSITION_MAGIC) == magic) {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         long type = PositionGetInteger(POSITION_TYPE);

         if (type == POSITION_TYPE_BUY)
            trade.PositionClose(symbol);
         else if (type == POSITION_TYPE_SELL)
            trade.PositionClose(symbol);
      }
   }
}





void UpdateTrendline(string name, int bars_back) {
    if(Bars(_Symbol,_Period)<bars_back) return;

    datetime t1 = iTime(_Symbol,_Period,bars_back);
    double p1 = GetPriceValue(bars_back, TL_CalcBase);  // sostituito iClose con GetPriceValue
    datetime t2 = iTime(_Symbol,_Period,0);
    double p2 = GetPriceValue(0, TL_CalcBase);          // sostituito iClose con GetPriceValue

    if(ObjectFind(0,name)<0)
        ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
    else {
        ObjectMove(0,name,0,t1,p1);
        ObjectMove(0,name,1,t2,p2);
    }
    double angle = GetSlope(name);
    ObjectSetInteger(0,name,OBJPROP_COLOR,(angle>=0)?clrLime:clrRed);
    ObjectSetInteger(0,name,OBJPROP_WIDTH,StringToInteger(StringSubstr(name,-1))+1);
}


double GetSlope(string obj) {
    long t1_raw, t2_raw;
    if(!ObjectGetInteger(0, obj, OBJPROP_TIME, 0, t1_raw) ||
       !ObjectGetInteger(0, obj, OBJPROP_TIME, 1, t2_raw))
        return 0.0;
    datetime t1 = (datetime)t1_raw;
    datetime t2 = (datetime)t2_raw;
    double p1 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
    double p2 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 1);
    double dx = (double)(t2 - t1) / 60.0;
    double dy = (p2 - p1) / _Point;
    double factor = 2.0;
    if(dx == 0.0) return 0.0;
    return MathArctan((dy / dx) * factor) * 180.0 / M_PI;
}

//+------------------------------------------------------------------+
//| NUOVA FUNZIONE: GetTrendRealStrength()                          |
//| Metodo: RGOLD - Strategia 4 (e futura estensione S1-S3)         |
//| Descrizione: calcola la "forza reale" di una trendline          |
//| sulla base dello scostamento diretto del prezzo e              |
//| dell’oscillazione interna tra punto A (inizio) e B (fine).      |
//+------------------------------------------------------------------+

// === PATCH PER STRENGTH REALE ===
double GetTrendRealStrength(string trendName) {
   datetime t1 = (datetime)ObjectGetInteger(0, trendName, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, trendName, OBJPROP_TIME, 1);
   double   p1 = ObjectGetDouble(0, trendName, OBJPROP_PRICE, 0);
   double   p2 = ObjectGetDouble(0, trendName, OBJPROP_PRICE, 1);
   int bars = TrendlineLengthBars(trendName);
   if (bars == 0) return 0.0;
   double scostamento = MathAbs(p2 - p1);
   return scostamento / bars / _Point;
}

int TrendlineLengthBars(string trendName) {
   datetime t1 = (datetime)ObjectGetInteger(0, trendName, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, trendName, OBJPROP_TIME, 1);
   return Bars(_Symbol, _Period, t1, t2);
}

//+------------------------------------------------------------------+
//| NOTE:                                                           |
//| Valori vicini a 1 → trend forte e coerente                      |
//| Valori < 0.3 → oscillazioni laterali o poco direzionali        |
//| Valori 0 → anomalia o barra piatta                             |
//+------------------------------------------------------------------+


// === PATCH PER CALCULATEMETRICS ===
void CalculateMetrics() {
    double a0 = GetSlope("Trendline0");
    double a1 = GetSlope("Trendline1");
    double a2 = GetSlope("Trendline2");

    double v0 = CalculateTrendlineVelocity("Trendline0");
    double v1 = CalculateTrendlineVelocity("Trendline1");
    double v2 = CalculateTrendlineVelocity("Trendline2");

    // ✅ Nuovi valori di forza direzionale realistica
    double f0 = GetTrendRealStrength("Trendline0");  // MICRO
    double f1 = GetTrendRealStrength("Trendline1");  // MACRO
    double f2 = GetTrendRealStrength("Trendline2");  // EXTRA

    double dist = (iClose(_Symbol,_Period,0)-ObjectGetDouble(0,"Trendline2",OBJPROP_PRICE,1))/_Point;

    

    // === TRACK COUNTER - Nuova tabella forza trend (logica grezza temporanea su LabelLeft_Lengths)
    string line = 
      "EXTRA: " + StringFormat("Idx: %.2f | %.1f° | %.2fpt/min | Bars: %d", f2, a2, v2, TrendlineLengthBars("Trendline2")) + "\n" +
      "MACRO: " + StringFormat("Idx: %.2f | %.1f° | %.2fpt/min | Bars: %d", f1, a1, v1, TrendlineLengthBars("Trendline1")) + "\n" +
      "MICRO: " + StringFormat("Idx: %.2f | %.1f° | %.2fpt/min | Bars: %d", f0, a0, v0, TrendlineLengthBars("Trendline0"));

    
}





int CountUP(int window) {
    int count = 0;
    for(int i=1; i<=window; i++) {
        double ma = GetSlope("Trendline1");
        double mi = GetSlope("Trendline0");
        if(mi > ma) count++;
    }
    return count;
}

int CountDOWN(int window) {
    int count = 0;
    for(int i=1; i<=window; i++) {
        double ma = GetSlope("Trendline1");
        double mi = GetSlope("Trendline0");
        if(mi < ma) count++;
    }
    return count;
}

int CountSUPPORT(int window) {
    int count = 0;
    for(int i=1; i<=window; i++) {
        double a0 = GetSlope("Trendline0");
        double a1 = GetSlope("Trendline1");
        double a2 = GetSlope("Trendline2");
        if((a0 > 0 && a1 > 0 && a2 > 0) || (a0 < 0 && a1 < 0 && a2 < 0))
            count++;
    }
    return count;
}

double GetMomentumCurrentTF() {
    double open = iOpen(_Symbol, _Period, 0);
    double close = iClose(_Symbol, _Period, 0);
    return MathAbs(close - open) / _Point;
}

double NormalizeMomentum(double momentum) {
    return MathMin(inp_momentum_max_factor, MathMax(inp_momentum_min_factor, momentum / inp_momentum_base));
}



void ApplyTrailingStop(int trailPips) {
   if (PositionsTotal() == 0) return;

   double momentum = GetMomentumCurrentTF();
   double factor = NormalizeMomentum(momentum);
   double adjustedTrail = trailPips / factor;

   // Ciclo sulle posizioni aperte
for (int i = 0; i < PositionsTotal(); i++) {
   ulong ticket = PositionGetTicket(i);
   if (!PositionSelectByTicket(ticket)) continue;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long type = PositionGetInteger(POSITION_TYPE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   // Prezzo attuale
   double price = (type == POSITION_TYPE_BUY)
                  ? SymbolInfoDouble(symbol, SYMBOL_BID)
                  : SymbolInfoDouble(symbol, SYMBOL_ASK);

   // Profitto in punti, non in valuta
   double profit_points = MathAbs(price - open) / point;

   // === FILTRO 1: profitto minimo prima del trailing dinamico
   if (profit_points < inp_profit_trigger_points) {
      Print("⏸️ Trailing bloccato: profitto attuale ", profit_points,
            "pt < soglia ", inp_profit_trigger_points, "pt");
      continue;
   }

   // === FILTRO 2: spike eccessivo nella candela corrente
   double candle_spike = iHigh(symbol, _Period, 0) - iLow(symbol, _Period, 0);
   if (candle_spike > inp_spike_threshold_points * point) {
      Print("⚠️ Spike rilevato nella candela: ", candle_spike / point,
            "pt > soglia ", inp_spike_threshold_points, "pt");
      continue;
   }

   // === Calcolo trailing dinamico basato su momentum
   double momentum = GetMomentumCurrentTF();
   double factor = NormalizeMomentum(momentum);
   double adjustedTrail = inp_trail_pips / factor;

   // === Nuovo SL calcolato
   double new_sl;
   if (type == POSITION_TYPE_BUY) {
      new_sl = NormalizeDouble(price - adjustedTrail * point, digits);
      if (sl < new_sl)
         executor.ModifyPosition(ticket, new_sl, tp);
   }
   else if (type == POSITION_TYPE_SELL) {
      new_sl = NormalizeDouble(price + adjustedTrail * point, digits);
      if (sl > new_sl || sl == 0.0)
         executor.ModifyPosition(ticket, new_sl, tp);
   }
   
   string lengths = StringFormat("LenMic: %d | LenMac: %d | LenExt: %d",
   TrendlineLengthBars("Trendline0"),
   TrendlineLengthBars("Trendline1"),
   TrendlineLengthBars("Trendline2"));

ObjectSetString(0, "LabelLeft5", OBJPROP_TEXT, lengths);

   // Audit opzionale
   AuditCheck::CheckTrailingLogic(profit_points, momentum, inp_profit_trigger_points, inp_momentum_base);
}
}
