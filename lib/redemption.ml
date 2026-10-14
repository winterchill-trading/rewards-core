open! Core

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Accepted
        | Completed
        | Refused of { code : string }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Repr = struct
  type t =
    { id : Redemption_id.Stable.V1.t
    ; user : User_id.Stable.V1.t
    ; account : Ledger.Account_id.Stable.V1.t
    ; quote : Cashback.Quote.Stable.V1.t
    ; created_at : Time_ns.Stable.Alternate_sexp.V1.t
    ; status : Status.Stable.V1.t
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { id : Redemption_id.t
  ; user : User_id.t
  ; account : Ledger.Account_id.t
  ; quote : Cashback.Quote.t
  ; created_at : Time_ns.Alternate_sexp.t
  ; status : Status.t
  }
[@@deriving sexp_of, compare, equal]

let create ~id ~user ~account ~quote ~created_at =
  { id; user; account; quote; created_at; status = Accepted }
;;

let same_request t ~user ~account ~points =
  User_id.equal t.user user
  && Ledger.Account_id.equal t.account account
  && t.quote.points = points
;;

let complete t =
  match t.status with
  | Accepted | Completed -> Ok { t with status = Completed }
  | Refused _ ->
    Or_error.error_s
      [%message "a refused redemption cannot complete" ~id:(t.id : Redemption_id.t)]
;;

let refuse t refusal =
  match t.status with
  | Accepted -> Ok { t with status = Refused { code = Refusal.code refusal } }
  | Completed | Refused _ ->
    Or_error.error_s
      [%message
        "only an accepted redemption can be refused"
          ~id:(t.id : Redemption_id.t)
          ~status:(t.status : Status.t)]
;;

let cause t = Cause.Redemption t.id

module Stable = struct
  module V1 = Repr
end
