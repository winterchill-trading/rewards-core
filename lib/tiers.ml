open! Core

module Repr = struct
  type t =
    { window : Time_ns.Span.Stable.V2.t
    ; tiers : Tier.Stable.V1.t list
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { window : Time_ns.Span.t
  ; tiers : Tier.t list
  }
[@@deriving sexp_of, compare, equal]

let validate (t : t) =
  let open Or_error.Let_syntax in
  let%bind () =
    if Time_ns.Span.( <= ) t.window Time_ns.Span.zero
    then Or_error.error_s [%message "tier window must be positive"]
    else Ok ()
  in
  let%bind () =
    match t.tiers with
    | [] -> Or_error.error_s [%message "no tiers"]
    | first :: _ when first.threshold <> 0 ->
      Or_error.error_s
        [%message "the first tier's threshold must be 0" ~code:(first.code : string)]
    | _ -> Ok ()
  in
  let%bind () =
    match
      List.find_consecutive_duplicate t.tiers ~equal:(fun (a : Tier.t) b ->
        a.threshold >= b.threshold)
    with
    | Some (_, (b : Tier.t)) ->
      Or_error.error_s
        [%message "thresholds must strictly increase" ~at:(b.code : string)]
    | None -> Ok ()
  in
  let%map () =
    match
      List.find_a_dup t.tiers ~compare:(fun (a : Tier.t) b -> String.compare a.code b.code)
    with
    | Some (d : Tier.t) -> Or_error.error_s [%message "repeated tier code" ~code:d.code]
    | None -> Ok ()
  in
  t
;;

let create ~window tiers = validate { window; tiers }
let find t code = List.find t.tiers ~f:(fun (x : Tier.t) -> String.equal x.code code)

let tier_for t ~points =
  List.fold t.tiers ~init:(List.hd_exn t.tiers) ~f:(fun acc (x : Tier.t) ->
    if x.threshold <= points then x else acc)
;;

let window_points t entries ~now =
  let since = Time_ns.sub now t.window in
  List.sum
    (module Int)
    entries
    ~f:(fun (e : Entry.t) ->
      if Kind.counts_for_tier (Entry.kind e)
         && Time_ns.( > ) e.at since
         && Time_ns.( <= ) e.at now
      then e.points
      else 0)
  |> Int.max 0
;;

module Status = struct
  type t =
    { tier : Tier.t
    ; next : Tier.t option
    ; window_points : int
    ; points_to_next : int option
    ; progress_percent : int
    }
  [@@deriving sexp_of, compare, equal]
end

let status t entries ~now : Status.t =
  let window_points = window_points t entries ~now in
  let tier = tier_for t ~points:window_points in
  let next = List.find t.tiers ~f:(fun (x : Tier.t) -> x.threshold > tier.threshold) in
  match next with
  | None ->
    { tier; next; window_points; points_to_next = None; progress_percent = 100 }
  | Some (n : Tier.t) ->
    let span = n.threshold - tier.threshold in
    let progress = (window_points - tier.threshold) * 100 / span in
    { tier
    ; next
    ; window_points
    ; points_to_next = Some (n.threshold - window_points)
    ; progress_percent = Int.clamp_exn progress ~min:0 ~max:99
    }
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
