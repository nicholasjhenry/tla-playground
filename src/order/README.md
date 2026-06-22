# order — a schema-evolution bug across a version boundary

One example in the [TlaPlayground](../../CLAUDE.md) sandbox. It walks the
project's verification pyramid end to end on a single concrete bug:

> **TLA+ proves the design → PropCheck checks the implementation matches → ExUnit pins the regression.**

The scenario: an in-memory, single-writer order whose *ownership* migrates
between nodes on different code versions (**V2 → V1 → V2**). A line item evolves
from a bare scalar `[10]` (price only, qty implicitly 1) to a map
`[%{price: 10, qty: 2}]`. **V2** introduced the `qty` field; **V1** predates it.
Created on V2, edited by V1, handed back — does `qty` survive? We watch the nodes
disagree, use **TLC** to find the exact round trip where the quantity is silently
lost, fix the design, and lock the fix in with tests.

## Start here

Read **[GUIDE.md](GUIDE.md)** — the worked tutorial, ~15 minutes. It covers
installing the toolchain, reproducing the disagreement across two nodes, model
checking the spec, the fix, and the PropCheck/ExUnit port.

## Layout

- `lib/` — `Order` (the data structure, both algorithms) plus `Order.Schema`
  (the carrier rule), `Order.Ownership` (the capability floor), and `NodeA` /
  `NodeB` (the two versions).
- `specs/` — `OrderItem.tla` / `.cfg`, the TLA+ spec of the round trip.
- `test/` — ExUnit, including the pinned error trace.
- `notebooks/order.livemd` — the order explored as a Livebook.
- `mprocs.yaml` — runs the two nodes side by side, baton-passing the order.

## The one-line lesson

A scalar has no room for a new fact. **Promote the carrier** — make the element
a map both versions can hold — *before* the field is given meaning. Tolerant
code carries; it does not comprehend: `%{item | price: price}` (carry), never
`%{price: price, qty: 1}` (rebuild, clobbers `qty`). The real safety gate is a
*code* invariant — *every owner ≥ a capability floor* — not the unprovable data
claim *is everything migrated?*

## Quick commands

From this directory (`src/order/`):

```sh
mise install                      # pinned Elixir / Erlang / Java
mix deps.get && mix test          # the Elixir side of the pyramid

# fetch the model checker once (gitignored), then check the spec:
curl -sL -o tla2tools.jar \
  https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
cd specs
mise exec -- java -cp ../tla2tools.jar pcal.trans OrderItem.tla \
  && mise exec -- java -cp ../tla2tools.jar tlc2.TLC -deadlock -config OrderItem.cfg OrderItem.tla
```
