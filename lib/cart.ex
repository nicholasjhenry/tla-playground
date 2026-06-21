defmodule Cart do
  @moduledoc """
  The shared data structure, migrated between nodes.

  On the wire a cart is just a map: `%{items: [integer], discount: integer}`.
  v2 added the `:discount` field. v1 was written before it existed.

  ponytail: plain map, not a struct. Both nodes run the same build, so a struct
  would be defined identically on both and couldn't show "v1 doesn't know the
  field". The map is the honest wire format; the *algorithm* is what differs.
  """

  # v1 algorithm: sums items. Never heard of :discount.
  def v1_total(cart), do: Enum.sum(cart.items)

  # v2 algorithm: applies the discount it added.
  def v2_total(cart), do: Enum.sum(cart.items) - Map.get(cart, :discount, 0)
end
