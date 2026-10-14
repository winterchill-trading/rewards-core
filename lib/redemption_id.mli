(** A redemption, chosen by the caller so a retried request books once (an idempotency key
    or a UUID).

    Ids use the ledger's alphabet ([A-Z a-z 0-9 _ - . : / @ +]) and are at most 100
    characters, so they fit into ledger idempotency keys with the prefixes this library
    adds. *)

open! Core
include Ledger.Validated_id.S

(** 100. *)
val max_length : int
