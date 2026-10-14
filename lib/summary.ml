open! Core

type t =
  { balance : int
  ; lifetime_earned : int
  ; tier : Tiers.Status.t
  ; redeemable : int
  ; expiring : (Date.t * int) list
  }
[@@deriving sexp_of]

let compute (program : Program.t) account ~now =
  let entries = Points_account.entries account in
  let balance = Points_account.balance account in
  { balance
  ; lifetime_earned = Points_account.lifetime_earned account
  ; tier = Tiers.status program.tiers entries ~now
  ; redeemable = Cashback.Rules.redeemable program.cashback ~balance
  ; expiring = Expiry.schedule program.expiry entries
  }
;;
