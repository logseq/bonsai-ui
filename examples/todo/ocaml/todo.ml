module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let document_revision = ID.Text_input.Document_revision.of_int64

type item =
  { id : int
  ; title : string
  ; completed : bool
  ; document_revision : ID.Text_input.document_revision
  ; accepted_local_revision : ID.Text_input.local_revision
  }

type state =
  { next_id : int
  ; selected : int option
  ; items : item list
  }

let equal = ( = )

let initial =
  { next_id = 4
  ; selected = Some 1
  ; items =
      [ { id = 1
        ; title = "Keep identity"
        ; completed = false
        ; document_revision = document_revision 1L
        ; accepted_local_revision = ID.Text_input.Local_revision.zero
        }
      ; { id = 2
        ; title = "Preserve focus"
        ; completed = false
        ; document_revision = document_revision 1L
        ; accepted_local_revision = ID.Text_input.Local_revision.zero
        }
      ; { id = 3
        ; title = "Dispose deleted resources"
        ; completed = true
        ; document_revision = document_revision 1L
        ; accepted_local_revision = ID.Text_input.Local_revision.zero
        }
      ]
  }
;;

let value title =
  let cursor = Ui.Text_editing.Utf16.length title in
  let selection =
    Ui.Text_editing.Range.create ~text:title ~start_utf16:cursor ~end_utf16:cursor
  in
  Ui.Text_editing.Value.create ~text:title ~selection ()
;;

let update_item state id update =
  { state with
    items = List.map (fun item -> if item.id = id then update item else item) state.items
  }
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal initial graph in
  let add =
    Driver.Handler.create
      handlers
      ~name:"todo-add"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state ->
          let item =
            { id = state.next_id
            ; title = Printf.sprintf "Todo %d" state.next_id
            ; completed = false
            ; document_revision = document_revision 1L
            ; accepted_local_revision = ID.Text_input.Local_revision.zero
            }
          in
          { next_id = state.next_id + 1
          ; selected = Some item.id
          ; items = state.items @ [ item ]
          }))
  in
  let reverse =
    Driver.Handler.create
      handlers
      ~name:"todo-reverse"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state -> { state with items = List.rev state.items }))
  in
  let items = Bonsai.Cont.map state ~f:(fun state -> state.items) in
  let selected = Bonsai.Cont.map state ~f:(fun state -> state.selected) in
  let rows =
    Bonsai.Cont.assoc_list
      (module Core.Int)
      items
      ~get_key:(fun item -> item.id)
      ~f:(fun item_id item _graph ->
        let dependencies = Bonsai.Cont.both set_state item_id in
        let equal_dependencies (left_set_state, left_id) (right_set_state, right_id) =
          left_set_state == right_set_state && Int.equal left_id right_id
        in
        let select =
          Driver.Handler.create
            handlers
            ~name:"todo-select"
            ~equal:equal_dependencies
            dependencies
            ~f:(fun (set_state, item_id) _ ->
              set_state (fun state -> { state with selected = Some item_id }))
        in
        let toggle =
          Driver.Handler.create
            handlers
            ~name:"todo-toggle"
            ~equal:equal_dependencies
            dependencies
            ~f:(fun (set_state, item_id) -> function
            | Ui.Event.Payload.Bool completed ->
              set_state (fun state ->
                update_item state item_id (fun item -> { item with completed }))
            | _ -> Bonsai.Effect.Ignore)
        in
        let delete =
          Driver.Handler.create
            handlers
            ~name:"todo-delete"
            ~equal:equal_dependencies
            dependencies
            ~f:(fun (set_state, item_id) _ ->
              set_state (fun state ->
                { state with
                  selected =
                    (if state.selected = Some item_id then None else state.selected)
                ; items =
                    List.filter (fun candidate -> candidate.id <> item_id) state.items
                }))
        in
        let edit =
          Driver.Handler.create
            handlers
            ~name:"todo-edit"
            ~equal:equal_dependencies
            dependencies
            ~f:(fun (set_state, item_id) -> function
            | Ui.Event.Payload.Text_edit edit ->
              set_state (fun state ->
                update_item state item_id (fun item ->
                  { item with
                    title = edit.text
                  ; document_revision =
                      ID.Text_input.Document_revision.succ item.document_revision
                  ; accepted_local_revision = edit.local_revision
                  }))
            | _ -> Bonsai.Effect.Ignore)
        in
        let submit =
          Driver.Handler.create
            handlers
            ~name:"todo-submit"
            ~equal:Unit.equal
            (Bonsai.Cont.return ())
            ~f:(fun () _ -> Bonsai.Effect.Ignore)
        in
        let focus =
          Driver.Handler.create
            handlers
            ~name:"todo-focus"
            ~equal:equal_dependencies
            dependencies
            ~f:(fun (set_state, item_id) -> function
            | Ui.Event.Payload.Bool true ->
              set_state (fun state -> { state with selected = Some item_id })
            | Ui.Event.Payload.Bool false | _ -> Bonsai.Effect.Ignore)
        in
        let primary_handlers =
          Bonsai.Cont.map2 select toggle ~f:(fun select toggle -> select, toggle)
        in
        let edit_handlers =
          Bonsai.Cont.map2 delete edit ~f:(fun delete edit -> delete, edit)
        in
        let input_handlers =
          Bonsai.Cont.map2 submit focus ~f:(fun submit focus -> submit, focus)
        in
        let row_handlers =
          Bonsai.Cont.map2
            primary_handlers
            (Bonsai.Cont.both edit_handlers input_handlers)
            ~f:(fun (select, toggle) ((delete, edit), (submit, focus)) ->
              select, toggle, delete, edit, submit, focus)
        in
        Bonsai.Cont.map2
          (Bonsai.Cont.both item selected)
          row_handlers
          ~f:(fun (item, selected) (select, toggle, delete, edit, submit, focus) ->
            let key = Ui.Key.int item.id in
            let action label title handler =
              Ui.View.button ~on_press:handler ~child:(Ui.View.text title) ()
              |> Ui.View.semantics ~properties:(Ui.Semantics.create ~label ())
            in
            Ui.View.column
              ~spacing:10.
              ~alignment:Ui.Layout.Horizontal_alignment.Leading
              [ Ui.View.text_field
                  ~key:(Ui.Key.string (Printf.sprintf "todo-editor-%d" item.id))
                  ~label:(Printf.sprintf "Todo %d title" item.id)
                  ~session_id:(ID.Text_input.Session_id.of_int64 (Int64.of_int item.id))
                  ~document_revision:item.document_revision
                  ~accepted_local_revision:item.accepted_local_revision
                  ~update_mode:Ui.Text_editing.Ack
                  ~value:(value item.title)
                  ~on_edit:edit
                  ~on_submit:submit
                  ~on_focus_changed:focus
                  ()
              ; Ui.View.row
                  ~spacing:12.
                  [ Ui.View.toggle
                      ~style:Ui.View.Toggle_style.Checkbox
                      ~label:(Ui.View.text (Printf.sprintf "Complete todo %d" item.id))
                      ~value:item.completed
                      ~on_changed:toggle
                      ()
                  ; Ui.View.spacer ()
                  ; action
                      (Printf.sprintf "Select todo %d" item.id)
                      (if selected = Some item.id then "Selected" else "Select")
                      select
                  ; action (Printf.sprintf "Delete todo %d" item.id) "Delete" delete
                  ]
              ]
            |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 12.)
            |> Ui.View.background
                 ~corner_radius:10.
                 ~color:(Ui.Style.Color.argb ~alpha:18 ~red:128 ~green:128 ~blue:128)
            |> Ui.View.semantics
                 ~key
                 ~properties:
                   (Ui.Semantics.create
                      ~label:item.title
                      ~selected:(selected = Some item.id)
                      ~children:Ui.Semantics.Children.Contain
                      ~value:(if item.completed then "Completed" else "Incomplete")
                      ())
            |> Ui.View.with_test_id (Ui.Test_id.string (Printf.sprintf "todo-%d" item.id))))
      graph
  in
  let static_handlers = Bonsai.Cont.both add reverse in
  Bonsai.Cont.map2 rows static_handlers ~f:(fun rows (add, reverse) ->
    let rows =
      match rows with
      | `Ok rows -> rows
      | `Duplicate_key item_id ->
        invalid_arg (Printf.sprintf "Todo: duplicate item ID %d" item_id)
    in
    let list =
      Ui.View.column ~spacing:10. rows
      |> Ui.View.Scroll.vertical
      |> Ui.View.Viewport.Vertical.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
      |> Ui.View.Viewport.Vertical.semantics
           ~properties:(Ui.Semantics.create ~children:Ui.Semantics.Children.Contain ())
    in
    Ui.View.Body.Vertical.create
      [ Ui.View.Body.Vertical.fixed
          (Ui.View.row
             ~spacing:12.
             [ Ui.View.text "Todo"
               |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:1 ())
             ; Ui.View.spacer ()
             ; Ui.View.button
                 ~style:Ui.View.Button_style.Prominent
                 ~on_press:add
                 ~child:(Ui.View.text "Add")
                 ()
             ; Ui.View.button ~on_press:reverse ~child:(Ui.View.text "Reverse") ()
             ]
           |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.))
      ; Ui.View.Body.Vertical.fill list
      ])
;;

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:0 ~green:105 ~blue:92) ()
;;

let application_component handlers graph =
  Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body)
;;

let app = App.create ~name:"Todo" application_component
