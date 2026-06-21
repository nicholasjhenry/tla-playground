----------------------------- MODULE MixedVersion -----------------------------
(***************************************************************************)
(* Skeleton for verifying that ONE data structure stays safe when two      *)
(* nodes run two DIFFERENT versions of the algorithm on it (the rolling-    *)
(* upgrade / hot-code-change / mixed-version case).                          *)
(*                                                                         *)
(* Fill in the four TODOs, then translate the PlusCal and model check.      *)
(* Conventions follow https://learntla.com .                                *)
(*                                                                         *)
(*   1. Rename the module + file together (MODULE Foo must live in Foo.tla).*)
(*   2. java -cp tla2tools.jar pcal.trans MixedVersion.tla                   *)
(*   3. java -cp tla2tools.jar tlc2.TLC -deadlock -config MixedVersion.cfg \  *)
(*        MixedVersion.tla   (-deadlock: this skeleton terminates by design)  *)
(***************************************************************************)
EXTENDS Integers, TLC

CONSTANTS Values            \* the domain your structure ranges over; keep tiny

Versions == {"v1", "v2"}    \* the two algorithm versions, one per node

\* === TODO 1 - OBSERVE =====================================================
\* The structure's *public meaning* under each version: what an observer of a
\* node running this version would say the current value is. Branch on the
\* version if the two versions interpret the same bytes differently.
Observe(version, st) == st.data

\* === TODO 2 - MERGE =======================================================
\* How `version` folds a peer's state into a copy of its own. THIS is where
\* mixed-version bugs live: model what the OLD version actually does with data
\* the NEW version produced (e.g. drops a field it doesn't understand), not
\* what you wish it did. Branch on `version`.
MergeInto(version, mine, peer) ==
  [data |-> mine.data \union peer.data]

(* --algorithm mixed_version
variables
  \* === TODO 3a - STRUCTURE SHAPE =========================================
  \* One replica per version. Make the record match your real struct.
  replica = [v \in Versions |-> [data |-> {}]];
  opsLeft = [v \in Versions |-> 3];    \* bounds local ops; keep small

define
  \* === TODO 3b - STRUCTURAL INVARIANT ====================================
  \* Must hold on EVERY node in EVERY state (well-formedness of one replica).
  Consistent == TRUE

  \* Agreement goal (already wired up): if the two nodes sync right now, do
  \* both versions end up observing the SAME value? Checked in every reachable
  \* state, so it must hold no matter what local history each node went through,
  \* and in BOTH merge directions.
  MergeAgrees ==
    LET s1 == MergeInto("v1", replica["v1"], replica["v2"])
        s2 == MergeInto("v2", replica["v2"], replica["v1"])
    IN  Observe("v1", s1) = Observe("v2", s2)
end define;

\* === TODO 4 - LOCAL OPERATION =============================================
\* A local mutation for `me`'s version. Give v1 and v2 different behaviour by
\* branching on `me` (with an `either`/`if`) — that asymmetry is the point.
macro LocalOp(me) begin
  with x \in Values do
    replica[me].data := replica[me].data \union {x};
  end with;
end macro;

process node \in Versions
begin
  Step:
    while opsLeft[self] > 0 do
      opsLeft[self] := opsLeft[self] - 1;
      LocalOp(self);
    end while;
end process;
end algorithm; *)
===============================================================================
