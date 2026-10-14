open! Core

module Repr = struct
  type t =
    { code : string
    ; name : string
    ; threshold : int
    ; benefits : Benefit.Stable.V1.t list
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { code : string
  ; name : string
  ; threshold : int
  ; benefits : Benefit.t list
  }
[@@deriving sexp_of, compare, equal]

let validate (t : t) =
  let open Or_error.Let_syntax in
  let%bind () =
    if String.is_empty t.code || String.is_empty t.name
    then Or_error.error_s [%message "tier needs a code and a name"]
    else Ok ()
  in
  let%bind () =
    if t.threshold < 0
    then Or_error.error_s [%message "negative threshold" ~threshold:(t.threshold : int)]
    else Ok ()
  in
  let%map () = Or_error.all_unit (List.map t.benefits ~f:Benefit.validate) in
  t
;;

let create ~code ~name ~threshold ?(benefits = []) () =
  validate { code; name; threshold; benefits }
  |> Or_error.tag_s ~tag:[%message "Rewards_core.Tier" code]
;;

let fx_spread_bps t ~standard =
  List.fold t.benefits ~init:standard ~f:(fun acc -> function
    | Fx_spread_cap { bps } -> Int.min acc bps
    | Fee_schedule _ | Perk _ -> acc)
;;

let fee_schedule t ~product ~currency =
  List.find_map t.benefits ~f:(function
    | Fee_schedule { product = p; fee }
      when String.equal p product
           && Money.Currency.equal (Money.Fee.currency fee) currency -> Some fee
    | Fx_spread_cap _ | Fee_schedule _ | Perk _ -> None)
;;

let fee t ~product ~standard =
  fee_schedule t ~product ~currency:(Money.Fee.currency standard)
  |> Option.value ~default:standard
;;

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
