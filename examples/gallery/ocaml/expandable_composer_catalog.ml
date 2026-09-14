module Ui = Bonsai_swiftui_ui
module V = Ui.View
module C = Ui.Native_widget.Expandable_message_composer

type state =
  { text : string
  ; action : string
  ; count : int
  ; background : int
  ; compact : bool
  ; enabled : bool
  ; show : bool
  ; generation : int
  }

let component ?(duration = 200) ?(curve = Ui.Animation.Curve.Ease_out) handlers graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { text = ""
      ; action = "None"
      ; count = 0
      ; background = 0
      ; compact = false
      ; enabled = true
      ; show = true
      ; generation = 0
      }
      graph
  in
  let controls =
    [ ("Background action", fun s -> { s with background = s.background + 1 })
    ; ("Toggle availability", fun s -> { s with enabled = not s.enabled })
    ; ("Toggle launcher style", fun s -> { s with compact = not s.compact })
    ; ("Toggle composer visibility", fun s -> { s with show = not s.show })
    ; ("Replace composer key", fun s -> { s with generation = s.generation + 1 })
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
      controls
  in
  let changed =
    Driver.Handler.create
      handlers
      ~name:"expandable-composer-event"
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        set_state (fun s ->
          match C.event_of_payload payload with
          | Some (Text_changed text) -> { s with text }
          | Some (Button_pressed { button_id; text }) ->
            let s =
              { s with
                action = Printf.sprintf "%d:%s" button_id text
              ; count = s.count + 1
              }
            in
            (match button_id with
             | 4 -> { s with compact = not s.compact }
             | 5 -> { s with enabled = false }
             | 6 -> { s with show = false }
             | 7 -> { s with generation = s.generation + 1 }
             | _ -> s)
          | None -> s))
  in
  let forbidden =
    Driver.Handler.create
      handlers
      ~name:"forbidden-launcher-child"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ -> set_state (fun s -> { s with action = "Forbidden child" }))
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both (Bonsai.Cont.all bindings) (Bonsai.Cont.both changed forbidden))
    ~f:(fun s (bindings, (changed, forbidden)) ->
      let controls =
        List.mapi
          (fun index (title, _) ->
             V.button ~on_press:(List.nth bindings index) ~child:(V.text title) ())
          controls
      in
      let action ?(visibility = C.Always) id tooltip symbol =
        C.button ~id ~tooltip ~visibility ~child:(V.symbol ~name:symbol ()) ()
      in
      V.column
        ([ V.text ("Observed draft: " ^ s.text)
         ; V.text ("Last action: " ^ s.action)
         ; V.text (Printf.sprintf "Actions: %d" s.count)
         ; V.text (Printf.sprintf "Background: %d" s.background)
         ]
         @ controls
         @
         if not s.show
         then []
         else
           [ C.create_with_handler
               ~key:(Ui.Key.int s.generation)
               ~enabled:s.enabled
               ~fab_presentation:(if s.compact then Compact else Extended)
               ~fab_label:"New message"
               ~fab_tooltip:"Open composer"
               ~fab_icon:
                 (V.button
                    ~on_press:forbidden
                    ~child:(V.symbol ~name:"square.and.pencil" ())
                    ())
               ~animation_duration_ms:duration
               ~animation_curve:curve
               ~max_lines:(if s.compact then 3 else 5)
               ~hint_text:
                 (if s.compact
                  then "Compact launcher draft"
                  else "Write an expanded message")
               ~buttons:
                 [ action 1 "Attach" "paperclip"
                 ; action ~visibility:When_empty 2 "Voice" "mic"
                 ; action ~visibility:When_non_empty 3 "Send" "arrow.up"
                 ; action 4 "Change launcher" "rectangle.compress.vertical"
                 ; action 5 "Disable composer" "lock"
                 ; action 6 "Remove from sheet" "trash"
                 ; action 7 "Reset from sheet" "arrow.clockwise"
                 ]
               ~on_event:changed
               ()
           ]))
;;
