# Modeling guide: distributed Elixir → TLA+ for mixed-version verification

How to turn "two nodes running two versions of an algorithm on a data structure"
into a spec TLC can check, and how to bring the result back into Elixir.

## Contents
- [Shape A vs Shape B](#shape-a-vs-shape-b)
- [Shape A snippet: one shared copy](#shape-a-snippet-one-shared-copy)
- [Elixir → TLA+ value mapping](#elixir--tla-value-mapping)
- [Modeling the two versions](#modeling-the-two-versions)
- [Forward vs backward compatibility](#forward-vs-backward-compatibility)
- [Invariant catalog](#invariant-catalog)
- [Modeling the network (only if you need multi-round)](#modeling-the-network)
- [From verified spec to Elixir tests](#from-verified-spec-to-elixir-tests)

## Shape A vs Shape B

The phrase "a data structure used on two nodes" hides two different systems.
Decide which you have; it changes the spec entirely.

| | Shape A — one shared copy | Shape B — replicated + merged |
|---|---|---|
| Storage | single copy both nodes reach | one copy per node |
| Examples in Elixir | a Postgres row via Ecto, one ETS table, a single GenServer reached by `:rpc`/`GenServer.call({name, node})` | CRDTs, `:pg`, `Phoenix.Tracker`, `Phoenix.PubSub` fan-out, gossiped GenServer state, the old/new state handed across `code_change/3` |
| What goes wrong | bad **interleavings**: lost updates, a guard that's stale by the time it acts | **divergence**: a merge that loses or resurrects data because one version misreads the other's shape |
| Model with | PlusCal `process`es + per-statement `label`s (atomic steps), check a per-state invariant | local ops + a `MergeInto` operator, check `MergeAgrees` (and a structural invariant) |
| Start from | the snippet below (bank-transfer pattern) | `templates/MixedVersion.tla` |

**The rolling-upgrade question is usually Shape B** — two nodes, two code
versions, reconciled state. Use the template. Reach for Shape A when there is
genuinely one shared copy being mutated concurrently.

## Shape A snippet: one shared copy

This is the learntla.com bank-transfer pattern, retargeted to "two versions
mutating one structure". Each `label` is one atomic step, so TLC explores every
interleaving of the two versions. Check a per-state invariant (here, a stand-in
`Safe`).

```tla
EXTENDS Integers, TLC
CONSTANTS Keys, Versions    \* Versions == {"v1", "v2"}

(* --algorithm shared
variables shared = [k \in Keys |-> 0];

define
  Safe == \A k \in Keys: shared[k] >= 0   \* replace with your real invariant
end define;

process worker \in Versions
variable k \in Keys, n \in 1..3;
begin
  Read:                                    \* v1 and v2 may read/transform
    n := shared[k];                        \*   the same key differently
  Write:                                   \* the gap between Read and Write
    shared[k] := DiffByVersion(self, n);   \*   is where interleavings bite
end process;
end algorithm; *)
```

The bug class here is the classic lost update / stale guard: `v1` reads, `v2`
reads, both write based on a value that's now wrong. The fine-grained labels are
what let TLC find it. (See https://learntla.com/core/concurrency.html.)

## Elixir → TLA+ value mapping

| Elixir | TLA+ | Notes |
|---|---|---|
| `%{k => v}` map | function `[k \in Keys \|-> v]` or function set `[Keys -> Vals]` | `[Keys -> Vals]` in `variables ... \in` enumerates *all* maps as initial states |
| `%Struct{a: x, b: y}` | record `[a \|-> x, b \|-> y]` | field access `r.a`; update `[r EXCEPT !.a = z]` |
| `MapSet` / set semantics | set `{1, 2, 3}`, `SUBSET S` | `\union`, `\intersect`, `\`, `\in`, `\subseteq`, `{x \in S : P(x)}` |
| `list` `[a, b]` | sequence `<<a, b>>` | `EXTENDS Sequences`; `Append`, `Head`, `Tail`, `Len`, `seq[i]` (1-indexed) |
| `{:ok, v}` / `{:error, e}` | tagged record `[tag \|-> "ok", val \|-> v]` | model "decisions as data": branch on `.tag` |
| atom / enum | model value (`v1`) or string (`"v1"`) | model values are distinct and unequal; good for ids |
| integer | `Integers`, ranges `1..10` | model money as cents; avoid Reals |
| `nil` / optional | a sentinel model value (`NULL`) or model presence in the domain | keep it explicit |
| GenServer state | the spec `variables` | the struct you keep in `handle_*` |
| `send` / `handle_info`, `:rpc`, PubSub | a `network` variable (set/bag of messages) + a deliver action | only needed for multi-round; see below |
| the two code versions | two `process`es / two action sets, branching on the version id | the heart of the model |
| a merge function (`Map.merge/3`, CRDT join) | the `MergeInto` operator | model what the code *does*, including dropped fields |

## Modeling the two versions

Encode the version in the node identity (`Versions == {"v1", "v2"}`) and make the
**behaviour branch on it**. The three places versions can differ:

- **`Observe(version, st)`** — they interpret the same stored bytes differently
  (the example: V1 ignores `removes`, V2 subtracts it).
- **`MergeInto(version, mine, peer)`** — they reconcile a peer's state
  differently (the example: V1 drops the `removes` field).
- **`LocalOp`** — they support different operations (the example: only V2 can
  remove).

A rolling upgrade means both run *simultaneously*, which is exactly two
processes with different action sets — no extra machinery needed. If only one
version exists at a time you don't have a mixed-version problem; the whole point
is the overlap window.

## Forward vs backward compatibility

Compatibility is **not symmetric**, so always model the merge in both directions:

- **Backward compat** (new reads old): V2 must do something sensible with a value
  V1 produced. Usually the easy direction.
- **Forward compat** (old reads new): V1 must not corrupt or lose a value V2
  produced. This is where mixed-version deploys break — old code meets a field or
  shape it predates. The example's bug is precisely a forward-compat failure.

`MergeAgrees` checks both because it computes `MergeInto("v1", v1, v2)` *and*
`MergeInto("v2", v2, v1)` and requires the observations to match. If you only
checked one direction you'd miss half the bugs.

A useful design rule the spec makes concrete: **forward-compatibility of the
DATA must ship before the new BEHAVIOUR.** Teach old code to carry/merge the new
field (a no-op pass-through) in one release; only enable the behaviour that
populates it once every node understands it.

## Invariant catalog

Pick the smallest set that captures "safe". Common ones for this problem:

- **`TypeOK`** — every variable stays in its expected domain. Cheap, always
  include it; catches modeling mistakes early.
- **Structural / well-formedness** (`Consistent`) — one replica is internally
  valid in isolation (e.g. `removes \subseteq adds`, no negative balance, no
  dangling reference). Check this *separately* from agreement.
- **Agreement / convergence** (`MergeAgrees`) — after a sync, both versions
  observe the same value. The defining safety property for Shape B.
- **No-loss** — nothing acknowledged is silently dropped: `Acked \subseteq
  Observe(...)`.
- **CRDT laws** (if you're rolling your own merge): idempotence
  `MergeInto(v, s, s) = s`, commutativity, associativity — encode as predicates
  over reachable states. Violating any of these is a convergence bug waiting to
  happen.
- **Shape A safety** — the domain rule that must survive interleavings (the
  bank's `NoOverdraft`).

## Modeling the network

Only reach for this if a single hypothetical sync (`MergeAgrees`) isn't enough and
you genuinely need multiple gossip rounds. Add a message bag and a deliver action:

```tla
variables network = {};   \* set of [to |-> node, st |-> state]
\* gossip:  network := network \union {[to |-> other, st |-> replica[self]]};
\* deliver: with m \in {mm \in network : mm.to = self} do
\*            replica[self] := MergeInto(self, replica[self], m.st);
\*            network := network \ {m};
\*          end with;
```

Convergence then becomes a *liveness* property (`<>[]Converged`) needing
`fair process` and care with fairness granularity — strictly harder than the
invariant-style `MergeAgrees`. **Prefer `MergeAgrees` first.** It already proves
"any reachable pair of states reconciles correctly", which is what you actually
care about, without temporal logic, fairness, or deadlock handling.

## From verified spec to Elixir tests

A green TLC run proves the *design*; it doesn't prove your *code* implements that
design. Carry it down the verification pyramid (TLC → PropCheck → ExUnit):

| TLA+ artifact | Elixir test artifact |
|---|---|
| `Next` actions (`LocalOp`, merge, deliver) | PropCheck/StreamData `commands` (one per operation) |
| process interleaving (Shape A) | `parallel_commands` — runs commands concurrently and checks linearizability, mirroring the labels TLC interleaved |
| a state invariant (`Consistent`, `MergeAgrees`) | the model's `invariant`/postcondition in the stateful test |
| the two versions | run the two real modules under test (`MyStruct.V1`, `MyStruct.V2`) and assert agreement |
| an error trace | a regression test in ExUnit pinning that exact scenario |

Concretely: the TLA+ `MergeAgrees` invariant becomes a PropCheck property that
generates random op histories on both version modules, merges, and asserts the
observed sets match — the same claim, now against real code. Shape A's
interleaving invariant becomes a `parallel_commands` model where PropCheck shuffles
concurrent operations and checks your invariant held. TLA+ tells you the design is
sound and hands you the cases worth generating; PropCheck checks the code matches;
ExUnit nails down the specific bugs you found so they never come back.
