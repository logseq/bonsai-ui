type capability =
  | Pure_ocaml
  | Network
  | System_sqlite
  | Entropy
  | Filesystem
  | Foreign_stubs of string
  | Unsupported of string

let network_packages =
  [ "tls"
  ; "tls-eio"
  ; "ca-certs-nss"
  ; "x509"
  ; "httpun"
  ; "httpun-eio"
  ; "httpun-ws"
  ; "gluten"
  ; "gluten-eio"
  ; "digestif"
  ; "domain-name"
  ; "uri"
  ]
;;

let sqlite_packages = [ "sqlite3" ]
let prohibited = [ "openssl"; "conf-openssl"; "eio-ssl"; "piaf" ]
let has_feature features feature = List.exists (Config.Feature.equal feature) features

let unsupported ~package capability recipe =
  Error
    (Printf.sprintf
       "Package %s uses unsupported capability %s; required cross-build recipe: %s"
       package
       capability
       recipe)
;;

let validate_capability ~features ~package = function
  | Pure_ocaml -> Ok ()
  | Network ->
    if has_feature features Config.Feature.Network
    then Ok ()
    else Error (Printf.sprintf "Package %s requires the network feature" package)
  | System_sqlite ->
    if has_feature features Config.Feature.Sqlite
    then Ok ()
    else Error (Printf.sprintf "Package %s requires the sqlite feature" package)
  | Entropy ->
    if has_feature features Config.Feature.Network
    then Ok ()
    else
      Error (Printf.sprintf "Package %s requires the network feature for entropy" package)
  | Filesystem ->
    if has_feature features Config.Feature.Core
    then Ok ()
    else Error (Printf.sprintf "Package %s requires the core filesystem policy" package)
  | Foreign_stubs recipe -> unsupported ~package "foreign stubs" recipe
  | Unsupported capability ->
    unsupported ~package capability "an explicit iPhoneOS cross-build recipe"
;;

let capability_of_package package =
  if
    String.equal package "mirage-crypto-rng"
    || String.equal package "mirage-crypto-rng.unix"
  then Entropy
  else if String.equal package "eio_posix"
  then Filesystem
  else if List.mem package network_packages
  then Network
  else if List.mem package sqlite_packages
  then System_sqlite
  else Pure_ocaml
;;

let validate_package ~features package =
  if List.mem package prohibited
  then Error (Printf.sprintf "Package %s uses a prohibited TLS backend" package)
  else validate_capability ~features ~package (capability_of_package package)
;;

let validate_packages ~target ~features packages =
  match target with
  | Plan.Macos -> Ok ()
  | Plan.Iphoneos ->
    List.fold_left
      (fun result package ->
         match result with
         | Error _ -> result
         | Ok () -> validate_package ~features package)
      (Ok ())
      packages
;;
