module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type gallery_card_event = Native_view_catalog.event = Activate

type model =
  { checked : bool
  ; press_count : int
  ; native_count : int
  ; text : string
  ; document_revision : ID.Text_input.document_revision
  ; accepted_local_revision : ID.Text_input.local_revision
  ; interaction_status : string
  ; segmented_single_ids : int64 list
  }

type handlers =
  { press : Ui.Event.Handler.t
  ; toggle : Ui.Event.Handler.t
  ; text_edit : Ui.Event.Handler.t
  ; text_submit : Ui.Event.Handler.t
  ; focus_changed : Ui.Event.Handler.t
  ; interaction : Ui.Event.Handler.t
  ; native : Ui.Event.Handler.t
  ; segmented_single : Ui.Event.Handler.t
  }

let equal_model left right =
  Bool.equal left.checked right.checked
  && Int.equal left.press_count right.press_count
  && Int.equal left.native_count right.native_count
  && String.equal left.text right.text
  && ID.Text_input.Document_revision.equal left.document_revision right.document_revision
  && ID.Text_input.Local_revision.equal
       left.accepted_local_revision
       right.accepted_local_revision
  && String.equal left.interaction_status right.interaction_status
  && List.equal Int64.equal left.segmented_single_ids right.segmented_single_ids
;;

let initial_model =
  { checked = false
  ; press_count = 0
  ; native_count = 0
  ; text = "Type 中文 or 😀"
  ; document_revision = ID.Text_input.Document_revision.zero
  ; accepted_local_revision = ID.Text_input.Local_revision.zero
  ; interaction_status = "Move, focus, tap, or press a key"
  ; segmented_single_ids = [ 1L ]
  }
;;

let gallery_card = Native_view_catalog.card

let interaction_label = function
  | Ui.Event.Payload.Tap _ -> "Tap received in OCaml"
  | Pointer _ -> "Pointer event received in OCaml"
  | Key _ -> "Key event received in OCaml"
  | Bool true -> "Focus entered"
  | Bool false -> "Focus left"
  | _ -> "Typed interaction received in OCaml"
;;

let make_handlers registry set_model =
  let update name f =
    Driver.Handler.create
      registry
      ~name
      ~equal:( == )
      set_model
      ~f:(fun set_model payload -> set_model (fun model -> f model payload))
  in
  let press =
    update "gallery-press" (fun model _ ->
      { model with press_count = model.press_count + 1 })
  in
  let toggle =
    update "gallery-toggle" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Bool checked -> { model with checked }
      | Unit -> { model with checked = not model.checked }
      | _ -> model)
  in
  let text_edit =
    update "gallery-text-edit" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Text_edit edit ->
        { model with
          text = edit.text
        ; document_revision = ID.Text_input.Document_revision.succ model.document_revision
        ; accepted_local_revision = edit.local_revision
        }
      | _ -> model)
  in
  let text_submit =
    update "gallery-text-submit" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Text value ->
        { model with interaction_status = "Submitted: " ^ value }
      | _ -> model)
  in
  let focus_changed =
    update "gallery-focus" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Bool focused ->
        { model with
          interaction_status =
            (if focused then "Text field focused" else "Text field blurred")
        }
      | _ -> model)
  in
  let interaction =
    update "gallery-interaction" (fun model payload ->
      { model with interaction_status = interaction_label payload })
  in
  let native =
    Driver.Handler.create_native
      registry
      ~name:"gallery-native-card"
      gallery_card
      ~equal:( == )
      set_model
      ~f:(fun set_model Activate ->
        set_model (fun model -> { model with native_count = model.native_count + 1 }))
  in
  let segmented_single =
    update "gallery-segmented-single" (fun model payload ->
      match payload with
      | Ui.Event.Payload.Int64 selected_id ->
        { model with segmented_single_ids = [ selected_id ] }
      | _ -> model)
  in
  let first_pair = Bonsai.Cont.map2 press toggle ~f:(fun press toggle -> press, toggle) in
  let second_pair =
    Bonsai.Cont.map2 text_edit text_submit ~f:(fun text_edit text_submit ->
      text_edit, text_submit)
  in
  let third_pair =
    Bonsai.Cont.map2 focus_changed interaction ~f:(fun focus_changed interaction ->
      focus_changed, interaction)
  in
  let first_half =
    Bonsai.Cont.map2
      first_pair
      second_pair
      ~f:(fun (press, toggle) (text_edit, text_submit) ->
        press, toggle, text_edit, text_submit)
  in
  let second_half =
    Bonsai.Cont.map2 third_pair native ~f:(fun (focus_changed, interaction) native ->
      focus_changed, interaction, native)
  in
  let existing =
    Bonsai.Cont.map2
      first_half
      second_half
      ~f:
        (fun
          (press, toggle, text_edit, text_submit) (focus_changed, interaction, native) ->
        press, toggle, text_edit, text_submit, focus_changed, interaction, native)
  in
  Bonsai.Cont.map2
    existing
    segmented_single
    ~f:
      (fun
        (press, toggle, text_edit, text_submit, focus_changed, interaction, native)
        segmented_single
      ->
      { press
      ; toggle
      ; text_edit
      ; text_submit
      ; focus_changed
      ; interaction
      ; native
      ; segmented_single
      })
;;

let section title children =
  Ui.View.group_box ~label:(Ui.View.text title) (Ui.View.column children)
;;

let text_value model =
  let offset = Ui.Text_editing.Utf16.length model.text in
  let selection =
    Ui.Text_editing.Range.create ~text:model.text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text:model.text ~selection ()
;;

let symbols_section () =
  let names = [ "envelope.fill"; "star.fill"; "person.crop.circle.badge.checkmark" ] in
  let mode label rendering =
    Ui.View.column
      [ Ui.View.text label
      ; Ui.View.row
          (List.map
             (fun name ->
                Ui.View.symbol
                  ~name
                  ~size:32.
                  ~rendering
                  ~color:(Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160)
                  ())
             names)
      ]
  in
  Ui.View.column
    [ Ui.View.text "SF Symbols"
    ; mode "Monochrome" Ui.View.Symbol_rendering.Monochrome
    ; mode "Hierarchical" Ui.View.Symbol_rendering.Hierarchical
    ; mode "Multicolor" Ui.View.Symbol_rendering.Multicolor
    ; Ui.View.row
        [ Ui.View.text "Inherited font and foreground"
        ; Ui.View.symbol ~name:"envelope" ()
        ]
    ]
;;

let frames_section () =
  let symbol () =
    Ui.View.symbol
      ~name:"star.fill"
      ~size:18.
      ~color:(Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160)
      ()
  in
  let row alignments =
    Ui.View.row
      (List.map
         (fun alignment -> Ui.View.frame ~width:72. ~height:48. ~alignment (symbol ()))
         alignments)
  in
  Ui.View.column
    [ Ui.View.text "Frames"
    ; Ui.View.text "Nine alignments in fixed cells"
    ; row Ui.Layout.Alignment.[ Top_start; Top_center; Top_end ]
    ; row Ui.Layout.Alignment.[ Center_start; Center; Center_end ]
    ; row Ui.Layout.Alignment.[ Bottom_start; Bottom_center; Bottom_end ]
    ; Ui.View.text "Fill width, trailing alignment"
    ; Ui.View.frame
        ~min_width:0.
        ~max_width:Ui.Layout.Frame_limit.Fill
        ~height:48.
        ~alignment:Center_end
        (symbol ())
    ; Ui.View.text "Minimum, ideal and maximum dimensions"
    ; Ui.View.frame
        ~min_width:40.
        ~ideal_width:140.
        ~max_width:(Ui.Layout.Frame_limit.Points 220.)
        ~min_height:24.
        ~ideal_height:48.
        ~max_height:(Ui.Layout.Frame_limit.Points 64.)
        (Ui.View.text "Flexible content")
    ; Ui.View.row
        [ Ui.View.text "Flexible gap"
        ; Ui.View.spacer ~min_length:0. ()
        ; Ui.View.text "Trailing"
        ]
    ]
;;

let modifiers_section () =
  let blue = Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160 in
  let orange = Ui.Style.Color.rgb ~red:255 ~green:148 ~blue:40 in
  let symbol () = Ui.View.symbol ~name:"star.fill" ~size:24. ~color:orange () in
  let insets =
    Ui.Layout.Edge_insets.only ~leading:28. ~top:8. ~trailing:4. ~bottom:8. ()
  in
  let padded_background =
    symbol ()
    |> Ui.View.padding ~insets
    |> Ui.View.background ~color:blue ~corner_radius:8.
  in
  let background_padded =
    symbol ()
    |> Ui.View.background ~color:blue ~corner_radius:8.
    |> Ui.View.padding ~insets
  in
  let overflowing () =
    Ui.View.spacer ~min_length:0. ()
    |> Ui.View.frame ~width:110. ~height:52.
    |> Ui.View.background ~color:orange
    |> Ui.View.frame ~width:88. ~height:40.
  in
  Ui.View.column
    [ Ui.View.text "Padding and background order"
    ; Ui.View.row [ padded_background; background_padded ]
    ; Ui.View.text "Explicit rounded clipping"
    ; Ui.View.row
        [ overflowing () |> Ui.View.clip ~corner_radius:12.
        ; overflowing () |> Ui.View.clip ~corner_radius:0. ~antialiased:false
        ]
    ; Ui.View.text "Opacity: 1.0 / 0.6 / 0.2"
    ; Ui.View.row
        (List.map
           (fun value ->
              symbol ()
              |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 10.)
              |> Ui.View.background ~color:blue ~corner_radius:8.
              |> Ui.View.opacity value)
           [ 1.; 0.6; 0.2 ])
    ; Ui.View.text "Leading and trailing follow direction"
    ; Ui.View.frame ~width:240. ~alignment:Center_start padded_background
    ]
;;

let stacks_section () =
  let blue = Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160 in
  let symbol () = Ui.View.symbol ~name:"star.fill" ~size:32. ~color:blue () in
  let surface =
    Ui.View.spacer ~min_length:0. ()
    |> Ui.View.frame ~width:80. ~height:48.
    |> Ui.View.background
         ~color:(Ui.Style.Color.rgb ~red:232 ~green:236 ~blue:244)
         ~corner_radius:8.
  in
  Ui.View.column
    ~spacing:14.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Native spacing and text baselines"
    ; Ui.View.row
        ~spacing:20.
        ~alignment:Ui.Layout.Vertical_alignment.First_text_baseline
        [ Ui.View.text "Two\nlines"; symbol (); Ui.View.text "Baseline" ]
    ; Ui.View.text "Stack alignment"
    ; Ui.View.row
        ~spacing:8.
        (List.map
           (fun alignment -> Ui.View.stack ~alignment [ surface; symbol () ])
           Ui.Layout.Alignment.[ Top_start; Center; Bottom_end ])
    ; Ui.View.text "Priority retains the primary label"
    ; Ui.View.row
        ~spacing:8.
        [ Ui.View.text "Primary content" |> Ui.View.layout_priority 1.
        ; Ui.View.text "Secondary content"
        ]
      |> Ui.View.frame ~width:160.
    ; Ui.View.text "Offset changes placement, not size"
    ; Ui.View.row
        ~spacing:20.
        [ surface; symbol () |> Ui.View.offset ~x:(-10.) ~y:8.; surface ]
    ]
;;

let weights_section () =
  let blue = Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160 in
  let orange = Ui.Style.Color.rgb ~red:255 ~green:148 ~blue:40 in
  let cell label color =
    Ui.View.text label
    |> Ui.View.frame ~min_width:0. ~max_width:Ui.Layout.Frame_limit.Fill ~height:32.
    |> Ui.View.background ~color ~corner_radius:6.
  in
  let vertical_cell label color =
    Ui.View.text label
    |> Ui.View.frame
         ~min_width:0.
         ~max_width:Ui.Layout.Frame_limit.Fill
         ~min_height:0.
         ~max_height:Ui.Layout.Frame_limit.Fill
    |> Ui.View.background ~color ~corner_radius:6.
  in
  Ui.View.column
    ~spacing:12.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Weighted horizontal shares: 1 / 2 / 3"
    ; Ui.View.Weighted.row
        ~spacing:4.
        [ Ui.View.Weighted.share ~weight:1. (cell "1" blue)
        ; Ui.View.Weighted.share ~weight:2. (cell "2" orange)
        ; Ui.View.Weighted.share ~weight:3. (cell "3" blue)
        ]
      |> Ui.View.frame ~width:280.
    ; Ui.View.text "Fixed content and remaining space"
    ; Ui.View.Weighted.row
        ~spacing:8.
        [ Ui.View.Weighted.fixed (Ui.View.text "Fixed")
        ; Ui.View.Weighted.share (cell "Remaining" orange)
        ]
      |> Ui.View.frame ~width:280.
    ; Ui.View.text "Content-sized share"
    ; Ui.View.Weighted.row
        ~spacing:8.
        [ Ui.View.Weighted.share ~fills:false (Ui.View.text "Intrinsic")
        ; Ui.View.Weighted.share (cell "Fill" blue)
        ]
      |> Ui.View.frame ~width:280. ~alignment:Center_start
    ; Ui.View.text "Weighted vertical shares: 1 / 2"
    ; Ui.View.Weighted.column
        ~spacing:4.
        [ Ui.View.Weighted.share (vertical_cell "1" blue)
        ; Ui.View.Weighted.share ~weight:2. (vertical_cell "2" orange)
        ]
      |> Ui.View.frame ~width:280. ~height:96.
    ]
;;

let overlays_section () =
  let blue = Ui.Style.Color.rgb ~red:35 ~green:105 ~blue:170 in
  let orange = Ui.Style.Color.rgb ~red:240 ~green:135 ~blue:35 in
  let block color width height =
    Ui.View.spacer ~min_length:0. ()
    |> Ui.View.frame ~width ~height
    |> Ui.View.background ~color ~corner_radius:6.
  in
  Ui.View.column
    ~spacing:12.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Native overlays"
    ; Ui.View.text "Badge extends beyond the base"
    ; block blue 240. 48.
      |> Ui.View.overlay
           ~alignment:Top_end
           ~overlay:
             (Ui.View.symbol ~name:"star.fill" ~size:24. ~color:orange ()
              |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all (-8.)))
    ; Ui.View.text "Inset content follows the base proposal"
    ; block blue 240. 56.
      |> Ui.View.overlay
           ~overlay:
             (Ui.View.spacer ~min_length:0. ()
              |> Ui.View.background ~color:orange ~corner_radius:3.
              |> Ui.View.frame
                   ~min_width:0.
                   ~max_width:Ui.Layout.Frame_limit.Fill
                   ~min_height:0.
                   ~max_height:Ui.Layout.Frame_limit.Fill
              |> Ui.View.padding
                   ~insets:
                     (Ui.Layout.Edge_insets.only
                        ~leading:24.
                        ~top:8.
                        ~trailing:8.
                        ~bottom:8.
                        ()))
    ; Ui.View.text "Independent corner labels"
    ; block blue 240. 64.
      |> Ui.View.overlay
           ~alignment:Top_start
           ~overlay:
             (Ui.View.text "Leading"
              |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 8.))
      |> Ui.View.overlay
           ~alignment:Bottom_end
           ~overlay:
             (Ui.View.text "Trailing"
              |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 8.))
    ]
;;

let dividers_section () =
  Ui.View.column
    ~spacing:12.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Native separators"
    ; Ui.View.text "In a row"
    ; Ui.View.row
        ~spacing:12.
        [ Ui.View.text "Leading"; Ui.View.divider (); Ui.View.text "Trailing" ]
      |> Ui.View.frame ~height:48.
    ; Ui.View.text "In a column"
    ; Ui.View.divider ()
    ; Ui.View.text "Inset separator"
    ; Ui.View.divider ()
      |> Ui.View.padding
           ~insets:(Ui.Layout.Edge_insets.only ~leading:24. ~trailing:12. ())
    ; Ui.View.text "Native appearance and thickness"
    ]
;;

let images_section () =
  let source = Ui.Style.Image_source.resource "gallery-demo.png" in
  let sample title sizing =
    Ui.View.column
      ~spacing:4.
      ~alignment:Ui.Layout.Horizontal_alignment.Leading
      [ Ui.View.text title
      ; Ui.View.image ~source ~sizing ()
        |> Ui.View.frame ~width:240. ~height:80.
        |> Ui.View.clip ~corner_radius:6.
        |> Ui.View.background ~color:(Ui.Style.Color.rgb ~red:230 ~green:235 ~blue:240)
      ]
  in
  Ui.View.column
    ~spacing:16.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Native image resources"
    ; sample "Original size" Ui.Style.Image_sizing.Original
    ; sample "Stretch" Ui.Style.Image_sizing.Stretch
    ; sample "Aspect Fit" Ui.Style.Image_sizing.Fit
    ; sample "Aspect Fill with explicit clipping" Ui.Style.Image_sizing.Fill
    ; Ui.View.text "Animated resource; Reduce Motion shows its first frame"
    ; Ui.View.image
        ~source:(Ui.Style.Image_source.resource "gallery-animation.gif")
        ~sizing:Ui.Style.Image_sizing.Stretch
        ()
      |> Ui.View.frame ~width:240. ~height:48.
    ]
;;

let text_section () =
  let sample = "A longer mail subject with an important ending" in
  let truncated label truncation =
    Ui.View.column
      ~spacing:4.
      ~alignment:Ui.Layout.Horizontal_alignment.Leading
      [ Ui.View.text label
      ; Ui.View.text ~line_limit:1 ~truncation sample
        |> Ui.View.frame ~width:220. ~alignment:Center_start
      ]
  in
  Ui.View.column
    ~spacing:16.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Native text layout"
    ; truncated "Tail truncation" Ui.Style.Text_truncation.Tail
    ; truncated "Head truncation" Ui.Style.Text_truncation.Head
    ; truncated "Middle truncation" Ui.Style.Text_truncation.Middle
    ; Ui.View.text
        ~style:(Ui.Style.Text_style.create ~font_size:18. ~line_spacing:8. ())
        "Eight-point line spacing\nSecond line\n世界 👩🏽‍💻"
    ; Ui.View.text ~text_align:End "Trailing paragraph alignment\nShort line"
    ; Ui.View.text "**Literal text**, without Markdown interpretation"
    ]
;;

let rich_text_section () =
  let span = Ui.Style.Text_span.create in
  let blue = Ui.Style.Color.rgb ~red:35 ~green:105 ~blue:170 in
  Ui.View.column
    ~spacing:16.
    ~alignment:Ui.Layout.Horizontal_alignment.Leading
    [ Ui.View.text "Attributed text"
    ; Ui.View.rich_text
        [ span "One paragraph, "
        ; span ~font_weight:Bold "multiple styles"
        ; span " and normal text."
        ]
    ; Ui.View.rich_text
        [ span "Unicode: "
        ; span ~font_size:24. ~color:blue ~italic:true "世界 👩🏽‍💻"
        ; span "\nNewlines stay in the same Text."
        ]
    ; Ui.View.rich_text
        [ span ~underline:true "Underline"
        ; span " / "
        ; span ~strikethrough:true "Obsolete text"
        ]
    ; Ui.View.rich_text
        [ span ~font_size:28. "Large "
        ; span ~font_size:14. "and small share a baseline."
        ]
    ; Ui.View.rich_text
        [ span "Long styled runs "
        ; span
            ~font_weight:Semi_bold
            ~color:blue
            "wrap naturally at the available width instead of becoming separate labels."
        ]
    ]
;;

let core_section handlers =
  let decorated =
    Ui.View.background
      ~color:(Ui.Style.Color.rgb ~red:35 ~green:105 ~blue:170)
      ~corner_radius:12.
      (Ui.View.padding
         ~insets:(Ui.Layout.Edge_insets.all 12.)
         (Ui.View.rich_text
            (List.map Ui.Style.Text_span.create [ "Typed "; "core "; "primitives" ])))
  in
  let stack =
    Ui.View.spacer ~min_length:0. ()
    |> Ui.View.frame ~width:180. ~height:54.
    |> Ui.View.overlay
         ~alignment:Top_start
         ~overlay:
           (Ui.View.text "Stack"
            |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.only ~leading:8. ~top:8. ())
           )
    |> Ui.View.overlay
         ~alignment:Bottom_end
         ~overlay:
           (Ui.View.text "Overlay"
            |> Ui.View.padding
                 ~insets:(Ui.Layout.Edge_insets.only ~trailing:8. ~bottom:8. ()))
  in
  section
    "Core layout and visuals"
    [ Ui.View.Weighted.row
        [ Ui.View.Weighted.share decorated
        ; Ui.View.Weighted.fixed
            (Ui.View.padding
               ~insets:(Ui.Layout.Edge_insets.only ~leading:12. ())
               (Ui.View.symbol
                  ~size:28.
                  ~color:(Ui.Style.Color.rgb ~red:244 ~green:180 ~blue:0)
                  ~name:"star.fill"
                  ()))
        ]
    ; Ui.View.frame
        ~max_width:Ui.Layout.Frame_limit.Fill
        ~max_height:Ui.Layout.Frame_limit.Fill
        (Ui.View.frame
           ~min_width:180.
           ~max_width:(Ui.Layout.Frame_limit.Points 320.)
           (Ui.View.clip
              (Ui.View.opacity
                 0.92
                 (Ui.View.projection_effect
                    ~transform:(Ui.Style.Projection.translate ~x:4. ())
                    stack))))
    ; Ui.View.safe_area_padding
        ~insets:(Ui.Layout.Edge_insets.only ~top:4. ())
        (Ui.View.text "Safe-area padding with inherited native environment")
    ; Ui.View.button
        ~style:Ui.View.Button_style.Automatic
        ~on_press:handlers.press
        ~child:(Ui.View.text "Core typed button")
        ()
    ]
;;

let controls_section model handlers =
  let icon name = Ui.View.symbol ~name () in
  let radio_options =
    [ Ui.View.Picker.option ~id:1L ~label:(Ui.View.text "First") ()
    ; Ui.View.Picker.option ~id:2L ~label:(Ui.View.text "Second") ()
    ]
  in
  section
    "Buttons and controls"
    [ Ui.View.button
        ~style:Ui.View.Button_style.Prominent
        ~on_press:handlers.press
        ~child:(Ui.View.text "Prominent button")
        ()
    ; Ui.View.button
        ~style:Ui.View.Button_style.Bordered
        ~on_press:handlers.press
        ~child:(Ui.View.text "Bordered secondary button")
        ()
    ; Ui.View.button
        ~style:Ui.View.Button_style.Bordered
        ~on_press:handlers.press
        ~child:(Ui.View.text "Bordered button")
        ()
    ; Ui.View.button
        ~style:Ui.View.Button_style.Automatic
        ~on_press:handlers.press
        ~child:(Ui.View.text (Printf.sprintf "Pressed %d times" model.press_count))
        ()
    ; Ui.View.button
        ~style:Ui.View.Button_style.Plain
        ~on_press:handlers.press
        ~child:(Ui.View.text "Plain button")
        ()
    ; Ui.View.button
        ~style:Ui.View.Button_style.Plain
        ~on_press:handlers.press
        ~child:
          (Ui.View.semantics
             ~properties:(Ui.Semantics.create ~label:"Favorite" ())
             (Ui.View.symbol ~name:"heart" ()))
        ()
    ; Ui.View.column
        [ Ui.View.row
            (List.map
               (fun size ->
                  Ui.View.button
                    ~style:Ui.View.Button_style.Prominent
                    ~on_press:handlers.press
                    ~child:
                      (Ui.View.semantics
                         ~properties:(Ui.Semantics.create ~label:"Add" ())
                         (icon "plus"))
                    ()
                  |> Ui.View.control_size ~size)
               [ Ui.View.Control_size.Small; Regular; Large ])
        ; Ui.View.button
            ~style:Ui.View.Button_style.Prominent
            ~on_press:handlers.press
            ~child:(Ui.View.label ~title:(Ui.View.text "Create") ~icon:(icon "plus") ())
            ()
        ]
    ; Ui.View.Picker.create
        ~selected_id:(Some 1L)
        ~on_select:handlers.press
        radio_options
        ()
    ; Ui.View.Picker.create
        ~label:"Layout"
        ~style:Ui.View.Picker.Segmented
        ~selected_id:
          (match model.segmented_single_ids with
           | id :: _ -> Some id
           | [] -> None)
        ~on_select:handlers.segmented_single
        [ Ui.View.Picker.option
            ~id:1L
            ~label:(Ui.View.row [ icon "list.bullet"; Ui.View.text "List" ])
            ()
        ; Ui.View.Picker.option
            ~id:2L
            ~label:(Ui.View.row [ icon "square.grid.2x2"; Ui.View.text "Grid" ])
            ()
        ; Ui.View.Picker.option ~id:3L ~enabled:false ~label:(Ui.View.text "Disabled") ()
        ]
        ()
    ; Ui.View.Picker.create
        ~label:"Disabled layout"
        ~style:Ui.View.Picker.Segmented
        ~enabled:false
        ~selected_id:(Some 1L)
        ~on_select:handlers.segmented_single
        [ Ui.View.Picker.option ~id:1L ~label:(Ui.View.text "List") ()
        ; Ui.View.Picker.option ~id:2L ~label:(Ui.View.text "Grid") ()
        ]
        ()
    ; Ui.View.Slider.create
        ~value:0.35
        ~step:0.1
        ~label:"Single value"
        ~on_change:handlers.press
        ~on_change_end:handlers.press
        ()
    ; Ui.View.Slider.range
        ~value:(Ui.View.Slider.Range.create ~start:0.2 ~end_:0.8)
        ~step:0.1
        ~label_start:"Low"
        ~label_end:"High"
        ~on_change:handlers.press
        ~on_change_end:handlers.press
        ()
    ; Ui.View.help ~message:"Native help text" (Ui.View.text "Hover for help")
    ; Ui.View.frame
        ~height:280.
        (Ui.Workflow.create
           ~layout:Ui.Workflow.Horizontal
           ~current_step_id:1L
           ~on_continue:handlers.press
           ~on_back:handlers.press
           [ Ui.Workflow.step
               ~id:1L
               ~title:(Ui.View.text "Edit")
               ~content:(Ui.View.text "Edit content")
               ()
           ; Ui.Workflow.step
               ~id:2L
               ~state:Ui.Workflow.Complete
               ~title:(Ui.View.text "Review")
               ~content:(Ui.View.text "Review content")
               ()
           ]
           ())
    ; Ui.View.disclosure_group
        ~expanded:model.checked
        ~on_changed:handlers.toggle
        ~label:(Ui.View.text "Panel details")
        ~content:(Ui.View.text "Panel body")
        ()
    ; Ui.View.row
        [ Ui.View.toggle
            ~style:Ui.View.Toggle_style.Checkbox
            ~label:(Ui.View.text "Completed")
            ~value:model.checked
            ~on_changed:handlers.toggle
            ()
        ; Ui.View.toggle
            ~style:Ui.View.Toggle_style.Switch
            ~label:(Ui.View.text "Enabled")
            ~value:model.checked
            ~on_changed:handlers.toggle
            ()
        ; Ui.View.toggle
            ~style:Ui.View.Toggle_style.Switch
            ~label:(Ui.View.text "Notifications")
            ~value:model.checked
            ~on_changed:handlers.toggle
            ()
        ]
    ; Ui.View.row
        [ Ui.View.group_box (Ui.View.text "Unlabelled group")
        ; Ui.View.group_box ~label:(Ui.View.text "Label") (Ui.View.text "Group content")
        ; Ui.View.group_box (Ui.View.group_box (Ui.View.text "Nested group"))
        ; Ui.View.divider ()
          |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:16. ())
        ]
    ; Ui.View.divider ()
    ; Ui.View.row
        [ Ui.View.progress ~style:Ui.View.Progress_style.Circular ~value:0.68 ()
        ; Ui.View.button
            ~style:Ui.View.Button_style.Plain
            ~on_press:handlers.press
            ~child:(Ui.View.text "Plain button")
            ()
        ]
    ; Ui.View.column
        [ Ui.View.text "Determinate linear progress"
        ; Ui.View.frame ~width:240. (Ui.View.progress ~value:0.68 ())
        ; Ui.View.text "Indeterminate linear progress"
        ; Ui.View.frame ~width:240. (Ui.View.progress ())
        ]
    ]
;;

let native_controls_catalog_section handlers =
  let icon name = Ui.View.symbol ~name () in
  let menu =
    [ Ui.View.Menu.action ~id:100L ~label:(Ui.View.text "Open") ()
    ; Ui.View.Menu.choice ~id:101L ~label:(Ui.View.text "Selected") ~selected:true ()
    ; Ui.View.Menu.choice ~id:102L ~label:(Ui.View.text "Pinned") ~selected:false ()
    ; Ui.View.Menu.divider ~id:105L
    ; Ui.View.Menu.section
        ~id:106L
        ~label:(Ui.View.text "Export")
        [ Ui.View.Menu.submenu
            ~id:103L
            ~label:(Ui.View.text "Format")
            [ Ui.View.Menu.action ~id:104L ~label:(Ui.View.text "PDF") () ]
        ]
    ]
  in
  section
    "Native controls catalog"
    [ Ui.View.Menu.create
        ~on_select:handlers.interaction
        ~label:(Ui.View.label ~title:(Ui.View.text "Create") ~icon:(icon "plus") ())
        [ Ui.View.Menu.action
            ~id:105L
            ~label:
              (Ui.View.label ~title:(Ui.View.text "Compose") ~icon:(icon "envelope") ())
            ()
        ]
    ; Ui.View.toggle
        ~style:Ui.View.Toggle_style.Button
        ~value:true
        ~on_changed:handlers.toggle
        ~label:(Ui.View.text "Toggle")
        ()
    ; Ui.View.row
        [ Ui.View.button
            ~style:Ui.View.Button_style.Prominent
            ~on_press:handlers.press
            ~child:(Ui.View.text "Export")
            ()
        ; Ui.View.Menu.create
            ~on_select:handlers.interaction
            ~label:(Ui.View.text "Export options")
            menu
        ]
    ; Ui.View.row
        [ Ui.View.frame
            ~width:180.
            (Ui.View.Slider.create
               ~label:"Value"
               ~value:0.35
               ~on_change_end:handlers.interaction
               ())
        ; Ui.View.frame
            ~width:180.
            (Ui.View.Slider.create
               ~label:"Value"
               ~value:0.65
               ~on_change_end:handlers.interaction
               ())
        ; Ui.View.frame
            ~width:80.
            ~height:180.
            (Ui.View.Slider.create
               ~label:"Value"
               ~axis:Ui.Layout.Axis.Vertical
               ~value:0.5
               ~on_change_end:handlers.interaction
               ())
        ]
    ; Ui.View.Slider.range
        ~label_start:"Lower value"
        ~label_end:"Upper value"
        ~value:(Ui.View.Slider.Range.create ~start:0.2 ~end_:0.8)
        ~on_change_end:handlers.interaction
        ()
    ]
;;

let interaction_section model handlers =
  let target =
    Ui.View.keyboard_listener
      ~autofocus:true
      ~key_policy:Ui.Event.Key_policy.Ignored
      ~on_key:handlers.interaction
      (Ui.View.focus_scope
         ~on_focus_changed:handlers.interaction
         (Ui.View.hover_region
            ~on_enter:handlers.interaction
            ~on_leave:handlers.interaction
            (Ui.View.gesture
               ~on_tap:handlers.interaction
               ~on_double_tap:handlers.interaction
               ~on_long_press:handlers.interaction
               ~on_pointer_down:handlers.interaction
               ~on_pointer_up:handlers.interaction
               (Ui.View.padding
                  ~insets:(Ui.Layout.Edge_insets.all 14.)
                  (Ui.View.text model.interaction_status)))))
  in
  section "Interactions" [ target ]
;;

let text_input_section model handlers =
  section
    "Text input and IME"
    [ Ui.View.text_field
        ~label:"Text input"
        ~session_id:(ID.Text_input.Session_id.of_int64 1L)
        ~document_revision:model.document_revision
        ~accepted_local_revision:model.accepted_local_revision
        ~update_mode:Ui.Text_editing.Ack
        ~value:(text_value model)
        ~on_edit:handlers.text_edit
        ~on_submit:handlers.text_submit
        ~on_focus_changed:handlers.focus_changed
        ()
    ; Ui.View.text ("Canonical OCaml value: " ^ model.text)
    ]
;;

let native_section model handlers =
  section
    "Native extension"
    [ Ui.Native_widget.widget_with_handler
        gallery_card
        ~key:(Ui.Key.string "gallery-native-card")
        ~props:(Printf.sprintf "Native card: %d" model.native_count)
        ~on_event:handlers.native
        ()
    ]
;;

let slider_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (20., 20., 40., true, false, 0) graph
  in
  let change name range ended =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        set_state (fun ((level, lower, upper, enabled, ignore, ends) as state) ->
          if (not enabled) || ignore
          then state
          else (
            let ends = ends + if ended then 1 else 0 in
            match payload with
            | Ui.Event.Payload.Float value when not range ->
              value, lower, upper, enabled, ignore, ends
            | Float_range { start; end_ } when range ->
              level, start, end_, enabled, ignore, ends
            | _ -> state)))
  in
  let control name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let inputs =
    [ change "level-change" false false
    ; change "level-end" false true
    ; change "range-change" true false
    ; change "range-end" true true
    ; control "sliders-enabled" (fun (v, l, u, e, i, n) -> v, l, u, not e, i, n)
    ; control "sliders-ignore" (fun (v, l, u, e, i, n) -> v, l, u, e, not i, n)
    ]
  in
  let inputs =
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      inputs
      (Bonsai.Cont.return [])
  in
  Bonsai.Cont.map2
    state
    inputs
    ~f:(fun (level, lower, upper, enabled, ignored, ends) -> function
    | [ level_change; level_end; range_change; range_end; toggle_enabled; toggle_ignore ]
      ->
      Ui.View.column
        [ Ui.View.text (Printf.sprintf "Ended: %d" ends)
        ; Ui.View.frame
            ~width:300.
            (Ui.View.Slider.create
               ~key:(Ui.Key.string "gallery-level")
               ~value:level
               ~min:0.
               ~max:100.
               ~step:10.
               ~enabled
               ~label:"Level"
               ~on_change:level_change
               ~on_change_end:level_end
               ())
        ; Ui.View.frame
            ~width:300.
            (Ui.View.Slider.range
               ~key:(Ui.Key.string "gallery-interval")
               ~value:(Ui.View.Slider.Range.create ~start:lower ~end_:upper)
               ~min:0.
               ~max:100.
               ~step:10.
               ~enabled
               ~label_start:"Lower"
               ~label_end:"Upper"
               ~on_change:range_change
               ~on_change_end:range_end
               ())
        ; Ui.View.frame
            ~width:80.
            ~height:180.
            (Ui.View.Slider.create
               ~key:(Ui.Key.string "gallery-vertical")
               ~value:level
               ~min:0.
               ~max:100.
               ~step:10.
               ~axis:Ui.Layout.Axis.Vertical
               ~enabled
               ~label:"Vertical level"
               ~on_change_end:level_end
               ())
        ; Ui.View.button
            ~on_press:toggle_enabled
            ~child:
              (Ui.View.text (if enabled then "Disable sliders" else "Enable sliders"))
            ()
        ; Ui.View.button
            ~on_press:toggle_ignore
            ~child:(Ui.View.text (if ignored then "Accept changes" else "Ignore changes"))
            ()
        ]
    | _ -> assert false)
;;

let choice_picker_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (Some (-1L), true, false, false) graph
  in
  let change =
    Driver.Handler.create
      handlers
      ~name:"picker-selection"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Int64 value when value = -1L || value = 2L ->
        set_state (fun (selected, enabled, ignore, reverse) ->
          ( (if enabled && not ignore then Some value else selected)
          , enabled
          , ignore
          , reverse ))
      | _ -> Bonsai.Effect.Ignore)
  in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let enabled = action "picker-enabled" (fun (s, e, i, r) -> s, not e, i, r) in
  let ignore = action "picker-ignore" (fun (s, e, i, r) -> s, e, not i, r) in
  let reverse = action "picker-reverse" (fun (s, e, i, r) -> s, e, i, not r) in
  let clear = action "picker-clear" (fun (_, e, i, r) -> None, e, i, r) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       change
       (Bonsai.Cont.both
          enabled
          (Bonsai.Cont.both ignore (Bonsai.Cont.both reverse clear))))
    ~f:
      (fun
        (selected, enabled, ignored, reversed)
        (change, (enable, (ignore, (reverse, clear)))) ->
      let label title symbol =
        Ui.View.label
          ~title:(Ui.View.text title)
          ~icon:(Ui.View.symbol ~name:symbol ())
          ()
      in
      let choices =
        [ Ui.View.Picker.option ~id:(-1L) ~label:(label "First" "list.bullet") ()
        ; Ui.View.Picker.option ~id:2L ~label:(label "Second" "square.grid.2x2") ()
        ; Ui.View.Picker.option ~id:3L ~enabled:false ~label:(Ui.View.text "Disabled") ()
        ]
      in
      let choices = if reversed then List.rev choices else choices in
      let pickers =
        List.map
          (fun (label, style) ->
             Ui.View.Picker.create
               ~key:(Ui.Key.string ("picker-" ^ label))
               ~label
               ~style
               ~enabled
               ~selected_id:selected
               ~on_select:change
               choices
               ())
          [ "Automatic", Ui.View.Picker.Automatic
          ; "Menu", Menu
          ; "Segmented", Segmented
          ; "Inline", Inline
          ]
      in
      let button label on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text label) ()
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        (pickers
         @ [ button (if enabled then "Disable pickers" else "Enable pickers") enable
           ; button
               (if ignored then "Accept picker changes" else "Ignore picker changes")
               ignore
           ; button "Reverse picker options" reverse
           ; button "Clear picker selection" clear
           ]))
;;

let civil_picker_component handlers graph =
  let initial_date = Ui.View.Date.create ~year:2024 ~month:2 ~day:29 in
  let initial_time = Ui.View.Time.create ~hour:12 ~minute:0 in
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      (initial_date, initial_time, true, false, false, false)
      graph
  in
  let change name =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        set_state (fun (date, time, enabled, ignore, restricted, replacement) ->
          if (not enabled) || ignore
          then date, time, enabled, ignore, restricted, replacement
          else (
            match payload with
            | Ui.Event.Payload.Civil_date { year; month; day } ->
              ( Ui.View.Date.create ~year ~month ~day
              , time
              , enabled
              , ignore
              , restricted
              , replacement )
            | Ui.Event.Payload.Civil_time { hour; minute } ->
              ( date
              , Ui.View.Time.create ~hour ~minute
              , enabled
              , ignore
              , restricted
              , replacement )
            | _ -> date, time, enabled, ignore, restricted, replacement)))
  in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let enable = action "civil-enable" (fun (d, t, e, i, r, b) -> d, t, not e, i, r, b) in
  let ignore = action "civil-ignore" (fun (d, t, e, i, r, b) -> d, t, e, not i, r, b) in
  let restrict =
    action "civil-restrict" (fun (_, t, e, i, r, b) -> initial_date, t, e, i, not r, b)
  in
  let replace = action "civil-replace" (fun (d, t, e, i, r, b) -> d, t, e, i, r, not b) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (change "civil-first")
       (Bonsai.Cont.both
          (change "civil-replacement")
          (Bonsai.Cont.both
             enable
             (Bonsai.Cont.both ignore (Bonsai.Cont.both restrict replace)))))
    ~f:
      (fun
        (date, time, enabled, ignored, restricted, replacement)
        (first, (second, (enable, (ignore, (restrict, replace))))) ->
      let on_change = if replacement then second else first in
      Ui.View.column
        [ Ui.View.text "Civil date and time"
        ; Ui.View.Date_picker.create
            ~key:(Ui.Key.string "civil-date")
            ~label:"Delivery date"
            ~selected:date
            ~first:initial_date
            ~last:(Ui.View.Date.create ~year:2025 ~month:3 ~day:10)
            ~selectable_dates:
              (if restricted
               then
                 [ initial_date
                 ; Ui.View.Date.create ~year:2025 ~month:1 ~day:2
                 ; Ui.View.Date.create ~year:2025 ~month:3 ~day:10
                 ]
               else [])
            ~enabled
            ~on_select:on_change
            ()
        ; Ui.View.Time_picker.create
            ~key:(Ui.Key.string "civil-time")
            ~label:"Delivery time"
            ~value:time
            ~enabled
            ~format:Ui.View.Time_picker.Hour_24
            ~on_changed:on_change
            ()
        ; Ui.View.text
            (Printf.sprintf
               "Selected: %04d-%02d-%02d %02d:%02d"
               date.year
               date.month
               date.day
               time.hour
               time.minute)
        ; Ui.View.button
            ~on_press:enable
            ~child:
              (Ui.View.text
                 (if enabled then "Disable civil controls" else "Enable civil controls"))
            ()
        ; Ui.View.button
            ~on_press:ignore
            ~child:
              (Ui.View.text
                 (if ignored then "Accept civil changes" else "Ignore civil changes"))
            ()
        ; Ui.View.button
            ~on_press:restrict
            ~child:
              (Ui.View.text (if restricted then "Allow date range" else "Restrict dates"))
            ()
        ; Ui.View.button
            ~on_press:replace
            ~child:(Ui.View.text "Replace civil handlers")
            ()
        ])
;;

let menu_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) ([], false, true, false, false) graph
  in
  let selected name =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Int64 id when List.mem id [ -7L; 9L; 21L ] ->
        set_state (fun (history, checked, enabled, ignored, replacement) ->
          if (not enabled) || ignored
          then history, checked, enabled, ignored, replacement
          else
            ( history @ [ id ]
            , (if id = 9L then not checked else checked)
            , enabled
            , ignored
            , replacement ))
      | _ -> Bonsai.Effect.Ignore)
  in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let enable = action "menu-enable" (fun (h, c, e, i, r) -> h, c, not e, i, r) in
  let ignore = action "menu-ignore" (fun (h, c, e, i, r) -> h, c, e, not i, r) in
  let replace = action "menu-replace" (fun (h, c, e, i, r) -> h, c, e, i, not r) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (selected "menu-original")
       (Bonsai.Cont.both
          (selected "menu-replacement")
          (Bonsai.Cont.both enable (Bonsai.Cont.both ignore replace))))
    ~f:
      (fun
        (history, checked, enabled, ignored, replacement)
        (first, (second, (enable, (ignore, replace)))) ->
      let on_select = if replacement then second else first in
      Ui.View.column
        [ Ui.View.Menu.create
            ~key:(Ui.Key.string "native-menu")
            ~enabled
            ~on_select
            ~label:
              (Ui.View.label
                 ~title:(Ui.View.text "Actions")
                 ~icon:(Ui.View.symbol ~name:"ellipsis.circle" ())
                 ())
            [ Ui.View.Menu.action
                ~id:(-7L)
                ~label:
                  (Ui.View.label
                     ~title:(Ui.View.text "Open")
                     ~icon:(Ui.View.symbol ~name:"folder" ())
                     ())
                ()
            ; Ui.View.Menu.divider ~id:50L
            ; Ui.View.Menu.section
                ~id:40L
                ~label:(Ui.View.text "Preferences")
                [ Ui.View.Menu.choice
                    ~id:9L
                    ~label:(Ui.View.text "Pinned")
                    ~selected:checked
                    ()
                ; Ui.View.Menu.action
                    ~id:11L
                    ~enabled:false
                    ~label:(Ui.View.text "Disabled action")
                    ()
                ]
            ; Ui.View.Menu.submenu
                ~id:20L
                ~label:(Ui.View.text "Export")
                [ Ui.View.Menu.action ~id:21L ~label:(Ui.View.text "PDF") () ]
            ; Ui.View.Menu.submenu
                ~id:30L
                ~enabled:false
                ~label:(Ui.View.text "Unavailable")
                [ Ui.View.Menu.action ~id:22L ~label:(Ui.View.text "Unavailable child") ()
                ]
            ]
        ; Ui.View.text ("Actions: " ^ String.concat "," (List.map Int64.to_string history))
        ; Ui.View.button
            ~on_press:enable
            ~child:(Ui.View.text (if enabled then "Disable menu" else "Enable menu"))
            ()
        ; Ui.View.button
            ~on_press:ignore
            ~child:
              (Ui.View.text
                 (if ignored then "Accept menu changes" else "Ignore menu changes"))
            ()
        ; Ui.View.button ~on_press:replace ~child:(Ui.View.text "Replace menu handler") ()
        ])
;;

let picker_component handlers graph =
  Bonsai.Cont.map2
    (Bonsai.Cont.both
       (choice_picker_component handlers graph)
       (civil_picker_component handlers graph))
    (Bonsai.Cont.both
       (menu_component handlers graph)
       (Selection_catalog.component handlers graph))
    ~f:(fun (choices, civil) (menu, selection) ->
      Ui.View.column [ choices; civil; menu; selection ])
;;

let multiple_selection_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) ([], true, false, false) graph in
  let choices = [ -1L, "First"; 2L, "Second"; 3L, "Disabled" ] in
  let changes =
    List.map
      (fun (id, _) ->
         Driver.Handler.create
           handlers
           ~name:("multiple-" ^ Int64.to_string id)
           ~equal:( == )
           set_state
           ~f:(fun set_state -> function
             | Ui.Event.Payload.Bool value ->
               set_state (fun (selected, enabled, ignored, reversed) ->
                 let selected =
                   if (not enabled) || ignored || id = 3L
                   then selected
                   else (
                     let rest = List.filter (fun old -> old <> id) selected in
                     if value then List.sort Int64.compare (id :: rest) else rest)
                 in
                 selected, enabled, ignored, reversed)
             | _ -> Bonsai.Effect.Ignore))
      choices
  in
  let changes =
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      changes
      (Bonsai.Cont.return [])
  in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let enable = action "multiple-enable" (fun (s, e, i, r) -> s, not e, i, r) in
  let ignore = action "multiple-ignore" (fun (s, e, i, r) -> s, e, not i, r) in
  let reverse = action "multiple-reverse" (fun (s, e, i, r) -> s, e, i, not r) in
  let clear = action "multiple-clear" (fun (_, e, i, r) -> [], e, i, r) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       changes
       (Bonsai.Cont.both
          enable
          (Bonsai.Cont.both ignore (Bonsai.Cont.both reverse clear))))
    ~f:
      (fun
        (selected, enabled, ignored, reversed)
        (changes, (enable, (ignore, (reverse, clear)))) ->
      let options = List.combine choices changes in
      let options = if reversed then List.rev options else options in
      let group title style =
        Ui.View.column
          ~key:(Ui.Key.string title)
          ~spacing:8.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          (Ui.View.text title
           :: List.map
                (fun ((id, label), on_changed) ->
                   Ui.View.toggle
                     ~key:(Ui.Key.int64 id)
                     ~style
                     ~enabled:(enabled && id <> 3L)
                     ~value:(List.mem id selected)
                     ~on_changed
                     ~label:
                       (let text = Ui.View.text (title ^ " " ^ label) in
                        if id = 3L
                        then text
                        else
                          Ui.View.row
                            ~spacing:6.
                            [ Ui.View.symbol
                                ~name:
                                  (if id = -1L then "list.bullet" else "square.grid.2x2")
                                ()
                            ; text
                            ])
                     ())
                options)
      in
      let button title on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text title) ()
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        [ group "Buttons" Ui.View.Toggle_style.Button
        ; group "Checkboxes" Ui.View.Toggle_style.Checkbox
        ; button (if enabled then "Disable choices" else "Enable choices") enable
        ; button (if ignored then "Accept choices" else "Ignore choices") ignore
        ; button "Reverse choices" reverse
        ; button "Clear choices" clear
        ])
;;

type opacity_model =
  { opacity_target : float
  ; opacity_id : int64
  ; opacity_duration : int
  ; opacity_completed : int64 list
  ; opacity_shown : bool
  }

let opacity_component handlers graph =
  let initial =
    { opacity_target = 1.
    ; opacity_id = 0L
    ; opacity_duration = 1200
    ; opacity_completed = []
    ; opacity_shown = true
    }
  in
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name f =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun model -> f model payload))
  in
  let target name value duration =
    bind name (fun m _ ->
      { m with
        opacity_target =
          (match value with
           | None -> m.opacity_target
           | Some value -> value)
      ; opacity_id = Int64.succ m.opacity_id
      ; opacity_duration = duration
      })
  in
  let fade = target "opacity-fade" (Some 0.2) 1200 in
  let restore = target "opacity-restore" (Some 1.) 1200 in
  let repeat = target "opacity-repeat" None 1200 in
  let instant = target "opacity-instant" (Some 0.6) 0 in
  let show =
    bind "opacity-show" (fun m _ -> { m with opacity_shown = not m.opacity_shown })
  in
  let completed =
    bind "opacity-completed" (fun m -> function
      | Ui.Event.Payload.Int64 id ->
        { m with opacity_completed = m.opacity_completed @ [ id ] }
      | _ -> m)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       fade
       (Bonsai.Cont.both
          restore
          (Bonsai.Cont.both
             repeat
             (Bonsai.Cont.both instant (Bonsai.Cont.both show completed)))))
    ~f:(fun m (fade, (restore, (repeat, (instant, (show, completed))))) ->
      let button title handler =
        Ui.View.button ~on_press:handler ~child:(Ui.View.text title) ()
      in
      let content =
        Ui.View.row
          ~spacing:8.
          [ Ui.View.symbol ~name:"star.fill" ~size:60. ()
          ; Ui.View.text "Animation preview"
          ]
      in
      let curve =
        match Int64.to_int (Int64.rem m.opacity_id 4L) with
        | 0 -> Ui.Animation.Curve.Linear
        | 1 -> Ease_in
        | 2 -> Ease_out
        | _ -> Ease_in_out
      in
      Ui.View.column
        ~spacing:12.
        [ Ui.View.text ("Opacity request: " ^ Int64.to_string m.opacity_id)
        ; Ui.View.text
            ("Completed: "
             ^
             if m.opacity_completed = []
             then "none"
             else String.concat "," (List.map Int64.to_string m.opacity_completed))
        ; Ui.View.frame
            ~height:100.
            (if m.opacity_shown
             then
               Ui.View.toggle
                 ~style:Ui.View.Toggle_style.Button
                 ~enabled:false
                 ~value:false
                 ~on_changed:show
                 ~label:
                   (Ui.View.animated_opacity
                      ~key:(Ui.Key.string "animated-opacity")
                      ~animation:
                        (Ui.Animation.create
                           ~id:
                             (Bonsai_swiftui_spec.Id.Ui.Animation_id.of_int64
                                m.opacity_id)
                           ~duration_ms:m.opacity_duration
                           ~curve
                           ())
                      ~opacity:m.opacity_target
                      ~on_completed:completed
                      content)
                 ()
             else Ui.View.text "Animation removed")
        ; button "Fade out" fade
        ; button "Restore opacity" restore
        ; button "Repeat opacity target" repeat
        ; button "Instant opacity" instant
        ; button
            (if m.opacity_shown then "Remove animation" else "Restore animation")
            show
        ])
;;

let projection_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0, 0) graph in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let next = bind "projection-next" (fun (mode, count) -> (mode + 1) mod 4, count) in
  let press = bind "projection-press" (fun (mode, count) -> mode, count + 1) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both next press)
    ~f:(fun (mode, count) (next, press) ->
      let transform =
        match mode with
        | 0 -> Ui.Style.Projection.identity
        | 1 -> Ui.Style.Projection.scale ~x:0.8 ~y:1.2 ()
        | 2 ->
          Ui.Style.Projection.matrix3 [| 1.; 0.2; 0.002; 0.3; 1.; 0.001; 0.; 0.; 1. |]
        | _ -> Ui.Style.Projection.translate ~x:16. ~y:8. ()
      in
      Ui.View.column
        ~spacing:20.
        [ Ui.View.text ("Projection mode: " ^ Int.to_string mode)
        ; Ui.View.text ("Projected actions: " ^ Int.to_string count)
        ; Ui.View.frame
            ~height:100.
            (Ui.View.projection_effect
               ~key:(Ui.Key.string "projection")
               ~transform
               (Ui.View.button
                  ~key:(Ui.Key.string "projected-button")
                  ~style:Ui.View.Button_style.Bordered
                  ~on_press:press
                  ~child:
                    (Ui.View.row
                       ~spacing:6.
                       [ Ui.View.symbol ~name:"star.fill" ()
                       ; Ui.View.text "Projected action"
                       ])
                  ()))
        ; Ui.View.button ~on_press:next ~child:(Ui.View.text "Next projection") ()
        ])
;;

let button_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (2, true, 0) graph in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let press = bind "button-action" (fun (s, e, n) -> s, e, if e then n + 1 else n) in
  let next = bind "button-next-size" (fun (s, e, n) -> (s + 1) mod 5, e, n) in
  let enable = bind "button-enable" (fun (s, e, n) -> s, not e, n) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both press (Bonsai.Cont.both next enable))
    ~f:(fun (index, enabled, count) (press, (next, enable)) ->
      let title, size =
        List.nth
          [ "Mini", Ui.View.Control_size.Mini
          ; "Small", Small
          ; "Regular", Regular
          ; "Large", Large
          ; "Extra large", Extra_large
          ]
          index
      in
      let button title style =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~enabled
          ~style
          ~on_press:press
          ~child:(Ui.View.text title)
          ()
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        [ Ui.View.text ("Button actions: " ^ Int.to_string count)
        ; Ui.View.text ("Size: " ^ title)
        ; Ui.View.control_size
            ~key:(Ui.Key.string "button-controls")
            ~size
            (Ui.View.column
               ~spacing:12.
               ~alignment:Ui.Layout.Horizontal_alignment.Leading
               [ button "Automatic" Ui.View.Button_style.Automatic
               ; button "Bordered" Ui.View.Button_style.Bordered
               ; button "Prominent" Ui.View.Button_style.Prominent
               ; Ui.View.button
                   ~key:(Ui.Key.string "refresh")
                   ~enabled
                   ~style:Ui.View.Button_style.Plain
                   ~on_press:press
                   ~child:
                     (Ui.View.semantics
                        ~properties:(Ui.Semantics.create ~label:"Refresh" ())
                        (Ui.View.symbol ~name:"arrow.clockwise" ()))
                   ()
               ])
        ; Ui.View.button ~on_press:next ~child:(Ui.View.text "Next control size") ()
        ; Ui.View.button
            ~on_press:enable
            ~child:
              (Ui.View.text (if enabled then "Disable buttons" else "Enable buttons"))
            ()
        ])
;;

type tag_model =
  { tag_actions : int
  ; tag_filter : bool
  ; tag_suggested : bool
  ; tag_ids : int64 list
  ; tag_selected : int64 list
  ; tag_enabled : bool
  ; tag_ignored : bool
  ; tag_reversed : bool
  }

let tag_component handlers graph =
  let initial =
    { tag_actions = 0
    ; tag_filter = false
    ; tag_suggested = true
    ; tag_ids = [ -1L; 2L; 3L ]
    ; tag_selected = []
    ; tag_enabled = true
    ; tag_ignored = false
    ; tag_reversed = false
    }
  in
  let model, set_model = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name f =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_model
      ~f:(fun set_model payload -> set_model (fun model -> f model payload))
  in
  let business name f =
    bind name (fun model payload ->
      if model.tag_enabled && not model.tag_ignored then f model payload else model)
  in
  let action =
    business "tag-action" (fun m _ -> { m with tag_actions = m.tag_actions + 1 })
  in
  let filter =
    business "tag-filter" (fun m -> function
      | Ui.Event.Payload.Bool value -> { m with tag_filter = value }
      | _ -> m)
  in
  let suggested =
    business "tag-suggested" (fun m -> function
      | Ui.Event.Payload.Bool value -> { m with tag_suggested = value }
      | _ -> m)
  in
  let tags =
    List.map
      (fun id ->
         let select =
           business
             ("tag-select-" ^ Int64.to_string id)
             (fun m -> function
               | Ui.Event.Payload.Bool value when List.mem id m.tag_ids ->
                 let rest = List.filter (fun old -> old <> id) m.tag_selected in
                 { m with
                   tag_selected =
                     (if value then List.sort Int64.compare (id :: rest) else rest)
                 }
               | _ -> m)
         in
         let remove =
           business
             ("tag-remove-" ^ Int64.to_string id)
             (fun m _ ->
                if id = 3L
                then m
                else
                  { m with
                    tag_ids = List.filter (fun old -> old <> id) m.tag_ids
                  ; tag_selected = List.filter (fun old -> old <> id) m.tag_selected
                  })
         in
         Bonsai.Cont.both select remove)
      initial.tag_ids
  in
  let tags =
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      tags
      (Bonsai.Cont.return [])
  in
  let enable =
    bind "tag-enable" (fun m _ -> { m with tag_enabled = not m.tag_enabled })
  in
  let ignore =
    bind "tag-ignore" (fun m _ -> { m with tag_ignored = not m.tag_ignored })
  in
  let reverse =
    bind "tag-reverse" (fun m _ -> { m with tag_reversed = not m.tag_reversed })
  in
  let restore =
    bind "tag-restore" (fun m _ ->
      { m with tag_ids = initial.tag_ids; tag_selected = [] })
  in
  Bonsai.Cont.map2
    model
    (Bonsai.Cont.both
       action
       (Bonsai.Cont.both
          filter
          (Bonsai.Cont.both
             suggested
             (Bonsai.Cont.both
                tags
                (Bonsai.Cont.both
                   enable
                   (Bonsai.Cont.both ignore (Bonsai.Cont.both reverse restore)))))))
    ~f:
      (fun
        m
        (action, (filter, (suggested, (tags, (enable, (ignore, (reverse, restore))))))) ->
      let label name symbol =
        Ui.View.row ~spacing:6. [ Ui.View.symbol ~name:symbol (); Ui.View.text name ]
      in
      let button ?(enabled = true) ?(style = Ui.View.Button_style.Bordered) title handler =
        Ui.View.button ~enabled ~style ~on_press:handler ~child:(Ui.View.text title) ()
      in
      let toggle title symbol value handler =
        Ui.View.toggle
          ~style:Ui.View.Toggle_style.Button
          ~enabled:m.tag_enabled
          ~value
          ~on_changed:handler
          ~label:(label title symbol)
          ()
      in
      let ids = if m.tag_reversed then List.rev m.tag_ids else m.tag_ids in
      let handlers = List.combine initial.tag_ids tags in
      let tokens =
        List.map
          (fun id ->
             let name, symbol =
               if id = -1L
               then "Work", "briefcase"
               else if id = 2L
               then "Personal", "person"
               else "Pinned", "pin"
             in
             let select, remove = List.assoc id handlers in
             Ui.View.row
               ~key:(Ui.Key.int64 id)
               ~spacing:8.
               (toggle name symbol (List.mem id m.tag_selected) select
                ::
                (if id = 3L
                 then []
                 else [ button ~enabled:m.tag_enabled ("Remove " ^ name) remove ])))
          ids
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        ([ Ui.View.text ("Actions: " ^ Int.to_string m.tag_actions)
         ; button ~enabled:m.tag_enabled "Assist" action
         ; button
             ~enabled:m.tag_enabled
             ~style:Ui.View.Button_style.Prominent
             "Suggestion"
             action
         ; toggle "Filter" "line.3.horizontal.decrease" m.tag_filter filter
         ; toggle "Suggested" "sparkles" m.tag_suggested suggested
         ]
         @ [ Ui.View.flow
               ~key:(Ui.Key.string "tags")
               ~spacing:12.
               ~line_spacing:12.
               tokens
           ]
         @ [ button (if m.tag_enabled then "Disable tags" else "Enable tags") enable
           ; button
               (if m.tag_ignored then "Accept tag changes" else "Ignore tag changes")
               ignore
           ; button "Reverse tags" reverse
           ; button "Restore tags" restore
           ]))
;;

let toggle_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) ([ false; false; false; false ], true, false) graph
  in
  let modes =
    [ "Automatic", Ui.View.Toggle_style.Automatic
    ; "Switch", Switch
    ; "Checkbox", Checkbox
    ; "Button", Button
    ]
  in
  let changes =
    List.mapi
      (fun index (name, _) ->
         Driver.Handler.create
           handlers
           ~name:("toggle-" ^ name)
           ~equal:( == )
           set_state
           ~f:(fun set_state payload ->
             match payload with
             | Ui.Event.Payload.Bool value ->
               set_state (fun (values, enabled, ignore) ->
                 ( (if enabled && not ignore
                    then List.mapi (fun i old -> if i = index then value else old) values
                    else values)
                 , enabled
                 , ignore ))
             | _ -> Bonsai.Effect.Ignore))
      modes
  in
  let changes =
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      changes
      (Bonsai.Cont.return [])
  in
  let button name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let enabled =
    button "toggle-enabled" (fun (values, enabled, ignore) -> values, not enabled, ignore)
  in
  let ignore =
    button "toggle-ignore" (fun (values, enabled, ignore) -> values, enabled, not ignore)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both changes (Bonsai.Cont.both enabled ignore))
    ~f:(fun (values, enabled, ignored) (changes, (toggle_enabled, toggle_ignore)) ->
      let toggles =
        List.mapi
          (fun i (title, style) ->
             Ui.View.toggle
               ~key:(Ui.Key.string ("gallery-toggle-" ^ title))
               ~style
               ~enabled
               ~value:(List.nth values i)
               ~on_changed:(List.nth changes i)
               ~label:(Ui.View.text title)
               ())
          modes
      in
      Ui.View.column
        (toggles
         @ [ Ui.View.button
               ~on_press:toggle_enabled
               ~child:
                 (Ui.View.text (if enabled then "Disable toggles" else "Enable toggles"))
               ()
           ; Ui.View.button
               ~on_press:toggle_ignore
               ~child:
                 (Ui.View.text (if ignored then "Accept changes" else "Ignore changes"))
               ()
           ]))
;;

let swipe_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0, true, false) graph in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let archive =
    action "swipe-archive" (fun (count, enabled, ignore) ->
      (if enabled && not ignore then count + 1 else count), enabled, ignore)
  in
  let toggle =
    action "swipe-enabled" (fun (count, enabled, ignore) -> count, not enabled, ignore)
  in
  let ignore =
    action "swipe-ignore" (fun (count, enabled, ignore) -> count, enabled, not ignore)
  in
  Bonsai.Cont.map
    (Bonsai.Cont.both state (Bonsai.Cont.both archive (Bonsai.Cont.both toggle ignore)))
    ~f:(fun ((count, enabled, ignored), (archive, (toggle, ignore))) ->
      let button label handler =
        Ui.View.button ~on_press:handler ~child:(Ui.View.text label) ()
      in
      let row name axis =
        let title = "Archive " ^ name in
        Ui.View.Swipe_actions.create
          ~key:(Ui.Key.string ("gallery-swipe-" ^ name))
          ~axis
          ~enabled
          ~group:"gallery-swipe"
          ~actions:
            [ Ui.View.Swipe_actions.action
                ~title
                ~side:Start
                ~enabled
                ~background:(Ui.Style.Color.rgb ~red:38 ~green:120 ~blue:60)
                ~full_swipe:true
                ~on_press:archive
                ~child:(Ui.View.text title)
                ()
            ]
          ~content:
            (Ui.View.frame
               ~width:320.
               ~height:100.
               (Ui.View.text ("Swipe " ^ name ^ " to archive")))
          ()
      in
      Ui.View.column
        [ Ui.View.text (Printf.sprintf "Archived: %d" count)
        ; button (if enabled then "Disable actions" else "Enable actions") toggle
        ; button (if ignored then "Accept actions" else "Ignore actions") ignore
        ; row "horizontal" Horizontal
        ; row "vertical" Vertical
        ])
;;

let morph_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (false, 0, 0) graph in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let toggle = action "morph-toggle" (fun (e, c, d) -> not e, c, d) in
  let compact = action "morph-compact" (fun (e, c, d) -> e, c + 1, d) in
  let expanded = action "morph-expanded" (fun (e, c, d) -> e, c, d + 1) in
  Bonsai.Cont.map
    (Bonsai.Cont.both state (Bonsai.Cont.both toggle (Bonsai.Cont.both compact expanded)))
    ~f:
      (fun
        ((is_expanded, compact_count, expanded_count), (toggle, (compact, expanded))) ->
      let button label handler =
        Ui.View.button ~on_press:handler ~child:(Ui.View.text label) ()
      in
      Ui.View.column
        [ button "Toggle surface" toggle
        ; Ui.View.Morphing_surface.create
            ~key:(Ui.Key.string "gallery-morph")
            ~expanded:is_expanded
            ~content:
              (if is_expanded
               then
                 Ui.View.column
                   ~key:(Ui.Key.string "expanded-content")
                   [ Ui.View.text (Printf.sprintf "Expanded count: %d" expanded_count)
                   ; button "Increment expanded" expanded
                   ]
               else
                 Ui.View.column
                   ~key:(Ui.Key.string "compact-content")
                   [ Ui.View.text (Printf.sprintf "Compact count: %d" compact_count)
                   ; button "Increment compact" compact
                   ])
            ()
        ])
;;

let tabs_component handlers graph =
  let metadata, set_metadata = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let update_metadata =
    Driver.Handler.create
      handlers
      ~name:"tabs-metadata"
      ~equal:( == )
      set_metadata
      ~f:(fun set_metadata _ -> set_metadata (fun phase -> (phase + 1) mod 4))
  in
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) ("mail", false, 0, 0, false) graph
  in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let mail = action "tabs-mail-increment" (fun (s, l, m, c, r) -> s, l, m + 1, c, r) in
  let chat = action "tabs-chat-increment" (fun (s, l, m, c, r) -> s, l, m, c + 1, r) in
  let lock = action "tabs-lock" (fun (s, l, m, c, r) -> s, not l, m, c, r) in
  let reorder = action "tabs-reorder" (fun (s, l, m, c, r) -> s, l, m, c, not r) in
  let select =
    Driver.Handler.create
      handlers
      ~name:"tabs-select"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Tab_selected key ->
        let key = ID.Navigation.Page_key.to_string key in
        set_state (fun ((_, locked, mail, chat, reversed) as state) ->
          if locked || not (String.equal key "mail" || String.equal key "chat")
          then state
          else key, locked, mail, chat, reversed)
      | _ -> Bonsai.Effect.Ignore)
  in
  let controls =
    Bonsai.Cont.both
      mail
      (Bonsai.Cont.both chat (Bonsai.Cont.both lock (Bonsai.Cont.both reorder select)))
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both controls (Bonsai.Cont.both metadata update_metadata))
    ~f:
      (fun
        (selected, locked, mail_count, chat_count, reversed)
        ((mail, (chat, (lock, (reorder, select)))), (metadata, update_metadata)) ->
      let button label on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text label) ()
      in
      let item name title count increment controls =
        let body =
          Ui.View.Body.Vertical.create
            [ Ui.View.Body.Vertical.fixed (Ui.View.text ("Selected tab: " ^ selected))
            ; Ui.View.Body.Vertical.fill
                (Ui.View.Scroll.vertical
                   (Ui.View.column
                      ([ Ui.View.text (Printf.sprintf "%s count: %d" title count)
                       ; Ui.View.text (Printf.sprintf "Tab metadata: %d" metadata)
                       ; button ("Increment " ^ name) increment
                       ; button (if locked then "Unlock tabs" else "Lock tabs") lock
                       ]
                       @ controls)))
            ]
        in
        Ui.View.Tabs.item
          ~page_key:(ID.Navigation.Page_key.of_string name)
          ~title
          ?badge:
            (if name <> "mail"
             then None
             else (
               match metadata with
               | 1 -> Some "0"
               | 2 -> Some "4611686018427387903"
               | 3 -> Some "•"
               | _ -> None))
          ?accessibility_label:
            (if name = "mail" && metadata <> 0 then Some "Inbox messages" else None)
          ~symbol:(if String.equal name "mail" then "tray" else "bubble.left")
          body
      in
      let items =
        [ item
            "mail"
            "Mail"
            mail_count
            mail
            [ button "Reorder tabs" reorder
            ; button "Update tab metadata" update_metadata
            ; Ui.View.text ("Tab order: " ^ if reversed then "reversed" else "original")
            ]
        ; item "chat" "Chat" chat_count chat []
        ]
      in
      Ui.View.Tabs.create
        ~selection:(ID.Navigation.Page_key.of_string selected)
        ~on_change:select
        (if reversed then List.rev items else items))
;;

let split_component ?(two_columns = false) handlers graph =
  let module Split = Ui.Navigation.Split_state in
  let equal (left, left_locked) (right, right_locked) =
    Split.equal left right && Bool.equal left_locked right_locked
  in
  let state, set_state =
    Bonsai_v017.state
      ~equal
      ( Split.create
          ~visibility:Ui.Navigation.Split_visibility.All
          ~compact_column:(if two_columns then Sidebar else Content)
          ()
      , false )
      graph
  in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let select =
    action "split-select" (fun (state, locked) ->
      ( Split.create
          ~visibility:(Split.visibility state)
          ~compact_column:Ui.Navigation.Split_column.Detail
          ~selection_key:(ID.Navigation.Page_key.of_string "message-42")
          ()
      , locked ))
  in
  let clear =
    action "split-clear" (fun (state, locked) ->
      ( Split.create
          ~visibility:(Split.visibility state)
          ~compact_column:(if two_columns then Sidebar else Content)
          ()
      , locked ))
  in
  let show =
    action "split-show-sidebar" (fun (state, locked) ->
      ( Split.create
          ~visibility:Ui.Navigation.Split_visibility.All
          ~compact_column:Ui.Navigation.Split_column.Sidebar
          ?selection_key:(Split.selection_key state)
          ()
      , locked ))
  in
  let lock = action "split-lock" (fun (state, locked) -> state, not locked) in
  let on_change =
    Driver.Handler.create
      handlers
      ~name:"split-change"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Navigation_split_changed requested ->
        set_state (fun (state, locked) ->
          if
            locked
            || not
                 (Option.equal
                    ID.Navigation.Page_key.equal
                    (Split.selection_key state)
                    (Split.selection_key requested))
          then state, locked
          else requested, locked)
      | _ -> Bonsai.Effect.Ignore)
  in
  let controls =
    Bonsai.Cont.both
      select
      (Bonsai.Cont.both clear (Bonsai.Cont.both show (Bonsai.Cont.both lock on_change)))
  in
  Bonsai.Cont.map2
    state
    controls
    ~f:(fun (state, locked) (select, (clear, (show, (lock, on_change)))) ->
      let button label on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text label) ()
      in
      let sidebar =
        Ui.View.column
          [ Ui.View.text "Mailboxes"
          ; button "Select message" select
          ; button
              (if locked then "Allow column changes" else "Keep columns unchanged")
              lock
          ]
      in
      let content =
        Ui.View.column
          [ Ui.View.text "Messages"
          ; button "Show sidebar" show
          ; Ui.View.text
              (match Split.visibility state with
               | All -> "Sidebar visible"
               | Automatic -> "Automatic sidebar"
               | Double_column | Detail_only -> "Sidebar hidden")
          ; Ui.View.text
              (if locked then "Column changes blocked" else "Column changes allowed")
          ]
      in
      let detail =
        Ui.View.column
          [ Ui.View.text
              (if Option.is_some (Split.selection_key state)
               then "Selected message"
               else "Select a message")
          ; button "Clear selection" clear
          ]
      in
      if two_columns
      then
        Ui.View.Navigation_split.two_columns
          ~state
          ~sidebar_title:"Folders"
          ~detail_title:"Reading"
          ~on_change
          ~sidebar:(Ui.View.Body.static (Ui.View.column [ sidebar; content ]))
          ~detail:(Ui.View.Body.static detail)
          ()
      else
        Ui.View.Navigation_split.create
          ~state
          ~sidebar_title:"Folders"
          ~content_title:"Messages"
          ~detail_title:"Reading"
          ~on_change
          ~sidebar:(Ui.View.Body.static sidebar)
          ~content:(Ui.View.Body.static content)
          ~detail:(Ui.View.Body.static detail)
          ())
;;

let safe_area_component handlers graph =
  let phase, set_phase = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let advance =
    Driver.Handler.create
      handlers
      ~name:"safe-area-advance"
      ~equal:( == )
      set_phase
      ~f:(fun set_phase _ -> set_phase (fun phase -> (phase + 1) mod 5))
  in
  Bonsai.Cont.map2 phase advance ~f:(fun phase advance ->
    let pane =
      Ui.View.text ""
      |> Ui.View.frame
           ~max_width:Ui.Layout.Frame_limit.Fill
           ~max_height:Ui.Layout.Frame_limit.Fill
      |> Ui.View.background ~color:(Ui.Style.Color.rgb ~red:0 ~green:0 ~blue:255)
    in
    let button =
      Ui.View.button ~on_press:advance ~child:(Ui.View.text "Advance safe-area policy") ()
      |> Ui.View.semantics
           ~properties:(Ui.Semantics.create ~identifier:"safe-area-advance" ())
    in
    Ui.View.Weighted.column
      ~spacing:0.
      [ Ui.View.Weighted.share pane; Ui.View.Weighted.fixed button ]
    |> Ui.View.safe_area_padding
         ~insets:
           (if phase = 4
            then
              Ui.Layout.Edge_insets.only ~leading:12. ~top:8. ~trailing:20. ~bottom:14. ()
            else Ui.Layout.Edge_insets.all 0.)
    |> Ui.View.ignores_safe_area
         ~regions:
           (if phase = 2
            then Ui.View.Safe_area_regions.Keyboard
            else if phase >= 3
            then All
            else Container)
         ~edges:(if phase = 0 then [] else [ Ui.Layout.Edge.Top ]))
;;

let progress_component handlers graph =
  let phase, set_phase = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let advance =
    Driver.Handler.create
      handlers
      ~name:"progress-advance"
      ~equal:( == )
      set_phase
      ~f:(fun set_phase _ -> set_phase (fun phase -> (phase + 1) mod 4))
  in
  Bonsai.Cont.map2 phase advance ~f:(fun phase advance ->
    let value =
      match phase with
      | 0 -> Some 0.25
      | 1 -> Some 0.75
      | 2 -> None
      | _ -> Some 1.
    in
    let progress style identifier =
      Ui.View.progress ~key:(Ui.Key.string identifier) ?value ~style ()
      |> Ui.View.semantics ~properties:(Ui.Semantics.create ~identifier ())
    in
    Ui.View.column
      ~spacing:16.
      [ Ui.View.frame
          ~width:240.
          (progress Ui.View.Progress_style.Linear "progress-linear")
      ; progress Ui.View.Progress_style.Circular "progress-circular"
      ; Ui.View.button ~on_press:advance ~child:(Ui.View.text "Advance progress") ()
        |> Ui.View.semantics
             ~properties:(Ui.Semantics.create ~identifier:"progress-advance" ())
      ])
;;

let scroll_component handlers graph =
  let expanded, set_expanded = Bonsai_v017.state ~equal:Bool.equal false graph in
  let grow =
    Driver.Handler.create
      handlers
      ~name:"scroll-grow"
      ~equal:( == )
      set_expanded
      ~f:(fun set_expanded _ -> set_expanded not)
  in
  Bonsai.Cont.map2 expanded grow ~f:(fun expanded grow ->
    let vertical =
      Ui.View.column
        ~spacing:0.
        (List.init
           (if expanded then 24 else 20)
           (fun index ->
              Ui.View.text (Printf.sprintf "Scrollable line %d" index)
              |> Ui.View.frame ~height:40.))
      |> Ui.View.Scroll.vertical
           ~key:(Ui.Key.string "gallery-vertical-scroll")
           ~shows_indicators:(not expanded)
      |> Ui.View.Viewport.Vertical.with_height ~height:200.
    in
    let horizontal =
      Ui.View.row
        ~spacing:0.
        (List.map
           (fun text ->
              Ui.View.text text |> Ui.View.frame ~width:(if expanded then 500. else 400.))
           [ "Leading content"; "Trailing content" ])
      |> Ui.View.Scroll.horizontal
           ~key:(Ui.Key.string "gallery-horizontal-scroll")
           ~shows_indicators:false
      |> Ui.View.Viewport.Horizontal.with_width ~width:300.
      |> Ui.View.frame ~height:100.
    in
    Ui.View.column
      ~spacing:12.
      [ Ui.View.button ~on_press:grow ~child:(Ui.View.text "Grow scroll content") ()
      ; vertical
      ; horizontal
      ])
;;

let collection_catalog ~horizontal ~measured removed expanded =
  Ui.View.Collection.Catalog.create
    ~keys:(List.init (10_000 - removed) (fun index -> Ui.Key.int (index + removed)))
    ~default_extent:(if horizontal then 120. else 40.)
    ~sizing:
      (if measured
       then Ui.View.Collection.Measured { revision = (if expanded then 1L else 0L) }
       else Declared)
    ~overrides:
      (if expanded
       then
         [ { Ui.View.Collection.index = 10 - removed
           ; extent = (if horizontal then 400. else 200.)
           }
         ]
       else [])
    ~expand_duration_ms:240
    ~collapse_duration_ms:190
    ()
;;

let collection_catalogs =
  Array.init 2 (fun measured ->
    Array.init 2 (fun axis ->
      Array.init 2 (fun removed ->
        Array.init 2 (fun expanded ->
          collection_catalog
            ~horizontal:(axis = 1)
            ~measured:(measured = 1)
            removed
            (expanded = 1)))))
;;

let collection_component ?(horizontal = false) ?(measured = false) handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0, false, 0, 0) graph in
  let range_handler =
    Driver.Handler.create
      handlers
      ~name:"collection-visible"
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        match Ui.View.Collection.visible_range_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some range ->
          set_state (fun (removed, expanded, _, _) ->
            let count = 10_000 - removed in
            let first = Int64.to_int (Int64.min (Int64.of_int count) range.first_index) in
            let last =
              Int64.to_int (Int64.min (Int64.of_int count) range.last_exclusive)
            in
            removed, expanded, first, last))
  in
  let remove =
    Driver.Handler.create
      handlers
      ~name:"collection-remove-first"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun (_, expanded, first, last) -> 1, expanded, first, last))
  in
  let expand =
    Driver.Handler.create
      handlers
      ~name:"collection-expand"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun (removed, expanded, first, last) ->
          removed, not expanded, first, last))
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both range_handler (Bonsai.Cont.both remove expand))
    ~f:(fun (removed, expanded, first, last) (on_visible_range, (remove, expand)) ->
      let catalog =
        collection_catalogs.(if measured then 1 else 0).(if horizontal then 1 else 0).(removed).(
        if expanded then 1 else 0)
      in
      let window =
        Ui.View.Collection.Window.create
          ~catalog
          ~visible_first_index:first
          ~visible_last_exclusive:last
      in
      let items =
        List.init (window.last_exclusive - window.first_index) (fun offset ->
          let index = removed + window.first_index + offset in
          Ui.View.column
            ~spacing:8.
            ([ Ui.View.text (Printf.sprintf "Row %d" index) ]
             @
             if expanded && index = 10
             then [ Ui.View.text "Expanded content stays in this keyed row." ]
             else [])
          |> Ui.View.Keyed.create ~key:(Ui.Key.int index))
      in
      let list =
        if horizontal
        then
          Ui.View.Collection.horizontal
            ~key:(Ui.Key.string "collection")
            ~catalog
            ~first_index:window.first_index
            ~items
            ~on_visible_range
            ()
          |> Ui.View.Viewport.Horizontal.with_width ~width:600.
          |> Ui.View.frame ~height:420.
        else
          Ui.View.Collection.vertical
            ~key:(Ui.Key.string "collection")
            ~catalog
            ~first_index:window.first_index
            ~items
            ~on_visible_range
            ()
          |> Ui.View.Viewport.Vertical.with_height ~height:600.
      in
      Ui.View.column
        [ Ui.View.button ~on_press:remove ~child:(Ui.View.text "Remove first row") ()
        ; Ui.View.button
            ~on_press:expand
            ~child:(Ui.View.text "Toggle row 10 expansion")
            ()
        ; list
        ])
;;

let semantics_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0L, false) graph in
  let press =
    Driver.Handler.create
      handlers
      ~name:"accessibility-press"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun (action, hidden) -> Int64.succ action, hidden))
  in
  let custom =
    Driver.Handler.create
      handlers
      ~name:"accessibility-action"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Int64 id when id = 41L || id = 42L ->
        set_state (fun (_, hidden) -> id, hidden)
      | _ -> Bonsai.Effect.Ignore)
  in
  let hide =
    Driver.Handler.create
      handlers
      ~name:"accessibility-hide"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ -> set_state (fun (action, _) -> action, true))
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both press (Bonsai.Cont.both custom hide))
    ~f:(fun (action, hidden) (press, (custom, hide)) ->
      let item =
        Ui.View.button ~on_press:press ~child:(Ui.View.text "Open mail item") ()
        |> Ui.View.semantics
             ~on_action:custom
             ~properties:
               (Ui.Semantics.create
                  ~label:"Mail item"
                  ~identifier:"gallery-accessibility-item"
                  ~hidden
                  ~actions:
                    [ Ui.Semantics.Action.create ~id:41L ~label:"Archive"
                    ; Ui.Semantics.Action.create ~id:42L ~label:"Mute"
                    ]
                  ())
      in
      let status = Printf.sprintf "Action %Ld" action in
      Ui.View.column
        ~spacing:12.
        [ item
        ; Ui.View.text status
          |> Ui.View.semantics
               ~properties:(Ui.Semantics.create ~label:status ~live_region:true ())
        ; Ui.View.button ~on_press:hide ~child:(Ui.View.text "Hide accessibility item") ()
          |> Ui.View.semantics
               ~properties:(Ui.Semantics.create ~identifier:"gallery-hide-button" ())
        ])
;;

let view
      model
      handlers
      collection
      scrolls
      semantics
      progress
      safe_areas
      ( splits
      , ( tabs
        , ( morph
          , ( swipe
            , ( toggles
              , ( sliders
                , ( pickers
                  , ( multiple
                    , ( tags
                      , ( buttons
                        , ( projections
                          , ( opacities
                            , ( workflows
                              , (disclosures, (groups, (labels, (badges, hover)))) ) ) )
                        ) ) ) ) ) ) ) ) ) )
  =
  let icon name = Ui.View.symbol ~name () in
  let body =
    Ui.View.column
      [ Ui.View.text "OCaml owns every value and handler on this page"
      ; symbols_section ()
      ; frames_section ()
      ; modifiers_section ()
      ; stacks_section ()
      ; weights_section ()
      ; overlays_section ()
      ; rich_text_section ()
      ; text_section ()
      ; dividers_section ()
      ; images_section ()
      ; collection
      ; scrolls
      ; semantics
      ; progress
      ; Ui.View.frame ~height:220. safe_areas
      ; Ui.View.frame ~height:360. splits
      ; Ui.View.frame ~height:280. tabs
      ; morph
      ; swipe
      ; toggles
      ; sliders
      ; pickers
      ; multiple
      ; tags
      ; buttons
      ; projections
      ; opacities
      ; workflows
      ; disclosures
      ; groups
      ; labels
      ; badges
      ; hover
      ; core_section handlers
      ; controls_section model handlers
      ; native_controls_catalog_section handlers
      ; interaction_section model handlers
      ; text_input_section model handlers
      ; native_section model handlers
      ]
  in
  let viewport =
    Ui.View.Scroll_sections.vertical
      ~key:(Ui.Key.string "gallery-scroll")
      ~pin_headers:true
      [ Ui.View.Scroll_sections.hero
          ~key:(Ui.Key.string "gallery-hero")
          ~height:200.
          ~stretch:true
          (Ui.View.text "Bonsai SwiftUI")
      ; Ui.View.Scroll_sections.section
          ~key:(Ui.Key.string "gallery-components")
          ~header:
            (Ui.View.text "Browse components"
             |> Ui.View.frame ~height:48. ~max_width:Ui.Layout.Frame_limit.Fill
             |> Ui.View.background
                  ~color:(Ui.Style.Color.rgb ~red:238 ~green:240 ~blue:245))
          [ Ui.View.Keyed.create ~key:(Ui.Key.string "catalog") body ]
      ]
    |> Ui.View.Viewport.Vertical.padding
         ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:24. ~vertical:16. ())
    |> Ui.View.Viewport.Vertical.semantics
         ~properties:
           (Ui.Semantics.create
              ~label:"Bonsai SwiftUI gallery"
              ~role:Ui.Semantics.Role.Generic
              ~value:(if model.checked then "Checked" else "Unchecked")
              ())
  in
  let footer =
    Ui.View.text
      (Printf.sprintf "Persistent bottom content · Actions: %d" model.press_count)
    |> Ui.View.frame ~height:24.
  in
  let toolbar_items =
    [ Ui.View.Toolbar.item
        ~key:(Ui.Key.string "gallery-increment")
        ~placement:Primary_action
        (Ui.View.button
           ~on_press:handlers.press
           ~child:
             (Ui.View.label
                ~title:(Ui.View.text "Increment counter")
                ~icon:(icon "plus")
                ())
           ())
    ]
  in
  let viewport =
    viewport
    |> Ui.View.Viewport.Vertical.overlay
         ~alignment:Ui.Layout.Alignment.Bottom_end
         ~overlay:
           (Ui.View.button
              ~on_press:handlers.press
              ~child:(Ui.View.label ~title:(Ui.View.text "New") ~icon:(icon "plus") ())
              ()
            |> Ui.View.padding
                 ~insets:(Ui.Layout.Edge_insets.only ~trailing:16. ~bottom:16. ()))
  in
  Ui.View.Body.Vertical.create
    [ Ui.View.Body.Vertical.fill viewport; Ui.View.Body.Vertical.fixed footer ]
  |> Ui.View.Body.toolbar ~items:toolbar_items
  |> Ui.View.Navigation_stack.create
       ~title:"Bonsai SwiftUI Gallery"
       ~on_path_change:handlers.interaction
       ~path:[]
  |> Ui.View.Body.static
;;

let workflow_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (1L, 0, false, false) graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let select =
    List.map
      (fun id ->
         Bonsai.Cont.map
           (bind
              ("workflow-select-" ^ Int64.to_string id)
              (fun (current, count, reverse, horizontal) _ ->
                 (if id = 4L then current else id), count, reverse, horizontal))
           ~f:(fun handler -> id, handler))
      [ 1L; 2L; 3L; 4L; 5L ]
    |> fun values ->
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      values
      (Bonsai.Cont.return [])
  in
  let next = bind "workflow-next" (fun (_, n, r, h) _ -> 2L, n, r, h) in
  let back = bind "workflow-back" (fun (_, n, r, h) _ -> 1L, n, r, h) in
  let act = bind "workflow-act" (fun (s, n, r, h) _ -> s, n + 1, r, h) in
  let reverse = bind "workflow-reverse" (fun (s, n, r, h) _ -> s, n, not r, h) in
  let axis = bind "workflow-axis" (fun (s, n, r, h) _ -> s, n, r, not h) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       select
       (Bonsai.Cont.both
          next
          (Bonsai.Cont.both back (Bonsai.Cont.both act (Bonsai.Cont.both reverse axis)))))
    ~f:
      (fun
        (current, count, reversed, horizontal)
        (select, (next, (back, (act, (reverse, axis))))) ->
      let button title handler =
        Ui.View.button ~on_press:handler ~child:(Ui.View.text title) ()
      in
      let steps =
        List.map
          (fun (id, title, status) ->
             Ui.Workflow.step
               ~id
               ~title:(Ui.View.text title)
               ~state:status
               ~on_select:(List.assoc id select)
               ~subtitle:(Ui.View.text (title ^ " description"))
               ~label:(Ui.View.text (title ^ " annotation"))
               ~content:(button ("Act in " ^ title) act)
               ())
          [ 1L, "Edit", Ui.Workflow.Editing
          ; 2L, "Review", Complete
          ; 3L, "Fix", Error
          ; 4L, "Locked", Disabled
          ; 5L, "Finish", Pending
          ]
      in
      Ui.View.column
        ~spacing:12.
        [ Ui.View.text (Printf.sprintf "Workflow: %Ld; actions: %d" current count)
        ; Ui.Workflow.create
            ~key:(Ui.Key.string "workflow")
            ~layout:(if horizontal then Horizontal else Vertical)
            ~current_step_id:current
            ~on_continue:next
            ~on_back:back
            (if reversed then List.rev steps else steps)
            ()
        ; button "Reverse workflow" reverse
        ; button "Change workflow layout" axis
        ])
;;

let disclosure_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) ([ 1L ], false, true, false, false, 0) graph
  in
  let bind name f =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> f state payload))
  in
  let selections =
    List.map
      (fun id ->
         Bonsai.Cont.map
           (bind
              ("disclosure-" ^ Int64.to_string id)
              (fun (expanded, single, enabled, reject, reverse, count) payload ->
                 let expanded =
                   match payload with
                   | Ui.Event.Payload.Bool next when enabled && (not reject) && id <> 3L
                     ->
                     if next
                     then
                       if single
                       then [ id ]
                       else List.sort_uniq Int64.compare (id :: expanded)
                     else List.filter (fun item -> item <> id) expanded
                   | _ -> expanded
                 in
                 expanded, single, enabled, reject, reverse, count))
           ~f:(fun handler -> id, handler))
      [ 1L; 2L; 3L ]
    |> fun values ->
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      values
      (Bonsai.Cont.return [])
  in
  let mode =
    bind "disclosure-mode" (fun (e, s, a, i, r, n) _ ->
      ( (if s
         then e
         else (
           match e with
           | [] -> []
           | id :: _ -> [ id ]))
      , not s
      , a
      , i
      , r
      , n ))
  in
  let enable =
    bind "disclosure-enable" (fun (e, s, a, i, r, n) _ -> e, s, not a, i, r, n)
  in
  let reject =
    bind "disclosure-reject" (fun (e, s, a, i, r, n) _ -> e, s, a, not i, r, n)
  in
  let reverse =
    bind "disclosure-reverse" (fun (e, s, a, i, r, n) _ -> e, s, a, i, not r, n)
  in
  let action =
    bind "disclosure-action" (fun (e, s, a, i, r, n) _ -> e, s, a, i, r, n + 1)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       selections
       (Bonsai.Cont.both
          mode
          (Bonsai.Cont.both
             enable
             (Bonsai.Cont.both reject (Bonsai.Cont.both reverse action)))))
    ~f:
      (fun
        (expanded, single, enabled, ignored, reversed, count)
        (selections, (mode, (enable, (reject, (reverse, action))))) ->
      let button title on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text title) ()
      in
      let items =
        List.map
          (fun (id, title, body) ->
             Ui.View.disclosure_group
               ~key:(Ui.Key.int64 id)
               ~expanded:(List.mem id expanded)
               ~enabled:(enabled && id <> 3L)
               ~on_changed:(List.assoc id selections)
               ~label:
                 (Ui.View.row
                    ~spacing:6.
                    [ Ui.View.symbol ~name:"envelope" ()
                    ; Ui.View.text title
                    ; button "Header action" action
                    ])
               ~content:(button ("Act in " ^ body) action)
               ())
          [ 1L, "Item one", "one"
          ; 2L, "Item two", "two"
          ; 3L, "Unavailable", "unavailable"
          ]
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        ([ Ui.View.text
             ("Expanded: "
              ^ String.concat "," (List.map Int64.to_string expanded)
              ^ "; actions: "
              ^ string_of_int count)
         ]
         @ (if reversed then List.rev items else items)
         @ [ button (if single then "Multiple expansion" else "Single expansion") mode
           ; button
               (if enabled then "Disable disclosures" else "Enable disclosures")
               enable
           ; button (if ignored then "Accept expansion" else "Reject expansion") reject
           ; button "Reverse disclosures" reverse
           ]))
;;

let group_box_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (None, 0, true, true, false) graph
  in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let select id =
    bind
      ("group-select-" ^ Int64.to_string id)
      (fun (selected, count, enabled, labelled, reversed) ->
         (if enabled then Some id else selected), count, enabled, labelled, reversed)
  in
  let action =
    bind "group-action" (fun (s, n, e, l, r) -> s, (if e then n + 1 else n), e, l, r)
  in
  let enable = bind "group-enable" (fun (s, n, e, l, r) -> s, n, not e, l, r) in
  let label = bind "group-label" (fun (s, n, e, l, r) -> s, n, e, not l, r) in
  let reverse = bind "group-reverse" (fun (s, n, e, l, r) -> s, n, e, l, not r) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (select 1L)
       (Bonsai.Cont.both
          (select 2L)
          (Bonsai.Cont.both
             action
             (Bonsai.Cont.both enable (Bonsai.Cont.both label reverse)))))
    ~f:
      (fun
        (selected, count, enabled, labelled, reversed)
        (select_one, (select_two, (action, (enable, (label, reverse))))) ->
      let button ?(enabled = true) title on_press =
        Ui.View.button ~enabled ~on_press ~child:(Ui.View.text title) ()
      in
      let cards =
        [ Ui.View.group_box
            ~key:(Ui.Key.int64 1L)
            ?label:
              (if labelled then Some (button ~enabled "Select one" select_one) else None)
            (button ~enabled "Act in one" action)
        ; Ui.View.button
            ~key:(Ui.Key.int64 2L)
            ~enabled
            ~on_press:select_two
            ~child:(Ui.View.group_box (Ui.View.text "Open two"))
            ()
        ]
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        ([ Ui.View.text
             ("Card: "
              ^ Option.fold ~none:"none" ~some:Int64.to_string selected
              ^ "; actions: "
              ^ string_of_int count)
         ]
         @ (if reversed then List.rev cards else cards)
         @ [ button (if labelled then "Hide group label" else "Show group label") label
           ; button "Reverse cards" reverse
           ; button
               (if enabled then "Disable card actions" else "Enable card actions")
               enable
           ]))
;;

let label_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (None, 0, 0, true, true, false) graph
  in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let select id =
    bind
      ("label-select-" ^ Int64.to_string id)
      (fun (s, n, a, e, d, r) ->
         (if e then Some id else s), (if e then n + 1 else n), a, e, d, r)
  in
  let info = bind "label-info" (fun (s, n, a, e, d, r) -> s, n, a + 1, e, d, r) in
  let enable = bind "label-enable" (fun (s, n, a, e, d, r) -> s, n, a, not e, d, r) in
  let details = bind "label-details" (fun (s, n, a, e, d, r) -> s, n, a, e, not d, r) in
  let reverse = bind "label-reverse" (fun (s, n, a, e, d, r) -> s, n, a, e, d, not r) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (select 1L)
       (Bonsai.Cont.both
          (select 2L)
          (Bonsai.Cont.both
             info
             (Bonsai.Cont.both enable (Bonsai.Cont.both details reverse)))))
    ~f:
      (fun
        (selected, opens, infos, enabled, decorated, reversed)
        (inbox, (archive, (info, (enable, (details, reverse))))) ->
      let button title on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text title) ()
      in
      let row id headline supporting symbol on_press =
        let title =
          Ui.View.column
            ~spacing:3.
            ~alignment:Ui.Layout.Horizontal_alignment.Leading
            ((if decorated
              then
                [ Ui.View.text
                    ~key:(Ui.Key.string "overline")
                    ~style:(Ui.Style.Text_style.create ~font_size:11. ())
                    "Mailboxes"
                ]
              else [])
             @ [ Ui.View.text ~key:(Ui.Key.string "headline") headline ]
             @
             if decorated
             then
               [ Ui.View.text
                   ~key:(Ui.Key.string "supporting")
                   ~style:(Ui.Style.Text_style.create ~font_size:12. ())
                   supporting
               ]
             else [])
        in
        let icon =
          if decorated then Ui.View.symbol ~name:symbol () else Ui.View.empty ()
        in
        let primary =
          Ui.View.button
            ~key:(Ui.Key.string "open")
            ~enabled
            ~style:
              (if selected = Some id then Ui.View.Button_style.Prominent else Bordered)
            ~on_press
            ~child:
              (Ui.View.frame
                 ~max_width:Ui.Layout.Frame_limit.Fill
                 ~alignment:Ui.Layout.Alignment.Center_start
                 (Ui.View.label ~title ~icon ()))
            ()
          |> Ui.View.semantics
               ~key:(Ui.Key.string "primary")
               ~properties:(Ui.Semantics.create ~selected:(selected = Some id) ())
        in
        Ui.View.Weighted.row
          ~key:(Ui.Key.int64 id)
          ~spacing:12.
          ([ Ui.View.Weighted.share primary ]
           @
           if decorated
           then
             [ Ui.View.Weighted.fixed
                 (Ui.View.button
                    ~key:(Ui.Key.string "info")
                    ~on_press:info
                    ~child:(Ui.View.text ("Info for " ^ headline))
                    ())
             ]
           else [])
      in
      let rows =
        [ row 1L "Inbox" "Unread messages" "envelope" inbox
        ; row 2L "Archive" "Saved messages" "archivebox" archive
        ]
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        ([ Ui.View.text
             ("Row: "
              ^ Option.fold ~none:"none" ~some:Int64.to_string selected
              ^ "; opens: "
              ^ string_of_int opens
              ^ "; info: "
              ^ string_of_int infos)
         ]
         @ (if reversed then List.rev rows else rows)
         @ [ button (if enabled then "Disable rows" else "Enable rows") enable
           ; button (if decorated then "Hide row details" else "Show row details") details
           ; button "Reverse rows" reverse
           ]))
;;

let badge_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (Some 8, 2, true, true, 0) graph
  in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let controls =
    [ ("Maximum badge", fun (_, a, v, e, n) -> Some max_int, a, v, e, n)
    ; ("Dot badge", fun (_, a, v, e, n) -> None, a, v, e, n)
    ; ("Zero badge", fun (_, a, v, e, n) -> Some 0, a, v, e, n)
    ; ( "Increment badge"
      , fun (c, a, v, e, n) ->
          ( Some
              (match c with
               | Some c when c < max_int -> c + 1
               | _ -> 0)
          , a
          , v
          , e
          , n ) )
    ; ("Move badge", fun (c, a, v, e, n) -> c, (a + 1) mod 3, v, e, n)
    ; ("visibility", fun (c, a, v, e, n) -> c, a, not v, e, n)
    ; ("enabled", fun (c, a, v, e, n) -> c, a, v, not e, n)
    ; ("Open notifications", fun (c, a, v, e, n) -> c, a, v, e, if e then n + 1 else n)
    ]
  in
  let controls =
    List.map
      (fun (name, f) -> Bonsai.Cont.map (bind ("badge-" ^ name) f) ~f:(fun h -> name, h))
      controls
    |> fun xs ->
    List.fold_right
      (fun x rest -> Bonsai.Cont.map2 x rest ~f:(fun x rest -> x :: rest))
      xs
      (Bonsai.Cont.return [])
  in
  Bonsai.Cont.map2
    state
    controls
    ~f:(fun (count, alignment, visible, enabled, actions) controls ->
      let handler name = List.assoc name controls in
      let button title on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text title) ()
      in
      let content =
        Ui.View.button
          ~key:(Ui.Key.string "notifications")
          ~enabled
          ~on_press:(handler "Open notifications")
          ~child:(Ui.View.text "Open notifications")
          ()
        |> Ui.View.semantics
             ~properties:
               (Ui.Semantics.create
                  ~value:(Option.fold ~none:"Unread" ~some:string_of_int count)
                  ())
      in
      let alignment =
        match alignment with
        | 0 -> Ui.Layout.Horizontal_alignment.Leading
        | 1 -> Center
        | _ -> Trailing
      in
      Ui.View.column
        ~spacing:12.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        ([ Ui.View.text ("Badge actions: " ^ string_of_int actions)
         ; Ui.View.badge ?count ~alignment ~visible content
           |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 24.)
         ]
         @ List.map
             (fun title -> button title (handler title))
             [ "Maximum badge"
             ; "Dot badge"
             ; "Zero badge"
             ; "Increment badge"
             ; "Move badge"
             ]
         @ [ button
               (if visible then "Hide badge" else "Show badge")
               (handler "visibility")
           ; button
               (if enabled then "Disable content" else "Enable content")
               (handler "enabled")
           ]))
;;

type hover_model =
  { hover_count : int
  ; hover_last : string
  ; hover_blocks : bool
  ; hover_front : bool
  ; hover_reverse : bool
  ; hover_alternate : bool
  ; hover_actions : int
  }

let hover_component registry graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { hover_count = 0
      ; hover_last = "No hover events"
      ; hover_blocks = true
      ; hover_front = true
      ; hover_reverse = false
      ; hover_alternate = false
      ; hover_actions = 0
      }
      graph
  in
  let event name =
    Driver.Handler.create
      registry
      ~name:("hover-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Pointer p ->
        set_state (fun state ->
          { state with
            hover_count = state.hover_count + 1
          ; hover_last =
              Printf.sprintf
                "%s: local %.1f,%.1f; global %.1f,%.1f; buttons %d"
                name
                p.local_x
                p.local_y
                p.global_x
                p.global_y
                p.buttons
          })
      | _ -> Bonsai.Effect.Ignore)
  in
  let action name f =
    Driver.Handler.create
      registry
      ~name:("hover-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Unit -> set_state f
      | _ -> Bonsai.Effect.Ignore)
  in
  let inputs =
    [ event "Parent enter"
    ; event "Parent leave"
    ; event "Back enter"
    ; event "Back leave"
    ; event "Front enter"
    ; event "Front leave"
    ; event "Replacement enter"
    ; event "Replacement leave"
    ; action "blocking" (fun s -> { s with hover_blocks = not s.hover_blocks })
    ; action "visibility" (fun s -> { s with hover_front = not s.hover_front })
    ; action "order" (fun s -> { s with hover_reverse = not s.hover_reverse })
    ; action "handlers" (fun s -> { s with hover_alternate = not s.hover_alternate })
    ; action "inner" (fun s -> { s with hover_actions = s.hover_actions + 1 })
    ]
  in
  let inputs =
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      inputs
      (Bonsai.Cont.return [])
  in
  Bonsai.Cont.map2 state inputs ~f:(fun state -> function
    | [ parent_enter
      ; parent_leave
      ; back_enter
      ; back_leave
      ; front_enter
      ; front_leave
      ; replacement_enter
      ; replacement_leave
      ; blocking
      ; visibility
      ; order
      ; handlers
      ; inner
      ] ->
      let button title on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text title) ()
      in
      let region key blocks_behind on_enter on_leave child =
        Ui.View.hover_region
          ~key:(Ui.Key.string key)
          ~blocks_behind
          ~on_enter
          ~on_leave
          child
      in
      let back =
        region
          "hover-back"
          true
          back_enter
          back_leave
          (Ui.View.frame ~width:240. ~height:140. (button "Inner action" inner)
           |> Ui.View.background ~color:(Ui.Style.Color.rgb ~red:190 ~green:215 ~blue:245)
          )
      in
      let front =
        region
          "hover-front"
          state.hover_blocks
          (if state.hover_alternate then replacement_enter else front_enter)
          (if state.hover_alternate then replacement_leave else front_leave)
          (Ui.View.frame ~width:120. ~height:70. (Ui.View.text "Front hover")
           |> Ui.View.background ~color:(Ui.Style.Color.rgb ~red:180 ~green:235 ~blue:195)
          )
      in
      let layers = if state.hover_front then [ back; front ] else [ back ] in
      let layers = if state.hover_reverse then List.rev layers else layers in
      Ui.View.column
        ~spacing:12.
        [ Ui.View.text ("Hover events: " ^ string_of_int state.hover_count)
        ; Ui.View.text state.hover_last
        ; region "hover-parent" true parent_enter parent_leave (Ui.View.stack layers)
        ; Ui.View.text ("Hover child actions: " ^ string_of_int state.hover_actions)
        ; button
            (if state.hover_blocks then "Allow hover behind" else "Block hover behind")
            blocking
        ; button
            (if state.hover_front then "Hide front hover" else "Show front hover")
            visibility
        ; button "Reverse hover regions" order
        ; button "Replace hover handlers" handlers
        ]
    | _ -> assert false)
;;

let help_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (false, true, 0) graph in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let press =
    bind "help-action" (fun (changed, enabled, count) ->
      changed, enabled, if enabled then count + 1 else count)
  in
  let change =
    bind "help-change" (fun (changed, enabled, count) -> not changed, enabled, count)
  in
  let enable =
    bind "help-enable" (fun (changed, enabled, count) -> changed, not enabled, count)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both press (Bonsai.Cont.both change enable))
    ~f:(fun (changed, enabled, count) (press, (change, enable)) ->
      let button title on_press =
        Ui.View.button ~on_press ~child:(Ui.View.text title) ()
      in
      Ui.View.column
        [ Ui.View.text "Native help"
        ; Ui.View.help
            ~key:(Ui.Key.string "archive-help")
            ~message:(if changed then "归档邮件 📬" else "Move this message to the archive")
            (Ui.View.button
               ~key:(Ui.Key.string "archive-action")
               ~enabled
               ~on_press:press
               ~child:(Ui.View.text "Archive")
               ())
        ; button "Change help" change
        ; button (if enabled then "Disable action" else "Enable action") enable
        ; Ui.View.text (Printf.sprintf "Help actions: %d" count)
        ])
;;

let popover_component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (false, false, false, 0, 0) graph
  in
  let bind name f =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> f state payload))
  in
  let show =
    bind "popover-show" (fun (_, reject, replacement, count, dismissals) _ ->
      true, reject, replacement, count, dismissals)
  in
  let hide =
    bind "popover-hide" (fun (_, reject, replacement, count, dismissals) _ ->
      false, reject, replacement, count, dismissals)
  in
  let action =
    bind "popover-action" (fun (shown, reject, replacement, count, dismissals) _ ->
      shown, reject, replacement, (if shown then count + 1 else count), dismissals)
  in
  let reject =
    bind "popover-reject" (fun (shown, reject, replacement, count, dismissals) _ ->
      shown, not reject, replacement, count, dismissals)
  in
  let replace =
    bind "popover-replace" (fun (shown, reject, replacement, count, dismissals) _ ->
      shown, reject, not replacement, count, dismissals)
  in
  let dismissal_owner =
    Bonsai.Cont.map2 set_state state ~f:(fun set_state (_, _, replacement, _, _) ->
      set_state, replacement)
  in
  let dismiss =
    Driver.Handler.create
      handlers
      ~name:"popover-dismiss"
      ~equal:(fun (a, x) (b, y) -> a == b && x = y)
      dismissal_owner
      ~f:(fun (set_state, _) -> function
        | Ui.Event.Payload.Bool false ->
          set_state (fun (shown, reject, replacement, count, dismissals) ->
            (if reject then shown else false), reject, replacement, count, dismissals + 1)
        | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       dismiss
       (Bonsai.Cont.both
          show
          (Bonsai.Cont.both
             hide
             (Bonsai.Cont.both action (Bonsai.Cont.both reject replace)))))
    ~f:
      (fun
        (shown, rejected, _, count, dismissals)
        (dismiss, (show, (hide, (action, (reject, replace))))) ->
      let button title on_press =
        Ui.View.button ~key:(Ui.Key.string title) ~on_press ~child:(Ui.View.text title) ()
      in
      let content =
        Ui.View.column
          [ Ui.View.text "Message details"
          ; Ui.View.text "Keep this message for later."
          ; button "Keep message" action
          ; button "Close details" hide
          ]
        |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
        |> Ui.View.frame ~width:280.
      in
      Ui.View.column
        [ Ui.View.Popover.create
            ~presented:shown
            ~on_presented_changed:dismiss
            ~content
            (button "Show details" show)
        ; button "Hide details" hide
        ; button (if rejected then "Accept dismissal" else "Reject dismissal") reject
        ; button "Replace dismissal handler" replace
        ; Ui.View.text (if shown then "Details: Open" else "Details: Closed")
        ; Ui.View.text (Printf.sprintf "Detail actions: %d" count)
        ; Ui.View.text (Printf.sprintf "Dismiss requests: %d" dismissals)
        ])
;;

let theme_component registry graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (true, false, 2, 0, 0) graph in
  let action name update =
    Driver.Handler.create registry ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let actions =
    [ action "theme-mode" (fun (explicit, font, size, inside, outside) ->
        not explicit, font, size, inside, outside)
    ; action "theme-font" (fun (explicit, font, size, inside, outside) ->
        explicit, not font, size, inside, outside)
    ; action "theme-size" (fun (explicit, font, size, inside, outside) ->
        explicit, font, (size + 1) mod 5, inside, outside)
    ; action "theme-inside" (fun (explicit, font, size, inside, outside) ->
        explicit, font, size, inside + 1, outside)
    ; action "theme-outside" (fun (explicit, font, size, inside, outside) ->
        explicit, font, size, inside, outside + 1)
    ]
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all actions)
    ~f:(fun (explicit, font, size, inside, outside) actions ->
      let button index title =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~on_press:(List.nth actions index)
          ~child:(Ui.View.text title)
          ()
      in
      let sizes =
        [ "Mini", Ui.Theme.Control_size.Mini
        ; "Small", Small
        ; "Regular", Regular
        ; "Large", Large
        ; "Extra large", Extra_large
        ]
      in
      let size_label, control_size = List.nth sizes size in
      let data =
        Ui.Theme.create
          ~mode:(if explicit then Dark else System)
          ?tint:
            (if explicit
             then Some (Ui.Style.Color.rgb ~red:128 ~green:90 ~blue:213)
             else None)
          ?font_family:(if font then Some "Menlo" else None)
          ~control_size
          ()
      in
      let scoped =
        Ui.View.column
          ~spacing:10.
          [ Ui.View.text "Scope sample"
          ; Ui.View.text (Printf.sprintf "Scoped actions: %d" inside)
          ; button 3 "Scoped action"
          ; Ui.View.group_box (Ui.View.text "Nested light scope; font inherits")
            |> Ui.View.theme
                 ~key:(Ui.Key.string "nested-light-theme")
                 ~data:(Ui.Theme.create ~mode:Light ())
          ]
        |> Ui.View.group_box
        |> Ui.View.theme ~key:(Ui.Key.string "interactive-theme") ~data
      in
      section
        "Scoped native theme"
        [ Ui.View.text
            (if explicit
             then "Appearance: explicit dark and purple"
             else "Appearance: inherited")
        ; Ui.View.text (if font then "Font: Menlo" else "Font: inherited")
        ; Ui.View.text ("Control size: " ^ size_label)
        ; Ui.View.row [ button 0 "Toggle scoped theme"; button 1 "Toggle scoped font" ]
        ; button 2 "Cycle control size"
        ; scoped
        ; Ui.View.group_box
            (Ui.View.column
               [ Ui.View.text "Outside sample"
               ; Ui.View.text (Printf.sprintf "Outside actions: %d" outside)
               ; button 4 "Outside action"
               ])
        ])
;;

let component registry graph =
  let model, set_model = Bonsai_v017.state ~equal:equal_model initial_model graph in
  let handlers = make_handlers registry set_model in
  let collection =
    Bonsai.Cont.map2
      (collection_component registry graph)
      (collection_component ~horizontal:true registry graph)
      ~f:(fun vertical horizontal -> Ui.View.column [ vertical; horizontal ])
  in
  let collection =
    Bonsai.Cont.map2
      collection
      (collection_component ~measured:true registry graph)
      ~f:(fun declared measured ->
        Ui.View.column [ declared; Ui.View.text "Measured collection"; measured ])
  in
  let collection =
    Bonsai.Cont.map2
      collection
      (Bonsai.Cont.both
         (Mixed_collection_catalog.component registry graph)
         (Mixed_collection_catalog.component ~horizontal:true registry graph))
      ~f:(fun collections (vertical, horizontal) ->
        Ui.View.column
          [ collections
          ; Ui.View.Body.with_size ~width:700. ~height:540. vertical
          ; Ui.View.Body.with_size ~width:900. ~height:400. horizontal
          ])
  in
  let scrolls =
    Bonsai.Cont.map2
      (scroll_component registry graph)
      (Bonsai.Cont.both
         (Carousel_catalog.component registry graph)
         (Bonsai.Cont.both
            (Scroll_sections_catalog.component registry graph)
            (Scroll_sections_catalog.component ~horizontal:true registry graph)))
      ~f:(fun scrolls (carousel, (vertical, horizontal)) ->
        Ui.View.column
          [ scrolls
          ; carousel
          ; Ui.View.Body.with_size ~width:700. ~height:540. vertical
          ; Ui.View.Body.with_size ~width:700. ~height:400. horizontal
          ])
  in
  let observers =
    List.concat_map
      (fun kind ->
         List.map
           (fun horizontal ->
              Scroll_observer_catalog.component ~kind ~horizontal registry graph)
           [ false; true ])
      [ 0; 1; 2; 3 ]
    |> Bonsai.Cont.all
  in
  let scrolls =
    Bonsai.Cont.map2 scrolls observers ~f:(fun content observers ->
      Ui.View.column
        (content :: List.map (Ui.View.Body.with_size ~width:700. ~height:300.) observers))
  in
  let scrolls =
    Bonsai.Cont.map2
      scrolls
      (Bonsai.Cont.both
         (Scroll_fill_catalog.component registry graph)
         (Scroll_fill_catalog.component ~horizontal:true registry graph))
      ~f:(fun scrolls (vertical, horizontal) ->
        Ui.View.column
          [ scrolls
          ; Ui.View.Body.with_size ~width:700. ~height:400. vertical
          ; Ui.View.Body.with_size ~width:700. ~height:400. horizontal
          ])
  in
  let initial_scrolls =
    List.concat_map
      (fun kind ->
         List.map
           (fun horizontal ->
              Initial_scroll_catalog.component
                ~kind
                ~horizontal
                ~initial:(if kind = 2 then 2 else 1)
                registry
                graph)
           [ false; true ])
      [ 0; 1; 2 ]
    |> Bonsai.Cont.all
  in
  let scrolls =
    Bonsai.Cont.map2 scrolls initial_scrolls ~f:(fun scrolls initial ->
      Ui.View.column
        (scrolls :: List.map (Ui.View.Body.with_size ~width:700. ~height:300.) initial))
  in
  let refreshes =
    List.map (fun kind -> Refresh_catalog.component ~kind registry graph) [ 0; 1; 2; 3 ]
    |> Bonsai.Cont.all
  in
  let scrolls =
    Bonsai.Cont.map2 scrolls refreshes ~f:(fun scrolls refreshes ->
      Ui.View.column
        (scrolls :: List.map (Ui.View.Body.with_size ~width:700. ~height:400.) refreshes))
  in
  let removals =
    Bonsai.Cont.all
      [ Removal_catalog.component registry graph
      ; Removal_catalog.component ~vertical:true registry graph
      ]
  in
  let scrolls =
    Bonsai.Cont.map2 scrolls removals ~f:(fun scrolls removals ->
      Ui.View.column
        (scrolls :: List.map (Ui.View.Body.with_size ~width:700. ~height:500.) removals))
  in
  let scrolls =
    Bonsai.Cont.map2
      scrolls
      (Contextual_selection_catalog.component registry graph)
      ~f:(fun scrolls selection ->
        Ui.View.column [ scrolls; Ui.View.frame ~width:900. ~height:600. selection ])
  in
  let searches =
    List.map
      (fun presentation -> Search_catalog.component ~presentation registry graph)
      [ 0; 1; 2 ]
    |> Bonsai.Cont.all
  in
  let scrolls =
    Bonsai.Cont.map2
      scrolls
      (Dropdown_catalog.component registry graph)
      ~f:(fun scrolls dropdown -> Ui.View.column [ scrolls; dropdown ])
  in
  let scrolls =
    Bonsai.Cont.map2 scrolls (theme_component registry graph) ~f:(fun scrolls theme ->
      Ui.View.column [ scrolls; theme ])
  in
  let scrolls =
    Bonsai.Cont.map2 scrolls searches ~f:(fun scrolls searches ->
      Ui.View.column
        (scrolls :: List.map (Ui.View.frame ~width:800. ~height:680.) searches))
  in
  let scrolls =
    Bonsai.Cont.map2
      scrolls
      (Table_catalog.component registry graph)
      ~f:(fun scrolls table ->
        Ui.View.column [ scrolls; Ui.View.frame ~width:820. ~height:740. table ])
  in
  let scrolls =
    Bonsai.Cont.map2
      scrolls
      (Composer_catalog.component registry graph)
      ~f:(fun scrolls composer ->
        Ui.View.column
          [ scrolls; section "Message composer" [ Ui.View.frame ~width:600. composer ] ])
  in
  let scrolls =
    Bonsai.Cont.map2
      scrolls
      (Expandable_composer_catalog.component registry graph)
      ~f:(fun scrolls composer ->
        Ui.View.column
          [ scrolls
          ; section "Expandable message composer" [ Ui.View.frame ~width:600. composer ]
          ])
  in
  let sheets = Sheet_catalog.component registry graph in
  let semantics =
    Bonsai.Cont.map2
      (Bonsai.Cont.map2
         (semantics_component registry graph)
         sheets
         ~f:(fun semantics sheets -> Ui.View.column [ semantics; sheets ]))
      (Bonsai.Cont.map2
         (help_component registry graph)
         (popover_component registry graph)
         ~f:(fun help popover -> Ui.View.column [ help; popover ]))
      ~f:(fun semantics help -> Ui.View.column [ semantics; help ])
  in
  let progress =
    Bonsai.Cont.map2
      (Bonsai.Cont.map2
         (progress_component registry graph)
         (Bonsai.Cont.map2
            (Toolbar_catalog.component registry graph)
            (App_bar_catalog.component registry graph)
            ~f:(fun toolbar app_bars ->
              Ui.View.column
                [ Ui.View.frame ~height:500. toolbar
                ; Ui.View.frame ~height:600. app_bars
                ]))
         ~f:(fun progress toolbar ->
           Ui.View.column [ progress; Ui.View.frame ~width:1000. toolbar ]))
      (Bonsai.Cont.both
         (Page_layout_catalog.component registry graph)
         (Sidebar_catalog.component registry graph))
      ~f:(fun progress (page, sidebar) ->
        Ui.View.column
          [ progress
          ; Ui.View.Body.with_size ~width:480. ~height:400. page
          ; Ui.View.Body.with_size ~width:900. ~height:640. sidebar
          ])
  in
  let safe_areas = safe_area_component registry graph in
  let splits =
    Bonsai.Cont.both
      (Bonsai.Cont.map2
         (split_component registry graph)
         (split_component ~two_columns:true registry graph)
         ~f:(fun three two -> Ui.View.column [ three; two ]))
      (Bonsai.Cont.both
         (tabs_component registry graph)
         (Bonsai.Cont.both
            (morph_component registry graph)
            (Bonsai.Cont.both
               (swipe_component registry graph)
               (Bonsai.Cont.both
                  (toggle_component registry graph)
                  (Bonsai.Cont.both
                     (slider_component registry graph)
                     (Bonsai.Cont.both
                        (picker_component registry graph)
                        (Bonsai.Cont.both
                           (multiple_selection_component registry graph)
                           (Bonsai.Cont.both
                              (tag_component registry graph)
                              (Bonsai.Cont.both
                                 (button_component registry graph)
                                 (Bonsai.Cont.both
                                    (projection_component registry graph)
                                    (Bonsai.Cont.both
                                       (opacity_component registry graph)
                                       (Bonsai.Cont.both
                                          (workflow_component registry graph)
                                          (Bonsai.Cont.both
                                             (disclosure_component registry graph)
                                             (Bonsai.Cont.both
                                                (group_box_component registry graph)
                                                (Bonsai.Cont.both
                                                   (label_component registry graph)
                                                   (Bonsai.Cont.both
                                                      (badge_component registry graph)
                                                      (hover_component registry graph)))))))))))))))))
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both model handlers)
    (Bonsai.Cont.both
       collection
       (Bonsai.Cont.both
          scrolls
          (Bonsai.Cont.both
             semantics
             (Bonsai.Cont.both progress (Bonsai.Cont.both safe_areas splits)))))
    ~f:
      (fun
        (model, handlers)
        (collection, (scrolls, (semantics, (progress, (safe_areas, splits))))) ->
      view model handlers collection scrolls semantics progress safe_areas splits)
;;
