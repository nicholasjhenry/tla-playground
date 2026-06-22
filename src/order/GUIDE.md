# Catching a Schema-Evolution Bug Before It Ships

During a rolling upgrade the *ownership* of an in-memory data structure migrates
between nodes on different code versions. In this tutorial we'll make that
concrete: a list element evolves from a bare scalar to a map, we hand it from a
new node to an old one and back, use a model checker to prove *when* that round
trip silently loses data, fix the design, and lock the fix in with tests.

This is the project's verification pyramid, walked end to end:

> **TLA+ proves the design → PropCheck checks the implementation matches → ExUnit pins the regression.**

## What We'll Do

By the end we'll have:

- run two nodes on **V1** and **V2** of an algorithm and seen them compute different answers
- used **TLC** to find the exact round trip where a quantity is silently lost
- **fixed** the design and watched TLC turn green
- ported the same property down to **PropCheck** and **ExUnit**

A line item evolved from a bare scalar (`10` — price only, qty implicitly 1) to
a map (`%{price: 10, qty: 2}`). **V2** introduced the quantity; **V1** was
written before it existed.

## Before We Start

You'll need:

- [mise](https://mise.jdx.dev) (the repo pins Erlang, Elixir, and Java in `mise.toml`)
- [mprocs](https://github.com/pvolok/mprocs) (`brew install mprocs`)
- this repository, and about 15 minutes

## Step 1: Set Up the Toolchain

Let's install the pinned runtimes and fetch the model checker. From this
directory (`src/order/`):

```bash
mise install
curl -sL -o tla2tools.jar \
  https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
```

Let's check everything's in place:

```bash
mise exec -- java -version
mix compile
```

We should see Java 21 report itself and the project compile clean. The
`tla2tools.jar` is gitignored on purpose — it's a downloaded tool, not source.

## Step 2: Watch the Two Versions Disagree

Now let's run both nodes side by side. `mprocs` reads `mprocs.yaml` and starts
each node in its own pane:

```bash
mprocs
```

The **node-b-v1** pane boots first and waits. The **node-a-v2** pane builds a V2
order, migrates it across, and waits for it back. In the **node-a-v2** pane we
should see:

```
A built v2 order: [%{price: 10, qty: 2}]
A (v2 algorithm) subtotal = 20  <- price × qty (correct)
A migrated the order to b@127.0.0.1. Waiting for v1 to edit a price and hand it back...
```

And in the **node-b-v1** pane:

```
B received order: [%{price: 10, qty: 2}]
B (v1 algorithm) subtotal = 10
  ^ v1 sums prices and assumes qty == 1 — it predates the field.
```

There it is: **20 on the new node, 10 on the old one**, from the very same order.

That difference, on its own, is benign — V1 just shows a stale subtotal for a
while. The dangerous question is the next one: what happens when V1 *edits the
order and writes it back*?

In the demo, V1 does the *tolerant* edit (it reaches in for `:price` and carries
`:qty`), so node A reports the quantity survived. Press `q` to quit mprocs. The
catastrophic alternative — V1 rebuilding the item and dropping `:qty` — is what
we hand to the model checker next.

## Step 3: Prove When It Becomes Data Loss

A live demo shows one interleaving. To check *every* ordering, we hand the
design to TLC. The spec in `specs/OrderItem.tla` models the risky case: a V1
node that edits the price by **rebuilding** the item and, having no slot for
`qty`, resets it to 1.

From the `specs/` directory:

```bash
cd specs
mise exec -- java -cp ../tla2tools.jar pcal.trans OrderItem.tla \
  && mise exec -- java -cp ../tla2tools.jar tlc2.TLC -config OrderItem.cfg OrderItem.tla
```

TLC explores the state space and hands back a counterexample:

```
Error: Invariant QtySurvives is violated.
Error: The behavior up to this point is:
State 1: <Initial predicate>
  intendedQty = 2  /\  item = [price |-> 1, qty |-> 2]
State 3: <V1EditPrice ...>
  intendedQty = 2  /\  item = [price |-> 9, qty |-> 1]
State 4: <HandBackToV2 ...>
  intendedQty = 2  /\  item = [price |-> 9, qty |-> 1]
```

Let's read it: V2 creates an item with `qty = 2` (State 1), V1 edits the price
and rebuilds the item, dropping `qty` to 1 (State 3). When ownership returns to
V2 (State 4) it reads back a quantity it never wrote — they diverge permanently.
Notice TLC reports **no** violation of `Consistent`: every item stayed a
perfectly well-formed map. The bug lives entirely in what V1 does with V2's data.

> Why is *this* the catastrophe and Step 2's 20-vs-10 wasn't? Because a stale
> subtotal is temporary, but a dropped field is forever — gone even after every
> node upgrades. The spec's header comment in `specs/OrderItem.tla` lays this out
> in full.

## Step 4: Fix the Design and Re-Prove It

The fix is to make the carrier forward-compatible: teach V1 to *carry* the
quantity even though it never acts on it. Open `specs/OrderItem.tla` and find
`EditPrice`:

```
EditPrice(version, item, newPrice) ==
  IF version = "v1"
  THEN [price |-> newPrice, qty |-> 1]
  ELSE [item EXCEPT !.price = newPrice]
```

Delete the `IF version = "v1" ... THEN ... ELSE` so both versions take the
second branch — V1 now reaches in for `price` and carries `qty`:

```
EditPrice(version, item, newPrice) == [item EXCEPT !.price = newPrice]
```

Re-run TLC (we add `-deadlock` because the fixed spec terminates cleanly):

```bash
mise exec -- java -cp ../tla2tools.jar tlc2.TLC -deadlock -config OrderItem.cfg OrderItem.tla
```

This time the design holds:

```
Model checking completed. No error has been found.
```

We've proven the fix. Let's restore the spec to its bug-finding state so it
keeps teaching, and return to the example root:

```bash
git checkout OrderItem.tla
cd ..
```

## Step 5: Port the Property Down to the Code

A green model proves the *design*, not the *code*. Let's check the Elixir
implementation matches it. `lib/order.ex` ships the tolerant `set_price/3`, and
`test/order_test.exs` encodes the same invariants as PropCheck properties:

```bash
mix test test/order_test.exs
```

We should see them pass:

```
....
Result: 4 passed (3 properties, 1 test)
```

Each test traces straight back to the spec:

- the spec's `Consistent` → property *"migrate_in always yields well-formed items"*
- the spec's `QtySurvives` → property *"set_price preserves every qty"* (plus the round-trip property — the one with teeth)
- the TLC counterexample (State 3) → the regression test *"a v1 price edit keeps the quantity v2 created"*

The property-based tests generate hundreds of random orders; the regression test
pins the exact state TLC found. Design proven, implementation checked, trace pinned.

## What We Built

We took one mixed-version question — *can V1 and V2 safely share this order?* —
all the way down the pyramid:

- **Saw** two live nodes disagree (`mprocs`)
- **Proved** with TLC exactly when a round trip becomes permanent data loss
- **Fixed** the design (carry the field) and re-proved it green
- **Pinned** the same invariants as PropCheck properties and an ExUnit regression

The lesson under all of it: **a scalar has no room for a new fact, so promote the
carrier before you give the field meaning** — make the element a map both
versions can hold one release before any node populates `qty`. Tolerant code
*carries*; it does not comprehend (`%{item | price: price}`, never
`%{price: price, qty: 1}`). And the gate that actually keeps you safe is a *code*
invariant — *every owner is at or above a capability floor* (`lib/order/ownership.ex`)
— not the unprovable data claim *is everything migrated?*

## Going Deeper

- `specs/OrderItem.tla` — the spec's footer documents a second fix (gating the new behaviour with the capability floor) you can encode and re-check
- `lib/order/ownership.ex` — the capability floor, in Elixir
- `.claude/tla-mixed-version-elixir/SKILL.md` — the full methodology, the Shape A vs B decision, and the Elixir→TLA+ mapping
- [`.claude/.../references/toolchain.md`](.claude/tla-mixed-version-elixir/references/toolchain.md) — reading TLC traces, bounding the state space, the deadlock-at-termination gotcha
- [learntla.com](https://learntla.com) — Hillel Wayne's guide, which the conventions here follow
- `CLAUDE.md` — the project's conventions and anti-patterns for this TLA+/Elixir combo
```
