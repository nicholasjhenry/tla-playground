defmodule NodeA do
  @moduledoc """
  The NEW node (V2, qty-aware). Creates an order with a real quantity, hands it
  to the OLD node for a price edit, and checks `qty` survived the round trip.
  """

  def run do
    Process.register(self(), :order_receiver)
    b = sibling("b")
    IO.puts("node A (v2) starting — will migrate an order to #{b} and back")
    connect(b)

    order = Order.add([], 10, 2)
    IO.puts("A built v2 order: #{inspect(order)}")
    IO.puts("A (v2 algorithm) subtotal = #{Order.subtotal(order)}  <- price × qty (correct)")

    # ponytail: tiny sleep so B's :order_receiver is registered before we send.
    # send/2 to an unregistered name drops silently; a connect-retry + sleep is
    # plenty for a two-node demo.
    Process.sleep(300)
    send({:order_receiver, b}, {:order, order, node()})
    IO.puts("A migrated the order to #{b}. Waiting for v1 to edit a price and hand it back...\n")
    await_return()
  end

  defp await_return do
    receive do
      {:edited, order} ->
        [%{qty: qty} = item] = order
        IO.puts("\nA got the order back: #{inspect(order)}")
        IO.puts("A (v2 algorithm) subtotal = #{Order.subtotal(order)}  <- price × qty")

        if qty == 2 do
          IO.puts(
            "  ^ qty: 2 SURVIVED the trip through v1 — it carried the field instead of rebuilding it."
          )
        else
          IO.puts(
            "  ^ qty was reset to #{qty}! v1 rebuilt the item and clobbered the quantity (the bug)."
          )
        end

        rebuilt = %{price: item.price, qty: 1}

        IO.puts(
          "  (had v1 rebuilt the map, it would read #{inspect(rebuilt)} — subtotal #{rebuilt.price * rebuilt.qty}, silently halved.)"
        )
    end
  end

  # B is the same short hostname, node name "b" instead of "a".
  defp sibling(name) do
    [_, host] = node() |> Atom.to_string() |> String.split("@")
    String.to_atom("#{name}@#{host}")
  end

  defp connect(b) do
    if Node.connect(b) == true do
      IO.puts("A connected to #{b}")
    else
      Process.sleep(500)
      connect(b)
    end
  end
end
