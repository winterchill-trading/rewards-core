(** The id of the event that caused an entry: a card transaction, a refund, an adjustment request.

    Ids use the ledger's alphabet ([A-Z a-z 0-9 _ - . : / @ +]) and are at most 100
    characters, so they fit into ledger idempotency keys with the prefixes this library
    adds. *)

open! Core
include Ledger.Validated_id.S

(** 100. *)
val max_length : int
