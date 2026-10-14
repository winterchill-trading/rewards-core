(** A points statement for one customer over a period [from <= at < until]: the opening
    balance, every entry in the period with the balance after it, totals per kind and
    the closing balance. [opening + sum of totals = closing] always holds ({!check}). *)

open! Core

module Line : sig
  type t =
    { entry : Entry.t
    ; balance_after : int
    }
  [@@deriving sexp_of]
end

type t =
  { user : User_id.t
  ; from : Time_ns.Alternate_sexp.t
  ; until : Time_ns.Alternate_sexp.t
  ; opening : int (** the sum of entries before [from] *)
  ; lines : Line.t list (** by time, then sequence number *)
  ; totals : (Kind.t * int) list (** every kind, in {!Kind.all} order, signed *)
  ; closing : int
  }
[@@deriving sexp_of]

(** The statement of [entries] (one customer's, in any order). Fails when [until] is
    before [from] or an entry belongs to another customer. *)
val create
  :  user:User_id.t
  -> from:Time_ns.t
  -> until:Time_ns.t
  -> Entry.t list
  -> t Or_error.t

(** Checks the running balances and [opening + totals = closing]. *)
val check : t -> unit Or_error.t
