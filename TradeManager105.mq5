
//SimpleManager.mq5 
//Trade Management EA                       

#include <Trade/Trade.mqh>
CTrade trade;



struct ManagedTrade
{
   ulong ticket;
   bool  moved_to_be;
};

ManagedTrade managed_trades[100];
int managed_count = 0;

bool IsManaged(ulong ticket)
{
   for(int i = 0; i < managed_count; i++)
      if(managed_trades[i].ticket == ticket)
         return true;
   return false;
}

void AddManaged(ulong ticket)
{
   if(managed_count >= 100) return; // prevent overflow
   managed_trades[managed_count].ticket     = ticket;
   managed_trades[managed_count].moved_to_be = true;
   managed_count++;
}


// Expert tick function                                             

void OnTick()
{
   ManagePositions();
   ManagePendingOrders();
}

// Manage open positions 

void ManagePositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      

      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(sl == 0) continue;

      double risk = MathAbs(entry - sl);

      // Set TP if not set
      if(tp == 0)
      {
         double new_tp = (type == POSITION_TYPE_BUY)
            ? entry + 2 * risk
            : entry - 2 * risk;

         trade.PositionModify(ticket, sl, new_tp);
         tp = new_tp; // update local variable so BE move uses correct tp
      }

      // Skip if already handled at 1:1
      if(IsManaged(ticket)) continue;

      double price = (type == POSITION_TYPE_BUY)
         ? SymbolInfoDouble(symbol, SYMBOL_BID)
         : SymbolInfoDouble(symbol, SYMBOL_ASK);

      double rr1_price = (type == POSITION_TYPE_BUY)
         ? entry + risk
         : entry - risk;

      bool reached_1to1 = (type == POSITION_TYPE_BUY)
         ? price >= rr1_price
         : price <= rr1_price;

      if(reached_1to1)
      {
         // Partial close (only if volume >= 0.02)
         if(volume >= 0.02)
         {
            double close_vol = volume / 2.0;
            double step      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            close_vol        = MathFloor(close_vol / step) * step;

            if(close_vol >= step)
               trade.PositionClosePartial(ticket, close_vol);
         }

         // Move SL to breakeven — fixed: use ticket (ulong), not symbol (string)
         trade.PositionModify(ticket, entry, tp);

         AddManaged(ticket);
      }
   }
}


//| Manage pending orders                                            


void ManagePendingOrders()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
     

      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl    = OrderGetDouble(ORDER_SL);
      double tp    = OrderGetDouble(ORDER_TP);
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(sl == 0 || tp != 0) continue;

      double risk = MathAbs(price - sl);
      double new_tp;

      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP)
         new_tp = price + 2 * risk;
      else if(type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)
         new_tp = price - 2 * risk;
      else
         continue;

      trade.OrderModify(ticket, price, sl, new_tp, ORDER_TIME_GTC, 0, 0);
   }
}
