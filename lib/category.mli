(** A merchant category that earn rules give a multiplier, such as [travel] or [groceries].

    Ids use the ledger's alphabet ([A-Z a-z 0-9 _ - . : / @ +]) and are at most 100
    characters, so they fit into ledger idempotency keys with the prefixes this library
    adds. *)

open! Core
include Ledger.Validated_id.S

(** 100. *)
val max_length : int
