type layout =
  | Vertical
  | Horizontal

type state =
  | Pending
  | Editing
  | Complete
  | Disabled
  | Error

type step =
  { id : int64
  ; title : View.t
  ; content : View.t
  ; subtitle : View.t option
  ; label : View.t option
  ; state : state
  ; on_select : Event.Handler.t option
  }

let step ~id ~title ~content ?subtitle ?label ?(state = Pending) ?on_select () =
  { id; title; content; subtitle; label; state; on_select }
;;

let disabled_action = Event.Handler.create (fun _ -> ())

let create
      ?key
      ?(layout = Vertical)
      ~current_step_id
      ?on_continue
      ?on_back
      ?(continue_label = "Continue")
      ?(back_label = "Back")
      steps
      ()
  =
  if steps = [] then invalid_arg "Workflow.create: steps must not be empty";
  let ids = Hashtbl.create (List.length steps) in
  List.iter
    (fun step ->
       if Hashtbl.mem ids step.id then invalid_arg "Workflow.create: duplicate step ID";
       Hashtbl.add ids step.id ())
    steps;
  if not (Hashtbl.mem ids current_step_id)
  then invalid_arg "Workflow.create: current_step_id must name a step";
  if String.trim continue_label = "" || String.trim back_label = ""
  then invalid_arg "Workflow.create: action labels must not be empty";
  let child_key role step = Key.string (role ^ Int64.to_string step.id) in
  let control ?key ~enabled handler child =
    View.button
      ?key
      ~enabled
      ~on_press:(Option.value handler ~default:disabled_action)
      ~child
      ()
  in
  let header index step =
    let marker, status =
      match step.state with
      | Pending -> View.text (string_of_int (index + 1)), "Pending"
      | Editing -> View.symbol ~name:"pencil" (), "Editing"
      | Complete -> View.symbol ~name:"checkmark.circle.fill" (), "Complete"
      | Disabled -> View.symbol ~name:"lock.fill" (), "Disabled"
      | Error -> View.symbol ~name:"exclamationmark.triangle.fill" (), "Error"
    in
    control
      ~key:(child_key "header-" step)
      ~enabled:(step.state <> Disabled && Option.is_some step.on_select)
      step.on_select
      (View.semantics
         ~properties:
           (Semantics.create ~selected:(step.id = current_step_id) ~value:status ())
         (View.row
            ~spacing:8.
            [ marker
            ; View.column
                ~spacing:2.
                ~alignment:Layout.Horizontal_alignment.Leading
                ((step.title :: Option.to_list step.subtitle) @ Option.to_list step.label)
            ]))
  in
  let body step =
    View.Morphing_surface.create
      ~key:(child_key "body-" step)
      ~expand_duration_ms:0
      ~collapse_duration_ms:0
      ~expanded:(step.id = current_step_id)
      ~compact_content:(View.empty ())
      ~expanded_content:step.content
      ()
  in
  let content =
    match layout with
    | Vertical ->
      List.mapi
        (fun index step ->
           View.column
             ~key:(child_key "step-" step)
             ~spacing:0.
             ~alignment:Layout.Horizontal_alignment.Leading
             [ header index step; body step ])
        steps
    | Horizontal ->
      [ View.flow
          ~key:(Key.string "headers")
          ~spacing:12.
          ~line_spacing:8.
          (List.mapi header steps)
      ; View.column ~key:(Key.string "bodies") ~spacing:0. (List.map body steps)
      ]
  in
  let actions =
    View.row
      ~key:(Key.string "actions")
      ~spacing:8.
      [ control
          ~key:(Key.string "continue")
          ~enabled:(Option.is_some on_continue)
          on_continue
          (View.text continue_label)
      ; control
          ~key:(Key.string "back")
          ~enabled:(Option.is_some on_back)
          on_back
          (View.text back_label)
      ]
  in
  View.column
    ?key
    ~spacing:8.
    ~alignment:Layout.Horizontal_alignment.Leading
    (content @ [ actions ])
;;
