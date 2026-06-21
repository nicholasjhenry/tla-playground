defmodule CartTest do
  @moduledoc """
  Ports the verified design down the pyramid: the TLA+ spec
  `specs/DiscountCart.tla` PROVES the design; these PropCheck properties check
  the Elixir implementation MATCHES it; the deterministic test PINS the exact
  counterexample TLC found.

  The spec's two invariants map straight across:
    Consistent  -> "a well-formed cart never goes negative"
    MergeAgrees -> "the discount survives a merge in either direction"
  """
  use ExUnit.Case, async: true
  use PropCheck

  # A well-formed cart, mirroring the spec's bounds: discount never exceeds what
  # the items can cover, so the v2 total stays non-negative (the Consistent rule).
  defp cart do
    let items <- list(choose(1, 5)) do
      let discount <- choose(0, length(items)) do
        %{items: items, discount: discount}
      end
    end
  end

  # --- Consistent: each replica stays well-formed (the spec invariant that PASSES)
  property "a well-formed cart never has a negative total" do
    forall c <- cart() do
      Cart.v2_total(c) >= 0
    end
  end

  # --- MergeAgrees: the invariant the spec is really about ---------------------
  # v1 and v2 must recover the SAME total after a sync. Because `merge/2` carries
  # the discount through (forward-compatible), the merge is order-independent and
  # the two nodes agree — exactly what TLC fails to find a counterexample for once
  # the design is fixed.
  property "MergeAgrees: both merge directions recover the same total" do
    forall {a, b} <- {cart(), cart()} do
      Cart.v2_total(Cart.merge(a, b)) == Cart.v2_total(Cart.merge(b, a))
    end
  end

  # The mechanism behind agreement, stated with teeth: a merge that dropped the
  # discount would fail this. This is the property that breaks the instant someone
  # "optimizes" v1 into a struct that doesn't declare :discount.
  property "merge never drops a discount" do
    forall {a, b} <- {cart(), cart()} do
      Cart.discount(Cart.merge(a, b)) == max(Cart.discount(a), Cart.discount(b))
    end
  end

  # --- Pin the exact TLC counterexample (specs/DiscountCart.tla, State 3) -------
  test "regression: the trace state keeps its discount through a v1 merge" do
    v2_cart = %{items: [1], discount: 1}  # what TLC reached: one item, discount 1
    v1_cart = %{items: [], discount: 0}   # the old node, empty

    # The shipping (forward-compatible) merge preserves the discount: 1 - 1 = 0.
    assert Cart.v2_total(Cart.merge(v1_cart, v2_cart)) == 0

    # The bug TLC found, made concrete: a v1 that rebuilds the cart from only the
    # fields it knows drops :discount, and a v2 reader now computes 1, not 0 —
    # the two nodes diverge. (Not shipped; inlined here to show the divergence.)
    lossy = %{items: Enum.uniq(v1_cart.items ++ v2_cart.items)}
    assert Cart.v2_total(lossy) == 1
  end
end
