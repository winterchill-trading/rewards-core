open! Core
module Amount = Money.Amount

type t =
  { basis : Money.Currency.t
  ; points_per_unit : int
  ; default_multiplier : int
  ; multipliers : int Category.Map.t
  ; bonuses : int Action.Map.t
  }
[@@deriving sexp_of, compare, equal]

let create
  ~basis
  ?(points_per_unit = 1)
  ?(default_multiplier = 1)
  ?(multipliers = [])
  ?(bonuses = [])
  ()
  =
  let open Or_error.Let_syntax in
  let%bind () =
    if points_per_unit < 0 || default_multiplier < 0
    then Or_error.error_s [%message "negative points per unit or default multiplier"]
    else Ok ()
  in
  let%bind multipliers =
    match Category.Map.of_alist multipliers with
    | `Duplicate_key c ->
      Or_error.error_s [%message "category listed twice" (c : Category.t)]
    | `Ok m ->
      (match Map.to_alist m |> List.find ~f:(fun (_, x) -> x < 0) with
       | Some (c, x) ->
         Or_error.error_s [%message "negative multiplier" (c : Category.t) (x : int)]
       | None -> Ok m)
  in
  let%map bonuses =
    match Action.Map.of_alist bonuses with
    | `Duplicate_key a -> Or_error.error_s [%message "action listed twice" (a : Action.t)]
    | `Ok m ->
      (match Map.to_alist m |> List.find ~f:(fun (_, x) -> x <= 0) with
       | Some (a, x) ->
         Or_error.error_s [%message "bonus must be positive" (a : Action.t) (x : int)]
       | None -> Ok m)
  in
  { basis; points_per_unit; default_multiplier; multipliers; bonuses }
;;

let multiplier t category =
  Map.find t.multipliers category |> Option.value ~default:t.default_multiplier
;;

let bonus t action = Map.find t.bonuses action
let floor_q q = Z.fdiv (Q.num q) (Q.den q)

let purchase t ~spend ~category ~rate =
  let open Result.Let_syntax in
  if not (Amount.is_positive spend)
  then
    Error
      (Refusal.Invalid
         (Error.create_s [%message "spend must be positive" (spend : Amount.t)]))
  else (
    let%map basis_q = Convert.major_units spend ~to_:t.basis ~rate in
    let multiplier = multiplier t category in
    let units = floor_q basis_q in
    let points = Z.to_int (Z.mul units (Z.of_int (t.points_per_unit * multiplier))) in
    let rate =
      if Money.Currency.equal (Amount.currency spend) t.basis
      then None
      else
        Option.bind rate ~f:(fun r ->
          Convert.orient r ~from:(Amount.currency spend) ~to_:t.basis)
    in
    ( points
    , { Earning.spend
      ; basis_amount = Amount.of_q ~rounding:Down t.basis basis_q
      ; rate
      ; category
      ; multiplier
      } ))
;;

let refunded (entries : Entry.t list) =
  List.filter_map entries ~f:(fun e -> Option.map e.earning ~f:(fun x -> x.spend))
;;

let clawback ~(purchase : Entry.t) ~earlier ~refund ~balance =
  let open Result.Let_syntax in
  let%bind (earning : Earning.t) =
    match purchase.earning with
    | Some e -> Ok e
    | None ->
      Error
        (Refusal.Invalid
           (Error.create_s [%message "purchase entry without earning details"]))
  in
  let currency = Amount.currency earning.spend in
  let%bind () =
    if Money.Currency.equal (Amount.currency refund) currency
    then Ok ()
    else
      Error
        (Refusal.Currency_mismatch { expected = currency; got = Amount.currency refund })
  in
  let%bind () =
    if Amount.is_positive refund
    then Ok ()
    else
      Error
        (Refusal.Invalid
           (Error.create_s [%message "refund must be positive" (refund : Amount.t)]))
  in
  let%map before = Amount.sum currency (refunded earlier) |> Refusal.of_or_error in
  let spend = Amount.minor_units earning.spend in
  let clawed_by total =
    (* Proportional and cumulative: the share for all refunds so far, minus the share for
       the refunds before this one, so rounding never adds up past the purchase. *)
    let total = Z.min total spend in
    Z.fdiv (Z.mul (Z.of_int purchase.points) total) spend
  in
  let before_units = Amount.minor_units before in
  let after_units = Z.add before_units (Amount.minor_units refund) in
  let points = Z.to_int (Z.sub (clawed_by after_units) (clawed_by before_units)) in
  let points = Int.min points (Int.max balance 0) in
  let basis_amount =
    Amount.mul_ratio
      ~rounding:Down
      earning.basis_amount
      (Q.make (Z.min (Amount.minor_units refund) spend) spend)
  in
  points, { earning with spend = refund; basis_amount }
;;

module Stable = struct
  module V1 = struct
    module Repr = struct
      type t =
        { basis : Money.Currency.Stable.V1.t
        ; points_per_unit : int
        ; default_multiplier : int
        ; multipliers : (Category.Stable.V1.t * int) list
        ; bonuses : (Action.Stable.V1.t * int) list
        }
      [@@deriving bin_io, sexp]
    end

    type nonrec t = t [@@deriving compare, equal]

    let to_repr (t : t) : Repr.t =
      { basis = t.basis
      ; points_per_unit = t.points_per_unit
      ; default_multiplier = t.default_multiplier
      ; multipliers = Map.to_alist t.multipliers
      ; bonuses = Map.to_alist t.bonuses
      }
    ;;

    let of_repr (r : Repr.t) =
      create
        ~basis:r.basis
        ~points_per_unit:r.points_per_unit
        ~default_multiplier:r.default_multiplier
        ~multipliers:r.multipliers
        ~bonuses:r.bonuses
        ()
      |> Or_error.ok_exn
    ;;

    let sexp_of_t t = Repr.sexp_of_t (to_repr t)
    let t_of_sexp s = of_repr (Repr.t_of_sexp s)

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type nonrec t = t

          let to_binable = to_repr
          let of_binable = of_repr
        end)
  end
end
