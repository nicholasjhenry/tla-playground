---------------------------- MODULE ReplicatedSet ----------------------------
(***************************************************************************)
(* WORKED EXAMPLE: a replicated set used across a rolling upgrade.          *)
(*                                                                         *)
(* Two nodes hold the same logical set but run different versions of the    *)
(* algorithm that maintains it:                                             *)
(*                                                                         *)
(*   "old" runs V1 - an add-only set (a G-Set). It has no concept of        *)
(*          removal and ignores any tombstones it receives.                 *)
(*   "new" runs V2 - an add/remove set using tombstones (a 2P-Set).         *)
(*          Removing an element records a tombstone; an element counts as    *)
(*          present only if it was added and not tombstoned.                 *)
(*                                                                         *)
(* The safety question: can these two versions share the structure during   *)
(* the upgrade and still AGREE on the contents once they sync?              *)
(*                                                                         *)
(* Run it and TLC violates MergeAgrees: V2 removes an element, V1 receives  *)
(* the update, cannot interpret the tombstone, and the element RESURRECTS.   *)
(* The two nodes never agree again. Note that Consistent still PASSES -      *)
(* each replica is locally well-formed; the defect lives entirely in how    *)
(* one version handles the other's data. See the footer for the fix.        *)
(*                                                                         *)
(* Translate + check:                                                       *)
(*   java -cp tla2tools.jar pcal.trans ReplicatedSet.tla                     *)
(*   java -cp tla2tools.jar tlc2.TLC -config ReplicatedSet.cfg ReplicatedSet.tla *)
(***************************************************************************)
EXTENDS Integers, TLC

CONSTANTS Elems            \* possible elements; {"a"} is enough to find the bug

Nodes == {"old", "new"}    \* "old" runs V1, "new" runs V2

\* What each version reports as the current members of the set.
Observe(node, st) ==
  IF node = "old" THEN st.adds            \* V1: no notion of removal
                  ELSE st.adds \ st.removes \* V2: subtract tombstones

\* How `node`'s version folds a peer's state into a copy of its own.
\* V1 ("old") merges the adds but DROPS the tombstones it cannot interpret.
MergeInto(node, mine, peer) ==
  IF node = "old"
  THEN [adds    |-> mine.adds \union peer.adds,
        removes |-> mine.removes]              \* tombstones silently dropped
  ELSE [adds    |-> mine.adds \union peer.adds,
        removes |-> mine.removes \union peer.removes]

(* --algorithm replicated_set
variables
  replica = [n \in Nodes |-> [adds |-> {}, removes |-> {}]];
  opsLeft = [n \in Nodes |-> 2];      \* small bound; the bug shows quickly

define
  TypeOK ==
    \A n \in Nodes:
      /\ replica[n].adds \subseteq Elems
      /\ replica[n].removes \subseteq Elems

  \* Each replica is locally well-formed: a tombstone only marks an added
  \* element. This stays TRUE the whole time - the structure is never corrupt.
  Consistent ==
    \A n \in Nodes: replica[n].removes \subseteq replica[n].adds

  \* The real question: if the two nodes sync right now, do both versions end
  \* up observing the SAME set? Checked in every reachable state and in both
  \* merge directions, so it must hold for every possible pair of local
  \* histories.
  MergeAgrees ==
    LET syncedOld == MergeInto("old", replica["old"], replica["new"])
        syncedNew == MergeInto("new", replica["new"], replica["old"])
    IN  Observe("old", syncedOld) = Observe("new", syncedNew)
end define;

process node \in Nodes
begin
  Step:
    while opsLeft[self] > 0 do
      opsLeft[self] := opsLeft[self] - 1;
      either
        \* both versions can add an element locally
        with e \in Elems do
          replica[self].adds := replica[self].adds \union {e};
        end with;
      or
        \* only V2 ("new") can remove, and only something it has added
        await self = "new" /\ replica[self].adds # {};
        with e \in replica[self].adds do
          replica[self].removes := replica[self].removes \union {e};
        end with;
      end either;
    end while;
end process;
end algorithm; *)
=============================================================================

(***************************************************************************)
(* THE FIX (re-verify after applying)                                       *)
(*                                                                         *)
(* The bug is that V1 cannot represent "this element was removed", so a      *)
(* tombstone produced by V2 is lost on merge and the element comes back.    *)
(* Real options, each of which you can re-encode and re-check here:          *)
(*                                                                         *)
(*  - Gate the new behaviour. Do not let V2 issue removals until EVERY node  *)
(*    understands tombstones (a two-phase / expand-then-migrate rollout).    *)
(*    Model this by adding `await AllNodesAreV2` before the remove branch;   *)
(*    MergeAgrees then holds.                                                *)
(*                                                                         *)
(*  - Make the structure forward-compatible first. Ship a V1.5 that carries  *)
(*    and merges the `removes` field even though it doesn't act on it, so no  *)
(*    tombstone is ever dropped. Model this by giving "old" the same         *)
(*    MergeInto branch as "new"; MergeAgrees then holds because Observe for  *)
(*    "old" would also need to subtract removes - which is exactly the point:*)
(*    forward-compatibility of the DATA must precede the new BEHAVIOUR.      *)
(*                                                                         *)
(* Re-run TLC after the change. When it passes it will report a "deadlock"   *)
(* at the terminal state (just normal termination) - add the -deadlock flag  *)
(* to silence that.                                                          *)
(***************************************************************************)
