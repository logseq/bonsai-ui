module Ui = Bonsai_swiftui_ui
module V = Ui.View
module ID = Bonsai_swiftui_spec.Id

type event = Activate

type state =
  { count : int
  ; child_count : int
  ; revision : int
  ; show : bool
  ; kind : int
  ; version : int
  ; alternate : bool
  ; show_child : bool
  ; invalid : bool
  }

let extension ~kind ~version =
  Ui.Native_widget.Extension.create
    ~kind_id:(ID.Native_widget.Kind_id.of_int kind)
    ~version
    ~capabilities:[ Ui.Native_widget.Capability.Stateful; Resource; Semantics ]
    ~encode_props:Bytes.of_string
    ~decode_event:(fun ~event_id bytes ->
      if ID.Native_widget.Event_id.to_int event_id = 1 && Bytes.length bytes = 0
      then Ok Activate
      else Error "Unknown native card event")
    ()
;;

let card = extension ~kind:1001 ~version:1

let component ?(nested = 0) handlers graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { count = 0
      ; child_count = 0
      ; revision = 0
      ; show = true
      ; kind = 1001
      ; version = 1
      ; alternate = false
      ; show_child = true
      ; invalid = false
      }
      graph
  in
  let actions =
    [ ("Change native properties", fun s -> { s with revision = s.revision + 1 })
    ; ("Toggle native card", fun s -> { s with show = not s.show })
    ; ( "Replace native kind"
      , fun s -> { s with kind = (if s.kind = 1001 then 1002 else 1001) } )
    ; ("Unknown native kind", fun s -> { s with kind = 1003 })
    ; ("Wrong native version", fun s -> { s with version = 2 })
    ; ("Invalid native properties", fun s -> { s with invalid = true })
    ; ("Replace native handler", fun s -> { s with alternate = not s.alternate })
    ; ("Toggle logical child", fun s -> { s with show_child = not s.show_child })
    ; ("Native child", fun s -> { s with child_count = s.child_count + 1 })
    ]
  in
  let bindings =
    List.map
      (fun (name, change) ->
         Driver.Handler.create
           handlers
           ~name
           ~equal:( == )
           set_state
           ~f:(fun set_state _ -> set_state change))
      actions
  in
  let native name definition =
    Driver.Handler.create_native
      handlers
      ~name
      definition
      ~equal:( == )
      set_state
      ~f:(fun set_state Activate -> set_state (fun s -> { s with count = s.count + 1 }))
  in
  let native =
    Bonsai.Cont.all
      [ native "catalog-native-card" card
      ; native "catalog-native-alternate" card
      ; native "catalog-native-second-kind" (extension ~kind:1002 ~version:1)
      ]
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both (Bonsai.Cont.all bindings) native)
    ~f:(fun s (bindings, natives) ->
      let native =
        List.nth natives (if s.kind = 1002 then 2 else if s.alternate then 1 else 0)
      in
      let button index =
        V.button
          ~on_press:(List.nth bindings index)
          ~child:(V.text (fst (List.nth actions index)))
          ()
      in
      let child = button 8 in
      let rec wrap level child =
        if level = 0
        then child
        else
          Ui.Native_widget.widget_with_handler
            card
            ~key:(Ui.Key.string "nested-native-card")
            ~props:(Printf.sprintf "Native layer %d" level)
            ~children:[ wrap (level - 1) child ]
            ~on_event:native
            ()
      in
      V.column
        ([ V.text (Printf.sprintf "Native events: %d" s.count)
         ; V.text (Printf.sprintf "Child events: %d" s.child_count)
         ]
         @ List.init 8 button
         @
         if not s.show
         then []
         else
           [ Ui.Native_widget.widget_with_handler
               (extension ~kind:s.kind ~version:s.version)
               ~key:(Ui.Key.string "native-card")
               ~props:
                 (if s.invalid
                  then "\255"
                  else Printf.sprintf "Native card: %d" s.revision)
               ~children:(if s.show_child then [ wrap nested child ] else [])
               ~on_event:native
               ()
           ]))
;;
