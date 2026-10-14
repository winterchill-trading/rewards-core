open! Core

module Repr = struct
  type t =
    { user : User_id.Stable.V1.t
    ; seq : int
    ; cause : Cause.Stable.V1.t
    ; points : int
    ; at : Time_ns.Stable.Alternate_sexp.V1.t
    ; earning : Earning.Stable.V1.t option
    ; note : string
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { user : User_id.t
  ; seq : int
  ; cause : Cause.t
  ; points : int
  ; at : Time_ns.Alternate_sexp.t
  ; earning : Earning.t option
  ; note : string
  }
[@@deriving sexp_of, compare, equal]

let kind t = Cause.kind t.cause
let key t = Cause.key t.cause

let validate (t : t) =
  let kind = Cause.kind t.cause in
  if t.seq < 0
  then Or_error.error_s [%message "negative sequence number" ~seq:(t.seq : int)]
  else if not (Kind.accepts kind ~points:t.points)
  then
    Or_error.error_s
      [%message "points have the wrong sign for the kind" (kind : Kind.t) ~points:(t.points : int)]
  else (
    match t.earning, t.cause with
    | None, _ | Some _, (Card_purchase _ | Card_refund _) -> Ok t
    | Some _, _ ->
      Or_error.error_s [%message "earning details only belong to card purchases and refunds"])
;;

let create ~user ~seq ~cause ~points ~at ?earning ?(note = "") () =
  validate { user; seq; cause; points; at; earning; note }
;;

let same_request a b = equal { a with seq = b.seq; at = b.at } b

module Stable = struct
  module V1 = struct
    include Repr

    let t_of_sexp sexp = Or_error.ok_exn (validate (t_of_sexp sexp))

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
