module Ui = Bonsai_swiftui_ui
module V = Ui.View
module S = Ui.Native_widget.Surface
module ID = Bonsai_swiftui_spec.Id

type fixture =
  | Cornell
  | Reading
  | Video
  | Movies
  | Recipes
  | Journal

type theme =
  | Warm
  | Cool

type field =
  { session : ID.Text_input.session_id
  ; revision : ID.Text_input.document_revision
  ; local : ID.Text_input.local_revision
  ; mode : Ui.Text_editing.update_mode
  ; value : Ui.Text_editing.Value.t
  }

type block =
  { id : int
  ; checklist : bool
  }

type state =
  { fixture : fixture
  ; theme : theme
  ; templates : bool
  ; editing : bool
  ; query : field
  ; title : field
  ; body : field
  ; expanded : string list
  ; blocks : block list
  ; next_id : int
  ; generation : int
  ; preview : string option
  }

let title = function
  | Cornell -> "Cornell Note Template"
  | Reading -> "Robert Pirosh"
  | Video -> "Video Checklist"
  | Movies -> "Movie Library"
  | Recipes -> "Recipes Collection"
  | Journal -> "Daily Journal"
;;

let reading =
  "Dear Sir,\n\n\
   I like words. I like the way a small word can open a very large door. I like the \
   rustle of paper, the click of a typewriter, and the quiet pause before a sentence \
   finds its feet. Some words are warm and round; others arrive with sharp corners and a \
   little rain still on their coats.\n\n\
   A good paragraph is a room with the windows open. It lets a thought wander in, take a \
   seat, and notice something it had passed a hundred times before. I keep a notebook \
   for these discoveries: the blue of an early train, a conversation overheard in a \
   bookshop, the smell of oranges on a winter afternoon.\n\n\
   Writing begins with paying attention. We collect ordinary things until they become \
   extraordinary in company. A key, a question, a small remembered kindness: each has a \
   place on the page. There is no hurry to know what they mean.\n\n\
   Tomorrow I will return to this desk and try again. I will read a little, cross \
   something out, and leave enough space for a better idea. For now, the afternoon light \
   is moving across the keys, and that is a fine place to begin.\n\n\
   Yours sincerely,\n\
   A reader"
;;

let seed_body = function
  | Reading -> reading
  | Cornell -> "Capture the central idea in your own words."
  | Video ->
    "Plan a short story worth sharing.\n\n\
     Title Ideas\n\
     Research Links\n\
     Sponsor Information\n\
     Shot List\n\n\
     Thumbnail Inspirations"
  | Movies ->
    "Films to remember\n\n\
     The Red Balloon — 1956\n\
     My Neighbor Totoro — 1988\n\
     The Grand Budapest Hotel — 2014"
  | Recipes ->
    "A collection from the kitchen\n\n\
     Lemon pasta\n\
     Roasted tomato soup\n\
     Apple and cinnamon cake"
  | Journal ->
    "Today, I noticed...\n\nOne thing I am grateful for\n\nA small intention for tomorrow"
;;

let field session text =
  { session = ID.Text_input.Session_id.of_int64 (Int64.of_int session)
  ; revision = ID.Text_input.Document_revision.of_int64 1L
  ; local = ID.Text_input.Local_revision.zero
  ; mode = Ui.Text_editing.Force_replace
  ; value =
      Ui.Text_editing.Value.create
        ~text
        ~selection:(Ui.Text_editing.Range.create ~text ~start_utf16:0 ~end_utf16:0)
        ()
  }
;;

let initial =
  { fixture = Cornell
  ; theme = Warm
  ; templates = false
  ; editing = false
  ; query = field 1 ""
  ; title = field 2 (title Cornell)
  ; body = field 3 (seed_body Cornell)
  ; expanded = []
  ; blocks = []
  ; next_id = 1
  ; generation = 1
  ; preview = None
  }
;;

let contents f = Ui.Text_editing.Value.text f.value

let edit_field current (edit : Ui.Event.Payload.text_edit) =
  if
    (not (ID.Text_input.Session_id.equal current.session edit.session_id))
    || ID.Text_input.Local_revision.compare edit.local_revision current.local <= 0
    || ID.Text_input.Document_revision.compare
         edit.base_document_revision
         current.revision
       > 0
  then current
  else (
    let range (r : Ui.Event.Payload.text_selection) =
      Ui.Text_editing.Range.create
        ~text:edit.text
        ~start_utf16:r.start_utf16
        ~end_utf16:r.end_utf16
    in
    { current with
      revision = ID.Text_input.Document_revision.succ current.revision
    ; local = edit.local_revision
    ; mode = Ui.Text_editing.Ack
    ; value =
        Ui.Text_editing.Value.create
          ~text:edit.text
          ~selection:(range edit.selection)
          ?composing:(Option.map range edit.composing)
          ()
    })
;;

let choose state fixture =
  let generation = state.generation + 1 in
  { state with
    fixture
  ; theme = (if fixture = Reading then Cool else Warm)
  ; templates = false
  ; editing = false
  ; expanded = []
  ; blocks = []
  ; next_id = 1
  ; generation
  ; title = field ((generation * 3) + 2) (title fixture)
  ; body = field ((generation * 3) + 3) (seed_body fixture)
  ; preview = None
  }
;;

let fixtures = [ Video; Movies; Recipes; Cornell; Reading; Journal ]

let slug = function
  | Cornell -> "cornell"
  | Reading -> "reading"
  | Video -> "video"
  | Movies -> "movies"
  | Recipes -> "recipes"
  | Journal -> "journal"
;;

let reset_query state =
  let session = ID.Text_input.Session_id.to_int64 state.query.session |> Int64.to_int in
  { state with query = field (session + 3) "" }
;;

let update name payload state =
  match name, payload with
  | "query", Ui.Event.Payload.Text_edit e ->
    { state with query = edit_field state.query e }
  | "title", Ui.Event.Payload.Text_edit e when state.editing ->
    { state with title = edit_field state.title e }
  | "body", Ui.Event.Payload.Text_edit e when state.editing ->
    { state with body = edit_field state.body e }
  | "back", _ -> reset_query { state with templates = true; editing = false }
  | "close-templates", _ -> { state with templates = false }
  | "sheet", Ui.Event.Payload.Bool false -> { state with templates = false }
  | "clear-search", _ -> reset_query state
  | "edit", _ -> { state with editing = true }
  | "done-editing", _ -> { state with editing = false }
  | "close-preview", _ -> { state with preview = None }
  | "preview-dismiss", Ui.Event.Payload.Bool false -> { state with preview = None }
  | "share", _ -> { state with preview = Some "Share preview" }
  | "more", Ui.Event.Payload.Int64 1L -> reset_query { state with templates = true }
  | "more", Ui.Event.Payload.Int64 2L ->
    { state with preview = Some "About this document" }
  | "theme", Ui.Event.Payload.Int64 1L -> { state with theme = Warm }
  | "theme", Ui.Event.Payload.Int64 2L -> { state with theme = Cool }
  | "insert", Ui.Event.Payload.Int64 id when id = 1L || id = 2L ->
    { state with
      blocks = state.blocks @ [ { id = state.next_id; checklist = id = 2L } ]
    ; next_id = state.next_id + 1
    }
  | "tools", Ui.Event.Payload.Int64 1L ->
    { state with preview = Some "Word count preview" }
  | "tools", Ui.Event.Payload.Int64 2L ->
    { state with preview = Some "Reading focus preview" }
  | "format", Ui.Event.Payload.Int64 1L ->
    { state with preview = Some "Text style preview" }
  | "format", Ui.Event.Payload.Int64 2L ->
    { state with preview = Some "Page layout preview" }
  | (("key-points" | "supporting-details") as id), _ ->
    { state with
      expanded =
        (if List.mem id state.expanded
         then List.filter (( <> ) id) state.expanded
         else id :: state.expanded)
    }
  | name, _ ->
    (match List.find_opt (fun f -> name = "select-" ^ slug f) fixtures with
     | Some fixture -> choose state fixture
     | None -> state)
;;

let rgb hex =
  Ui.Style.Color.rgb
    ~red:((hex lsr 16) land 255)
    ~green:((hex lsr 8) land 255)
    ~blue:(hex land 255)
;;

let alpha a hex =
  Ui.Style.Color.argb
    ~alpha:a
    ~red:((hex lsr 16) land 255)
    ~green:((hex lsr 8) land 255)
    ~blue:(hex land 255)
;;

let ink = rgb 0x342b25
let muted = rgb 0x887e72
let tid id v = V.with_test_id (Ui.Test_id.string id) v
let key = Ui.Key.string
let pad n = V.padding ~insets:(Ui.Layout.Edge_insets.all n)

let inset ?(h = 0.) ?(v = 0.) child =
  V.padding ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:h ~vertical:v ()) child
;;

let full =
  V.frame
    ~max_width:Ui.Layout.Frame_limit.Fill
    ~alignment:Ui.Layout.Alignment.Center_start
;;

let gap n = V.spacer ~min_length:0. () |> V.frame ~height:n

let semantic name child =
  V.semantics ~properties:(Ui.Semantics.create ~label:name ()) child
;;

let handler hs name = List.assoc name hs

let button hs id name child =
  V.button
    ~key:(key id)
    ~style:Plain
    ~on_press:(handler hs id)
    ~child:(child |> semantic name)
    ()
  |> tid id
;;

let icon_button hs id name icon = button hs id name (V.symbol ~name:icon ())

let menu hs id name binding icon items =
  V.Menu.create
    ~key:(key id)
    ~on_select:(handler hs binding)
    ~label:(icon |> semantic name)
    (List.map (fun (id, text) -> V.Menu.action ~id ~label:(V.text text) ()) items)
  |> tid id
;;

let palette = function
  | Warm ->
    ( rgb 0xf0e2cb
    , rgb 0xe9dac3
    , alpha 65 0xffddaa
    , [ rgb 0xb88258; rgb 0xe3c39e; rgb 0xf4e7cd; rgb 0xbc865c ] )
  | Cool ->
    ( rgb 0xe6f5fa
    , rgb 0xd9eaf0
    , alpha 60 0xe1f6ff
    , [ rgb 0xd6c4e0; rgb 0xf2ccdf; rgb 0xe4c4da; rgb 0xbccddb ] )
;;

let shared_theme theme =
  let page, block, tint, _ = palette theme in
  Ui.Theme.create
    ~mode:Light
    ~tint:ink
    ~defaults:
      (Ui.Theme.Defaults.create
         ~colors:
           [ Primary, ink
           ; Secondary, muted
           ; Page, page
           ; Card, page
           ; Inset, block
           ; Search, alpha 75 0xbfc0c6
           ; Border, alpha 110 0xffffff
           ; Shadow, alpha 40 0x563520
           ; Material_tint, tint
           ]
         ())
    ()
;;

let input
      ?(appearance = Ui.Text_editing.Field_appearance.Rounded)
      hs
      id
      field
      ~multiline
      ~name
      ~binding
  =
  let on_edit = handler hs binding in
  let on_submit =
    handler
      hs
      (if multiline
       then "ignore"
       else if id = "title-editor"
       then "done-editing"
       else "ignore")
  in
  let on_focus_changed = handler hs "ignore" in
  (if multiline
   then
     V.text_editor
       ~key:(key id)
       ~session_id:field.session
       ~document_revision:field.revision
       ~accepted_local_revision:field.local
       ~update_mode:field.mode
       ~value:field.value
       ~on_edit
       ~on_submit
       ~on_focus_changed
       ~max_utf8_bytes:65536
       ()
   else
     V.text_field
       ~key:(key id)
       ~label:name
       ~appearance
       ~prompt:name
       ~session_id:field.session
       ~document_revision:field.revision
       ~accepted_local_revision:field.local
       ~update_mode:field.mode
       ~value:field.value
       ~on_edit
       ~on_submit
       ~on_focus_changed
       ~max_utf8_bytes:4096
       ())
  |> tid id
  |>
  if multiline
  then
    fun child ->
      V.semantics ~properties:(Ui.Semantics.create ~label:name ~children:Contain ()) child
  else Fun.id
;;

let divider () = V.divider ()

let dots () =
  V.text ~style:(Ui.Style.Text_style.create ~color:(rgb 0xb5a88f) ()) "·  ·  ·"
  |> V.frame ~max_width:Fill ~alignment:Center
  |> inset ~v:3.
;;

let disclosure hs state id name text =
  let expanded = List.mem id state.expanded in
  V.column
    ~alignment:Leading
    ~spacing:6.
    ([ V.button
         ~key:(key ("disclosure-" ^ id))
         ~style:Plain
         ~on_press:(handler hs id)
         ~child:
           (V.row
              ~spacing:12.
              [ V.symbol
                  ~name:(if expanded then "chevron.down" else "chevron.right")
                  ~size:10.
                  ()
              ; V.text name
              ]
            |> full
            |> semantic (name ^ if expanded then ", expanded" else ", collapsed"))
         ()
       |> tid ("disclosure-" ^ id)
     ]
     @
     if expanded
     then
       [ V.text ~style:(Ui.Style.Text_style.create ~font_size:16. ()) text
         |> tid ("details-" ^ id)
         |> inset ~h:20.
       ]
     else [])
;;

let cornell hs state =
  let section child = child |> pad 14. |> full |> S.create ~recipe:Inset_section in
  V.column
    ~alignment:Leading
    ~spacing:14.
    [ V.text
        ~style:(Ui.Style.Text_style.create ~font_size:23. ~font_weight:Bold ())
        "Lesson Title"
      |> section
    ; V.column
        ~alignment:Trailing
        ~spacing:2.
        [ V.text ~style:(Ui.Style.Text_style.create ~role:Hint ()) "Date:"
        ; V.text
            ~style:(Ui.Style.Text_style.create ~role:Hint ~italic:true ())
            "Use “/today” to insert date"
        ]
      |> V.frame ~max_width:Fill ~alignment:Center_end
      |> inset ~h:8. ~v:2.
    ; V.column
        ~alignment:Leading
        ~spacing:4.
        [ V.text "Main notes"
        ; disclosure
            hs
            state
            "key-points"
            "Key Points"
            "Write one clear idea, then connect it to what you already know."
        ; disclosure
            hs
            state
            "supporting-details"
            "Supporting Details"
            "Add examples, observations and questions that support the main idea."
        ]
      |> section
    ; dots ()
    ; V.column
        ~alignment:Leading
        [ V.text "Key words / Concepts"
        ; V.text
            ~style:(Ui.Style.Text_style.create ~role:Hint ~italic:true ())
            "Use “Assistant” with the prompt “Suggest Key words, Important Terms, and \
             Definitions based on Main notes & Key thoughts”"
        ; V.text "•    ...\n•    ...\n•    ..."
        ]
      |> section
    ; dots ()
    ; V.column
        ~alignment:Leading
        [ V.text ~style:(Ui.Style.Text_style.create ~font_size:19. ()) "Summary"
        ; V.text (contents state.body)
        ]
      |> section
    ]
;;

let cover ?(height = 206.) () =
  V.image ~sizing:Fill ~source:(Ui.Style.Image_source.resource "typewriter.png") ()
  |> V.frame ~max_width:Fill ~height
  |> V.clip ~corner_radius:Ui.Theme.Defaults.Values.small_corner
;;

let document hs state =
  let title_view =
    if state.fixture = Cornell
    then
      V.row
        ~spacing:4.
        [ V.text
            ~style:(Ui.Style.Text_style.create ~role:Editor_title ())
            (contents state.title)
          |> full
        ; V.text
            ~style:(Ui.Style.Text_style.create ~font_size:12. ~font_weight:Bold ())
            "◯₆"
          |> semantic "Decorative count ornament"
        ]
    else
      V.text
        ~style:(Ui.Style.Text_style.create ~role:Page_title ())
        (contents state.title)
      |> full
  in
  let content =
    (if state.fixture = Reading then [ cover () ] else [])
    @ [ title_view; divider () ]
    @ (if state.fixture = Cornell
       then [ cornell hs state ]
       else
         [ V.text
             ~style:(Ui.Style.Text_style.create ~line_spacing:4. ())
             (contents state.body)
         ])
    @ List.map
        (fun b ->
           (if b.checklist
            then V.row [ V.symbol ~name:"square" ~size:16. (); V.text "Review this note" ]
            else V.text "A new paragraph to explore.")
           |> tid ("inserted-" ^ string_of_int b.id))
        state.blocks
    @ [ gap 12.
      ; V.text
          ~style:(Ui.Style.Text_style.create ~role:Section_label ())
          "End of document"
        |> tid "document-end"
      ]
  in
  V.column ~alignment:Leading ~spacing:18. content
  |> full
  |> S.create ~recipe:Content_card ~content_inset:true ~border_color:(alpha 50 0xffffff)
  |> tid "document-card"
  |> inset ~h:16.
;;

let ring () =
  V.spacer ~min_length:0. ()
  |> V.frame ~width:26. ~height:26.
  |> S.create
       ~corner_radius:13.
       ~fill:
         (Angular
            [ rgb 0xee5355
            ; rgb 0xeddf38
            ; rgb 0x64c8df
            ; rgb 0x6251df
            ; rgb 0xe146bf
            ; rgb 0xee5355
            ])
  |> V.overlay
       ~overlay:
         (V.spacer ~min_length:0. ()
          |> V.frame ~width:16. ~height:16.
          |> V.background
               ~corner_radius:Ui.Theme.Defaults.Values.small_corner
               ~color:(rgb 0xf3eadf))
;;

let bottom hs =
  V.row
    ~spacing:0.
    [ V.row
        ~spacing:3.
        [ menu
            hs
            "tools-menu"
            "Document tools"
            "tools"
            (V.symbol ~name:"text.magnifyingglass" ())
            [ 1L, "Word count"; 2L, "Reading focus" ]
        ; menu
            hs
            "format-menu"
            "Text and page style"
            "format"
            (V.symbol ~name:"paintbrush.pointed" ())
            [ 1L, "Text style"; 2L, "Page layout" ]
        ; icon_button hs "edit" "Edit note" "pencil"
        ]
      |> S.create ~recipe:Material_action_group
    ; V.spacer ~min_length:10. ()
    ; V.row
        [ menu
            hs
            "theme-menu"
            "Document theme"
            "theme"
            (V.symbol ~name:"circle" ~size:26. ())
            [ 1L, "Warm paper"; 2L, "Cool paper" ]
          |> V.frame ~min_width:26. ~min_height:26.
          |> V.overlay ~overlay:(ring ())
        ; menu
            hs
            "insert-menu"
            "Insert block"
            "insert"
            (V.symbol ~name:"plus.circle.fill" ())
            [ 1L, "Paragraph"; 2L, "Checklist" ]
        ]
      |> S.create ~recipe:Material_action_group
    ]
  |> inset ~h:26. ~v:10.
  |> tid "bottom-controls"
;;

let top hs =
  V.row
    [ icon_button hs "back" "Templates" "chevron.left"
      |> S.create ~recipe:Material_action_group
    ; V.spacer ()
    ; V.row
        [ icon_button hs "share" "Share preview" "square.and.arrow.up"
        ; menu
            hs
            "more-menu"
            "More document actions"
            "more"
            (V.symbol ~name:"ellipsis.circle" ())
            [ 1L, "Templates"; 2L, "About this document" ]
        ]
      |> S.create ~recipe:Material_action_group
    ]
  |> inset ~h:22. ~v:10.
;;

let editor hs state =
  V.Weighted.column
    ~spacing:0.
    [ V.Weighted.fixed
        (V.row
           [ V.text ~style:(Ui.Style.Text_style.create ~role:Editor_title ()) "Edit note"
           ; V.spacer ()
           ; button
               hs
               "done-editing"
               "Done"
               (V.text ~style:(Ui.Style.Text_style.create ~font_weight:Bold ()) "Done")
           ]
         |> pad 16.)
    ; V.Weighted.fixed
        (input
           hs
           "title-editor"
           state.title
           ~multiline:false
           ~name:"Title"
           ~binding:"title"
         |> pad 16.)
    ; V.Weighted.fixed
        (V.text
           ~style:(Ui.Style.Text_style.create ~role:Hint ())
           "Plain text • Changes stay in this session"
         |> inset ~h:16.)
    ; V.Weighted.share
        (input
           hs
           "body-editor"
           state.body
           ~multiline:true
           ~name:"Note content"
           ~binding:"body"
         |> pad 16.
         |> V.frame ~max_height:Fill)
    ]
  |> V.frame ~max_width:Fill ~max_height:Fill
;;

let preview_tile fixture =
  let accent =
    match fixture with
    | Movies -> 0xe76b61
    | Recipes -> 0x86c9e6
    | Cornell -> 0xcaaa70
    | Reading -> 0xbbcdd7
    | Journal -> 0xbec6af
    | Video -> 0xe4e1d6
  in
  let mini =
    V.column
      ~alignment:Leading
      ~spacing:7.
      ((if fixture = Reading then [ cover ~height:58. () ] else [ gap 10. ])
       @ [ V.text
             ~style:(Ui.Style.Text_style.create ~font_size:10. ~font_weight:Bold ())
             (title fixture)
         ; divider ()
         ]
       @
       match fixture with
       | Video ->
         List.map
           (V.text ~style:(Ui.Style.Text_style.create ~font_size:8. ()))
           [ "▾  Title Ideas"
           ; "▾  Research Links"
           ; "▾  Sponsor Information"
           ; "▾  Shot List"
           ; ""
           ; "Thumbnail Inspirations"
           ]
       | Cornell ->
         List.map
           (V.text ~style:(Ui.Style.Text_style.create ~font_size:8. ()))
           [ "Lesson Title"
           ; ""
           ; "Main notes"
           ; "▸  Key Points"
           ; "▸  Supporting Details"
           ; "·  ·  ·"
           ; "Key words / Concepts"
           ]
       | _ ->
         List.map
           (V.text ~style:(Ui.Style.Text_style.create ~font_size:7. ~color:muted ()))
           [ "A place for your ideas"
           ; "_____________________"
           ; "_________________"
           ; "_____________________"
           ; "______________"
           ])
    |> pad 12.
    |> V.frame ~max_width:Fill ~height:172. ~alignment:Top_start
    |> V.clip ~corner_radius:Ui.Theme.Defaults.Values.small_corner
    |> V.background
         ~corner_radius:Ui.Theme.Defaults.Values.small_corner
         ~color:(rgb 0xf6f2e6)
  in
  mini |> pad 7. |> V.background ~corner_radius:13. ~color:(rgb accent)
;;

let tile hs f =
  V.button
    ~key:(key ("template-" ^ slug f))
    ~style:Plain
    ~on_press:(handler hs ("select-" ^ slug f))
    ~child:
      (V.column
         ~alignment:Leading
         ~spacing:7.
         [ preview_tile f
         ; V.text
             ~style:(Ui.Style.Text_style.create ~role:Caption ~color:muted ())
             (if f = Reading then "Reading · Robert Pirosh" else title f)
         ]
       |> semantic ("Use " ^ title f))
    ()
  |> tid ("template-" ^ slug f)
;;

let grid hs items =
  let rec rows = function
    | [] -> []
    | a :: b :: rest ->
      V.Weighted.row
        ~spacing:14.
        ~alignment:Top
        [ V.Weighted.share (tile hs a); V.Weighted.share (tile hs b) ]
      :: rows rest
    | [ a ] ->
      [ V.Weighted.row
          ~spacing:14.
          ~alignment:Top
          [ V.Weighted.share (tile hs a); V.Weighted.share (V.spacer ()) ]
      ]
  in
  V.column ~alignment:Leading ~spacing:18. (rows items)
;;

let catalog hs state =
  let query = String.lowercase_ascii (String.trim (contents state.query)) in
  let matches f =
    let haystack =
      String.lowercase_ascii (title f ^ if f = Reading then " reading" else "")
    in
    let n = String.length query in
    let rec find i =
      i + n <= String.length haystack && (String.sub haystack i n = query || find (i + 1))
    in
    find 0
  in
  let content =
    if query <> ""
    then (
      match List.filter matches fixtures with
      | [] ->
        V.column
          ~alignment:Leading
          [ V.text
              ~style:(Ui.Style.Text_style.create ~role:Empty_title ())
              "No templates found"
          ; V.text
              ~style:(Ui.Style.Text_style.create ~color:muted ())
              "Try another title or clear your search."
          ]
        |> inset ~v:32.
      | found -> grid hs found)
    else
      V.column
        ~alignment:Leading
        ~spacing:12.
        [ V.text ~style:(Ui.Style.Text_style.create ~role:Section_label ()) "MY TEMPLATES"
        ; grid hs [ Video ]
        ; divider ()
        ; V.text
            ~style:(Ui.Style.Text_style.create ~role:Section_label ())
            "COLLECT EVERYTHING"
        ; grid hs [ Movies; Recipes ]
        ; divider ()
        ; V.text
            ~style:(Ui.Style.Text_style.create ~role:Section_label ())
            "CRAFT FOR SELF-IMPROVEMENT"
        ; grid hs [ Cornell; Reading; Journal ]
        ]
  in
  V.Body.Vertical.create
    [ V.Body.Vertical.fixed
        (V.column
           ~alignment:Leading
           ~spacing:12.
           [ V.row
               [ V.text
                   ~style:
                     (Ui.Style.Text_style.create
                        ~role:Sheet_title
                        ~color:(rgb 0x242426)
                        ())
                   "Templates"
               ; V.spacer ()
               ; button
                   hs
                   "close-templates"
                   "Close templates"
                   (V.symbol ~name:"xmark.circle.fill" ~color:(alpha 90 0x929299) ())
               ]
             |> inset ~h:6.
           ; divider ()
           ; V.row
               ~spacing:10.
               ([ V.symbol ~name:"magnifyingglass" ~color:(rgb 0x929299) ()
                ; input
                    ~appearance:Plain
                    hs
                    "template-search"
                    state.query
                    ~multiline:false
                    ~name:"Search"
                    ~binding:"query"
                ]
                @
                if contents state.query = ""
                then []
                else
                  [ button
                      hs
                      "clear-search"
                      "Clear search"
                      (V.symbol ~name:"xmark.circle.fill" ~color:(rgb 0x929299) ())
                  ])
             |> inset ~h:12.
             |> S.create ~recipe:Search
           ]
         |> inset ~h:20. ~v:14.)
    ; V.Body.Vertical.fill (content |> inset ~h:18. ~v:10. |> V.Scroll.vertical)
    ]
  |> V.Body.Private.to_widget
  |> V.frame ~ideal_width:440. ~max_width:(Points 560.)
  |> S.create
       ~presentation_background:true
       ~recipe:Translucent_sheet
       ~border_color:(alpha 180 0xffffff)
       ~fill:(Ultra_thin_material (alpha 0 0xe9e9ee))
;;

let preview hs state =
  V.column
    ~alignment:Leading
    [ V.row
        [ V.text
            ~style:(Ui.Style.Text_style.create ~role:Editor_title ())
            (Option.value state.preview ~default:"")
        ; V.spacer ()
        ; icon_button hs "close-preview" "Close preview" "xmark.circle.fill"
        ]
    ; V.text
        ~style:(Ui.Style.Text_style.create ~font_weight:Bold ())
        (contents state.title)
    ; V.text "This is a local demo preview. Nothing is sent or saved."
    ; V.text
        ~style:(Ui.Style.Text_style.create ~font_size:15. ~color:muted ())
        (match state.preview with
         | Some "Word count preview" ->
           Printf.sprintf
             "%d words in the editable text."
             (contents state.body
              |> String.split_on_char ' '
              |> List.filter (fun s -> String.trim s <> "")
              |> List.length)
         | _ ->
           "Use Templates, Edit, Document theme or Insert block to explore the live \
            document controls.")
    ]
  |> pad 24.
  |> V.frame ~ideal_width:400. ~min_height:240.
;;

let render hs state =
  let _, _, _, colors = palette state.theme in
  let background =
    V.spacer ~min_length:0. ()
    |> V.frame ~max_width:Fill ~max_height:Fill
    |> S.create ~fill:(Linear colors)
    |> V.ignores_safe_area ~regions:Container
  in
  let content =
    if state.editing
    then editor hs state
    else
      V.Body.Vertical.create
        [ V.Body.Vertical.fixed (top hs)
        ; V.Body.Vertical.fixed (gap 18.)
        ; V.Body.Vertical.fill
            (V.column ~alignment:Leading ~spacing:0. [ document hs state; gap 96. ]
             |> V.Scroll.vertical
                  ~key:(key ("document-scroll-" ^ string_of_int state.generation))
                  ~shows_indicators:false)
        ]
      |> V.Body.overlay ~alignment:Bottom_center ~overlay:(bottom hs)
      |> V.Body.Private.to_widget
  in
  V.stack [ background |> tid "document-background"; content ]
  |> tid (if state.theme = Warm then "theme-warm" else "theme-cool")
  |> V.Sheet.create
       ~key:(key "templates-sheet")
       ~sizing:Page
       ~detents:[ Fraction 0.98 ]
       ~shows_drag_indicator:false
       ~presented:state.templates
       ~on_presented_changed:(handler hs "sheet")
       ~content:(catalog hs state)
  |> tid "templates-sheet"
  |> V.Sheet.create
       ~key:(key "preview-sheet")
       ~sizing:Fitted
       ~detents:[ Medium ]
       ~presented:(Option.is_some state.preview)
       ~on_presented_changed:(handler hs "preview-dismiss")
       ~content:(preview hs state)
  |> V.theme ~data:(shared_theme state.theme)
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let names =
    [ "query"
    ; "title"
    ; "body"
    ; "back"
    ; "close-templates"
    ; "sheet"
    ; "clear-search"
    ; "edit"
    ; "done-editing"
    ; "close-preview"
    ; "preview-dismiss"
    ; "share"
    ; "more"
    ; "theme"
    ; "insert"
    ; "tools"
    ; "format"
    ; "key-points"
    ; "supporting-details"
    ; "ignore"
    ]
    @ List.map (fun f -> "select-" ^ slug f) fixtures
  in
  let bindings =
    List.map
      (fun name ->
         Driver.Handler.create
           handlers
           ~name:("note-" ^ name)
           ~equal:( == )
           set_state
           ~f:(fun set_state payload -> set_state (update name payload))
         |> Bonsai.Cont.map ~f:(fun h -> name, h))
      names
    |> Bonsai.Cont.all
  in
  Bonsai.Cont.map2 state bindings ~f:(fun state hs -> render hs state)
;;

let app =
  App.create ~name:"Bonsai Note" (fun h g ->
    Bonsai.Cont.map (component h g) ~f:(fun v ->
      App.View.create ~theme:(shared_theme Warm) ~body:(V.Body.static v)))
;;
