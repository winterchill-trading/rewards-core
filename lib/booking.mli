(** The ledger entry that pays a completed redemption. Pure: it builds the entry and the
    caller appends it to its journal.

    A cashback is an expense of the bank: it debits the rewards expense account in the
    payout currency and credits the customer's account. The idempotency key is
    [rewards:redemption:<id>], so booking the same redemption twice is a duplicate the
    journal recognises, and the reference is the redemption id. *)

open! Core

module Chart : sig
  type t = { rewards_expense : Money.Currency.t -> Ledger.Account_id.t }

  (** [expense:rewards/<currency>]. *)
  val default : t

  (** The expense accounts for these currencies, ready to open. *)
  val accounts : t -> currencies:Money.Currency.t list -> Ledger.Account.t list
end

(** [rewards:redemption:<id>]. *)
val idempotency_key : Redemption_id.t -> Ledger.Idempotency_key.t Or_error.t

(** The cash entry for a [Completed] redemption, effective at its creation time. Fails for
    a redemption in any other state. *)
val cashback
  :  Chart.t
  -> Redemption.t
  -> recorded_at:Time_ns.t
  -> Ledger.Entry.t Or_error.t

(** Applies entries to balances in order, as a journal would; use it to check an entry
    before appending it. *)
val apply : Ledger.Balances.t -> Ledger.Entry.t list -> Ledger.Balances.t Or_error.t
