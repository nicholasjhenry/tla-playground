# TLA+ toolchain reference

Everything you need to translate PlusCal and run the TLC model checker on the
specs in this skill.

## Contents
- [Install](#install)
- [The two-step run (translate, then check)](#the-two-step-run)
- [Editor options](#editor-options)
- [The .cfg file format](#the-cfg-file-format)
- [Bounding the state space](#bounding-the-state-space)
- [Reading an error trace](#reading-an-error-trace)
- [The deadlock-at-termination gotcha](#the-deadlock-at-termination-gotcha)
- [Apalache, for larger scopes](#apalache-for-larger-scopes)

## Install

You need **Java (JDK 11+)** and **`tla2tools.jar`**, which bundles the PlusCal
translator, the SANY parser, and the TLC model checker.

- Download the latest `tla2tools.jar` from the releases page:
  https://github.com/tlaplus/tlaplus/releases
- The guide this skill follows (https://learntla.com/core/setup.html) walks
  through the GUI Toolbox, which also ships `tla2tools.jar` inside it.

Quick sanity check:
```
java -cp tla2tools.jar tlc2.TLC -h
```

## The two-step run

PlusCal lives inside a comment block; you translate it into TLA+ first, then
check. The translator **rewrites the `.tla` file in place**, inserting the
generated TLA+ between `\* BEGIN TRANSLATION` and `\* END TRANSLATION` markers.

```
# 1. translate PlusCal -> TLA+ (edits the file in place)
java -cp tla2tools.jar pcal.trans MixedVersion.tla

# 2. model check against the config
java -cp tla2tools.jar tlc2.TLC -config MixedVersion.cfg MixedVersion.tla
```

Chain them while iterating:
```
java -cp tla2tools.jar pcal.trans MixedVersion.tla \
  && java -cp tla2tools.jar tlc2.TLC -config MixedVersion.cfg MixedVersion.tla
```

If TLC can't find the config it defaults to `<ModuleName>.cfg`, so `-config` is
optional when they share a name — but pass it explicitly to avoid surprises.

Parse-only check (fast feedback on syntax, after translating):
```
java -cp tla2tools.jar tla2sany.SANY MixedVersion.tla
```
PlusCal syntax errors are reported by `pcal.trans` itself; SANY then validates the
generated TLA+.

## Editor options

- **VSCode TLA+ extension** (`tlaplus.vscode-ide`): translate-on-save and
  "TLA+: Check model with TLC" from the command palette. Best for fast local
  iteration; reads the same `.tla`/`.cfg` files.
- **TLA+ Toolbox** (the GUI in learntla.com's setup chapter): `File > Translate
  PlusCal Algorithm` (Ctrl/Cmd+T), then `TLC Model Checker > New Model`, add your
  invariants/properties in the model page, run with F11. Good for learning and for
  clicking through error traces.

## The .cfg file format

The config tells TLC what to run. Common directives:

- `SPECIFICATION Spec` — for PlusCal output, always this (the translator
  generates a temporal formula named `Spec`). Use `INIT Init` + `NEXT Next`
  instead only for hand-written TLA+ without a `Spec` formula.
- `CONSTANTS Foo = {"a", "b"}` — bind each `CONSTANT`. Bare identifiers like `a`
  become *model values* (distinct, unequal atoms); quoted strings are strings.
- `INVARIANT Name` — a state predicate checked on every reachable state. List
  several with one `INVARIANT` line each.
- `PROPERTY Name` — a temporal property (e.g. `<>[]Converged`). Needs fairness in
  the spec to be meaningful; the invariant-style `MergeAgrees` in this skill
  avoids temporal logic on purpose.
- `CONSTRAINT Name` — a state predicate; TLC stops exploring past states where it
  is false. Use it to bound counters and keep the model finite.
- `SYMMETRY Perms` — declare interchangeable model values symmetric to shrink the
  state space (define `Perms == Permutations(SomeSet)` with `EXTENDS TLC`).
- `VIEW Name` — collapse states that differ only in fields you don't care about.

## Bounding the state space

Design bugs almost always appear at tiny scope, and TLC explores *every* state,
so cost grows fast. Keep it small deliberately:

- 1–2 elements in the value domain, exactly 2 nodes (the two versions).
- Small `opsLeft` budgets (2–4). Raise only if a bug needs a longer history.
- Add a `CONSTRAINT` on any counter that could grow without bound.
- Use `SYMMETRY` when element identities are interchangeable.

A passing small model is strong evidence, not a proof: an error needing larger
parameters can still hide. But in practice "works at 3, works at 300" holds
remarkably often.

## Reading an error trace

When an invariant or property fails, TLC prints the **shortest behavior** that
reaches the violation: an ordered list of states from the initial state to the
bad one. Each state shows every variable's value, and the action/label that
produced it. To debug:

1. Look at the **final state** — that's where the invariant is false.
2. Walk **backwards** to see the exact sequence of operations (which version did
   what, in which order) that set it up.
3. Translate that state's variables back to your Elixir structs/messages. The
   trace *is* the concrete failing scenario — often one you'd never have written
   a test for.
4. Change the *design* (the merge, the wire format, a rollout gate), re-translate,
   re-check. Repeat until clean.

## The deadlock-at-termination gotcha

The specs here terminate (every process reaches "Done"). When nothing is left to
do, TLC sees a state with no successors and, by default, reports it as a
**deadlock**. For a terminating algorithm that's expected — it's the system going
idle, not a bug. Two things follow:

- While a real invariant is still violated, TLC reports *that* first (invariants
  are checked before successors), so the buggy example shows the `MergeAgrees`
  violation, not a deadlock.
- Once you've fixed the design and expect a clean run, silence the false alarm
  with the `-deadlock` flag (it tells TLC not to treat terminal states as
  errors), or uncheck "Deadlock" on the Toolbox model page:
  ```
  java -cp tla2tools.jar tlc2.TLC -deadlock -config Spec.cfg Spec.tla
  ```

## Apalache, for larger scopes

[Apalache](https://apalache.informal.systems/) is an alternative, *symbolic*
model checker for TLA+ (SMT-based). With type annotations it can check larger or
unbounded scopes that overwhelm TLC's explicit enumeration. Reasonable next step
once the TLC model passes at small N and you want more assurance — but TLC, as
taught on learntla.com, is the right default to start.
