---
name: tla-mixed-version-elixir
description: >-
  Use TLA+ (the formal specification language taught at https://learntla.com) to
  verify that a single data structure is safe to use across two nodes that run
  two DIFFERENT versions of an algorithm on it — the classic rolling-upgrade /
  hot-code-change / mixed-version problem in distributed Elixir. Reach for this
  whenever the user mentions TLA+, PlusCal, model checking, formal verification,
  learntla, "design is broken", rolling deploys, mixed/multi-version
  compatibility, forward/backward compatibility of state, CRDT convergence,
  replicated GenServer state, `code_change/3`, two nodes disagreeing, or "can two
  nodes running different code safely share this data structure" — even if they
  don't say "TLA+" explicitly. Produces a PlusCal spec + TLC config the user
  runs locally, plus the mapping back to Elixir/PropCheck.
---

# Verifying mixed-version data structures with TLA+ (for distributed Elixir)

## What this skill is for

During a rolling upgrade (or a hot `code_change/3`, or any partial deploy) two
nodes run two different versions of an algorithm **at the same time**, against
**the same logical data structure**. The question this skill answers is:

> Can version V1 (old) and version V2 (new) both operate on this data structure
> without corrupting it or making the two nodes permanently disagree?

This is a *design* question, not a code question — it lives in the interleavings
and merges, exactly where tests rarely look. TLA+ explores **every** ordering and
combination for you and hands back a concrete counterexample when the design is
broken. Conventions here follow https://learntla.com (Hillel Wayne's guide):
PlusCal algorithms, the `---- MODULE ... ====` wrapper, a `define` block for
invariants, and TLC as the model checker.

## Pick the shape first

Two structurally different situations hide under "two nodes, two versions". Decide
which one you have before modeling — it changes the whole spec. Details and the
Elixir→TLA+ mapping are in `references/modeling-guide.md`.

- **Shape B — replicated structure that gets merged (the usual rolling-upgrade
  case).** Each node holds its own copy; copies are reconciled by a merge (CRDT
  join, `:pg`/`Phoenix.Tracker` sync, gossip, or the old/new state handed across
  `code_change/3`). The danger is **divergence**: a merge that silently loses or
  resurrects data because one version doesn't understand the other's shape. This
  is what `templates/MixedVersion.tla` and `examples/ReplicatedSet.tla` model.
  **Start here unless you're sure it's Shape A.**

- **Shape A — one shared copy mutated concurrently.** A single row reached via
  Ecto from both nodes, one ETS table, one GenServer reached by RPC. The danger
  is **bad interleavings** (lost updates, broken guards). Model it with PlusCal
  processes and per-statement `labels`, then check a per-state invariant — the
  bank-transfer pattern from learntla.com. See `references/modeling-guide.md`
  for the snippet.

## Workflow

1. **State the three things in plain language**, before any TLA+: (a) the data
   structure, (b) what V1 does vs what V2 does to it, (c) the safety property
   that must survive both ("both nodes observe the same members", "balance never
   negative", "no key is dropped"). If you can't name (c), stop and find it — a
   spec with no property checks nothing.

2. **Copy the starting point.** Shape B → `templates/MixedVersion.tla` +
   `templates/MixedVersion.cfg`. Read `examples/ReplicatedSet.tla` first as a
   fully worked instance (it finds a real bug). Rename the module to match the
   filename (TLA+ requires `MODULE Foo` live in `Foo.tla`).

3. **Map your Elixir state to TLA+ values** using the table in
   `references/modeling-guide.md` (map→function, struct→record, MapSet→set,
   list→sequence, etc.). Keep the domain *tiny* (1–2 elements, 2 nodes); design
   bugs almost always show up at small scope.

4. **Fill the four hooks** in the template, each marked `TODO`:
   `Observe` (what the structure *means* under each version), `MergeInto` (how
   each version folds a peer's state in — branch on the version, that asymmetry
   is the whole point), `LocalOp` (a version's local mutation), and `Consistent`
   (the per-node structural invariant). The agreement check `MergeAgrees` is
   already wired up.

5. **Translate and check, small.** See `references/toolchain.md` for exact
   commands. The short version (command line):
   ```
   java -cp tla2tools.jar pcal.trans MixedVersion.tla \
     && java -cp tla2tools.jar tlc2.TLC -deadlock -config MixedVersion.cfg MixedVersion.tla
   ```
   Or the VSCode TLA+ extension / the Toolbox (what learntla.com walks through).
   The `-deadlock` flag suppresses a benign "deadlock" report at the terminal
   state — these specs terminate by design (drop the flag if you actually want to
   check for liveness/stuck states).

6. **Read the counterexample.** TLC prints the exact sequence of states leading
   to the violation. Map the final state's variables back to your Elixir state to
   see the concrete scenario. **Fix the design** (the merge, the wire format, a
   migration gate) and re-check until it passes. A passing small model isn't a
   proof, but empirically catches the overwhelming majority of design bugs.

7. **Port the verified design down the pyramid.** Once TLC is green, encode the
   *same* invariant as a PropCheck property and the *same* operations as
   `commands` / `parallel_commands`, then pin concrete cases in ExUnit. TLA+
   proves the design; PropCheck checks the implementation matches it; ExUnit
   guards regressions. The mapping is in `references/modeling-guide.md`.

## The mixed-version trap, in one example

The worked example (`examples/ReplicatedSet.tla`) models a replicated set where
V1 is add-only (a G-Set) and V2 adds tombstone-based removal (a 2P-Set). Each
*replica* stays perfectly well-formed (`Consistent` passes). But TLC still fails
`MergeAgrees`: V2 removes an element, V1 receives the update, doesn't understand
the tombstone, and the element **resurrects** — the two nodes never agree again.
That's the shape of nearly every mixed-version bug: each side is locally correct,
and the defect lives entirely in what one version does with the other's data. The
example's footer notes describe the fix and how to re-verify it.

## Files in this skill

- `templates/MixedVersion.tla` + `.cfg` — Shape B skeleton; translates and checks
  green as-is, then you fill the four `TODO`s.
- `examples/ReplicatedSet.tla` + `.cfg` — worked Shape B example that *finds* a
  real mixed-version bug; read this to learn the pattern.
- `references/modeling-guide.md` — Shape A vs B decision, full Elixir→TLA+
  mapping, an invariant catalog, modeling the two versions and the network, and
  the spec→PropCheck/ExUnit bridge.
- `references/toolchain.md` — install + exact translate/check commands, the `.cfg`
  format, bounding the state space, reading error traces, the deadlock-at-
  termination gotcha, and Apalache for larger scopes.

## Keep in mind

- Check the **structural** invariant (`Consistent`) and the **agreement**
  invariant (`MergeAgrees`) separately. "Each replica is well-formed" and "the
  two replicas agree" are different claims, and mixed-version bugs love the gap.
- Always model the merge in **both directions** (V1←V2 and V2←V1). Compatibility
  is not symmetric: old reading new often breaks even when new reading old is
  fine.
- Bigger constants rarely find new bugs and cost a lot of RAM. Start at the
  smallest scope that can even express the bug (often a single element).
