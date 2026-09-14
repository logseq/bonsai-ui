let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "counter")
    Counter.app
;;

module Ui = Bonsai_swiftui_ui

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-dropdown")
    (App.create ~name:"Gallery Dropdown" (fun handlers graph ->
       Bonsai.Cont.map (Dropdown_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-theme")
    (App.create ~name:"Gallery Theme" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.theme_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "full-gallery")
    (App.create ~name:"Bonsai SwiftUI Gallery" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body)))
;;

let keyboard_events_component ~autofocus handlers graph =
  let history, set_history = Bonsai_v017.state ~equal:String.equal "" graph in
  let handler =
    Driver.Handler.create
      handlers
      ~name:"keyboard"
      ~equal:( == )
      set_history
      ~f:(fun set_history -> function
      | Ui.Event.Payload.Key { logical_key; physical_key; action; modifiers } ->
        let action =
          match action with
          | Key_down -> "down"
          | Key_up -> "up"
          | Key_repeat -> "repeat"
        in
        let entry =
          Printf.sprintf
            "%Ld:%Ld:%s:%d;"
            (Bonsai_swiftui_spec.Id.Input.Logical_key.to_int64 logical_key)
            (Bonsai_swiftui_spec.Id.Input.Physical_key.to_int64 physical_key)
            action
            modifiers
        in
        set_history (fun history -> history ^ entry)
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 history handler ~f:(fun history on_key ->
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:
        (Ui.View.Body.static
           (Ui.View.keyboard_listener
              ~autofocus
              ~on_key
              (Ui.View.frame ~width:240. ~height:40. (Ui.View.text history)))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-keyboard-events")
    (App.create
       ~name:"Native Keyboard Events"
       (keyboard_events_component ~autofocus:false))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-keyboard-autofocus")
    (App.create
       ~name:"Native Keyboard Autofocus"
       (keyboard_events_component ~autofocus:true))
;;

let keyboard_nested_component ~handled handlers graph =
  let module Input = Bonsai_swiftui_spec.Id.Text_input in
  let history, set_history = Bonsai_v017.state ~equal:String.equal "" graph in
  let handler name =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_history
      ~f:(fun set_history -> function
      | Ui.Event.Payload.Key { logical_key; physical_key; action; modifiers } ->
        let action =
          match action with
          | Key_down -> "down"
          | Key_up -> "up"
          | Key_repeat -> "repeat"
        in
        let entry =
          Printf.sprintf
            "%s:%Ld:%Ld:%s:%d;"
            name
            (Bonsai_swiftui_spec.Id.Input.Logical_key.to_int64 logical_key)
            (Bonsai_swiftui_spec.Id.Input.Physical_key.to_int64 physical_key)
            action
            modifiers
        in
        set_history (fun history -> history ^ entry)
      | _ -> Bonsai.Effect.Ignore)
  in
  let ignore = Ui.Event.Handler.create (fun _ -> ()) in
  let value =
    Ui.Text_editing.Value.create
      ~text:"Draft"
      ~selection:(Ui.Text_editing.Range.create ~text:"Draft" ~start_utf16:0 ~end_utf16:5)
      ()
  in
  let field id =
    Ui.View.text_field
      ~label:("Field " ^ Int.to_string id)
      ~session_id:(Input.Session_id.of_int64 (Int64.of_int id))
      ~document_revision:(Input.Document_revision.of_int64 1L)
      ~accepted_local_revision:Input.Local_revision.zero
      ~update_mode:Ui.Text_editing.Force_replace
      ~value
      ~on_edit:ignore
      ~on_submit:ignore
      ~on_focus_changed:ignore
      ()
  in
  Bonsai.Cont.map2
    history
    (Bonsai.Cont.both (handler "outer") (handler "inner"))
    ~f:(fun history (outer, inner) ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.text ("Keys: " ^ history)
                ; Ui.View.keyboard_listener
                    ~on_key:outer
                    (Ui.View.column
                       [ Ui.View.keyboard_listener
                           ~key_policy:
                             (if handled then Ui.Event.Key_policy.Handled else Ignored)
                           ~on_key:inner
                           (field 1)
                       ; field 2
                       ])
                ; field 3
                ])))
;;

let () =
  List.iter
    (fun (name, handled) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name (keyboard_nested_component ~handled)))
    [ "native-keyboard-ignored", false; "native-keyboard-handled", true ]
;;

let civil_events_component handlers graph =
  let history, set_history = Bonsai_v017.state ~equal:String.equal "" graph in
  let handler name =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_history
      ~f:(fun set_history payload ->
        let entry =
          match payload with
          | Ui.Event.Payload.Civil_date { year; month; day } ->
            Some (Printf.sprintf "date:%04d-%02d-%02d;" year month day)
          | Ui.Event.Payload.Civil_time { hour; minute } ->
            Some (Printf.sprintf "time:%02d:%02d;" hour minute)
          | _ -> None
        in
        match entry with
        | Some entry -> set_history (fun history -> history ^ entry)
        | None -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2
    history
    (Bonsai.Cont.both (handler "civil-date") (handler "civil-time"))
    ~f:(fun history (on_select, on_changed) ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.Date_picker.create
                    ~selected:(Ui.View.Date.create ~year:2000 ~month:2 ~day:29)
                    ~first:(Ui.View.Date.create ~year:1 ~month:1 ~day:1)
                    ~last:(Ui.View.Date.create ~year:9999 ~month:12 ~day:31)
                    ~on_select
                    ()
                ; Ui.View.Time_picker.create
                    ~value:(Ui.View.Time.create ~hour:12 ~minute:0)
                    ~on_changed
                    ()
                ; Ui.View.text history
                ])))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-civil-events")
    (App.create ~name:"Native Civil Events" civil_events_component)
;;

let pointer_events_component handlers graph =
  let history, set_history = Bonsai_v017.state ~equal:String.equal "" graph in
  let handler name =
    Driver.Handler.create
      handlers
      ~name:("pointer-" ^ name)
      ~equal:( == )
      set_history
      ~f:(fun set_history -> function
      | Ui.Event.Payload.Pointer pointer ->
        let kind =
          match pointer.pointer_kind with
          | Mouse -> "mouse"
          | Touch -> "touch"
          | Stylus -> "stylus"
          | Inverted_stylus -> "inverted-stylus"
          | Trackpad -> "trackpad"
          | Unknown_pointer -> "unknown"
        in
        let entry =
          Printf.sprintf
            "%s:%Ld:%.3f:%.3f:%.3f:%.3f:%s:%d;"
            name
            (Bonsai_swiftui_spec.Id.Input.Pointer_id.to_int64 pointer.pointer_id)
            pointer.local_x
            pointer.local_y
            pointer.global_x
            pointer.global_y
            kind
            pointer.buttons
        in
        set_history (fun history -> history ^ entry)
      | _ -> Bonsai.Effect.Ignore)
  in
  let enter_leave = Bonsai.Cont.both (handler "enter") (handler "leave") in
  let down_up = Bonsai.Cont.both (handler "down") (handler "up") in
  Bonsai.Cont.map2
    history
    (Bonsai.Cont.both enter_leave down_up)
    ~f:(fun history ((on_enter, on_leave), (on_pointer_down, on_pointer_up)) ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.hover_region
                ~on_enter
                ~on_leave
                (Ui.View.gesture ~on_pointer_down ~on_pointer_up (Ui.View.text history)))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-pointer-events")
    (App.create ~name:"Native Pointer Events" pointer_events_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "host_navigation")
    Host_navigation.app
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "mail-collection")
    Mail.app
;;

let symbols_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-symbol"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let symbol =
      Ui.View.symbol
        ~name:(if selected then "star.fill" else "star")
        ~size:(if selected then 40. else 32.)
        ~color:
          (if selected
           then Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0
           else Ui.Style.Color.rgb ~red:0 ~green:0 ~blue:255)
        ~rendering:
          (if selected
           then Ui.View.Symbol_rendering.Hierarchical
           else Ui.View.Symbol_rendering.Monochrome)
        ()
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child:symbol ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "symbols")
    (App.create ~name:"Symbols" symbols_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-symbols")
    (App.create ~name:"Gallery Symbols" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.symbols_section ())))))
;;

let frames_component handlers graph =
  let flexible, set_flexible = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-frame"
      ~equal:( == )
      set_flexible
      ~f:(fun set_flexible -> function
      | Ui.Event.Payload.Unit -> set_flexible not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 flexible toggle ~f:(fun flexible toggle ->
    let symbol =
      Ui.View.symbol
        ~name:"star.fill"
        ~size:18.
        ~color:(Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0)
        ()
    in
    let body =
      if flexible
      then
        Ui.View.frame
          ~min_width:0.
          ~max_width:Ui.Layout.Frame_limit.Fill
          ~min_height:20.
          ~ideal_height:50.
          ~max_height:(Ui.Layout.Frame_limit.Points 90.)
          ~alignment:Bottom_end
          symbol
      else Ui.View.frame ~width:100. ~height:70. ~alignment:Top_start symbol
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child:body ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "frames")
    (App.create ~name:"Frames" frames_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-frames")
    (App.create ~name:"Gallery Frames" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.frames_section ())))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "spacers")
    (App.create ~name:"Spacers" (fun _ _ ->
       let symbol () =
         Ui.View.symbol
           ~name:"star.fill"
           ~size:18.
           ~color:(Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0)
           ()
       in
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:
              (Ui.View.Body.static
                 (Ui.View.row
                    [ symbol ()
                    ; Ui.View.frame ~width:100. (Ui.View.spacer ~min_length:0. ())
                    ; symbol ()
                    ])))))
;;

let modifiers_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-modifiers"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let body =
      Ui.View.symbol
        ~name:"star.fill"
        ~size:18.
        ~color:(Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0)
        ()
      |> Ui.View.padding
           ~insets:
             (Ui.Layout.Edge_insets.only
                ~leading:(if selected then 20. else 12.)
                ~top:(if selected then 4. else 8.)
                ~trailing:(if selected then 2. else 4.)
                ~bottom:(if selected then 8. else 6.)
                ())
      |> Ui.View.background
           ~corner_radius:(if selected then 4. else 8.)
           ~color:
             (if selected
              then Ui.Style.Color.rgb ~red:0 ~green:255 ~blue:0
              else Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160)
      |> Ui.View.clip
           ~corner_radius:(if selected then 6. else 10.)
           ~antialiased:(not selected)
      |> Ui.View.opacity (if selected then 0.4 else 0.7)
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child:body ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "modifiers")
    (App.create ~name:"Modifiers" modifiers_component)
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-modifiers")
    (App.create ~name:"Gallery Modifiers" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.modifiers_section ())))))
;;

let stacks_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-stacks"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let body =
      Ui.View.column
        ~alignment:(if selected then Ui.Layout.Horizontal_alignment.Trailing else Leading)
        ~spacing:(if selected then 16. else 4.)
        [ Ui.View.row
            ~alignment:
              (if selected then Ui.Layout.Vertical_alignment.Last_text_baseline else Top)
            ~spacing:(if selected then 20. else 4.)
            [ Ui.View.text "Primary content"
              |> Ui.View.layout_priority (if selected then 1. else 0.)
            ; Ui.View.text "Secondary content"
              |> Ui.View.offset
                   ~x:(if selected then -7. else 0.)
                   ~y:(if selected then 9. else 0.)
            ]
          |> Ui.View.frame ~width:150. ~height:60.
        ; Ui.View.stack
            ~alignment:(if selected then Bottom_end else Top_start)
            [ Ui.View.text "Two\nlines"
            ; Ui.View.symbol
                ~name:"star.fill"
                ~size:30.
                ~color:(Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0)
                ()
            ]
        ]
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child:body ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "stacks")
    (App.create ~name:"Stacks" stacks_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-stacks")
    (App.create ~name:"Gallery Stacks" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.stacks_section ())))))
;;

let weights_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-weights"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let block key color =
      Ui.View.spacer ~min_length:0. ()
      |> Ui.View.frame ~height:20.
      |> Ui.View.background ~key:(Ui.Key.string key) ~color
    in
    let red = block "red" (Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0) in
    let blue = block "blue" (Ui.Style.Color.rgb ~red:0 ~green:0 ~blue:255) in
    let items =
      if selected
      then
        [ Ui.View.Weighted.share ~weight:3. blue; Ui.View.Weighted.share ~weight:1. red ]
      else
        [ Ui.View.Weighted.share ~weight:1. red; Ui.View.Weighted.share ~weight:2. blue ]
    in
    let body =
      Ui.View.Weighted.row ~spacing:0. items |> Ui.View.frame ~width:300. ~height:20.
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child:body ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "weights")
    (App.create ~name:"Weights" weights_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-weights")
    (App.create ~name:"Gallery Weights" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.weights_section ())))))
;;

let overlays_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-overlays"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let block color width height =
      Ui.View.spacer ~min_length:0. ()
      |> Ui.View.frame ~width ~height
      |> Ui.View.background ~color
    in
    let base = block (Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0) 100. 60. in
    let overlay =
      block (Ui.Style.Color.rgb ~red:0 ~green:0 ~blue:255) 32. 16.
      |> Ui.View.padding
           ~insets:
             (Ui.Layout.Edge_insets.symmetric
                ~horizontal:(if selected then -4. else 4.)
                ~vertical:(if selected then -2. else 2.)
                ())
    in
    let body =
      Ui.View.overlay
        ~alignment:(if selected then Bottom_end else Top_start)
        ~overlay
        base
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child:body ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "overlays")
    (App.create ~name:"Overlays" overlays_component)
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-overlays")
    (App.create ~name:"Gallery Overlays" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.overlays_section ())))))
;;

let rich_text_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-rich-text"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let child =
      Ui.View.rich_text
        [ Ui.Style.Text_span.create (if selected then "Unread: " else "Read: ")
        ; Ui.Style.Text_span.create
            ~font_size:(if selected then 24. else 18.)
            ~font_weight:(if selected then Bold else Medium)
            ~color:
              (if selected
               then Ui.Style.Color.rgb ~red:0 ~green:0 ~blue:255
               else Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0)
            ~underline:selected
            (if selected then "世界 👩🏽‍💻" else "Hello")
        ]
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "rich-text")
    (App.create ~name:"Rich Text" rich_text_component)
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-rich-text")
    (App.create ~name:"Gallery Rich Text" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.rich_text_section ())))))
;;

let text_layout_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-text-layout"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let style =
      Ui.Style.Text_style.create
        ~font_size:(if selected then 20. else 16.)
        ~font_weight:(if selected then Bold else Medium)
        ~line_spacing:(if selected then 8. else 0.)
        ~color:
          (if selected
           then Ui.Style.Color.rgb ~red:0 ~green:0 ~blue:255
           else Ui.Style.Color.rgb ~red:255 ~green:0 ~blue:0)
        ()
    in
    let child =
      Ui.View.text
        ~style
        ~text_align:(if selected then End else Start)
        ~line_limit:(if selected then 2 else 3)
        ~truncation:(if selected then Middle else Tail)
        "First: a longer subject\nSecond: 世界 👩🏽‍💻\nLast: another longer line"
      |> Ui.View.frame ~width:180.
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "text-layout")
    (App.create ~name:"Text Layout" text_layout_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-text")
    (App.create ~name:"Gallery Text" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.text_section ())))))
;;

let images_component handlers graph =
  let selected, set_selected = Bonsai_v017.state ~equal:Bool.equal false graph in
  let toggle =
    Driver.Handler.create
      handlers
      ~name:"toggle-images"
      ~equal:( == )
      set_selected
      ~f:(fun set_selected -> function
      | Ui.Event.Payload.Unit -> set_selected not
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 selected toggle ~f:(fun selected toggle ->
    let child =
      Ui.View.image
        ~source:(Ui.Style.Image_source.resource "gallery-demo.png")
        ~sizing:(if selected then Fill else Fit)
        ~scale:(if selected then 2. else 1.)
        ()
      |> Ui.View.frame ~width:120. ~height:80.
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static (Ui.View.button ~on_press:toggle ~child ())))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "images")
    (App.create ~name:"Images" images_component)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-images")
    (App.create ~name:"Gallery Images" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.images_section ())))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery-dividers")
    (App.create ~name:"Gallery Dividers" (fun _ _ ->
       Bonsai.Cont.return
         (App.View.create
            ~theme:(Ui.Theme.create ())
            ~body:(Ui.View.Body.static (Gallery.dividers_section ())))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "text-session")
    (App.create ~name:"Text Session" (fun handlers graph ->
       Bonsai.Cont.map (Text_input_example.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-collection")
    (App.create ~name:"Native Collection" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.collection_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  List.iter
    (fun (name, horizontal) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name:"Measured Collection" (fun handlers graph ->
            Bonsai.Cont.map
              (Gallery.collection_component ~measured:true ~horizontal handlers graph)
              ~f:(fun body ->
                App.View.create
                  ~theme:(Ui.Theme.create ())
                  ~body:(Ui.View.Body.static body)))))
    [ "native-measured", false; "native-measured-horizontal", true ]
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-scroll")
    (App.create ~name:"Gallery Scroll" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.scroll_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-semantics")
    (App.create ~name:"Gallery Accessibility" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.semantics_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-progress")
    (App.create ~name:"Gallery Progress" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.progress_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-safe-area")
    (App.create ~name:"Gallery Safe Areas" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.safe_area_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-navigation")
    (App.create ~name:"Native Navigation" (fun handlers graph ->
       Bonsai.Cont.map (Navigation.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let navigation_paths_component ~accept handlers graph =
  let keys, set_keys = Bonsai_v017.state ~equal:( = ) [ "first"; "second" ] graph in
  let on_path_change =
    Driver.Handler.create
      handlers
      ~name:"navigation-path-request"
      ~equal:( == )
      set_keys
      ~f:(fun set_keys -> function
      | Ui.Event.Payload.Navigation_path_changed keys when accept ->
        let keys = List.map Bonsai_swiftui_spec.Id.Navigation.Page_key.to_string keys in
        set_keys (fun _ -> keys)
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 keys on_path_change ~f:(fun keys on_path_change ->
    let path =
      List.map
        (fun key ->
           Ui.View.Navigation_stack.destination
             ~page_key:(Bonsai_swiftui_spec.Id.Navigation.Page_key.of_string key)
             ~title:key
             (Ui.View.Body.static (Ui.View.text key)))
        keys
    in
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:
        (Ui.View.Body.static
           (Ui.View.Navigation_stack.create
              ~title:"Paths"
              ~on_path_change
              ~path
              (Ui.View.Body.static (Ui.View.text "Root")))))
;;

let () =
  List.iter
    (fun (name, accept) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name:"Navigation Paths" (navigation_paths_component ~accept)))
    [ "native-navigation-paths", true; "native-navigation-veto", false ]
;;

let () =
  List.iter
    (fun (name, two_columns) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name:"Gallery Split" (fun handlers graph ->
            Bonsai.Cont.map
              (Gallery.split_component ~two_columns handlers graph)
              ~f:(fun body ->
                App.View.create
                  ~theme:(Ui.Theme.create ())
                  ~body:(Ui.View.Body.static body)))))
    [ "native-split", false; "native-split-two-columns", true ]
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-tabs")
    (App.create ~name:"Gallery Tabs" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.tabs_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-swipe")
    (App.create ~name:"Gallery Swipe Actions" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.swipe_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-morph")
    (App.create ~name:"Gallery Morph" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.morph_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-toggle")
    (App.create ~name:"Gallery Toggles" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.toggle_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-slider")
    (App.create ~name:"Gallery Sliders" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.slider_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "clock")
    Clock.app
;;

let native_focus_scope_component handlers graph =
  let module Input = Bonsai_swiftui_spec.Id.Text_input in
  let history name =
    let value, set_value = Bonsai_v017.state ~equal:String.equal "" graph in
    let handler =
      Driver.Handler.create
        handlers
        ~name
        ~equal:( == )
        set_value
        ~f:(fun set_value -> function
        | Ui.Event.Payload.Bool focused ->
          set_value (fun previous -> previous ^ if focused then "+" else "-")
        | _ -> Bonsai.Effect.Ignore)
    in
    value, handler
  in
  let outer, outer_handler = history "outer-focus" in
  let inner, inner_handler = history "inner-focus" in
  let ignore = Ui.Event.Handler.create (fun _ -> ()) in
  let value =
    Ui.Text_editing.Value.create
      ~text:"Draft"
      ~selection:(Ui.Text_editing.Range.create ~text:"Draft" ~start_utf16:0 ~end_utf16:0)
      ()
  in
  let field id =
    Ui.View.text_field
      ~label:("Field " ^ Int.to_string id)
      ~session_id:(Input.Session_id.of_int64 (Int64.of_int id))
      ~document_revision:(Input.Document_revision.of_int64 1L)
      ~accepted_local_revision:Input.Local_revision.zero
      ~update_mode:Ui.Text_editing.Force_replace
      ~value
      ~on_edit:ignore
      ~on_submit:ignore
      ~on_focus_changed:ignore
      ()
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both outer inner)
    (Bonsai.Cont.both outer_handler inner_handler)
    ~f:(fun (outer, inner) (outer_handler, inner_handler) ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.text ("Outer: " ^ outer)
                ; Ui.View.text ("Inner: " ^ inner)
                ; Ui.View.focus_scope
                    ~on_focus_changed:outer_handler
                    (Ui.View.column
                       [ Ui.View.focus_scope
                           ~on_focus_changed:inner_handler
                           (Ui.View.column [ field 1; field 2 ])
                       ; field 3
                       ])
                ])))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-focus-scope")
    (App.create ~name:"Native Focus Scope" native_focus_scope_component)
;;

let native_field_component ~secure ~autofocus handlers graph =
  let module ID = Bonsai_swiftui_spec.Id in
  let text, set_text = Bonsai_v017.state ~equal:String.equal "Draft" graph in
  let revision, set_revision = Bonsai_v017.state ~equal:Int64.equal 0L graph in
  let submitted, set_submitted =
    Bonsai_v017.state ~equal:String.equal "Not submitted" graph
  in
  let edit =
    Driver.Handler.create
      handlers
      ~name:"native-field-edit"
      ~equal:( == )
      (Bonsai.Cont.both set_text set_revision)
      ~f:(fun (set_text, set_revision) -> function
      | Ui.Event.Payload.Text_edit edit ->
        Bonsai.Effect.Many
          [ set_text (fun _ -> edit.text)
          ; set_revision (fun _ ->
              ID.Text_input.Local_revision.to_int64 edit.local_revision)
          ]
      | _ -> Bonsai.Effect.Ignore)
  in
  let submit =
    Driver.Handler.create
      handlers
      ~name:"native-field-submit"
      ~equal:( == )
      set_submitted
      ~f:(fun set_submitted -> function
      | Ui.Event.Payload.Text text -> set_submitted (fun _ -> "Submitted: " ^ text)
      | _ -> Bonsai.Effect.Ignore)
  in
  let focus =
    Driver.Handler.create
      handlers
      ~name:"native-field-focus"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both text revision)
    (Bonsai.Cont.both submitted (Bonsai.Cont.both edit (Bonsai.Cont.both submit focus)))
    ~f:(fun (text, revision) (submitted, (edit, (submit, focus))) ->
      let length = Ui.Text_editing.Utf16.length text in
      let selection =
        Ui.Text_editing.Range.create ~text ~start_utf16:length ~end_utf16:length
      in
      let value = Ui.Text_editing.Value.create ~text ~selection () in
      let field =
        (if secure then Ui.View.secure_field else Ui.View.text_field)
          ~label:"Native field"
          ~autofocus
          ~session_id:(ID.Text_input.Session_id.of_int64 1L)
          ~document_revision:
            (ID.Text_input.Document_revision.of_int64 (Int64.succ revision))
          ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 revision)
          ~update_mode:(if revision = 0L then Ui.Text_editing.Force_replace else Ack)
          ~value
          ~submit_on_return:true
          ~max_utf8_bytes:64
          ~on_edit:edit
          ~on_submit:submit
          ~on_focus_changed:focus
          ()
      in
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ field; Ui.View.text ("Received: " ^ text); Ui.View.text submitted ])))
;;

let () =
  List.iter
    (fun (name, secure, autofocus) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name (native_field_component ~secure ~autofocus)))
    [ "native-field", false, false
    ; "native-secure-field", true, false
    ; "native-autofocus", false, true
    ]
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "todo")
    Todo.app
;;

let () = Network_fixture.register ()

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "sqlite_worker")
    Sqlite_worker_example.app
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "host_effects")
    Host_effects.app
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-picker")
    (App.create ~name:"Gallery Picker" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.picker_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-multiple-selection")
    (App.create ~name:"Gallery Multiple Selection" (fun handlers graph ->
       Bonsai.Cont.map
         (Gallery.multiple_selection_component handlers graph)
         ~f:(fun body ->
           App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-tags")
    (App.create ~name:"Gallery Tags" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.tag_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-buttons")
    (App.create ~name:"Gallery Buttons" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.button_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-projection")
    (App.create ~name:"Gallery Projection" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.projection_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-opacity")
    (App.create ~name:"Gallery Animated Opacity" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.opacity_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-workflow")
    (App.create ~name:"Gallery Workflow" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.workflow_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-disclosure")
    (App.create ~name:"Gallery Disclosure" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.disclosure_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-groups")
    (App.create ~name:"Gallery GroupBox" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.group_box_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-labels")
    (App.create ~name:"Gallery Label" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.label_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-badges")
    (App.create ~name:"Gallery Badge" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.badge_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-hover")
    (App.create ~name:"Gallery Hover" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.hover_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-civil-picker")
    (App.create ~name:"Native Civil Picker" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.civil_picker_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-menu")
    (App.create ~name:"Native Menu" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.menu_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-selection-catalog")
    (App.create ~name:"Native Selection Catalog" (fun handlers graph ->
       Bonsai.Cont.map (Selection_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-carousel")
    (App.create ~name:"Native Carousel" (fun handlers graph ->
       Bonsai.Cont.map (Carousel_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-help")
    (App.create ~name:"Native Help" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.help_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-popover")
    (App.create ~name:"Native Popover" (fun handlers graph ->
       Bonsai.Cont.map (Gallery.popover_component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-sheet")
    (App.create ~name:"Native Sheet" (fun handlers graph ->
       Bonsai.Cont.map (Sheet_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-page-layout")
    (App.create ~name:"Gallery Page Layout" (fun handlers graph ->
       Bonsai.Cont.map (Page_layout_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body)))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-sidebar")
    (App.create ~name:"Gallery Sidebar" (fun handlers graph ->
       Bonsai.Cont.map (Sidebar_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body)))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-toolbar")
    (App.create ~name:"Gallery Toolbar" (fun handlers graph ->
       Bonsai.Cont.map (Toolbar_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-app-bars")
    (App.create ~name:"Gallery App Bars" (fun handlers graph ->
       Bonsai.Cont.map (App_bar_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  List.iter
    (fun (name, horizontal) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name:"Gallery Sections" (fun handlers graph ->
            Bonsai.Cont.map
              (Scroll_sections_catalog.component ~horizontal handlers graph)
              ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
    [ "native-sections", false; "native-sections-horizontal", true ]
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-collection-horizontal")
    (App.create ~name:"Horizontal Collection" (fun handlers graph ->
       Bonsai.Cont.map
         (Gallery.collection_component ~horizontal:true handlers graph)
         ~f:(fun body ->
           App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  List.iter
    (fun kind ->
       List.iter
         (fun horizontal ->
            let name =
              Printf.sprintf
                "native-scroll-observer-%d-%s"
                kind
                (if horizontal then "h" else "v")
            in
            Native_backend.embed
              ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
              (App.create ~name:"Gallery Scroll Observers" (fun handlers graph ->
                 Bonsai.Cont.map
                   (Scroll_observer_catalog.component ~kind ~horizontal handlers graph)
                   ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
         [ false; true ])
    [ 0; 1; 2; 3 ]
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-scroll-observer-nested")
    (App.create ~name:"Nested Scroll Observers" (fun handlers graph ->
       Bonsai.Cont.map
         (Scroll_observer_catalog.nested_component handlers graph)
         ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body)))
;;

let () =
  List.iter
    (fun (name, horizontal) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create ~name:"Gallery Scroll Fill" (fun handlers graph ->
            Bonsai.Cont.map
              (Scroll_fill_catalog.component ~horizontal handlers graph)
              ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
    [ "native-scroll-fill", false; "native-scroll-fill-horizontal", true ]
;;

let () =
  List.iter
    (fun kind ->
       List.iter
         (fun horizontal ->
            List.iter
              (fun initial ->
                 let name =
                   Printf.sprintf
                     "native-initial-%d-%s-%d"
                     kind
                     (if horizontal then "h" else "v")
                     initial
                 in
                 Native_backend.embed
                   ~name:
                     (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
                   (App.create ~name:"Gallery Initial Scroll" (fun handlers graph ->
                      Bonsai.Cont.map
                        (Initial_scroll_catalog.component
                           ~kind
                           ~horizontal
                           ~initial
                           handlers
                           graph)
                        ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
              (if kind = 2 then [ 0; 1; 2 ] else [ 0; 1 ]))
         [ false; true ])
    [ 0; 1; 2 ]
;;

let () =
  List.iter
    (fun kind ->
       Native_backend.embed
         ~name:
           (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
              (Printf.sprintf "native-refresh-%d" kind))
         (App.create ~name:"Gallery Refresh" (fun handlers graph ->
            Bonsai.Cont.map
              (Refresh_catalog.component ~kind handlers graph)
              ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
    [ 0; 1; 2; 3 ]
;;

let () =
  List.iter
    (fun vertical ->
       Native_backend.embed
         ~name:
           (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
              (if vertical then "native-removal-v" else "native-removal-h"))
         (App.create ~name:"Gallery Removal" (fun handlers graph ->
            Bonsai.Cont.map
              (Removal_catalog.component ~vertical handlers graph)
              ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
    [ false; true ]
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-contextual-selection")
    (App.create ~name:"Gallery Contextual Selection" (fun handlers graph ->
       Bonsai.Cont.map
         (Contextual_selection_catalog.component handlers graph)
         ~f:(fun body ->
           App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  List.iter
    (fun presentation ->
       Native_backend.embed
         ~name:
           (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
              (Printf.sprintf "native-search-%d" presentation))
         (App.create ~name:"Gallery Search" (fun handlers graph ->
            Bonsai.Cont.map
              (Search_catalog.component ~presentation handlers graph)
              ~f:(fun body ->
                App.View.create
                  ~theme:(Ui.Theme.create ())
                  ~body:(Ui.View.Body.static body)))))
    [ 0; 1; 2 ]
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-table")
    (App.create ~name:"Gallery Table" (fun handlers graph ->
       Bonsai.Cont.map (Table_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  List.iter
    (fun horizontal ->
       Native_backend.embed
         ~name:
           (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
              (if horizontal then "native-mixed-h" else "native-mixed-v"))
         (App.create ~name:"Gallery Mixed Collection" (fun handlers graph ->
            Bonsai.Cont.map
              (Mixed_collection_catalog.component ~horizontal handlers graph)
              ~f:(fun body -> App.View.create ~theme:(Ui.Theme.create ()) ~body))))
    [ false; true ]
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-view")
    (App.create ~name:"Gallery Native View" (fun handlers graph ->
       Bonsai.Cont.map (Native_view_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-view-nested")
    (App.create ~name:"Gallery Nested Native Views" (fun handlers graph ->
       Bonsai.Cont.map
         (Native_view_catalog.component ~nested:8 handlers graph)
         ~f:(fun body ->
           App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-composer")
    (App.create ~name:"Gallery Composer" (fun handlers graph ->
       Bonsai.Cont.map (Composer_catalog.component handlers graph) ~f:(fun body ->
         App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-composer-focus")
    (App.create ~name:"Gallery Composer Focus" (fun handlers graph ->
       Bonsai.Cont.map
         (Composer_catalog.component ~autofocus:true handlers graph)
         ~f:(fun body ->
           App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-expandable-composer")
    (App.create ~name:"Gallery Expandable Composer" (fun handlers graph ->
       Bonsai.Cont.map
         (Expandable_composer_catalog.component handlers graph)
         ~f:(fun body ->
           App.View.create ~theme:(Ui.Theme.create ()) ~body:(Ui.View.Body.static body))))
;;

let gesture_events_component handlers graph =
  let history, set_history = Bonsai_v017.state ~equal:String.equal "" graph in
  let handler name =
    Driver.Handler.create
      handlers
      ~name:("gesture-" ^ name)
      ~equal:( == )
      set_history
      ~f:(fun set_history payload ->
        let entry =
          match payload with
          | Ui.Event.Payload.Tap tap ->
            let kind =
              match tap.pointer_kind with
              | Mouse -> "mouse"
              | Touch -> "touch"
              | Stylus -> "stylus"
              | Inverted_stylus -> "inverted-stylus"
              | Trackpad -> "trackpad"
              | Unknown_pointer -> "unknown"
            in
            Printf.sprintf
              "%s:%.3f:%.3f:%.3f:%.3f:%s;"
              name
              tap.local_x
              tap.local_y
              tap.global_x
              tap.global_y
              kind
          | Unit when name = "long" -> "long;"
          | _ -> "Unexpected payload;"
        in
        set_history (fun history -> history ^ entry))
  in
  Bonsai.Cont.map2
    history
    (Bonsai.Cont.both
       (handler "tap")
       (Bonsai.Cont.both (handler "double") (handler "long")))
    ~f:(fun history (on_tap, (on_double_tap, on_long_press)) ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.gesture
                ~on_tap
                ~on_double_tap
                ~on_long_press
                (Ui.View.text history))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-gesture-events")
    (App.create ~name:"Native Gesture Events" gesture_events_component)
;;

let gesture_window_component ?(hover = false) ~multiple handlers graph =
  let history, set_history = Bonsai_v017.state ~equal:String.equal "Events:" graph in
  let version, set_version = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let visible, set_visible = Bonsai_v017.state ~equal:Bool.equal true graph in
  let handler name =
    Driver.Handler.create
      handlers
      ~name:("gesture-window-" ^ name)
      ~equal:(fun (a, _) (b, _) -> Int.equal a b)
      (Bonsai.Cont.both version set_history)
      ~f:(fun (version, set_history) payload ->
        let entry =
          match payload with
          | Ui.Event.Payload.Tap tap ->
            Printf.sprintf
              "%s-%d:%.3f:%.3f:%.3f:%.3f:%s;"
              name
              version
              tap.local_x
              tap.local_y
              tap.global_x
              tap.global_y
              (match tap.pointer_kind with
               | Mouse -> "mouse"
               | Stylus -> "stylus"
               | Inverted_stylus -> "inverted-stylus"
               | Unknown_pointer -> "unknown"
               | _ -> "other")
          | Pointer pointer ->
            Printf.sprintf
              "%s-%d:%Ld:%.3f:%.3f:%.3f:%.3f:%s:%d;"
              name
              version
              (Bonsai_swiftui_spec.Id.Input.Pointer_id.to_int64 pointer.pointer_id)
              pointer.local_x
              pointer.local_y
              pointer.global_x
              pointer.global_y
              (match pointer.pointer_kind with
               | Mouse -> "mouse"
               | Stylus -> "stylus"
               | Inverted_stylus -> "inverted-stylus"
               | Unknown_pointer -> "unknown"
               | _ -> "other")
              pointer.buttons
          | Unit -> Printf.sprintf "%s-%d;" name version
          | _ -> "Unexpected payload;"
        in
        set_history (fun history -> history ^ entry))
  in
  let change name state f =
    Driver.Handler.create handlers ~name ~equal:( == ) state ~f:(fun set_state _ ->
      set_state f)
  in
  let enter = handler "enter" in
  let leave = handler "leave" in
  let tap = handler "tap" in
  let double = handler "double" in
  let long = handler "long" in
  let down = handler "down" in
  let up = handler "up" in
  let nested = handler "nested" in
  let replace = change "replace-gesture-handler" set_version Int.succ in
  let remove = change "remove-gesture-target" set_visible not in
  let both = Bonsai.Cont.both in
  Bonsai.Cont.map2
    (both (both history visible) (both enter leave))
    (both
       (both tap double)
       (both (both long down) (both (both up nested) (both replace remove))))
    ~f:
      (fun
        ((history, visible), (enter, leave))
        ((tap, double), ((long, down), ((up, nested), (replace, remove)))) ->
      let button label on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text label) ()
      in
      let target =
        Ui.View.column
          ~spacing:0.
          [ Ui.View.text "Gesture target" |> Ui.View.frame ~width:320. ~height:120.
          ; button "Nested action" nested |> Ui.View.frame ~width:320. ~height:60.
          ]
        |> Ui.View.background ~color:(Ui.Style.Color.rgb ~red:210 ~green:230 ~blue:250)
        |> Ui.View.gesture
             ~key:(Ui.Key.string "gesture-target")
             ~on_tap:tap
             ?on_double_tap:(if multiple then Some double else None)
             ?on_long_press:(if multiple then Some long else None)
             ?on_pointer_down:(if multiple then Some down else None)
             ?on_pointer_up:(if multiple then Some up else None)
      in
      let target =
        if hover
        then Ui.View.hover_region ~on_enter:enter ~on_leave:leave target
        else target
      in
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                ~spacing:10.
                [ (if visible
                   then target
                   else
                     Ui.View.text "Target removed"
                     |> Ui.View.frame ~width:320. ~height:180.)
                ; Ui.View.row
                    [ button "Replace handler" replace; button "Remove target" remove ]
                ; Ui.View.text history |> Ui.View.frame ~width:400. ~height:60.
                ])))
;;

let () =
  List.iter
    (fun (name, multiple, hover) ->
       Native_backend.embed
         ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string name)
         (App.create
            ~name:"Native Gesture Window"
            (gesture_window_component ~hover ~multiple)))
    [ "native-gesture-window", true, false
    ; "native-gesture-window-single", false, false
    ; "native-gesture-window-pointer", true, true
    ]
;;

let application_bridge_component handlers graph =
  let module Platform = Host_effect.Application_platform in
  let platform = Driver.Handler.application_platform handlers in
  let history, set_history = Bonsai_v017.state ~equal:String.equal "" graph in
  let cancellation = Platform.Cancellation.create () in
  let describe bytes =
    Printf.sprintf "%d:%s" (Bytes.length bytes) (Digest.to_hex (Digest.bytes bytes))
  in
  let append set_history entry = set_history (fun history -> history ^ entry ^ ";") in
  let on_activate =
    Bonsai.Cont.map set_history ~f:(fun set_history ->
      Bonsai.Effect.of_thunk (fun () ->
        Platform.on_event platform (fun bytes ->
          append set_history ("event:" ^ describe bytes))))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate graph;
  let request ?cancellation label bytes =
    Driver.Handler.create
      handlers
      ~name:("application-" ^ label)
      ~equal:( == )
      set_history
      ~f:(fun set_history _ ->
        Bonsai.Effect.bind
          (Platform.request ?cancellation platform bytes)
          ~f:(fun result ->
            let result =
              match result with
              | Ok bytes -> "ok:" ^ describe bytes
              | Error Unavailable -> "unavailable"
              | Error Payload_too_large -> "payload-too-large"
              | Error (Handler_failed message) ->
                "handler-failed:" ^ describe (Bytes.of_string message)
              | Error Cancelled -> "cancelled"
              | Error Shutdown -> "shutdown"
              | Error Runtime_replaced -> "runtime-replaced"
              | Error (Invalid_response message) ->
                "invalid-response:" ^ describe (Bytes.of_string message)
            in
            append set_history (label ^ ":" ^ result)))
  in
  let first = request ~cancellation "First" (Bytes.of_string "\000one\255") in
  let second = request "Second" (Bytes.of_string "\128two\000") in
  let large = request "Large" (Bytes.make Platform.maximum_payload_bytes '\255') in
  let overflow =
    request "Overflow" (Bytes.make (Platform.maximum_payload_bytes + 1) '\255')
  in
  let cancel =
    Driver.Handler.create
      handlers
      ~name:"application-cancel"
      ~equal:( == )
      (Bonsai.Cont.return ())
      ~f:(fun () _ ->
        Bonsai.Effect.of_thunk (fun () -> Platform.Cancellation.cancel cancellation))
  in
  let increment =
    Driver.Handler.create
      handlers
      ~name:"application-increment"
      ~equal:( == )
      set_history
      ~f:(fun set_history _ -> append set_history "increment")
  in
  Bonsai.Cont.map2
    history
    (Bonsai.Cont.both
       (Bonsai.Cont.both first second)
       (Bonsai.Cont.both
          (Bonsai.Cont.both large overflow)
          (Bonsai.Cont.both cancel increment)))
    ~f:(fun history ((first, second), ((large, overflow), (cancel, increment))) ->
      let button label on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text label) ()
      in
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.text history
                ; button "First" first
                ; button "Second" second
                ; button "Large" large
                ; button "Overflow" overflow
                ; button "Cancel" cancel
                ; button "Increment" increment
                ])))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-application-bridge")
    (App.create ~name:"Application Bridge" application_bridge_component)
;;

let file_results_component ?(export = false) handlers graph =
  let host = Driver.Handler.host_effects handlers in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Files idle" graph in
  let describe (file : Host_effect.file) =
    let path =
      match file.path with
      | None -> "none"
      | Some path -> path
    in
    let data =
      match file.data with
      | None -> "none"
      | Some bytes ->
        Printf.sprintf "%d:%s" (Bytes.length bytes) (Digest.to_hex (Digest.bytes bytes))
    in
    path ^ ":" ^ data
  in
  let on_press =
    Driver.Handler.create
      handlers
      ~name:"file-import"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind
          (if export
           then
             Bonsai.Effect.map
               (Host_effect.save_file
                  host
                  ~suggested_name:"Opaque.bin"
                  ~data:(Bytes.of_string "\000\255\128")
                  ())
               ~f:
                 (Result.map (function
                    | None -> []
                    | Some file -> [ file ]))
           else
             Host_effect.pick_files
               ~allow_multiple:true
               ~allowed_extensions:[ "txt"; "bin" ]
               host
               ())
          ~f:(fun result ->
            set_status (fun _ ->
              match result with
              | Ok files -> "Files: " ^ String.concat "|" (List.map describe files)
              | Error (Invalid_response _) -> "Files: invalid response"
              | Error _ -> "Files: error")))
  in
  Bonsai.Cont.map2 status on_press ~f:(fun status on_press ->
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:
        (Ui.View.Body.static
           (Ui.View.column
              [ Ui.View.text status
              ; Ui.View.button
                  ~on_press
                  ~child:(Ui.View.text (if export then "Export file" else "Import files"))
                  ()
              ])))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-file-results")
    (App.create ~name:"File Results" file_results_component)
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-file-export")
    (App.create ~name:"File Export" (file_results_component ~export:true))
;;

let node_services_component handlers graph =
  let module Platform = Host_effect.Application_platform in
  let module Input = Bonsai_swiftui_spec.Id.Text_input in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Nodes idle" graph in
  let visible, set_visible = Bonsai_v017.state ~equal:Bool.equal true graph in
  let host = Driver.Handler.host_effects handlers in
  let platform = Driver.Handler.application_platform handlers in
  let on_activate =
    Bonsai.Cont.map2 set_status set_visible ~f:(fun set_status set_visible ->
      Bonsai.Effect.of_thunk (fun () ->
        Platform.on_event platform (fun bytes ->
          let command = Bytes.to_string bytes in
          let report result =
            set_status (fun previous -> previous ^ "Nodes: " ^ result ^ ";")
          in
          let unit_result = function
            | Ok () -> "ok"
            | Error _ -> "error"
          in
          match String.split_on_char ':' command with
          | [ "remove" ] -> set_visible (fun _ -> false)
          | [ "clear" ] ->
            Bonsai.Effect.bind (Host_effect.clear_focus host ()) ~f:(fun r ->
              report (unit_result r))
          | [ operation; target ] ->
            let node_id =
              Bonsai_swiftui_spec.Id.Ui.Node_id.of_int64 (Int64.of_string target)
            in
            (match operation with
             | "focus" ->
               Bonsai.Effect.bind (Host_effect.request_focus host ~node_id) ~f:(fun r ->
                 report (unit_result r))
             | "measure" ->
               Bonsai.Effect.bind (Host_effect.measure_layout host ~node_id) ~f:(function
                 | Ok layout ->
                   report
                     (Printf.sprintf
                        "%.3f,%.3f,%.3f,%.3f"
                        layout.left
                        layout.top
                        layout.width
                        layout.height)
                 | Error _ -> report "error")
             | _ -> Bonsai.Effect.Ignore)
          | _ -> Bonsai.Effect.Ignore)))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate graph;
  let ignore = Ui.Event.Handler.create (fun _ -> ()) in
  let value =
    Ui.Text_editing.Value.create
      ~text:"Draft"
      ~selection:(Ui.Text_editing.Range.create ~text:"Draft" ~start_utf16:0 ~end_utf16:0)
      ()
  in
  let field ~secure ~enabled id =
    (if secure then Ui.View.secure_field else Ui.View.text_field)
      ~label:(if secure then "Secure" else if enabled then "Plain" else "Disabled")
      ~enabled
      ~session_id:(Input.Session_id.of_int64 id)
      ~document_revision:(Input.Document_revision.of_int64 1L)
      ~accepted_local_revision:Input.Local_revision.zero
      ~update_mode:Ui.Text_editing.Force_replace
      ~value
      ~on_edit:ignore
      ~on_submit:ignore
      ~on_focus_changed:ignore
      ()
  in
  Bonsai.Cont.map2 status visible ~f:(fun status visible ->
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:
        (Ui.View.Body.static
           (Ui.View.column
              ~spacing:8.
              ([ Ui.View.text ~line_limit:1 status
                 |> Ui.View.frame ~width:300. ~height:20.
               ]
               @
               if visible
               then
                 [ field ~secure:false ~enabled:true 1L
                 ; field ~secure:true ~enabled:true 2L
                 ; field ~secure:false ~enabled:false 3L
                 ; Ui.View.text_editor
                     ~session_id:(Input.Session_id.of_int64 4L)
                     ~document_revision:(Input.Document_revision.of_int64 1L)
                     ~accepted_local_revision:Input.Local_revision.zero
                     ~update_mode:Ui.Text_editing.Force_replace
                     ~value
                     ~on_edit:ignore
                     ~on_submit:ignore
                     ~on_focus_changed:ignore
                     ()
                   |> Ui.View.frame ~height:50.
                 ; Ui.View.text "Measured" |> Ui.View.frame ~width:120. ~height:40.
                 ]
               else []))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-node-services")
    (App.create ~name:"Node Services" node_services_component)
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-environment")
    (App.create ~name:"Native Environment" (fun context _graph ->
       Bonsai.Cont.map (App.Context.environment context) ~f:(fun env ->
         let insets (value : Environment.edge_insets) =
           Printf.sprintf "%g,%g,%g,%g" value.left value.top value.right value.bottom
         in
         let text =
           Printf.sprintf
             "width=%g|height=%g|scale=%g|text=%g|brightness=%s|platform=%s|locale=%s|safe=%s|keyboard=%s|voiceover=%b|bold=%b|invert=%b|animations=%b|motion=%b|contrast=%b|orientation=%s|pointers=%d"
             env.viewport_width
             env.viewport_height
             env.device_pixel_ratio
             env.text_scale
             (match env.brightness with
              | Light -> "light"
              | Dark -> "dark")
             env.platform
             env.locale
             (insets env.safe_area)
             (insets env.keyboard_insets)
             env.accessible_navigation
             env.bold_text
             env.invert_colors
             env.disable_animations
             env.reduced_motion
             env.high_contrast
             (match env.orientation with
              | Portrait -> "portrait"
              | Landscape -> "landscape")
             env.pointer_kinds
         in
         App.View.create
           ~theme:(Ui.Theme.create ())
           ~body:(Ui.View.Body.static (Ui.View.text text)))))
;;

let native_button_focus_component handlers graph =
  let model, set_model = Bonsai_v017.state ~equal:( = ) (0, true, true, true, 0) graph in
  let command name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_model ~f:(fun set_model _ ->
      set_model update)
  in
  let toggle_enabled = command "enable" (fun (n, e, a, s, g) -> n, not e, a, s, g) in
  let toggle_autofocus = command "autofocus" (fun (n, e, a, s, g) -> n, e, not a, s, g) in
  let toggle_visible = command "visible" (fun (n, e, a, s, g) -> n, e, a, not s, g) in
  let rebind = command "rebind" (fun (n, e, a, s, g) -> n, e, a, s, g + 1) in
  let press =
    Driver.Handler.create
      handlers
      ~name:"focus-action"
      ~equal:(fun (left, a) (right, b) -> left == right && a = b)
      (Bonsai.Cont.both set_model (Bonsai.Cont.map model ~f:(fun (_, _, _, _, g) -> g)))
      ~f:(fun (set_model, generation) _ ->
        set_model (fun (n, e, a, s, g) ->
          (n + if generation = 0 then 1 else 10), e, a, s, g))
  in
  let bindings =
    Bonsai.Cont.both
      (Bonsai.Cont.both press toggle_enabled)
      (Bonsai.Cont.both toggle_autofocus (Bonsai.Cont.both toggle_visible rebind))
  in
  Bonsai.Cont.map2
    model
    bindings
    ~f:
      (fun
        (count, enabled, autofocus, visible, _)
        ((press, toggle_enabled), (toggle_autofocus, (toggle_visible, rebind)))
      ->
      let command label handler =
        Ui.View.button ~on_press:handler ~child:(Ui.View.text label) ()
      in
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                ([ Ui.View.text (Printf.sprintf "Actions: %d" count) ]
                 @ (if visible
                    then
                      [ Ui.View.button
                          ~key:(Ui.Key.string "focus-target")
                          ~autofocus
                          ~enabled
                          ~on_press:press
                          ~child:(Ui.View.text "Focused action")
                          ()
                      ]
                    else [])
                 @ [ command "Toggle enabled" toggle_enabled
                   ; command "Toggle autofocus" toggle_autofocus
                   ; command "Toggle visible" toggle_visible
                   ; command "Replace handler" rebind
                   ]))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-button-focus")
    (App.create ~name:"Native Button Focus" native_button_focus_component)
;;

let scroll_services_component ~kind ~horizontal handlers graph =
  let module Platform = Host_effect.Application_platform in
  let status, set_status =
    Bonsai_v017.state ~equal:String.equal "Scroll service:" graph
  in
  let visible, set_visible = Bonsai_v017.state ~equal:Bool.equal true graph in
  let current = ref None in
  let host = Driver.Handler.host_effects handlers in
  let platform = Driver.Handler.application_platform handlers in
  let activate =
    Bonsai.Cont.map2 set_status set_visible ~f:(fun set_status set_visible ->
      Bonsai.Effect.of_thunk (fun () ->
        Platform.on_event platform (fun bytes ->
          match String.split_on_char ':' (Bytes.to_string bytes) with
          | [ "remove" ] -> set_visible (fun _ -> false)
          | [ "restore" ] -> set_visible (fun _ -> true)
          | [ "cancel" ] ->
            Bonsai.Effect.of_thunk (fun () ->
              Option.iter Host_effect.Cancellation.cancel !current)
          | [ operation; target; alignment; animated ]
            when operation = "scroll" || operation = "cancelled" ->
            let cancellation = Host_effect.Cancellation.create () in
            current := Some cancellation;
            if operation = "cancelled" then Host_effect.Cancellation.cancel cancellation;
            let node_id =
              Bonsai_swiftui_spec.Id.Ui.Node_id.of_int64 (Int64.of_string target)
            in
            Bonsai.Effect.bind
              (Host_effect.scroll_to
                 ~cancellation
                 ~alignment:(float_of_string alignment)
                 ~animated:(bool_of_string animated)
                 host
                 ~node_id)
              ~f:(fun result ->
                let label =
                  match result with
                  | Ok () -> "ok"
                  | Error Host_effect.Cancelled -> "cancelled"
                  | Error _ -> "error"
                in
                set_status (fun previous -> previous ^ label ^ ";"))
          | _ -> Bonsai.Effect.Ignore)))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate:activate graph;
  let body =
    if kind = 4
    then
      Bonsai.Cont.return
        (Ui.View.Body.Vertical.create
           [ Ui.View.Body.Vertical.fill
               (Ui.View.Scroll.vertical (Ui.View.text "Short content"))
           ])
    else Scroll_observer_catalog.component ~kind ~horizontal handlers graph
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both status visible)
    body
    ~f:(fun (status, visible) body ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.text status
                ; (if visible
                   then Ui.View.Body.with_size ~width:640. ~height:480. body
                   else Ui.View.text "Removed scroll")
                ])))
;;

let () =
  List.iter
    (fun kind ->
       List.iter
         (fun horizontal ->
            Native_backend.embed
              ~name:
                (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
                   (Printf.sprintf
                      "native-scroll-service-%d-%s"
                      kind
                      (if horizontal then "h" else "v")))
              (App.create
                 ~name:"Native Scroll Service"
                 (scroll_services_component ~kind ~horizontal)))
         [ false; true ])
    [ 0; 1; 2; 3; 4 ]
;;

let notice_service_component ~automatic handlers graph =
  let module Platform = Host_effect.Application_platform in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Notices:" graph in
  let host = Driver.Handler.host_effects handlers in
  let platform = Driver.Handler.application_platform handlers in
  let cancellations = Hashtbl.create 8 in
  let activate =
    Bonsai.Cont.map set_status ~f:(fun set_status ->
      let show message duration_ms action_label =
        let cancellation = Host_effect.Cancellation.create () in
        Hashtbl.replace cancellations message cancellation;
        Bonsai.Effect.bind
          (Host_effect.show_notice
             ~cancellation
             ?action_label
             ~duration_ms
             host
             ~message
             ())
          ~f:(fun result ->
            let reason =
              match result with
              | Ok Host_effect.Action -> "action"
              | Ok Host_effect.Dismiss -> "dismiss"
              | Ok Host_effect.Swipe -> "swipe"
              | Ok Host_effect.Timeout -> "timeout"
              | Error Host_effect.Cancelled -> "cancelled"
              | Error _ -> "error"
            in
            set_status (fun previous -> previous ^ message ^ "=" ^ reason ^ ";"))
      in
      Bonsai.Effect.Many
        [ Bonsai.Effect.of_thunk (fun () ->
            Platform.on_event platform (fun bytes ->
              match String.split_on_char ':' (Bytes.to_string bytes) with
              | [ "show"; message; duration; action ] ->
                show
                  message
                  (int_of_string duration)
                  (if action = "-" then None else Some action)
              | [ "cancel"; message ] ->
                Bonsai.Effect.of_thunk (fun () ->
                  Option.iter
                    Host_effect.Cancellation.cancel
                    (Hashtbl.find_opt cancellations message))
              | _ -> Bonsai.Effect.Ignore))
        ; (if automatic
           then show "Startup notice" 1000 (Some "Continue")
           else Bonsai.Effect.Ignore)
        ])
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate:activate graph;
  Bonsai.Cont.map status ~f:(fun status ->
    App.View.create
      ~theme:(Ui.Theme.create ())
      ~body:
        (Ui.View.Body.static
           (Ui.View.column [ Ui.View.text status; Ui.View.text "Notification content" ])))
;;

let () =
  List.iter
    (fun automatic ->
       Native_backend.embed
         ~name:
           (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
              (if automatic then "native-notice-auto" else "native-notice"))
         (App.create ~name:"Native Notifications" (notice_service_component ~automatic)))
    [ false; true ]
;;

let menu_service_component handlers graph =
  let module Platform = Host_effect.Application_platform in
  let module ID = Bonsai_swiftui_spec.Id in
  let host = Driver.Handler.host_effects handlers in
  let platform = Driver.Handler.application_platform handlers in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Menus:" graph in
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let cancellations = Hashtbl.create 8 in
  let show set_status tag mode =
    let cancellation = Host_effect.Cancellation.create () in
    Hashtbl.replace cancellations tag cancellation;
    let item id label enabled : Host_effect.native_menu_item =
      { item_id = ID.Host.Native_menu_item_id.of_string id; label; enabled }
    in
    let items =
      if mode = "large"
      then
        List.init 128 (fun index ->
          let id = string_of_int (index + 1) in
          item id ("Action " ^ id) true)
      else if mode = "unicode"
      then [ item "é" "Composed ID" false; item "é" "Decomposed ID" true ]
      else
        [ item "open" "Open document" (mode <> "disabled")
        ; item "disabled" "Unavailable action" false
        ; item "保存😀" "Save copy 😀" (mode <> "disabled")
        ]
    in
    Bonsai.Effect.bind
      (Host_effect.show_native_menu ~cancellation host items)
      ~f:(fun result ->
        let value =
          match result with
          | Ok None -> "dismissed"
          | Ok (Some id) -> ID.Host.Native_menu_item_id.to_string id
          | Error Host_effect.Cancelled -> "cancelled"
          | Error _ -> "error"
        in
        set_status (fun prior -> prior ^ tag ^ "=" ^ value ^ ";"))
  in
  let activate =
    Bonsai.Cont.map set_status ~f:(fun set_status ->
      Bonsai.Effect.of_thunk (fun () ->
        Platform.on_event platform (fun bytes ->
          match String.split_on_char ':' (Bytes.to_string bytes) with
          | [ "show"; tag; mode ] -> show set_status tag mode
          | [ "file"; tag ] ->
            let cancellation = Host_effect.Cancellation.create () in
            Hashtbl.replace cancellations tag cancellation;
            Bonsai.Effect.bind
              (Host_effect.pick_files ~cancellation host ())
              ~f:(fun result ->
                let value =
                  match result with
                  | Ok _ -> "files"
                  | Error Host_effect.Cancelled -> "cancelled"
                  | Error _ -> "error"
                in
                set_status (fun prior -> prior ^ tag ^ "=" ^ value ^ ";"))
          | [ "cancel"; tag ] ->
            Bonsai.Effect.of_thunk (fun () ->
              Option.iter
                Host_effect.Cancellation.cancel
                (Hashtbl.find_opt cancellations tag))
          | _ -> Bonsai.Effect.Ignore)))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate:activate graph;
  let open_menu =
    Driver.Handler.create
      handlers
      ~name:"show-action-menu"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ -> show set_status "button" "regular")
  in
  let background =
    Driver.Handler.create
      handlers
      ~name:"menu-background-action"
      ~equal:( == )
      set_count
      ~f:(fun set_count _ -> set_count (fun value -> value + 1))
  in
  Bonsai.Cont.map3
    (Bonsai.Cont.both status count)
    open_menu
    background
    ~f:(fun (status, count) open_menu background ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.text status
                ; Ui.View.text (Printf.sprintf "Background: %d" count)
                ; Ui.View.button
                    ~on_press:open_menu
                    ~child:(Ui.View.text "Show action menu")
                    ()
                ; Ui.View.button
                    ~on_press:background
                    ~child:(Ui.View.text "Background action")
                    ()
                ])))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "native-menu-service")
    (App.create ~name:"Native Menu Service" menu_service_component)
;;

let haptic_service_component handlers graph =
  let host = Driver.Handler.host_effects handlers in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Haptics:" graph in
  let perform set_status tag kind ?cancellation () =
    Bonsai.Effect.bind
      (Host_effect.haptic_feedback ?cancellation host kind)
      ~f:(fun result ->
        let result =
          match result with
          | Ok () -> "ok"
          | Error Host_effect.Cancelled -> "cancelled"
          | Error _ -> "error"
        in
        set_status (fun previous -> previous ^ tag ^ "=" ^ result ^ ";"))
  in
  let button tag perform_request =
    Driver.Handler.create
      handlers
      ~name:("haptic-" ^ tag)
      ~equal:( == )
      set_status
      ~f:(fun set_status _ -> perform_request set_status)
    |> Bonsai.Cont.map ~f:(fun handler ->
      Ui.View.button ~on_press:handler ~child:(Ui.View.text tag) ())
  in
  let kinds =
    [ "light", Host_effect.Haptic_light
    ; "medium", Host_effect.Haptic_medium
    ; "heavy", Host_effect.Haptic_heavy
    ; "selection", Host_effect.Haptic_selection
    ]
  in
  let buttons =
    List.map
      (fun (tag, kind) -> button tag (fun set_status -> perform set_status tag kind ()))
      kinds
  in
  let cancelled =
    button "cancel" (fun set_status ->
      let cancellation = Host_effect.Cancellation.create () in
      Bonsai.Effect.Many
        [ perform set_status "cancel" Host_effect.Haptic_light ~cancellation ()
        ; Bonsai.Effect.of_thunk (fun () -> Host_effect.Cancellation.cancel cancellation)
        ])
  in
  let burst =
    button "burst" (fun set_status ->
      Bonsai.Effect.Many
        (List.init 8 (fun _ -> perform set_status "burst" Host_effect.Haptic_selection ())))
  in
  Bonsai.Cont.map2
    status
    (Bonsai.Cont.all (buttons @ [ cancelled; burst ]))
    ~f:(fun status buttons ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:(Ui.View.Body.static (Ui.View.column (Ui.View.text status :: buttons))))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-haptic-service")
    (App.create ~name:"Native Haptic Service" haptic_service_component)
;;

let picker_service_component handlers graph =
  let module Platform = Host_effect.Application_platform in
  let module ID = Bonsai_swiftui_spec.Id in
  let host = Driver.Handler.host_effects handlers in
  let platform = Driver.Handler.application_platform handlers in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Pickers:" graph in
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let cancellations = Hashtbl.create 8 in
  let show set_status tag mode =
    let cancellation = Host_effect.Cancellation.create () in
    Hashtbl.replace cancellations tag cancellation;
    let date year month day = Host_effect.civil_date ~year ~month ~day in
    let first = date 2024 2 10 in
    let last = date 2025 3 15 in
    let initial = date 2024 2 29 in
    let date_string (value : Host_effect.civil_date) =
      Printf.sprintf "%04d-%02d-%02d" value.year value.month value.day
    in
    let finish request render =
      Bonsai.Effect.map request ~f:(function
        | Ok None -> "dismissed"
        | Ok (Some value) -> render value
        | Error Host_effect.Cancelled -> "cancelled"
        | Error _ -> "error")
    in
    let request =
      match mode with
      | "time" ->
        finish
          (Host_effect.pick_time
             ~cancellation
             ~initial:(Host_effect.civil_time ~hour:23 ~minute:59)
             host
             ())
          (fun (value : Host_effect.civil_time) ->
             Printf.sprintf "%02d:%02d" value.hour value.minute)
      | "range" ->
        finish
          (Host_effect.pick_date_range
             ~cancellation
             ~initial:(Host_effect.civil_date_range ~start:initial ~end_:(date 2024 3 1))
             ~first
             ~last
             host
             ())
          (fun (value : Host_effect.civil_date_range) ->
             date_string value.start ^ "/" ^ date_string value.end_)
      | "historical" ->
        finish
          (Host_effect.pick_date
             ~cancellation
             ~initial:(date 1582 10 10)
             ~first:(date 1 1 1)
             ~last:(date 9999 12 31)
             host
             ())
          date_string
      | "default" ->
        finish (Host_effect.pick_date ~cancellation ~first ~last host ()) date_string
      | "menu" ->
        finish
          (Host_effect.show_native_menu
             ~cancellation
             host
             [ { item_id = ID.Host.Native_menu_item_id.of_string "open"
               ; label = "Open document"
               ; enabled = true
               }
             ])
          ID.Host.Native_menu_item_id.to_string
      | _ ->
        finish
          (Host_effect.pick_date ~cancellation ~initial ~first ~last host ())
          date_string
    in
    Bonsai.Effect.bind request ~f:(fun value ->
      set_status (fun prior -> prior ^ tag ^ "=" ^ value ^ ";"))
  in
  let activate =
    Bonsai.Cont.map set_status ~f:(fun set_status ->
      Bonsai.Effect.of_thunk (fun () ->
        Platform.on_event platform (fun bytes ->
          match String.split_on_char ':' (Bytes.to_string bytes) with
          | [ "show"; tag; mode ] -> show set_status tag mode
          | [ "file"; tag ] ->
            let cancellation = Host_effect.Cancellation.create () in
            Hashtbl.replace cancellations tag cancellation;
            Bonsai.Effect.bind
              (Host_effect.pick_files ~cancellation host ())
              ~f:(fun result ->
                let value =
                  match result with
                  | Ok _ -> "files"
                  | Error Host_effect.Cancelled -> "cancelled"
                  | Error _ -> "error"
                in
                set_status (fun prior -> prior ^ tag ^ "=" ^ value ^ ";"))
          | [ "cancel"; tag ] ->
            Bonsai.Effect.of_thunk (fun () ->
              Option.iter
                Host_effect.Cancellation.cancel
                (Hashtbl.find_opt cancellations tag))
          | _ -> Bonsai.Effect.Ignore)))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate:activate graph;
  let open_menu =
    Driver.Handler.create
      handlers
      ~name:"show-action-menu"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ -> show set_status "button" "regular")
  in
  let background =
    Driver.Handler.create
      handlers
      ~name:"menu-background-action"
      ~equal:( == )
      set_count
      ~f:(fun set_count _ -> set_count (fun value -> value + 1))
  in
  Bonsai.Cont.map3
    (Bonsai.Cont.both status count)
    open_menu
    background
    ~f:(fun (status, count) open_menu background ->
      App.View.create
        ~theme:(Ui.Theme.create ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.column
                [ Ui.View.text status
                ; Ui.View.text (Printf.sprintf "Background: %d" count)
                ; Ui.View.button
                    ~on_press:open_menu
                    ~child:(Ui.View.text "Show action menu")
                    ()
                ; Ui.View.button
                    ~on_press:background
                    ~child:(Ui.View.text "Background action")
                    ()
                ])))
;;

let () =
  Native_backend.embed
    ~name:
      (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string
         "native-picker-service")
    (App.create ~name:"Native Picker Service" picker_service_component)
;;
