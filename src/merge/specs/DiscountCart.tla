---------------------------- MODULE DiscountCart ----------------------------
(***************************************************************************)
(* WORKED SPEC for the lib/ demo: a cart migrated across a rolling upgrade. *)
(*                                                                         *)
(* The cart is `%{items, discount}`. v2 introduced the `discount` field;    *)
(* v1 was written before it existed.                                        *)
(*                                                                         *)
(*   v1 (old): adds items. Has NO concept of `discount`. When it folds a     *)
(*             peer's cart into its own it keeps only the fields it knows -   *)
(*             so a discount produced by v2 is DROPPED on write-back.        *)
(*   v2 (new): adds items AND can set a discount.                            *)
(*                                                                         *)
(* A subtlety worth stating: v1 and v2 computing different *totals* during   *)
(* the upgrade is NOT the bug - that is the feature rolling out, and a v1     *)
(* node briefly showing an undiscounted total is benign. The catastrophic    *)
(* bug is DATA LOSS: if v1 drops the discount when it handles the cart, the   *)
(* discount is gone permanently - even after every node is on v2. So the     *)
(* property we check is whether the discount SURVIVES a round-trip through    *)
(* v1, not whether the two totals match.                                     *)
(*                                                                         *)
(* Run it and TLC violates MergeAgrees: v2 sets a discount, the cart passes  *)
(* through v1, v1 cannot carry the field, and the discount vanishes. Note    *)
(* Consistent still PASSES - each replica stays well-formed; the defect      *)
(* lives entirely in how v1 handles v2's data. See the footer for the fix.   *)
(*                                                                         *)
(* Translate + check:                                                       *)
(*   java -cp tla2tools.jar pcal.trans DiscountCart.tla                       *)
(*   java -cp tla2tools.jar tlc2.TLC -config DiscountCart.cfg DiscountCart.tla *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, TLC

CONSTANTS Items            \* possible items; {"a"} is enough to find the bug

Versions == {"v1", "v2"}   \* one node per version

\* The discounted total the stored data SUPPORTS. This is the cart's true
\* meaning (v2 is the source of truth for what a cart is worth). Both nodes
\* should recover the SAME total after a sync - the discount must survive the
\* trip. Version-agnostic on purpose: the asymmetry that breaks things lives in
\* the merge below, not in how the total is read.
Observe(version, st) == Cardinality(st.items) - st.disc

\* How `version` folds a peer's cart into a copy of its own.
\* v1 keeps only its OWN discount (always 0) - it has no field to carry the
\* peer's, so v2's discount is silently dropped. v2 carries the larger discount.
MergeInto(version, mine, peer) ==
  IF version = "v1"
  THEN [items |-> mine.items \union peer.items, disc |-> mine.disc]
  ELSE [items |-> mine.items \union peer.items,
        disc  |-> IF peer.disc > mine.disc THEN peer.disc ELSE mine.disc]

(* --algorithm discount_cart
variables
  \* One replica per version. A cart is items (a set) + a discount.
  replica = [v \in Versions |-> [items |-> {}, disc |-> 0]];
  opsLeft = [v \in Versions |-> 2];     \* small bound; the bug shows quickly

define
  TypeOK ==
    \A v \in Versions:
      /\ replica[v].items \subseteq Items
      /\ replica[v].disc \in 0..Cardinality(Items)

  \* Each replica is locally well-formed: the discount never exceeds what the
  \* items can cover, so a total is never negative. This stays TRUE throughout -
  \* the structure is never corrupt, yet the design is still broken.
  Consistent ==
    \A v \in Versions:
      /\ replica[v].disc >= 0
      /\ replica[v].disc <= Cardinality(replica[v].items)

  \* If the two nodes sync right now, do both recover the SAME discounted total?
  \* Checked in every reachable state and in BOTH merge directions, so it must
  \* hold for every pair of local histories. Fails the moment v1 drops a discount.
  MergeAgrees ==
    LET s1 == MergeInto("v1", replica["v1"], replica["v2"])
        s2 == MergeInto("v2", replica["v2"], replica["v1"])
    IN  Observe("v1", s1) = Observe("v2", s2)
end define;

process node \in Versions
begin
  Step:
    while opsLeft[self] > 0 do
      opsLeft[self] := opsLeft[self] - 1;
      either
        \* both versions can add an item locally
        with i \in Items do
          replica[self].items := replica[self].items \union {i};
        end with;
      or
        \* only v2 can set a discount, and only one the items can cover
        await self = "v2" /\ replica[self].items # {}
              /\ replica[self].disc < Cardinality(replica[self].items);
        replica[self].disc := replica[self].disc + 1;
      end either;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "6c931923" /\ chksum(tla) = "7d263344")
VARIABLES pc, replica, opsLeft

(* define statement *)
TypeOK ==
  \A v \in Versions:
    /\ replica[v].items \subseteq Items
    /\ replica[v].disc \in 0..Cardinality(Items)




Consistent ==
  \A v \in Versions:
    /\ replica[v].disc >= 0
    /\ replica[v].disc <= Cardinality(replica[v].items)




MergeAgrees ==
  LET s1 == MergeInto("v1", replica["v1"], replica["v2"])
      s2 == MergeInto("v2", replica["v2"], replica["v1"])
  IN  Observe("v1", s1) = Observe("v2", s2)


vars == << pc, replica, opsLeft >>

ProcSet == (Versions)

Init == (* Global variables *)
        /\ replica = [v \in Versions |-> [items |-> {}, disc |-> 0]]
        /\ opsLeft = [v \in Versions |-> 2]
        /\ pc = [self \in ProcSet |-> "Step"]

Step(self) == /\ pc[self] = "Step"
              /\ IF opsLeft[self] > 0
                    THEN /\ opsLeft' = [opsLeft EXCEPT ![self] = opsLeft[self] - 1]
                         /\ \/ /\ \E i \in Items:
                                    replica' = [replica EXCEPT ![self].items = replica[self].items \union {i}]
                            \/ /\ self = "v2" /\ replica[self].items # {}
                                  /\ replica[self].disc < Cardinality(replica[self].items)
                               /\ replica' = [replica EXCEPT ![self].disc = replica[self].disc + 1]
                         /\ pc' = [pc EXCEPT ![self] = "Step"]
                    ELSE /\ pc' = [pc EXCEPT ![self] = "Done"]
                         /\ UNCHANGED << replica, opsLeft >>

node(self) == Step(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == (\E self \in Versions: node(self))
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 
=============================================================================

(***************************************************************************)
(* THE FIX (re-verify after applying)                                       *)
(*                                                                         *)
(* The bug is that v1 has no field to carry a discount, so a discount        *)
(* produced by v2 is lost the moment v1 folds the cart in. Two real options, *)
(* each re-encodable and re-checkable here:                                  *)
(*                                                                         *)
(*  - Gate the new behaviour. Do not let v2 set a discount until EVERY node   *)
(*    can carry the field (expand-then-migrate). Model by adding              *)
(*    `await AllNodesCarryDiscount` before the discount branch.               *)
(*                                                                         *)
(*  - Make the DATA forward-compatible first (the convention in CLAUDE.md):   *)
(*    ship a v1.5 that carries and merges `disc` as a no-op pass-through even  *)
(*    though it never acts on it, so no discount is ever dropped. Model by     *)
(*    giving "v1" the SAME MergeInto branch as "v2". MergeAgrees then holds -  *)
(*    forward-compat of the DATA must ship before the new BEHAVIOUR. This is   *)
(*    exactly the map-vs-struct pass-through in lib/node_b.ex: the cart is a   *)
(*    plain map, so the extra field rides along harmlessly instead of being    *)
(*    dropped by a struct that doesn't declare it.                            *)
(*                                                                         *)
(* Re-run TLC after the change. When it passes it reports a "deadlock" at the *)
(* terminal state (normal termination) - add -deadlock to silence it.         *)
(***************************************************************************)
