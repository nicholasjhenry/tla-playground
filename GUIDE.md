# Catching a Mixed-Version Bug Before It Ships

During a rolling upgrade, two nodes run two versions of your code at the same
time, against the same data. In this tutorial we'll make that situation concrete:
we'll watch two Elixir nodes disagree about a shopping cart, use a model checker
to prove *when* that disagreement turns into permanent data loss, fix the design,
and lock the fix in with tests.

This is the project's verification pyramid, walked end to end:

> **TLA+ proves the design → PropCheck checks the implementation matches → ExUnit pins the regression.**

## What We'll Do

By the end we'll have:

- run two nodes on **v1** and **v2** of an algorithm and seen them compute different answers
- used **TLC** to find the exact sequence where a discount is silently lost
- **fixed** the design and watched TLC turn green
- ported the same property down to **PropCheck** and **ExUnit**

The cart is a plain map: `%{items: [10, 20, 30], discount: 5}`. **v2** introduced
the `discount` field; **v1** was written before it existed.

## Before We Start

You'll need:

- [mise](https://mise.jdx.dev) (the repo pins Erlang, Elixir, and Java in `mise.toml`)
- [mprocs](https://github.com/pvolok/mprocs) (`brew install mprocs`)
- this repository, and about 15 minutes

## Step 1: Set Up the Toolchain

Let's install the pinned runtimes and fetch the model checker. From the repo root:

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

We should see Java 21 report itself and the project compile clean:

```
openjdk version "21.0.11" 2026-04-21 LTS
...
Generated tla_playground app
```

The `tla2tools.jar` is gitignored on purpose — it's a downloaded tool, not source.

## Step 2: Watch the Two Versions Disagree

Now let's run both nodes side by side. `mprocs` reads `mprocs.yaml` and starts each
node in its own pane:

```bash
mprocs
```

The **node-b-v1** pane boots first and waits. The **node-a-v2** pane builds a v2
cart and migrates it across. In the **node-a-v2** pane we should see:

```
A built v2 cart: %{items: [10, 20, 30], discount: 5}
A (v2 algorithm) total = 55  <- discount applied (correct)
A migrated the cart to b@127.0.0.1. Watch the node-b pane for v1's answer.
```

And in the **node-b-v1** pane:

```
B received cart: %{items: [10, 20, 30], discount: 5}
B (v1 algorithm) total = 60
  ^ v1 silently ignores :discount — it didn't exist when v1 was written.
```

There it is: **55 on the new node, 60 on the old one**, from the very same cart.
Press `q` to quit mprocs.

That difference, on its own, is benign — v1 just shows an undiscounted total for a
while. The dangerous question is the next one: what happens when v1 *writes the
cart back*?

## Step 3: Prove When It Becomes Data Loss

A live demo shows one interleaving. To check *every* ordering, we hand the design to
TLC. The spec in `specs/DiscountCart.tla` models the risky case: a v1 node that
folds the cart into its own copy and, having no field for `discount`, drops it.

From the `specs/` directory:

```bash
cd specs
mise exec -- java -cp ../tla2tools.jar pcal.trans DiscountCart.tla \
  && mise exec -- java -cp ../tla2tools.jar tlc2.TLC -config DiscountCart.cfg DiscountCart.tla
```

TLC explores the state space and hands back a counterexample:

```
Error: Invariant MergeAgrees is violated.
Error: The behavior up to this point is:
State 1: <Initial predicate>
  replica = [v1 |-> [items |-> {}, disc |-> 0], v2 |-> [items |-> {}, disc |-> 0]]
State 2: <Step("v2") ...>
  replica = [v1 |-> [items |-> {}, disc |-> 0], v2 |-> [items |-> {"a"}, disc |-> 0]]
State 3: <Step("v2") ...>
  replica = [v1 |-> [items |-> {}, disc |-> 0], v2 |-> [items |-> {"a"}, disc |-> 1]]
```

Let's read it: v2 adds an item (State 2), then sets a discount (State 3). At that
point, if the two nodes sync, v1's merge drops the discount and the two nodes
recover different totals — they diverge permanently. Notice TLC reports **no**
violation of `Consistent`: every replica stayed perfectly well-formed. The bug
lives entirely in what v1 does with v2's data.

> Why is *this* the catastrophe and Step 2's 55-vs-60 wasn't? Because a wrong total
> is temporary, but a dropped field is forever — gone even after every node upgrades.
> The spec's header comment in `specs/DiscountCart.tla` lays this out in full.

## Step 4: Fix the Design and Re-Prove It

The fix is to make the data forward-compatible: teach v1 to *carry* the discount
even though it never acts on it. Open `specs/DiscountCart.tla` and find `MergeInto`:

```
MergeInto(version, mine, peer) ==
  IF version = "v1"
  THEN [items |-> mine.items \union peer.items, disc |-> mine.disc]
  ELSE [items |-> mine.items \union peer.items,
        disc  |-> IF peer.disc > mine.disc THEN peer.disc ELSE mine.disc]
```

Delete the `IF version = "v1" ... THEN ... ELSE` so both versions take the second
branch — v1 now carries `disc` too:

```
MergeInto(version, mine, peer) ==
  [items |-> mine.items \union peer.items,
   disc  |-> IF peer.disc > mine.disc THEN peer.disc ELSE mine.disc]
```

Re-run TLC (we add `-deadlock` because the fixed spec terminates cleanly):

```bash
mise exec -- java -cp ../tla2tools.jar tlc2.TLC -deadlock -config DiscountCart.cfg DiscountCart.tla
```

This time the design holds:

```
Model checking completed. No error has been found.
```

We've proven the fix. Let's restore the spec to its bug-finding state so it keeps
teaching, and return to the repo root:

```bash
git checkout DiscountCart.tla
cd ..
```

## Step 5: Port the Property Down to the Code

A green model proves the *design*, not the *code*. Let's check the Elixir
implementation matches it. `lib/cart.ex` ships the forward-compatible `merge/2`,
and `test/cart_test.exs` encodes the same invariants as PropCheck properties:

```bash
mix test test/cart_test.exs
```

We should see them pass:

```
....
Result: 4 passed (3 properties, 1 test)
```

Each test traces straight back to the spec:

- the spec's `Consistent` → property *"a well-formed cart never has a negative total"*
- the spec's `MergeAgrees` → property *"both merge directions recover the same total"* (plus *"merge never drops a discount"* — the one with teeth)
- the TLC counterexample (State 3) → the regression test *"the trace state keeps its discount through a v1 merge"*

The property-based tests generate hundreds of random carts; the regression test
pins the exact state TLC found. Design proven, implementation checked, trace pinned.

## What We Built

We took one mixed-version question — *can v1 and v2 safely share this cart?* — all
the way down the pyramid:

- **Saw** two live nodes disagree (`mprocs`)
- **Proved** with TLC exactly when the disagreement becomes permanent data loss
- **Fixed** the design (carry the field) and re-proved it green
- **Pinned** the same invariants as PropCheck properties and an ExUnit regression

The lesson under all of it: **forward-compatibility of the data must ship before the
new behaviour.** v1 has to carry `discount` as a no-op pass-through one release
before any node populates it — which is exactly why the demo uses a plain map (the
field rides along) instead of a struct (which would drop it).

## Going Deeper

- `specs/DiscountCart.tla` — the spec's footer documents a second fix (gating the new behaviour) you can encode and re-check
- `.claude/tla-mixed-version-elixir/SKILL.md` — the full methodology, the Shape A vs B decision, and the Elixir→TLA+ mapping
- [`.claude/.../references/toolchain.md`](.claude/tla-mixed-version-elixir/references/toolchain.md) — reading TLC traces, bounding the state space, the deadlock-at-termination gotcha
- [learntla.com](https://learntla.com) — Hillel Wayne's guide, which the conventions here follow
- `CLAUDE.md` — the project's conventions and anti-patterns for this TLA+/Elixir combo
