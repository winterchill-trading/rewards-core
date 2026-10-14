open! Core

module Append = struct
  type t =
    | Appended
    | Cause_taken of Entry.t
    | Stale of { length : int }
  [@@deriving sexp_of, compare, equal]
end

module Insert = struct
  type t =
    | Inserted
    | Exists of Redemption.t
  [@@deriving sexp_of, compare, equal]
end

module type S = sig
  type 'a io
  type t

  val entries : t -> User_id.t -> Entry.t list io
  val append : t -> Entry.t -> Append.t io
  val users : t -> User_id.t list io
  val find_redemption : t -> Redemption_id.t -> Redemption.t option io
  val insert_redemption : t -> Redemption.t -> Insert.t io
  val update_redemption : t -> Redemption.t -> unit Or_error.t io
end
