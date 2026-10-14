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

(* Lots are kept oldest first; consumption takes from the front. *)
let consume lots points =
  let rec go lots points =
    match lots with
    | [] -> []
    | (date, open_) :: rest ->
      if points >= open_ then go rest (points - open_) else (date, open_ - points) :: rest
  in
  go lots points
;;

let open_lots ~days entries =
  List.fold entries ~init:Fqueue.empty ~f:(fun lots (e : Entry.t) ->
    if e.points > 0
    then (
      let earned_on = Time_ns.to_date e.at ~zone:Time_float.Zone.utc in
      Fqueue.enqueue lots (Date.add_days earned_on days, e.points))
    else Fqueue.of_list (consume (Fqueue.to_list lots) (-e.points)))
  |> Fqueue.to_list
;;

let schedule (policy : Policy.t) entries =
  match policy with
  | Never -> []
  | After_days days ->
    open_lots ~days entries
    |> List.filter ~f:(fun (_, n) -> n > 0)
    |> List.sort_and_group ~compare:(fun (a, _) (b, _) -> Date.compare a b)
    |> List.map ~f:(fun group ->
      fst (List.hd_exn group), List.sum (module Int) group ~f:snd)
;;

let due policy entries ~as_of =
  schedule policy entries
  |> List.sum (module Int) ~f:(fun (date, n) -> if Date.( <= ) date as_of then n else 0)
;;
