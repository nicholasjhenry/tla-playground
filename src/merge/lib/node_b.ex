defmodule NodeB do
  @moduledoc "The OLD node. Runs the v1 algorithm. Receives a cart and processes it."

  def start do
    Process.register(self(), :cart_receiver)
    IO.puts("node B (v1) ready — waiting for a cart to be migrated here...")
    loop()
  end

  defp loop do
    receive do
      {:cart, cart} ->
        IO.puts("\nB received cart: #{inspect(cart)}")
        IO.puts("B (v1 algorithm) total = #{Cart.v1_total(cart)}")
        IO.puts("  ^ v1 silently ignores :discount — it didn't exist when v1 was written.")
        IO.puts("  (no crash: the extra field rides along harmlessly. The bug is a WRONG total.)")
        loop()
    end
  end
end
