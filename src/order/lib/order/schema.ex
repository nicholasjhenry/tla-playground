defmodule Order.Schema do
  @moduledoc """
  Single source of truth for the line-item carrier and its evolution.

  A line item evolved from a bare scalar (`10`, price only, qty implicitly 1)
  to a map (`%{price: 10, qty: 2}`). The bare integer has no slot for the new
  fact — so tolerance needs *somewhere* to stash it. This module is that "what
  a bare scalar means" rule, defined ONCE so both versions share it and the
  assumption can't drift between them.

  ponytail: one tiny module, two functions. The rule is small; the discipline
  is keeping it in exactly one place rather than restating `n -> %{price: n,
  qty: 1}` at every call site where it could quietly diverge.
  """

  @typedoc "Canonical line item from the carrier change onward."
  @type item :: %{price: non_neg_integer(), qty: pos_integer()}

  @doc """
  Lift one element from the V1 representation to the canonical map.

  COMMITS to a semantic answer: the bare integer is the UNIT price, and an
  unrecorded quantity defaults to 1. If V1's scalar was ever a LINE TOTAL this
  default is silently wrong the moment qty is edited — this is the one place
  that decision lives. Idempotent: an already-canonical value passes through.
  """
  @spec lift(integer() | item()) :: item()
  def lift(price) when is_integer(price), do: %{price: price, qty: 1}
  def lift(%{price: _, qty: _} = item), do: item

  @doc "Lift a whole list. Call at an ownership boundary, not per-operation."
  @spec upgrade([integer() | item()]) :: [item()]
  def upgrade(items), do: Enum.map(items, &lift/1)
end
