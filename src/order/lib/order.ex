defmodule Order do
  @moduledoc """
  The shared data structure, whose OWNERSHIP migrates between nodes on different
  code versions (V2 → V1 → V2). An order is a list of line items.

  This is ONE module shown at its safe end-state, not three parallel modules.
  The durable concept keeps its stable name `Order`; the version lives in the
  node and in capability data (`Order.Ownership`), never in a module path —
  see `notebooks/order.livemd` for the earlier reader-only/writer-flip snapshots.

  Two algorithms live here, exactly as `src/merge/lib/cart.ex` carried both
  `v1_total` and `v2_total`:

    * `subtotal/1`     — v2 (qty-aware): price × qty.
    * `subtotal_v1/1`  — v1 (old): sums prices, assumes qty == 1. Benign-but-wrong
                          while a v1 node owns the order — the feature rolling out.

  The CATASTROPHE the TLA+ spec (`specs/OrderItem.tla`) checks is not the wrong
  subtotal; it is DATA LOSS — a v1 edit that resets `qty`. The fix is the one
  line in `set_price/3`: reach in for `price` and CARRY the rest (`%{item |
  price: price}`), never rebuild the item (`%{price: price, qty: 1}`, which
  typechecks, passes every v1 test, and clobbers `qty` on every edit). Tolerant
  code carries; it does not comprehend. The lossy rebuild is pinned as the
  divergence regression in `test/order_test.exs`.
  """

  alias Order.Schema

  @doc """
  THE ownership boundary. Every order enters here on receipt; lift ONCE so the
  operations below never observe a bare integer and never normalize themselves.
  A path that reaches an operation without passing through here is the bug.
  """
  def migrate_in(items), do: items |> Schema.upgrade() |> Enum.map(&rederive/1)

  # Re-derive (don't trust) any field coupled to what a v1 node may have edited.
  # A no-op today; the seam where invariants get re-established if one appears.
  defp rederive(item), do: item

  # v2 (qty-aware) subtotal: price × qty. The source of truth for what an order
  # is worth.
  def subtotal(items), do: Enum.sum(Enum.map(items, &(&1.price * &1.qty)))

  # v1 (old) subtotal: sums prices, assumes qty == 1. Tolerates a map if one
  # appears early, but never reads qty — it predates the field.
  def subtotal_v1(items) do
    Enum.sum(
      Enum.map(items, fn
        n when is_integer(n) -> n
        %{price: p} -> p
      end)
    )
  end

  def add(items, price, qty), do: items ++ [%{price: price, qty: qty}]

  # The tolerant v1 edit: reach in for price, carry the rest. qty rides along.
  # This one line is the whole forward-compatibility mechanism.
  def set_price(items, i, price), do: List.update_at(items, i, &%{&1 | price: price})

  def set_qty(items, i, qty), do: List.update_at(items, i, &%{&1 | qty: qty})
end
