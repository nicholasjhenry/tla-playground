defmodule NodeA do
  @moduledoc "The NEW node. Runs v2. Builds a v2 cart and migrates it to node B."

  def run do
    b = sibling("b")
    IO.puts("node A (v2) starting — will migrate a cart to #{b}")
    connect(b)

    cart = %{items: [10, 20, 30], discount: 5}
    IO.puts("A built v2 cart: #{inspect(cart)}")
    IO.puts("A (v2 algorithm) total = #{Cart.v2_total(cart)}  <- discount applied (correct)")

    # ponytail: tiny sleep so B's :cart_receiver is registered before we send.
    # send/2 to an unregistered name drops silently; a connect-retry + sleep is
    # plenty for a two-node demo. A GenServer/handshake would be overkill here.
    Process.sleep(300)
    send({:cart_receiver, b}, {:cart, cart})
    IO.puts("A migrated the cart to #{b}. Watch the node-b pane for v1's answer.\n")
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
