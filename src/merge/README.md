# merge — a mixed-version cart bug

One example in the [TlaPlayground](../../CLAUDE.md) sandbox. It walks the
project's verification pyramid end to end on a single concrete bug:

> **TLA+ proves the design → PropCheck checks the implementation matches → ExUnit pins the regression.**

The scenario: during a rolling upgrade, two Elixir nodes run two versions of a
shopping-cart algorithm against the same data. The cart is a plain map,
`%{items: [10, 20, 30], discount: 5}`; **v2** introduced the `discount` field and
**v1** predates it. We watch the nodes disagree, use **TLC** to find the exact
sequence where a discount is silently lost, fix the design, and lock the fix in
with tests.

## Start here

Read **[GUIDE.md](GUIDE.md)** — the worked tutorial, ~15 minutes. It covers
installing the toolchain, reproducing the disagreement across two nodes, model
checking the spec, the fix, and the PropCheck/ExUnit port.

## Layout

- `lib/` — `Cart` plus `NodeA` / `NodeB` (the two versions) and the PropCheck model.
- `specs/` — `DiscountCart.tla` / `.cfg`, the TLA+ spec of the merge.
- `test/` — ExUnit, including the pinned error trace.
- `notebooks/cart.livemd` — the cart explored as a Livebook.
- `mprocs.yaml` — runs the two nodes side by side.

## Quick commands

From this directory (`src/merge/`):

```sh
mise install                      # pinned Elixir / Erlang / Java
mix deps.get && mix test          # the Elixir side of the pyramid

# fetch the model checker once (gitignored), then check the spec:
curl -sL -o tla2tools.jar \
  https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
cd specs
mise exec -- java -cp ../tla2tools.jar pcal.trans DiscountCart.tla \
  && mise exec -- java -cp ../tla2tools.jar tlc2.TLC -deadlock -config DiscountCart.cfg DiscountCart.tla
```
