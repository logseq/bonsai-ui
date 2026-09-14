module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type destination =
  { id : int64
  ; title : string
  ; symbol : string
  ; enabled : bool
  }

let mailboxes =
  [ { id = 117L; title = "Inbox"; symbol = "tray"; enabled = true }
  ; { id = 119L; title = "Archive"; symbol = "archivebox"; enabled = true }
  ]
;;

let accounts =
  [ { id = 121L; title = "中文😀"; symbol = "person"; enabled = true }
  ; { id = 125L; title = "Unavailable"; symbol = "lock"; enabled = false }
  ]
;;

let destinations = mailboxes @ accounts

type state =
  { selected : int64
  ; visibility : Ui.Navigation.Split_visibility.t
  ; compact : Ui.Navigation.Split_column.t
  ; modal : bool
  ; presented : bool
  ; ignored : bool
  ; reversed : bool
  ; compose_enabled : bool
  ; trailing_at_bottom : bool
  ; actions : int
  ; counts : (int64 * int) list
  }

let initial =
  { selected = 117L
  ; visibility = All
  ; compact = Sidebar
  ; modal = false
  ; presented = false
  ; ignored = false
  ; reversed = false
  ; compose_enabled = true
  ; trailing_at_bottom = true
  ; actions = 0
  ; counts = []
  }
;;

let selected_key state = ID.Navigation.Page_key.of_string (Int64.to_string state.selected)
let count state = Option.value (List.assoc_opt state.selected state.counts) ~default:0

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name:("sidebar-catalog-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
    |> Bonsai.Cont.map ~f:(fun handler -> name, handler)
  in
  let action name update = bind name (fun state _ -> update state) in
  let select (destination : destination) =
    action (Int64.to_string destination.id) (fun state ->
      if state.ignored || not destination.enabled
      then state
      else { state with selected = destination.id; compact = Detail })
  in
  let controls =
    [ action "increment" (fun state ->
        { state with
          counts =
            (state.selected, count state + 1)
            :: List.remove_assoc state.selected state.counts
        })
    ; action "compose" (fun state ->
        if state.compose_enabled
        then { state with actions = state.actions + 1 }
        else state)
    ; action "help" (fun state -> { state with actions = state.actions + 1 })
    ; action "reverse" (fun state -> { state with reversed = not state.reversed })
    ; action "ignore" (fun state -> { state with ignored = not state.ignored })
    ; action "enable" (fun state ->
        { state with compose_enabled = not state.compose_enabled })
    ; action "trailing" (fun state ->
        { state with trailing_at_bottom = not state.trailing_at_bottom })
    ; action "show" (fun state ->
        { state with visibility = All; compact = Sidebar; presented = true })
    ; action "close" (fun state ->
        { state with visibility = Detail_only; presented = false })
    ; action "modal" (fun state -> { state with modal = true; presented = true })
    ; action "embedded" (fun state ->
        { state with modal = false; visibility = All; compact = Sidebar })
    ; bind "dismiss" (fun state -> function
        | Ui.Event.Payload.Bool false when not state.ignored ->
          { state with presented = false }
        | _ -> state)
    ; bind "columns" (fun state -> function
        | Ui.Event.Payload.Navigation_split_changed requested
          when (not state.ignored)
               && Ui.Navigation.Split_state.compact_column requested <> Content
               && Option.equal
                    ID.Navigation.Page_key.equal
                    (Ui.Navigation.Split_state.selection_key requested)
                    (Some (selected_key state)) ->
          { state with
            visibility = Ui.Navigation.Split_state.visibility requested
          ; compact = Ui.Navigation.Split_state.compact_column requested
          }
        | _ -> state)
    ]
    @ List.map select destinations
  in
  let controls =
    List.fold_right
      (fun control rest ->
         Bonsai.Cont.map2 control rest ~f:(fun control rest -> control :: rest))
      controls
      (Bonsai.Cont.return [])
  in
  Bonsai.Cont.map2 state controls ~f:(fun state controls ->
    let handler name = List.assoc name controls in
    let button ?(enabled = true) name title =
      Ui.View.button
        ~key:(Ui.Key.string name)
        ~enabled
        ~on_press:(handler name)
        ~child:(Ui.View.text title)
        ()
    in
    let heading title =
      Ui.View.text title
      |> Ui.View.semantics ~properties:(Ui.Semantics.create ~role:Header ())
    in
    let row (destination : destination) =
      Ui.View.button
        ~key:(Ui.Key.string (Int64.to_string destination.id))
        ~enabled:destination.enabled
        ~on_press:(handler (Int64.to_string destination.id))
        ~child:
          (Ui.View.label
             ~title:(Ui.View.text destination.title)
             ~icon:(Ui.View.symbol ~name:destination.symbol ())
             ())
        ()
      |> Ui.View.semantics
           ~key:(Ui.Key.string (Int64.to_string destination.id))
           ~properties:
             (Ui.Semantics.create ~selected:(state.selected = destination.id) ())
    in
    let section title rows =
      Ui.View.column
        ~key:(Ui.Key.string title)
        (heading title :: List.map row (if state.reversed then List.rev rows else rows))
    in
    let trailing =
      Ui.View.column
        ~key:(Ui.Key.string "trailing")
        [ button "help" "Sidebar help"
        ; Ui.View.text
            (if state.trailing_at_bottom
             then "Trailing: bottom"
             else "Trailing: after destinations")
        ]
    in
    let rows =
      [ section "Mailboxes" mailboxes; Ui.View.divider (); section "Account" accounts ]
      @ if state.trailing_at_bottom then [] else [ trailing ]
    in
    let sidebar =
      Ui.View.Body.Vertical.create
        ([ Ui.View.Body.Vertical.fixed
             (Ui.View.column
                [ heading "Navigation"
                ; button ~enabled:state.compose_enabled "compose" "Compose"
                ; button "close" "Close sidebar"
                ])
         ; Ui.View.Body.Vertical.fill
             (Ui.View.Scroll.vertical
                ~key:(Ui.Key.string "destinations")
                (Ui.View.column rows))
         ]
         @
         if state.trailing_at_bottom then [ Ui.View.Body.Vertical.fixed trailing ] else []
        )
      |> Ui.View.Body.padding ~insets:(Ui.Layout.Edge_insets.all 12.)
    in
    let selected =
      List.find
        (fun (destination : destination) -> destination.id = state.selected)
        destinations
    in
    let detail =
      Ui.View.column
        [ Ui.View.text ("Selected destination: " ^ selected.title)
        ; Ui.View.text (Printf.sprintf "Detail count: %d" (count state))
        ; Ui.View.text (Printf.sprintf "Sidebar actions: %d" state.actions)
        ; button "increment" "Increment detail"
        ; button "show" "Show sidebar"
        ; button "modal" "Open modal sidebar"
        ; button "embedded" "Use split sidebar"
        ; button "reverse" "Reverse destinations"
        ; button "ignore" (if state.ignored then "Accept changes" else "Ignore changes")
        ; button
            "enable"
            (if state.compose_enabled then "Disable compose" else "Enable compose")
        ; button "trailing" "Move trailing content"
        ]
    in
    let content =
      if state.modal
      then
        Ui.View.Sheet.create
          ~sizing:Fitted
          ~presented:state.presented
          ~on_presented_changed:(handler "dismiss")
          ~content:(Ui.View.Body.with_size ~width:360. ~height:520. sidebar)
          detail
      else
        Ui.View.Navigation_split.two_columns
          ~state:
            (Ui.Navigation.Split_state.create
               ~visibility:state.visibility
               ~compact_column:state.compact
               ~selection_key:(selected_key state)
               ())
          ~sidebar_title:"Navigation"
          ~detail_title:selected.title
          ~on_change:(handler "columns")
          ~sidebar
          ~detail:(Ui.View.Body.static detail)
          ()
    in
    Ui.View.Body.static
      (Ui.View.frame
         ~max_width:Ui.Layout.Frame_limit.Fill
         ~max_height:Ui.Layout.Frame_limit.Fill
         content))
;;
