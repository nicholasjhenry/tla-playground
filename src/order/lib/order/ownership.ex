defmodule Order.Ownership do
  @moduledoc """
  The actual safety gate — and it is a CODE invariant, not a data one.

  "All data migrated" is unprovable under lazy migration, so we never gate on
  it. "Every owner is at or above a capability floor", enforced at the handoff
  boundary, makes the data question moot: no order carrying a new-shape fact is
  ever owned by a node that can't honour it.

  This is the Elixir twin of the spec's *second* fix (gate the new behaviour):
  raise the floor only after the writer-flip it guards is universally safe.
  Capability is tag-as-data — the one place a version number legitimately lives.
  """

  @type capability :: :reader_only | :map_writer | :qty_aware

  @rank %{reader_only: 1, map_writer: 2, qty_aware: 3}

  # Raise the floor only after the writer-flip it guards is universally safe:
  #   :reader_only  while the reader-only release rolls out
  #   :map_writer   once every node can read maps and a node may write them
  #   :qty_aware    once every node is qty-aware and qty != 1 may be written
  @floor :reader_only

  @doc "May a node advertising `cap` take ownership under the current floor?"
  @spec can_own?(capability()) :: boolean()
  def can_own?(cap), do: Map.fetch!(@rank, cap) >= Map.fetch!(@rank, @floor)
end
