module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type url_editor =
  { value : Ui.Text_editing.Value.t
  ; document_revision : ID.Text_input.document_revision
  ; accepted_local_revision : ID.Text_input.local_revision
  }

let url_controls handlers host set_status graph =
  let initial =
    let text = "https://example.com" in
    let cursor = Ui.Text_editing.Utf16.length text in
    let selection =
      Ui.Text_editing.Range.create ~text ~start_utf16:cursor ~end_utf16:cursor
    in
    { value = Ui.Text_editing.Value.create ~text ~selection ()
    ; document_revision = ID.Text_input.Document_revision.of_int64 1L
    ; accepted_local_revision = ID.Text_input.Local_revision.zero
    }
  in
  let equal left right =
    Ui.Text_editing.Value.equal left.value right.value
    && ID.Text_input.Document_revision.equal
         left.document_revision
         right.document_revision
    && ID.Text_input.Local_revision.equal
         left.accepted_local_revision
         right.accepted_local_revision
  in
  let state, set_state = Bonsai_v017.state ~equal initial graph in
  let session_id = ID.Text_input.Session_id.of_int64 1L in
  let edit =
    Driver.Handler.create
      handlers
      ~name:"host-effects-url-edit"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Text_edit edit ->
        set_state (fun state ->
          if
            (not (ID.Text_input.Session_id.equal session_id edit.session_id))
            || ID.Text_input.Local_revision.compare
                 edit.local_revision
                 state.accepted_local_revision
               <= 0
            || ID.Text_input.Document_revision.compare
                 edit.base_document_revision
                 state.document_revision
               > 0
          then state
          else (
            let range (selection : Ui.Event.Payload.text_selection) =
              Ui.Text_editing.Range.create
                ~text:edit.text
                ~start_utf16:selection.start_utf16
                ~end_utf16:selection.end_utf16
            in
            { value =
                Ui.Text_editing.Value.create
                  ~text:edit.text
                  ~selection:(range edit.selection)
                  ?composing:(Option.map range edit.composing)
                  ()
            ; document_revision =
                ID.Text_input.Document_revision.succ state.document_revision
            ; accepted_local_revision = edit.local_revision
            }))
      | _ -> Bonsai.Effect.Ignore)
  in
  let open_url =
    Driver.Handler.create
      handlers
      ~name:"host-effects-url-open"
      ~equal:( == )
      (Bonsai.Cont.both state set_status)
      ~f:(fun (state, set_status) _ ->
        Bonsai.Effect.bind
          (Host_effect.open_url host (Ui.Text_editing.Value.text state.value))
          ~f:(fun result ->
            set_status (fun _ ->
              match result with
              | Ok () -> "URL opened"
              | Error _ -> "URL open failed")))
  in
  let focus =
    Driver.Handler.create
      handlers
      ~name:"host-effects-url-focus"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ -> Bonsai.Effect.Ignore)
  in
  let clear_focus =
    Driver.Handler.create
      handlers
      ~name:"host-effects-clear-focus"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind (Host_effect.clear_focus host ()) ~f:(fun result ->
          set_status (fun _ ->
            match result with
            | Ok () -> "Input focus cleared"
            | Error _ -> "Unable to clear input focus")))
  in
  Bonsai.Cont.map3
    state
    (Bonsai.Cont.both edit focus)
    (Bonsai.Cont.both open_url clear_focus)
    ~f:(fun state (edit, focus) (open_url, clear_focus) ->
      [ Ui.View.text_field
          ~label:"URL"
          ~keyboard:Ui.Text_editing.Keyboard.Url
          ~submit_label:Ui.Text_editing.Submit_label.Go
          ~session_id
          ~document_revision:state.document_revision
          ~accepted_local_revision:state.accepted_local_revision
          ~update_mode:Ui.Text_editing.Ack
          ~value:state.value
          ~on_edit:edit
          ~on_submit:open_url
          ~on_focus_changed:focus
          ()
      ; Ui.View.button ~on_press:open_url ~child:(Ui.View.text "Open URL") ()
      ; Ui.View.button ~on_press:clear_focus ~child:(Ui.View.text "Clear focus") ()
      ])
;;

let clipboard_preview text =
  let maximum_bytes = 4096 in
  if String.length text <= maximum_bytes
  then text
  else (
    let boundary = ref maximum_bytes in
    while !boundary > 0 && Char.code text.[!boundary] land 0xc0 = 0x80 do
      decr boundary
    done;
    String.sub text 0 !boundary ^ "…")
;;

let application_controls handlers graph =
  let module Platform = Host_effect.Application_platform in
  let platform = Driver.Handler.application_platform handlers in
  let status, set_status =
    Bonsai_v017.state ~equal:String.equal "No application request has run" graph
  in
  let notification, set_notification =
    Bonsai_v017.state ~equal:String.equal "No application event received" graph
  in
  let decode tag bytes =
    if
      Bytes.length bytes < 3
      || Bytes.length bytes > 1026
      || Bytes.get bytes 0 <> '\001'
      || Char.code (Bytes.get bytes 1) <> tag
    then None
    else (
      let text = Bytes.sub_string bytes 2 (Bytes.length bytes - 2) in
      if String.for_all (fun char -> Char.code char >= 32 && Char.code char < 127) text
      then Some text
      else None)
  in
  let on_activate =
    Bonsai.Cont.map set_notification ~f:(fun set_notification ->
      Bonsai.Effect.of_thunk (fun () ->
        Platform.on_event platform (fun bytes ->
          match decode 2 bytes with
          | Some zone -> set_notification (fun _ -> "Application time zone: " ^ zone)
          | None -> Bonsai.Effect.Ignore)))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate graph;
  let request =
    Driver.Handler.create
      handlers
      ~name:"host-effects-application-bundle"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind
          (Platform.request platform (Bytes.of_string "\001\001"))
          ~f:(fun result ->
            set_status (fun _ ->
              match result with
              | Ok bytes ->
                (match decode 1 bytes with
                 | Some identifier -> "Application bundle: " ^ identifier
                 | None -> "Invalid application response")
              | Error Unavailable -> "Application bridge unavailable"
              | Error _ -> "Application request failed")))
  in
  Bonsai.Cont.map3 status notification request ~f:(fun status notification on_press ->
    [ Ui.View.text status
    ; Ui.View.button ~on_press ~child:(Ui.View.text "Read application bundle") ()
    ; Ui.View.text notification
    ])
;;

let file_controls handlers graph =
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Files idle" graph in
  let host = Driver.Handler.host_effects handlers in
  let import =
    Driver.Handler.create
      handlers
      ~name:"host-effects-import-files"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind
          (Host_effect.pick_files
             host
             ~allowed_extensions:[ "txt"; "bin" ]
             ~allow_multiple:true
             ())
          ~f:(function
            | Ok [] -> set_status (fun _ -> "File import cancelled")
            | Ok files ->
              set_status (fun _ -> Printf.sprintf "Imported %d files" (List.length files))
            | Error _ -> set_status (fun _ -> "File import failed")))
  in
  let export =
    Driver.Handler.create
      handlers
      ~name:"host-effects-export-file"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind
          (Host_effect.save_file
             host
             ~suggested_name:"Bonsai.txt"
             ~data:(Bytes.of_string "Exported by Bonsai SwiftUI")
             ())
          ~f:(function
            | Ok None -> set_status (fun _ -> "File export cancelled")
            | Ok (Some _) -> set_status (fun _ -> "File exported")
            | Error _ -> set_status (fun _ -> "File export failed")))
  in
  Bonsai.Cont.map3 status import export ~f:(fun status import export ->
    [ Ui.View.text status
    ; Ui.View.button ~on_press:import ~child:(Ui.View.text "Import files") ()
    ; Ui.View.button ~on_press:export ~child:(Ui.View.text "Export file") ()
    ])
;;

let notice_controls handlers graph =
  let host = Driver.Handler.host_effects handlers in
  let current = ref None in
  let status, set_status =
    Bonsai_v017.state ~equal:String.equal "Notification: idle" graph
  in
  let show name message action_label duration_ms =
    Driver.Handler.create handlers ~name ~equal:( == ) set_status ~f:(fun set_status _ ->
      Bonsai.Effect.bind
        (Bonsai.Effect.of_thunk (fun () ->
           let token = Host_effect.Cancellation.create () in
           current := Some token;
           token))
        ~f:(fun cancellation ->
          Bonsai.Effect.bind
            (Host_effect.show_notice
               ~cancellation
               ?action_label
               ~duration_ms
               host
               ~message
               ())
            ~f:(fun result ->
              Bonsai.Effect.bind
                (Bonsai.Effect.of_thunk (fun () ->
                   match !current with
                   | Some token when token == cancellation -> current := None
                   | _ -> ()))
                ~f:(fun () ->
                  set_status (fun _ ->
                    match result with
                    | Ok Action -> "Notification: action"
                    | Ok Dismiss -> "Notification: dismissed"
                    | Ok Swipe -> "Notification: swiped"
                    | Ok Timeout -> "Notification: timed out"
                    | Error Cancelled -> "Notification: cancelled"
                    | Error _ -> "Notification: failed")))))
  in
  let show_action = show "host-effects-notice" "Changes saved" (Some "Undo") 4000 in
  let show_timed = show "host-effects-timed-notice" "Refresh complete" None 1000 in
  let cancel =
    Driver.Handler.create
      handlers
      ~name:"host-effects-cancel-notice"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ ->
        Bonsai.Effect.of_thunk (fun () ->
          Option.iter Host_effect.Cancellation.cancel !current))
  in
  Bonsai.Cont.map3
    status
    (Bonsai.Cont.both show_action show_timed)
    cancel
    ~f:(fun status (show_action, show_timed) cancel ->
      [ Ui.View.text status
      ; Ui.View.button ~on_press:show_action ~child:(Ui.View.text "Show notification") ()
      ; Ui.View.button
          ~on_press:show_timed
          ~child:(Ui.View.text "Show timed notification")
          ()
      ; Ui.View.button ~on_press:cancel ~child:(Ui.View.text "Cancel notification") ()
      ])
;;

let menu_controls handlers graph =
  let host = Driver.Handler.host_effects handlers in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Action: idle" graph in
  let choose =
    Driver.Handler.create
      handlers
      ~name:"host-effects-action-menu"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        let item id label enabled : Host_effect.native_menu_item =
          { item_id = ID.Host.Native_menu_item_id.of_string id; label; enabled }
        in
        Bonsai.Effect.bind
          (Host_effect.show_native_menu
             host
             [ item "open" "Open item" true
             ; item "duplicate" "Duplicate item" true
             ; item "unavailable" "Unavailable action" false
             ])
          ~f:(fun result ->
            set_status (fun _ ->
              match result with
              | Ok (Some id) -> "Action: " ^ ID.Host.Native_menu_item_id.to_string id
              | Ok None -> "Action: dismissed"
              | Error Host_effect.Cancelled -> "Action: cancelled"
              | Error _ -> "Action: failed")))
  in
  Bonsai.Cont.map2 status choose ~f:(fun status choose ->
    [ Ui.View.text status
    ; Ui.View.button ~on_press:choose ~child:(Ui.View.text "Choose action") ()
    ])
;;

let haptic_controls handlers graph =
  let host = Driver.Handler.host_effects handlers in
  let status, set_status = Bonsai_v017.state ~equal:String.equal "Haptic: idle" graph in
  let kinds =
    [ "light", Host_effect.Haptic_light
    ; "medium", Host_effect.Haptic_medium
    ; "heavy", Host_effect.Haptic_heavy
    ; "selection", Host_effect.Haptic_selection
    ]
  in
  let buttons =
    List.map
      (fun (name, kind) ->
         Driver.Handler.create
           handlers
           ~name:("host-effects-haptic-" ^ name)
           ~equal:( == )
           set_status
           ~f:(fun set_status _ ->
             Bonsai.Effect.bind (Host_effect.haptic_feedback host kind) ~f:(fun result ->
               set_status (fun _ ->
                 match result with
                 | Ok () -> "Haptic: " ^ name ^ " requested"
                 | Error Host_effect.Cancelled -> "Haptic: cancelled"
                 | Error _ -> "Haptic: failed")))
         |> Bonsai.Cont.map ~f:(fun handler ->
           Ui.View.button ~on_press:handler ~child:(Ui.View.text ("Haptic " ^ name)) ()))
      kinds
  in
  Bonsai.Cont.map2 status (Bonsai.Cont.all buttons) ~f:(fun status buttons ->
    Ui.View.text status :: buttons)
;;

let picker_controls handlers graph =
  let host = Driver.Handler.host_effects handlers in
  let status, set_status =
    Bonsai_v017.state ~equal:String.equal "Selection: idle" graph
  in
  let date year month day = Host_effect.civil_date ~year ~month ~day in
  let first = date 2024 1 1 in
  let last = date 2030 12 31 in
  let initial = date 2024 2 29 in
  let render_date (value : Host_effect.civil_date) =
    Printf.sprintf "%04d-%02d-%02d" value.year value.month value.day
  in
  let button name label request render =
    Driver.Handler.create handlers ~name ~equal:( == ) set_status ~f:(fun set_status _ ->
      Bonsai.Effect.bind (request ()) ~f:(fun result ->
        set_status (fun _ ->
          match result with
          | Ok (Some value) -> render value
          | Ok None -> "Selection: dismissed"
          | Error Host_effect.Cancelled -> "Selection: cancelled"
          | Error _ -> "Selection: failed")))
    |> Bonsai.Cont.map ~f:(fun on_press ->
      Ui.View.button ~on_press ~child:(Ui.View.text label) ())
  in
  let buttons =
    [ button
        "host-effects-date"
        "Choose date"
        (fun () -> Host_effect.pick_date ~initial ~first ~last host ())
        (fun value -> "Date: " ^ render_date value)
    ; button
        "host-effects-date-range"
        "Choose date range"
        (fun () ->
           Host_effect.pick_date_range
             ~initial:(Host_effect.civil_date_range ~start:initial ~end_:(date 2024 3 1))
             ~first
             ~last
             host
             ())
        (fun (value : Host_effect.civil_date_range) ->
           "Range: " ^ render_date value.start ^ "/" ^ render_date value.end_)
    ; button
        "host-effects-time"
        "Choose time"
        (fun () ->
           Host_effect.pick_time
             ~format:Host_effect.System
             ~initial:(Host_effect.civil_time ~hour:23 ~minute:59)
             host
             ())
        (fun (value : Host_effect.civil_time) ->
           Printf.sprintf "Time: %02d:%02d" value.hour value.minute)
    ]
  in
  Bonsai.Cont.map2 status (Bonsai.Cont.all buttons) ~f:(fun status buttons ->
    Ui.View.text status :: buttons)
;;

let component handlers graph =
  let environment = App.Context.environment handlers in
  let status, set_status =
    Bonsai_v017.state ~equal:String.equal "No host request has run" graph
  in
  let host = Driver.Handler.host_effects handlers in
  let url_controls = url_controls handlers host set_status graph in
  let application_controls = application_controls handlers graph in
  let file_controls =
    Bonsai.Cont.map2
      (file_controls handlers graph)
      (Bonsai.Cont.map2
         (haptic_controls handlers graph)
         (picker_controls handlers graph)
         ~f:( @ ))
      ~f:( @ )
  in
  let notice_controls =
    Bonsai.Cont.map2
      (notice_controls handlers graph)
      (menu_controls handlers graph)
      ~f:( @ )
  in
  let read_clipboard =
    Driver.Handler.create
      handlers
      ~name:"host-effects-read"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind (Host_effect.Clipboard.read host ()) ~f:(function
          | Ok text -> set_status (fun _ -> "Clipboard: " ^ clipboard_preview text)
          | Error _ -> set_status (fun _ -> "Clipboard read failed")))
  in
  let write_clipboard =
    Driver.Handler.create
      handlers
      ~name:"host-effects-write"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind
          (Host_effect.Clipboard.write host "Written by Bonsai SwiftUI")
          ~f:(function
          | Ok () -> set_status (fun _ -> "Clipboard write completed")
          | Error _ -> set_status (fun _ -> "Clipboard write failed")))
  in
  let read_platform =
    Driver.Handler.create
      handlers
      ~name:"host-effects-platform-information"
      ~equal:( == )
      set_status
      ~f:(fun set_status _ ->
        Bonsai.Effect.bind (Host_effect.platform_information host ()) ~f:(function
          | Ok information ->
            set_status (fun _ ->
              Printf.sprintf
                "Platform: %s\nOS version: %s\nLocale: %s"
                information.operating_system
                information.operating_system_version
                information.locale_name)
          | Error _ -> set_status (fun _ -> "Platform information failed")))
  in
  let handlers =
    let window_action name request success =
      Driver.Handler.create
        handlers
        ~name
        ~equal:( == )
        set_status
        ~f:(fun set_status _ ->
          Bonsai.Effect.bind (request ()) ~f:(function
            | Ok () -> set_status (fun _ -> success)
            | Error (Host_effect.Failed message) ->
              set_status (fun _ -> "Window request failed: " ^ clipboard_preview message)
            | Error _ -> set_status (fun _ -> "Window request failed")))
    in
    let rename =
      window_action
        "host-effects-window-title"
        (fun () -> Host_effect.set_window_title host "Bonsai SwiftUI 本地😀")
        "Window title updated"
    in
    let resize =
      window_action
        "host-effects-window-size"
        (fun () -> Host_effect.set_window_size host ~width:760. ~height:560.)
        "Window size updated"
    in
    Bonsai.Cont.map2
      (Bonsai.Cont.both (Bonsai.Cont.both read_clipboard write_clipboard) read_platform)
      (Bonsai.Cont.both rename resize)
      ~f:(fun ((read, write), platform) (rename, resize) ->
        read, write, platform, rename, resize)
  in
  Bonsai.Cont.map3
    (Bonsai.Cont.both status environment)
    handlers
    (Bonsai.Cont.both
       url_controls
       (Bonsai.Cont.both
          application_controls
          (Bonsai.Cont.both file_controls notice_controls)))
    ~f:
      (fun
        (status, environment)
        (read_clipboard, write_clipboard, read_platform, rename, resize)
        (url_controls, (application_controls, (file_controls, notice_controls))) ->
      let content =
        Ui.View.column
          ~spacing:16.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          ([ Ui.View.text ~line_limit:12 status
           ; Ui.View.text
               (Printf.sprintf
                  "Environment: \
                   platform=%s|width=%g|height=%g|keyboard=%g|safe=%g,%g,%g,%g"
                  environment.platform
                  environment.viewport_width
                  environment.viewport_height
                  environment.keyboard_insets.bottom
                  environment.safe_area.left
                  environment.safe_area.top
                  environment.safe_area.right
                  environment.safe_area.bottom)
           ; Ui.View.button
               ~style:Ui.View.Button_style.Prominent
               ~on_press:read_clipboard
               ~child:(Ui.View.text "Read clipboard")
               ()
           ; Ui.View.button
               ~on_press:write_clipboard
               ~child:(Ui.View.text "Write clipboard")
               ()
           ; Ui.View.button
               ~on_press:read_platform
               ~child:(Ui.View.text "Read platform information")
               ()
           ; Ui.View.button ~on_press:rename ~child:(Ui.View.text "Rename window") ()
           ; Ui.View.button ~on_press:resize ~child:(Ui.View.text "Resize window") ()
           ]
           @ url_controls
           @ application_controls
           @ file_controls
           @ notice_controls)
        |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 24.)
        |> Ui.View.Scroll.vertical
      in
      Ui.View.Body.Vertical.create
        [ Ui.View.Body.Vertical.fixed
            (Ui.View.text
               ~style:
                 (Ui.Style.Text_style.create
                    ~font_size:28.
                    ~font_weight:Ui.Style.Font_weight.Bold
                    ())
               "Host Effects"
             |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:1 ())
             |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 24.))
        ; Ui.View.Body.Vertical.fill content
        ])
;;

let app =
  let theme = Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:198 ~green:40 ~blue:40) () in
  App.create ~name:"Host Effects" (fun handlers graph ->
    Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
      App.View.create ~theme ~body))
;;
