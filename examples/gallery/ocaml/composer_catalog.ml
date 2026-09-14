module Ui = Bonsai_swiftui_ui
module V = Ui.View
module Composer = Ui.Native_widget.Message_composer

type state =
  { text : string
  ; last_action : string
  ; changes : int
  ; enabled : bool
  ; send_enabled : bool
  ; show : bool
  ; generation : int
  ; alternate : bool
  }

let component ?(autofocus = false) handlers graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { text = ""
      ; last_action = "None"
      ; changes = 0
      ; enabled = true
      ; send_enabled = true
      ; show = true
      ; generation = 0
      ; alternate = false
      }
      graph
  in
  let controls =
    [ ("Toggle composer", fun s -> { s with enabled = not s.enabled })
    ; ("Toggle send", fun s -> { s with send_enabled = not s.send_enabled })
    ; ("Change composer layout", fun s -> { s with alternate = not s.alternate })
    ; ("Remove composer", fun s -> { s with show = not s.show })
    ; ("Reset draft", fun s -> { s with generation = s.generation + 1 })
    ]
  in
  let controls_bindings =
    List.map
      (fun (name, change) ->
         Driver.Handler.create
           handlers
           ~name
           ~equal:( == )
           set_state
           ~f:(fun set_state _ -> set_state change))
      controls
  in
  let changed =
    Driver.Handler.create
      handlers
      ~name:"composer-event"
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        set_state (fun s ->
          match Composer.event_of_payload payload with
          | Some (Text_changed text) -> { s with text; changes = s.changes + 1 }
          | Some (Button_pressed { button_id; text }) ->
            { s with last_action = Printf.sprintf "%d:%s" button_id text }
          | None -> s))
  in
  let nested =
    Driver.Handler.create
      handlers
      ~name:"forbidden-composer-label"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun s -> { s with last_action = "Forbidden nested action" }))
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (Bonsai.Cont.all controls_bindings)
       (Bonsai.Cont.both changed nested))
    ~f:(fun s (bindings, (changed, nested)) ->
      let controls =
        List.mapi
          (fun i (name, _) ->
             V.button ~on_press:(List.nth bindings i) ~child:(V.text name) ())
          controls
      in
      V.column
        ([ V.text ("Observed draft: " ^ s.text)
         ; V.text ("Last action: " ^ s.last_action)
         ; V.text (Printf.sprintf "Changes: %d" s.changes)
         ]
         @ controls
         @
         if not s.show
         then []
         else
           [ Composer.create_with_handler
               ~key:(Ui.Key.int s.generation)
               ~enabled:s.enabled
               ~autofocus
               ~hint_text:
                 (if s.alternate then "Revised message hint" else "Write a message")
               ~max_lines:(if s.alternate then 3 else 5)
               ~buttons:
                 [ Composer.button
                     ~id:1
                     ~tooltip:"Attach"
                     ~position:Leading
                     ~child:
                       (V.button ~on_press:nested ~child:(V.text "Custom attachment") ())
                     ()
                 ; Composer.button
                     ~id:2
                     ~tooltip:"Voice"
                     ~visibility:When_empty
                     ~child:(V.text "Voice label")
                     ()
                 ; Composer.button
                     ~id:3
                     ~tooltip:"Send"
                     ~visibility:When_non_empty
                     ~style:Filled
                     ~enabled:s.send_enabled
                     ~child:(V.text "Send label")
                     ()
                 ]
               ~on_event:changed
               ()
           ]))
;;
