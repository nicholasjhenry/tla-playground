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
  def v2_total(cart), do: Enum.sum(cart.items) - discount(cart)

  @doc """
  Fold a peer's cart into this one (what a node does on sync / write-back).

  This is the operation the TLA+ spec `specs/DiscountCart.tla` model-checks. It
  is the design TLC proved *safe*: items are set-unioned and the discount is
  carried through — even by v1, which never acts on it — because a cart is a
  plain map, so the field rides along instead of being dropped. `discount/1`'s
  default is the forward-compat seam: a v1 cart that predates the field merges
  fine. The spec's *broken* branch (v1 rebuilds the cart and drops `:discount`)
  is pinned as the divergence regression in the test.

  ponytail: items are deduped by value (`Enum.uniq`), i.e. treated as a set like
  the spec — two distinct items at the same price collapse. Fine for the sandbox;
  switch items to a MapSet of ids if that ever matters.
  """
  def merge(mine, peer) do
    %{
      items: Enum.uniq(mine.items ++ peer.items),
      discount: max(discount(mine), discount(peer))
    }
  end

  def discount(cart), do: Map.get(cart, :discount, 0)
end
