open! Core

module Policy = struct
  module Repr = struct
    type t =
      | Never
      | After_days of int
    [@@deriving bin_io, sexp, compare, equal]
  end

  type t = Repr.t =
    | Never
    | After_days of int
  [@@deriving sexp, compare, equal]

  let validate = function
    | After_days n when n < 1 ->
      Or_error.error_s [%message "expiry needs at least one day" (n : int)]
    | Never | After_days _ -> Ok ()
  ;;

  module Stable = struct
    module V1 = struct
      include Repr

      let t_of_sexp s =
        let t = t_of_sexp s in
        Or_error.ok_exn (validate t);
        t
      ;;

      include
        Binable.Of_binable_without_uuid [@alert "-legacy"]
          (Repr)
          (struct
            type nonrec t = t

            let to_binable = Fn.id

            let of_binable t =
              Or_error.ok_exn (validate t);
              t
            ;;
          end)
    end
  end
end

(* Open points by expiry date. Spending takes from the earliest expiry date first, so
   entries recorded out of time order (a late settlement) still leave the points that
   expire last. *)
let consume lots points =
  let rec go lots points =
    if points <= 0
    then lots
    else (
      match Map.min_elt lots with
      | None -> lots
      | Some (date, open_) ->
        if points >= open_
        then go (Map.remove lots date) (points - open_)
        else Map.set lots ~key:date ~data:(open_ - points))
  in
  go lots points
;;

let open_lots ~days entries =
  List.fold entries ~init:Date.Map.empty ~f:(fun lots (e : Entry.t) ->
    if e.points > 0
    then (
      let earned_on = Time_ns.to_date e.at ~zone:Time_float.Zone.utc in
      Map.update lots (Date.add_days earned_on days) ~f:(fun prev ->
        Option.value prev ~default:0 + e.points))
    else consume lots (-e.points))
;;

let schedule (policy : Policy.t) entries =
  match policy with
  | Never -> []
  | After_days days ->
    open_lots ~days entries |> Map.to_alist |> List.filter ~f:(fun (_, n) -> n > 0)
;;

let due policy entries ~as_of =
  schedule policy entries
  |> List.sum (module Int) ~f:(fun (date, n) -> if Date.( <= ) date as_of then n else 0)
;;
