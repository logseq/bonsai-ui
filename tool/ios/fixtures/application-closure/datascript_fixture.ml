open Datascript
module Pure_dependency = Astring.String
module Utf_decoder = Uutf
module Unicode_normalization = Uunf
module Unicode_properties = Uucp

let indexed_string =
  { cardinality = One
  ; unique = Some Identity
  ; indexed = true
  ; is_component = false
  ; no_history = false
  ; doc = None
  ; value_type = Some StringType
  ; tuple_attrs = None
  ; tuple_types = None
  }
;;

let require condition message = if not condition then failwith message

let persist path =
  let session = Datascript_sqlite.open_session path in
  let storage = Datascript_sqlite.storage session in
  let db = empty_db ~schema:[ "fact/id", indexed_string ] ~storage () in
  let report =
    transact
      db
      [ Add (Temp_id "physical-iphone", "fact/id", String "physical-iphone")
      ; Add
          (Temp_id "physical-iphone", "fact/value", String "typed-datascript-sqlite-fact")
      ]
  in
  store ~storage report.db_after;
  Datascript_sqlite.close session
;;

let restore path =
  let session = Datascript_sqlite.open_session path in
  let storage = Datascript_sqlite.storage session in
  let db =
    match restore storage with
    | Some db -> db
    | None -> failwith "expected a persisted DataScript database"
  in
  let entity =
    match entity db (Lookup_ref ("fact/id", String "physical-iphone")) with
    | Some entity -> entity
    | None -> failwith "expected the persisted typed fact"
  in
  require
    (entity_attr entity "fact/value"
     = Some (One_value (String "typed-datascript-sqlite-fact")))
    "restored typed fact does not match";
  require
    (Pure_dependency.is_prefix ~affix:"typed-" "typed-datascript-sqlite-fact")
    "the generic pure OCaml dependency was not linked";
  Datascript_sqlite.close session
;;

let () =
  Rrbvec_probe.run ();
  match Array.to_list Sys.argv with
  | [ _; "persist"; path ] -> persist path
  | [ _; "restore"; path ] -> restore path
  | _ -> invalid_arg "usage: datascript_fixture <persist|restore> <database-path>"
;;
