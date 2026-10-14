(** The programme's operations over a {!Store.S}: each one reads the customer's ledger,
    decides with the pure modules ({!Earn_rules}, {!Cashback}, {!Expiry}), and appends
    at most one entry. A decision made against a ledger that changed before the append
    is made again (up to a few times, then [Contended]).

    Every operation is idempotent by its cause: calling it again for the same event
    returns [Already_booked] with the first entry, and a call that reuses an event id
    with different content is refused with [Cause_conflict]. A zero-point result (a
    category that earns nothing, nothing left to expire) is [Nothing_to_book] and
    stores nothing; refunds are the exception (see [refund_purchase]).

    The engine never touches the money ledger: [redeem] returns the redemption, and the
    caller books {!Booking.cashback} into its journal once the redemption is
    [Completed]. *)

open! Core

module Outcome : sig
  type t =
    | Booked of Entry.t
    | Already_booked of Entry.t
    | Nothing_to_book
  [@@deriving sexp_of, compare, equal]
end

module Make (M : Monad.S) (Store : Store.S with type 'a io := 'a M.t) : sig
  type t

  val create : Program.t -> Store.t -> t
  val program : t -> Program.t

  (** The customer's ledger, folded. Fails if the store returns entries that break the
      ledger rules. *)
  val account : t -> User_id.t -> Points_account.t Or_error.t M.t

  (** Earns points for a settled card purchase (see {!Earn_rules.purchase}). [rate]
      converts the purchase currency to the basis currency, typically the mid rate of
      the settlement date. A redelivery is a conflict only if the amount or category
      differs. *)
  val settle_purchase
    :  t
    -> user:User_id.t
    -> purchase:Source_id.t
    -> spend:Money.Amount.t
    -> category:Category.t
    -> rate:Money.Rate.t option
    -> at:Time_ns.t
    -> (Outcome.t, Refusal.t) Result.t M.t

  (** Takes points back for a refund of [purchase] (see {!Earn_rules.clawback}). The
      refund is booked even when it takes no whole point back, so the next refund of
      the same purchase sees the full amount refunded. A purchase that earned nothing
      gives [Nothing_to_book]. *)
  val refund_purchase
    :  t
    -> user:User_id.t
    -> refund:Source_id.t
    -> purchase:Source_id.t
    -> amount:Money.Amount.t
    -> at:Time_ns.t
    -> (Outcome.t, Refusal.t) Result.t M.t

  (** Grants an action's bonus, once per customer. [Unknown_action] when the programme
      has no bonus for it. *)
  val complete_action
    :  t
    -> user:User_id.t
    -> action:Action.t
    -> at:Time_ns.t
    -> (Outcome.t, Refusal.t) Result.t M.t

  (** A manual correction of [points] (either sign, not zero) with a reason, keyed by
      the request id [id]. A negative adjustment cannot take the balance below zero. *)
  val adjust
    :  t
    -> user:User_id.t
    -> id:Source_id.t
    -> points:int
    -> reason:string
    -> at:Time_ns.t
    -> (Outcome.t, Refusal.t) Result.t M.t

  (** Books the points due to expire on [as_of] (see {!Expiry}). *)
  val expire
    :  t
    -> user:User_id.t
    -> as_of:Date.t
    -> at:Time_ns.t
    -> (Outcome.t, Refusal.t) Result.t M.t

  (** {!expire} for every customer in the store, in id order. *)
  val expire_all
    :  t
    -> as_of:Date.t
    -> at:Time_ns.t
    -> (User_id.t * (Outcome.t, Refusal.t) Result.t) list M.t

  (** Prices a cashback without recording anything. *)
  val quote_cashback
    :  t
    -> user:User_id.t
    -> points:int
    -> currency:Money.Currency.t
    -> rate:Money.Rate.t option
    -> (Cashback.Quote.t, Refusal.t) Result.t M.t

  (** Redeems [points] as cashback into [account] (in [currency]). [id] is the
      idempotency key of the request: a retry with the same id, customer, account and
      points returns the stored redemption (finishing it if a crash interrupted it),
      priced as the first time; the same id with anything else is
      [Redemption_conflict].

      The answer is [Ok r] once a redemption is recorded. Check [r.status]: [Completed]
      means the points are spent and the cash entry is due; [Refused] means the balance
      fell between pricing and spending. Validation failures before anything is
      recorded are [Error]. *)
  val redeem
    :  t
    -> id:Redemption_id.t
    -> user:User_id.t
    -> account:Ledger.Account_id.t
    -> currency:Money.Currency.t
    -> points:int
    -> rate:Money.Rate.t option
    -> now:Time_ns.t
    -> (Redemption.t, Refusal.t) Result.t M.t

  (** See {!Summary}. *)
  val summary : t -> user:User_id.t -> now:Time_ns.t -> Summary.t Or_error.t M.t

  (** See {!Statement}. *)
  val statement
    :  t
    -> user:User_id.t
    -> from:Time_ns.t
    -> until:Time_ns.t
    -> Statement.t Or_error.t M.t
end
