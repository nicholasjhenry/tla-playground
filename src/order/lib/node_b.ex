defmodule NodeB do
  @moduledoc """
  The OLD node (V1). Predates `qty`. Receives an order, edits a price, hands it
  back. It must CARRY `qty` it doesn't understand — not rebuild the item.
  """

  def start do
    Process.register(self(), :order_receiver)
    IO.puts("node B (v1) ready — waiting for an order to be migrated here...")
    loop()
  end

  defp loop do
    receive do
      {:order, order, from} ->
        IO.puts("\nB received order: #{inspect(order)}")
        IO.puts("B (v1 algorithm) subtotal = #{Order.subtotal_v1(order)}")
        IO.puts("  ^ v1 sums prices and assumes qty == 1 — it predates the field. A wrong")
        IO.puts("    subtotal while v1 owns the order is benign. The bug is DROPPING qty.")

        # The tolerant edit: reach in for :price, carry :qty along. The lossy
        # alternative — rebuilding `%{price: 8, qty: 1}` — would typecheck, pass
        # every v1 test, and clobber qty. That one choice is the whole bug.
        edited = Order.set_price(order, 0, 8)
        IO.puts("B edited the price (carrying qty it doesn't understand): #{inspect(edited)}")
        send({:order_receiver, from}, {:edited, edited})
        IO.puts("B handed the order back to #{from}. Watch the node-a pane.")
        loop()
    end
  end
end
