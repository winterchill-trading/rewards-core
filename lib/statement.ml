open! Core

module Line = struct
  type t =
    { entry : Entry.t
    ; balance_after : int
    }
  [@@deriving sexp_of]
end

type t =
  { user : User_id.t
  ; from : Time_ns.Alternate_sexp.t
  ; until : Time_ns.Alternate_sexp.t
  ; opening : int
  ; lines : Line.t list
  ; totals : (Kind.t * int) list
  ; closing : int
  }
[@@deriving sexp_of]

let create ~user ~from ~until entries =
  if Time_ns.( < ) until from
  then Or_error.error_s [%message "statement period ends before it starts"]
  else (
    match
      List.find entries ~f:(fun (e : Entry.t) -> not (User_id.equal e.user user))
    with
    | Some e ->
      Or_error.error_s
        [%message "entry for another customer" ~user:(e.user : User_id.t)]
    | None ->
      let before, rest =
        List.partition_tf entries ~f:(fun (e : Entry.t) -> Time_ns.( < ) e.at from)
      in
      let opening = List.sum (module Int) before ~f:(fun e -> e.points) in
      let in_period =
        List.filter rest ~f:(fun (e : Entry.t) -> Time_ns.( < ) e.at until)
        |> List.sort ~compare:(fun (a : Entry.t) b ->
          Comparable.lexicographic
            [ (fun (a : Entry.t) b -> Time_ns.compare a.at b.at)
            ; (fun (a : Entry.t) b -> Int.compare a.seq b.seq)
            ]
            a
            b)
      in
      let closing, rev_lines =
        List.fold in_period ~init:(opening, []) ~f:(fun (balance, acc) entry ->
          let balance = balance + entry.points in
          balance, { Line.entry; balance_after = balance } :: acc)
      in
      let totals =
        List.map Kind.all ~f:(fun kind ->
          ( kind
          , List.sum (module Int) in_period ~f:(fun e ->
              if Kind.equal (Entry.kind e) kind then e.points else 0) ))
      in
      Ok { user; from; until; opening; lines = List.rev rev_lines; totals; closing })
;;

let check t =
  let sum = t.opening + List.sum (module Int) t.totals ~f:snd in
  let running =
    List.fold_result t.lines ~init:t.opening ~f:(fun balance (line : Line.t) ->
      let balance = balance + line.entry.points in
      if balance = line.balance_after
      then Ok balance
      else
        Or_error.error_s
          [%message "running balance differs" ~seq:(line.entry.seq : int)])
  in
  match running with
  | Error _ as e -> Or_error.ignore_m e
  | Ok last when last <> t.closing || sum <> t.closing ->
    Or_error.error_s
      [%message
        "opening + movements <> closing"
          ~opening:(t.opening : int)
          ~closing:(t.closing : int)
          (sum : int)]
  | Ok _ -> Ok ()
;;
