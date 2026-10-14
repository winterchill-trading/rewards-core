open! Core

module Make (M : Monad.S) = struct
  type 'a io = 'a M.t

  module Ledger_rows = struct
    type t =
      { rev_entries : Entry.t list
      ; length : int
      ; by_key : Entry.t String.Map.t
      }

    let empty = { rev_entries = []; length = 0; by_key = String.Map.empty }
  end

  type t =
    { ledgers : Ledger_rows.t User_id.Table.t
    ; redemptions : Redemption.t Redemption_id.Table.t
    }

  let create () =
    { ledgers = User_id.Table.create (); redemptions = Redemption_id.Table.create () }
  ;;

  let rows t user = Hashtbl.find t.ledgers user |> Option.value ~default:Ledger_rows.empty
  let entries t user = M.return (List.rev (rows t user).rev_entries)

  let append t (entry : Entry.t) =
    let rows = rows t entry.user in
    M.return
      (match Map.find rows.by_key (Entry.key entry) with
       | Some existing -> Store.Append.Cause_taken existing
       | None when entry.seq <> rows.length -> Stale { length = rows.length }
       | None ->
         Hashtbl.set
           t.ledgers
           ~key:entry.user
           ~data:
             { rev_entries = entry :: rows.rev_entries
             ; length = rows.length + 1
             ; by_key = Map.set rows.by_key ~key:(Entry.key entry) ~data:entry
             };
         Appended)
  ;;

  let users t = M.return (Hashtbl.keys t.ledgers |> List.sort ~compare:User_id.compare)
  let find_redemption t id = M.return (Hashtbl.find t.redemptions id)

  let insert_redemption t (r : Redemption.t) =
    M.return
      (match Hashtbl.add t.redemptions ~key:r.id ~data:r with
       | `Ok -> Store.Insert.Inserted
       | `Duplicate -> Exists (Hashtbl.find_exn t.redemptions r.id))
  ;;

  let update_redemption t (r : Redemption.t) =
    M.return
      (if Hashtbl.mem t.redemptions r.id
       then Ok (Hashtbl.set t.redemptions ~key:r.id ~data:r)
       else
         Or_error.error_s
           [%message "no such redemption" ~id:(r.id : Redemption_id.t)])
  ;;

  let redemptions t =
    Hashtbl.data t.redemptions
    |> List.sort ~compare:(fun (a : Redemption.t) b -> Redemption_id.compare a.id b.id)
  ;;
end
