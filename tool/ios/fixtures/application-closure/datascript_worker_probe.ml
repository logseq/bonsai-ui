open Datascript

type t =
  { session : Datascript_sqlite.session
  ; directory : string
  }

type json_probe =
  { identifier : string
  ; revision : int
  }
[@@deriving yojson]

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

let fact_id = "physical-iphone-worker"
let fact_value = "typed-datascript-worker-fact"

let marker value =
  Printf.printf "%s\n%!" value;
  prerr_endline value
;;

let require condition message = if not condition then failwith message

let publish directory name value =
  let path = Filename.concat directory name in
  let temporary = path ^ ".tmp" in
  let channel = open_out_bin temporary in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel value);
  Sys.rename temporary path
;;

let verify_json_round_trip () =
  let expected = { identifier = "physical-iphone-worker"; revision = 1 } in
  match json_probe_of_yojson (json_probe_to_yojson expected) with
  | Ok actual when actual = expected -> marker "BONSAI_DERIVING_YOJSON_ROUND_TRIP"
  | Ok _ -> failwith "derived JSON codec round trip changed the value"
  | Error message -> failwith ("derived JSON codec round trip failed: " ^ message)
;;

let validate_fact db =
  let entity =
    match entity db (Lookup_ref ("fact/id", String fact_id)) with
    | Some entity -> entity
    | None -> failwith "expected the persisted DataScript Worker fact"
  in
  require
    (entity_attr entity "fact/value" = Some (One_value (String fact_value)))
    "restored DataScript Worker fact does not match"
;;

let open_ (config : Sqlite_worker_config.t) =
  let path =
    Filename.concat config.application_support_directory "datascript-worker-probe.sqlite3"
  in
  try
    Rrbvec_probe.run ();
    verify_json_round_trip ();
    let session = Datascript_sqlite.open_session path in
    try
      let storage = Datascript_sqlite.storage session in
      let phase =
        match Datascript.restore storage with
        | Some db ->
          validate_fact db;
          marker "BONSAI_DATASCRIPT_WORKER_RESTORED";
          "restored"
        | None ->
          let db = empty_db ~schema:[ "fact/id", indexed_string ] ~storage () in
          let report =
            transact
              db
              [ Add (Temp_id fact_id, "fact/id", String fact_id)
              ; Add (Temp_id fact_id, "fact/value", String fact_value)
              ]
          in
          Datascript.store ~storage report.db_after;
          validate_fact report.db_after;
          marker "BONSAI_DATASCRIPT_WORKER_PERSISTED";
          "persisted"
      in
      publish config.application_support_directory "probe-ready" phase;
      Ok { session; directory = config.application_support_directory }
    with
    | exn ->
      Datascript_sqlite.close session;
      raise exn
  with
  | exn -> Error ("DataScript Worker probe failed: " ^ Printexc.to_string exn)
;;

let close resource =
  Datascript_sqlite.close resource.session;
  publish resource.directory "probe-closed" "closed";
  marker "BONSAI_DATASCRIPT_WORKER_SHUTDOWN"
;;

let persistence_probe : t Sqlite_worker_service.persistence_probe = { open_; close }
