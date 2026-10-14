open! Core

module Repr = struct
  type t =
    { earn : Earn_rules.Stable.V1.t
    ; tiers : Tiers.Stable.V1.t
    ; cashback : Cashback.Rules.Stable.V1.t
    ; expiry : Expiry.Policy.Stable.V1.t
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { earn : Earn_rules.t
  ; tiers : Tiers.t
  ; cashback : Cashback.Rules.t
  ; expiry : Expiry.Policy.t
  }
[@@deriving sexp_of, compare, equal]

let validate (t : t) =
  let open Or_error.Let_syntax in
  let%bind () = Expiry.Policy.validate t.expiry in
  if Money.Currency.equal t.earn.basis (Cashback.Rules.basis t.cashback)
  then Ok t
  else
    Or_error.error_s
      [%message
        "cashback and earning use different basis currencies"
          ~earn:(t.earn.basis : Money.Currency.t)
          ~cashback:(Cashback.Rules.basis t.cashback : Money.Currency.t)]
;;

let create ~earn ~tiers ~cashback ~expiry = validate { earn; tiers; cashback; expiry }
let basis t = t.earn.basis

module Stable = struct
  module V1 = struct
    include Repr

    let t_of_sexp s = Or_error.ok_exn (validate (t_of_sexp s))

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable t = Or_error.ok_exn (validate t)
        end)
  end
end
