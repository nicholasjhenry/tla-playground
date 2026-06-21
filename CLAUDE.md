# CLAUDE.md — TlaPlayground

Personal learning sandbox for **TLA+** (formal specification, taught at
[learntla.com](https://learntla.com)) applied to **distributed Elixir**. The
recurring question: *can two nodes running two different versions of an algorithm
share one data structure safely?* — the rolling-upgrade / `code_change/3` /
mixed-version problem. Work flows down a verification pyramid: **TLA+ proves the
design → PropCheck checks the implementation matches → ExUnit pins regressions.**

This is a sandbox, not a library. Optimize for learning clarity, not reuse.

## Stack

- **Elixir 1.20.1** on **Erlang/OTP 29.0.2**, pinned in `mise.toml` (run `mise install`).
- **PropCheck** — the property-testing library for the "port the verified design
  down to Elixir" step. Not yet a dependency; add to `mix.exs` `deps/0` when the
  first spec is ported.
- **ExUnit** — built in; `mix test`.
- **TLA+ toolchain** — Java (pinned `temurin-21` in `mise.toml`) plus
  `tla2tools.jar` (PlusCal translator + SANY parser + TLC model checker). The jar
  is *not* vendored (gitignored at repo root); download once from
  [tlaplus releases](https://github.com/tlaplus/tlaplus/releases). Run the
  toolchain through `mise exec -- java ...` so it uses the pinned JDK. VSCode TLA+
  extension or the Toolbox also work.

## Layout

- `lib/tla_playground/` — Elixir modules (versioned algorithm modules, e.g.
  `MyStruct.V1` / `MyStruct.V2`, plus their PropCheck stateful models).
- `specs/` — **TLA+ artifacts live here**, not in `lib/`. One `MODULE Foo` per
  `Foo.tla` (TLA+ requires the filename to match the module), its `Foo.cfg`
  beside it. PlusCal lives in a comment block and `pcal.trans` rewrites the
  `.tla` in place; TLC drops state-output dirs next to it — keep all that out of
  the Elixir tree so `mix compile` stays clean.
- `.claude/tla-mixed-version-elixir/` — **the domain skill.** Read it before
  doing any TLA+ work here. It carries the template, a worked example that finds
  a real bug, the Elixir→TLA+ mapping, the toolchain commands, and the
  spec→PropCheck/ExUnit bridge.

## Knowledge sources (read these, don't guess)

- `.claude/tla-mixed-version-elixir/SKILL.md` — the workflow and the
  mixed-version trap, end to end.
- `.claude/.../references/modeling-guide.md` — Shape A vs B, value mapping,
  invariant catalog, the test bridge.
- `.claude/.../references/toolchain.md` — install, exact run commands, `.cfg`
  format, reading error traces.
- [learntla.com](https://learntla.com) — Hillel Wayne's guide; the conventions
  here (PlusCal, `define` block, TLC) follow it.

## Related skills

These auto-load by description; named here as a nudge — for this TLA+/Elixir
combo, reach for them by name when relevant:

- `tla-mixed-version-elixir` — the project skill; the TLA+ workflow itself.
- `arc-distributed-systems` — CRDT convergence, merges, partitions: the Shape B domain.
- `elixir-otp` — `code_change/3` and GenServer state across upgrades, i.e. the mixed-version mechanism.
- `elixir-testing` — ExUnit / stateful-property patterns; where the PropCheck port lands.
- `modeling-algebraic` — make-illegal-states-unrepresentable, the design discipline TLA+ verifies.
- `modeling-state-transition` — state machines; TLA+ *is* a state-transition formalism (the `Next` relation).

## Running the toolchain

Translate PlusCal → TLA+, then model-check, from `specs/`:

```sh
java -cp tla2tools.jar pcal.trans MixedVersion.tla \
  && java -cp tla2tools.jar tlc2.TLC -deadlock -config MixedVersion.cfg MixedVersion.tla
```

`-deadlock` silences the benign "deadlock" report at the terminal state — these
specs terminate by design. **Drop it while a bug is still expected** (TLC reports
the real invariant violation first either way).

## Conventions & anti-patterns

- **Pick the shape before modeling.** Shape B (replicated + merged) is the usual
  rolling-upgrade case → start from `templates/MixedVersion.tla`. Shape A (one
  shared copy, concurrent mutation) → PlusCal processes + per-statement labels.
  They produce structurally different specs; choosing wrong wastes the spec.
- **Always model the merge in both directions** (V1←V2 *and* V2←V1).
  Compatibility is not symmetric — old code reading new state breaks even when
  new reading old is fine. The `MergeAgrees` invariant checks both on purpose.
- **Check structural and agreement invariants separately.** "Each replica is
  well-formed" (`Consistent`) and "the two replicas agree" (`MergeAgrees`) are
  different claims; mixed-version bugs live in the gap.
- **Keep the scope tiny** — 1–2 elements, exactly 2 nodes, small op budgets.
  Design bugs show up at small N; bigger constants rarely find new bugs and burn
  RAM fast.
- **Don't stop at a green TLC run.** A passing small model is strong evidence,
  not a proof, and proves the *design*, not the *code*. Port the same invariant
  to a PropCheck property and pin the error trace as an ExUnit test.
- **Forward-compat of the DATA ships before the new BEHAVIOUR** — teach old code
  to carry/merge a new field (no-op pass-through) one release before any node
  populates it.

## Maintenance

Personal sandbox, so light: bump the **Stack** section when `mise.toml` changes
or PropCheck lands in `mix.exs`; refresh **Conventions** if a TLA+ pattern here
keeps tripping the AI. The `.claude/tla-mixed-version-elixir` skill is the source
of truth for the methodology — defer to it over this summary.
