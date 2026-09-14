(** Versioned application payload for the SQLite Worker example. *)

type t =
  { database_path : string
  ; application_support_directory : string
  }

val encode : t -> bytes
val decode : bytes -> (t, string) result
