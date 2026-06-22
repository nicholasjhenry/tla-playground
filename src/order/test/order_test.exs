defmodule OrderTest do
  @moduledoc """
  Ports the verified design down the pyramid: the TLA+ spec
  `specs/OrderItem.tla` PROVES the design; these PropCheck properties check the
  Elixir implementation MATCHES it; the deterministic test PINS the exact
  counterexample TLC found.

  The spec's two invariants map straight across:
    Consistent   -> "a migrated order is always well-formed maps"
    QtySurvives  -> "a v1 price edit never changes a qty"
  """
  use ExUnit.Case, async: true
  use PropCheck

  # A canonical line item, mirroring the spec's bounds.
  defp item do
    let {price, qty} <- {choose(1, 5), choose(1, 3)} do
      %{price: price, qty: qty}
    end
  end

  defp order, do: non_empty(list(item()))

  # --- Consistent: the carrier is always a well-formed map (the invariant that
  # PASSES). migrate_in lifts bare scalars and leaves maps canonical.
  property "migrate_in always yields well-formed items with qty >= 1" do
    forall raw <- non_empty(list(oneof([choose(1, 5), item()]))) do
      Enum.all?(Order.migrate_in(raw), &match?(%{price: p, qty: q} when p >= 0 and q >= 1, &1))
    end
  end

  # --- QtySurvives: the invariant the spec is really about ---------------------
  # The tolerant v1 edit reaches in for :price and carries the rest, so a price
  # edit NEVER moves a qty. This is the property the rebuild-bug violates, and
  # exactly what TLC fails to find a counterexample for once the design is fixed.
  property "set_price preserves every qty (the seam invariant)" do
    forall o <- order() do
      i = :rand.uniform(length(o)) - 1
      qtys_before = Enum.map(o, & &1.qty)
      qtys_after = Enum.map(Order.set_price(o, i, 99), & &1.qty)
      qtys_before == qtys_after
    end
  end

  # The same claim stated as a full V1 round trip: lift on receipt, edit a price,
  # and the quantity v2 created is the quantity v2 reads back.
  property "qty survives a V2 -> V1 -> V2 round trip" do
    forall o <- order() do
      migrated = Order.migrate_in(o)
      i = :rand.uniform(length(migrated)) - 1
      Enum.at(Order.set_price(migrated, i, 99), i).qty == Enum.at(migrated, i).qty
    end
  end

  # --- Pin the exact TLC counterexample (specs/OrderItem.tla, State 3) ---------
  test "regression: a v1 price edit keeps the quantity v2 created" do
    # what TLC reached: one item, qty 2
    order = [%{price: 1, qty: 2}]

    # The shipping (tolerant) edit carries qty: 2 through a price change.
    edited = Order.set_price(order, 0, 9)
    assert edited == [%{price: 9, qty: 2}]
    assert Order.subtotal(edited) == 18

    # The bug TLC found, made concrete: a v1 that REBUILDS the item from only
    # the fields it knows resets qty to 1 — subtotal silently halves to 9.
    # (Not shipped; inlined here to show the divergence.)
    rebuilt = List.update_at(order, 0, fn _ -> %{price: 9, qty: 1} end)
    assert Order.subtotal(rebuilt) == 9
  end
end
