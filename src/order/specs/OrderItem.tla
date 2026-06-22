----------------------------- MODULE OrderItem -----------------------------
(***************************************************************************)
(* WORKED SPEC for the lib/ demo: an order line item migrated across a      *)
(* version boundary, single-writer, ownership handed V2 -> V1 -> V2.        *)
(*                                                                         *)
(* The item evolved from a bare price scalar to a map [price, qty]. v2      *)
(* creates it with a real qty; ownership then migrates to v1 and back.       *)
(*                                                                         *)
(*   v1 (old): edits the PRICE. It predates qty. The BROKEN v1 REBUILDS the  *)
(*             item from the fields it knows, resetting qty to 1 - so a qty   *)
(*             set by v2 is DROPPED the moment v1 touches the item.           *)
(*   v2 (new): creates the item with price AND qty, and reads qty back.       *)
(*                                                                         *)
(* A subtlety worth stating: while v1 owns the item it computes a subtotal    *)
(* that ignores qty (assumes 1). A briefly-wrong subtotal on the old node is  *)
(* NOT the bug - that is the feature rolling out. The catastrophic bug is     *)
(* DATA LOSS: if v1 resets qty when it edits the price, the quantity is gone  *)
(* permanently - even after every node is on v2. So the property we check is  *)
(* whether qty SURVIVES the round trip through v1, not whether the two        *)
(* subtotals match.                                                          *)
(*                                                                         *)
(* Why no concurrency? This is a single-writer baton pass: exactly one node   *)
(* owns the item at a time. Modelling it with parallel processes would test   *)
(* a race the design forbids. The honest model is the sequential hand-off     *)
(* below; the nondeterminism that matters is the qty v2 chose at creation.    *)
(*                                                                         *)
(* Run it and TLC violates QtySurvives: v2 creates qty 2, v1 edits the price  *)
(* and rebuilds the item, qty drops to 1. Note Consistent still PASSES - the  *)
(* item is always a well-formed map; the defect is the lost value, not a      *)
(* broken shape. See the footer for the fix.                                  *)
(*                                                                         *)
(* Translate + check:                                                       *)
(*   java -cp tla2tools.jar pcal.trans OrderItem.tla                          *)
(*   java -cp tla2tools.jar tlc2.TLC -config OrderItem.cfg OrderItem.tla       *)
(***************************************************************************)
EXTENDS Integers, TLC

CONSTANTS MaxQty           \* largest qty v2 may create; 2 is enough to find the bug

\* How `version` edits the item's price. v1 has no slot for qty in the
\* representation it knows, so the broken edit REBUILDS the item and resets qty
\* to 1 - silently dropping v2's quantity. v2 reaches in and carries qty along.
EditPrice(version, item, newPrice) ==
  IF version = "v1"
  THEN [price |-> newPrice, qty |-> 1]
  ELSE [item EXCEPT !.price = newPrice]

(* --algorithm order_item
variables
  \* qty v2 chose at creation, then the item it created, then the live owner.
  intendedQty \in 1..MaxQty;
  item = [price |-> 1, qty |-> intendedQty];
  owner = "v2";

define
  TypeOK ==
    /\ item.price \in 0..9
    /\ item.qty \in 1..MaxQty
    /\ owner \in {"v1", "v2"}

  \* The item is always a well-formed map - the carrier was promoted, so the
  \* shape never breaks. This stays TRUE throughout, yet the design is broken:
  \* a structural check cannot see the lost quantity.
  Consistent == item.qty >= 1 /\ item.price >= 0

  \* The qty v2 reads back must equal the qty it created - the field must
  \* survive the trip through v1. Fails the instant a v1 edit rebuilds the item.
  QtySurvives == owner = "v2" => item.qty = intendedQty
end define;

begin
  HandToV1:
    owner := "v1";
  V1EditPrice:
    \* v1 owns the item and changes its price.
    item := EditPrice("v1", item, 9);
  HandBackToV2:
    owner := "v2";
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "3a0700e7" /\ chksum(tla) = "ef88511b")
VARIABLES pc, intendedQty, item, owner

(* define statement *)
TypeOK ==
  /\ item.price \in 0..9
  /\ item.qty \in 1..MaxQty
  /\ owner \in {"v1", "v2"}




Consistent == item.qty >= 1 /\ item.price >= 0



QtySurvives == owner = "v2" => item.qty = intendedQty


vars == << pc, intendedQty, item, owner >>

Init == (* Global variables *)
        /\ intendedQty \in 1..MaxQty
        /\ item = [price |-> 1, qty |-> intendedQty]
        /\ owner = "v2"
        /\ pc = "HandToV1"

HandToV1 == /\ pc = "HandToV1"
            /\ owner' = "v1"
            /\ pc' = "V1EditPrice"
            /\ UNCHANGED << intendedQty, item >>

V1EditPrice == /\ pc = "V1EditPrice"
               /\ item' = EditPrice("v1", item, 9)
               /\ pc' = "HandBackToV2"
               /\ UNCHANGED << intendedQty, owner >>

HandBackToV2 == /\ pc = "HandBackToV2"
                /\ owner' = "v2"
                /\ pc' = "Done"
                /\ UNCHANGED << intendedQty, item >>

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == pc = "Done" /\ UNCHANGED vars

Next == HandToV1 \/ V1EditPrice \/ HandBackToV2
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(pc = "Done")

\* END TRANSLATION 
=============================================================================

(***************************************************************************)
(* THE FIX (re-verify after applying)                                       *)
(*                                                                         *)
(* The bug is that v1 REBUILDS the item from the fields it knows, so qty -    *)
(* a fact it predates - is dropped. Two real options, each re-checkable here: *)
(*                                                                         *)
(*  - Make the carrier forward-compatible first (the convention in CLAUDE.md *)
(*    and the lib/ default). v1 must reach in for price and CARRY the rest,   *)
(*    not rebuild. Model by giving "v1" the SAME EditPrice branch as "v2":    *)
(*      EditPrice(version, item, newPrice) == [item EXCEPT !.price = newPrice] *)
(*    QtySurvives then holds - tolerant code carries, it does not comprehend. *)
(*    This is exactly the one line in `Order.set_price/3`: `%{item | price:    *)
(*    price}` (carry) versus `%{price: price, qty: 1}` (rebuild, clobbers qty).*)
(*                                                                         *)
(*  - Gate the new behaviour. Do not let v2 create a qty > 1 until EVERY node  *)
(*    is qty-aware (the capability floor in `Order.Ownership`). Model by       *)
(*    setting `intendedQty = 1` (or CONSTANT MaxQty = 1): no qty != 1 exists   *)
(*    to lose, so QtySurvives holds by construction.                          *)
(*                                                                         *)
(* Re-run TLC after the change. When it passes it reports a "deadlock" at the *)
(* terminal state (normal termination) - add -deadlock to silence it.         *)
(***************************************************************************)
