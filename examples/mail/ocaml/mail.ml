module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type mailbox =
  | Inbox
  | Archived
  | Trash

type category =
  | Primary
  | Promotions
  | Updates

type attachment =
  { name : string
  ; kind : string
  ; size : string
  }

type outline_tone =
  | Default
  | Muted

type outline_node =
  { text : string
  ; tone : outline_tone
  ; children : outline_node list
  }

type message =
  { id : int
  ; sender : string
  ; address : string
  ; subject : string
  ; preview : string
  ; body : string
  ; timestamp : string
  ; read : bool
  ; starred : bool
  ; mailbox : mailbox
  ; category : category
  ; attachment : attachment option
  ; outline : outline_node list
  }

type app_destination =
  | Mail
  | Chat
  | Spaces
  | Meet

type mail_destination =
  | Inbox_view
  | Starred_view
  | Archived_view
  | Trash_view
  | Settings_view

type load_state =
  | Idle
  | Loading_more of
      { generation : int
      ; cursor : int
      }

type state =
  { messages : message list
  ; layout_revision : int64
  ; selected_id : int option
  ; expanded_id : int option
  ; notice : string option
  ; card_notice : string option
  ; selected_app_destination : app_destination
  ; selected_mail_destination : mail_destination
  ; split_visibility : Ui.Navigation.Split_visibility.t
  ; compact_column : Ui.Navigation.Split_column.t
  ; next_cursor : int
  ; next_generation : int
  ; load_state : load_state
  ; painted_first_index : int
  ; painted_last_exclusive : int
  }

let message
      id
      sender
      address
      subject
      preview
      body
      timestamp
      ~read
      ~starred
      ?(category = Primary)
      ?attachment
      ?outline
      ()
  =
  let outline =
    Option.value
      outline
      ~default:
        [ { text = subject
          ; tone = Default
          ; children = [ { text = preview; tone = Default; children = [] } ]
          }
        ; { text = "Prepared for local review"; tone = Muted; children = [] }
        ]
  in
  { id
  ; sender
  ; address
  ; subject
  ; preview
  ; body
  ; timestamp
  ; read
  ; starred
  ; mailbox = Inbox
  ; category
  ; attachment
  ; outline
  }
;;

let curated_messages =
  [ message
      1
      "Mara Vale"
      "mara@willowpost.example"
      "The field notes are ready"
      "I gathered the last observations from the north plot."
      "Hello,\n\n\
       I gathered the last observations from the north plot and organized them into a \
       short set of field notes. The new growth is holding steady after the rain.\n\n\
       Highlights:\n\
       • Five young maples are ready for wiring.\n\
       • The cedar bench needs fresh shade cloth.\n\
       • Watering can move to the summer schedule.\n\n\
       I will bring the printed notes to our next workshop.\n\n\
       Mara"
      "9:42 AM"
      ~read:false
      ~starred:true
      ~outline:
        [ { text = "Field notes from the north plot"; tone = Default; children = [] }
        ; { text = "Highlights"
          ; tone = Default
          ; children =
              [ { text = "Five young maples are ready for wiring"
                ; tone = Default
                ; children = []
                }
              ; { text = "Cedar bench needs fresh shade cloth"
                ; tone = Default
                ; children = []
                }
              ; { text = "Move watering to the summer schedule"
                ; tone = Default
                ; children = []
                }
              ]
          }
        ; { text = "Printed notes at the next workshop — Mara"
          ; tone = Muted
          ; children = []
          }
        ]
      ()
  ; message
      2
      "River Tan"
      "river@smallhours.example"
      "A quieter plan for Thursday"
      "Could we move the review to the garden table?"
      "Hi,\n\n\
       Could we move Thursday's review to the garden table at 3 PM? I simplified the \
       agenda to the three decisions that need us both.\n\n\
       River"
      "8:16 AM"
      ~read:true
      ~starred:false
      ()
  ; message
      3
      "Orin Studio"
      "notes@orinstudio.example"
      "Your kiln shelf reservation"
      "The west shelf is held through Monday afternoon."
      "Your west kiln shelf reservation is confirmed through Monday at 4 PM. Reply at \
       the studio desk if you need a longer firing window."
      "Yesterday"
      ~read:true
      ~starred:false
      ~category:Updates
      ()
  ; message
      4
      "Juniper Works"
      "hello@juniperworks.example"
      "Workshop guide and material list"
      "Everything for the miniature landscape session is attached."
      "Hello,\n\n\
       The guide for Saturday's miniature landscape session is attached. Please bring a \
       small towel and wear something comfortable for working with soil.\n\n\
       See you there,\n\
       Juniper Works"
      "Yesterday"
      ~read:false
      ~starred:false
      ~attachment:
        { name = "Miniature-landscape-guide.pdf"; kind = "PDF"; size = "1.8 MB" }
      ()
  ; message
      5
      "Eli North"
      "eli@copperfern.example"
      "Three sketches from the station"
      "The second study has the strongest silhouette."
      "I made three small sketches while waiting at the station. The second one has the \
       strongest silhouette, so I think we should develop that direction."
      "Jul 24"
      ~read:false
      ~starred:true
      ()
  ; message
      6
      "Bramble Library"
      "desk@bramblelibrary.example"
      "Reserved book is available"
      "We will hold The Shape of Small Gardens for seven days."
      "The Shape of Small Gardens is ready for pickup at the main desk. We will hold it \
       for seven days."
      "Jul 23"
      ~read:true
      ~starred:false
      ~category:Updates
      ()
  ; message
      7
      "Nia Moss"
      "nia@papertrail.example"
      "Photos from the morning walk"
      "The fog made the old footbridge look completely new."
      "The fog made the old footbridge look completely new. I selected six photos that \
       tell the story without repeating the same view."
      "Jul 22"
      ~read:true
      ~starred:false
      ()
  ; message
      8
      "Lantern Market"
      "news@lanternmarket.example"
      "Handmade tools this weekend"
      "Local makers are bringing carving knives and wire cutters."
      "This weekend's market includes a small collection of handmade garden tools from \
       local makers."
      "Jul 21"
      ~read:false
      ~starred:false
      ~category:Promotions
      ()
  ; message
      9
      "Aster Quinn"
      "aster@quietledger.example"
      "Budget notes, revised"
      "I moved the display stands into the optional column."
      "I revised the workshop budget and moved the display stands into the optional \
       column. The new total leaves a comfortable reserve."
      "Jul 19"
      ~read:true
      ~starred:true
      ()
  ; message
      10
      "Stone & Stem"
      "orders@stoneandstem.example"
      "Order packed for collection"
      "Your glazed trays will be ready after noon."
      "Your set of glazed trays has been packed and will be ready for collection after \
       noon tomorrow."
      "Jul 18"
      ~read:true
      ~starred:false
      ~category:Updates
      ()
  ; message
      11
      "Tomas Reed"
      "tomas@longtable.example"
      "Notes on the patient pine"
      "I agree that one more season is the right call."
      "I agree that one more season is the right call. The trunk is gaining character, \
       and the lower branch can wait before the next decision."
      "Jul 16"
      ~read:false
      ~starred:false
      ()
  ; message
      12
      "Lumen House"
      "events@lumenhouse.example"
      "Courtyard supper confirmation"
      "Your table for four is confirmed for Friday."
      "Your courtyard table for four is confirmed for Friday at 7 PM. We look forward to \
       welcoming you."
      "Jul 14"
      ~read:true
      ~starred:false
      ()
  ]
;;

let generated_message id =
  message
    id
    (Printf.sprintf "Field Correspondent %d" id)
    (Printf.sprintf "dispatch-%d@fieldnotes.example" id)
    (Printf.sprintf "Field Dispatch %d" id)
    (Printf.sprintf "A concise update from field station %d." id)
    (Printf.sprintf
       "Hello,\n\n\
        This is the deterministic field dispatch for station %d. The notes are ready for \
        the next local review.\n\n\
        Field Correspondent %d"
       id
       id)
    "Earlier"
    ~read:(id mod 2 = 0)
    ~starred:(id mod 7 = 0)
    ~category:
      (match id mod 3 with
       | 0 -> Primary
       | 1 -> Promotions
       | _ -> Updates)
    ~outline:
      [ { text = Printf.sprintf "Field dispatch from station %d" id
        ; tone = Default
        ; children =
            [ { text = "A concise station update is ready"
              ; tone = Default
              ; children = []
              }
            ; { text = "Queued for the next local review"; tone = Muted; children = [] }
            ]
        }
      ]
    ()
;;

let generated_messages ~first_id ~count =
  List.init count (fun offset -> generated_message (first_id + offset))
;;

let initial_messages = curated_messages @ generated_messages ~first_id:13 ~count:8

let messages_for_cursor cursor =
  generated_messages ~first_id:((cursor * 20) + 1) ~count:20
;;

let initial =
  { messages = initial_messages
  ; layout_revision = 0L
  ; selected_id = None
  ; expanded_id = None
  ; notice = None
  ; card_notice = None
  ; selected_app_destination = Mail
  ; selected_mail_destination = Inbox_view
  ; split_visibility = Ui.Navigation.Split_visibility.All
  ; compact_column = Ui.Navigation.Split_column.Content
  ; next_cursor = 1
  ; next_generation = 0
  ; load_state = Idle
  ; painted_first_index = 0
  ; painted_last_exclusive = 20
  }
;;

let equal_state = ( = )

let update_message state id update =
  { state with
    messages =
      List.map
        (fun candidate -> if candidate.id = id then update candidate else candidate)
        state.messages
  }
;;

let find_message messages id =
  List.find_opt (fun message -> Int.equal message.id id) messages
;;

let message_is_visible state message =
  match state.selected_mail_destination with
  | Inbox_view -> message.mailbox = Inbox
  | Starred_view -> message.starred
  | Archived_view -> message.mailbox = Archived
  | Trash_view -> message.mailbox = Trash
  | Settings_view -> false
;;

let clear_expansion state = { state with expanded_id = None; card_notice = None }

let clear_expansion_if state message_id =
  if state.expanded_id = Some message_id then clear_expansion state else state
;;

let sanitize_expansion state =
  match state.expanded_id with
  | None -> state
  | Some message_id ->
    (match find_message state.messages message_id with
     | Some message when message_is_visible state message -> state
     | None | Some _ -> clear_expansion state)
;;

let category_label = function
  | Primary -> "Primary"
  | Promotions -> "Promotions"
  | Updates -> "Updates"
;;

let color red green blue = Ui.Style.Color.rgb ~red ~green ~blue
let background = color 241 246 251
let surface = color 253 253 255
let search_surface = color 255 255 255
let primary = color 67 95 138
let primary_container = color 220 231 248
let text_primary = color 28 32 38
let text_secondary = color 91 99 110
let unread_surface = color 239 246 255
let star_color = color 218 154 34
let archive_surface = color 80 125 88
let trash_surface = color 179 55 62

let style ?size ?weight ?spacing ?color () =
  Ui.Style.Text_style.create
    ?font_size:size
    ?font_weight:weight
    ?line_spacing:spacing
    ?color
    ()
;;

let styled_text
      ?size
      ?weight
      ?spacing
      ?color
      ?line_limit
      ?(truncation = Ui.Style.Text_truncation.Tail)
      value
  =
  Ui.View.text
    ~style:(style ?size ?weight ?spacing ?color ())
    ?line_limit
    ~truncation
    value
;;

let padding ?(horizontal = 0.) ?(vertical = 0.) child =
  Ui.View.padding ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal ~vertical ()) child
;;

let icon ?size ?color name = Ui.View.symbol ?size ?color ~name ()

let avatar message =
  let avatar_colors =
    [ color 214 229 246
    ; color 229 219 242
    ; color 211 235 224
    ; color 244 224 210
    ; color 226 229 204
    ]
  in
  let background = List.nth avatar_colors (message.id mod List.length avatar_colors) in
  let initial =
    if String.length message.sender = 0 then "?" else String.make 1 message.sender.[0]
  in
  Ui.View.frame
    ~width:40.
    ~height:40.
    (Ui.View.background
       ~color:background
       ~corner_radius:20.
       (Ui.View.frame
          ~max_width:Ui.Layout.Frame_limit.Fill
          ~max_height:Ui.Layout.Frame_limit.Fill
          (styled_text
             ~size:16.
             ~weight:Ui.Style.Font_weight.Medium
             ~color:primary
             initial)))
;;

let semantic_icon_button ~test_id ~label ~selected ~on_press ~name ~color =
  Ui.View.button
    ~style:Ui.View.Button_style.Plain
    ~on_press
    ~child:(icon ~size:22. ~color name)
    ()
  |> Ui.View.with_test_id (Ui.Test_id.string test_id)
  |> Ui.View.semantics
       ~properties:
         (Ui.Semantics.create ~label ~role:Ui.Semantics.Role.Button ~selected ())
;;

let star_control on_press message ~detail =
  semantic_icon_button
    ~test_id:
      (if detail then "mail-detail-star" else Printf.sprintf "mail-star-%d" message.id)
    ~label:
      (Printf.sprintf
         "%s message from %s"
         (if message.starred then "Starred" else "Not starred")
         message.sender)
    ~selected:message.starred
    ~on_press
    ~name:(if message.starred then "star.fill" else "star")
    ~color:(if message.starred then star_color else text_secondary)
;;

let search_header on_menu =
  Ui.View.frame
    ~height:56.
    (Ui.View.background
       ~color:search_surface
       ~corner_radius:28.
       (Ui.View.Weighted.row
          [ Ui.View.Weighted.fixed
              (semantic_icon_button
                 ~test_id:"mail-menu"
                 ~label:"Menu"
                 ~selected:false
                 ~on_press:on_menu
                 ~name:"line.3.horizontal"
                 ~color:primary)
          ; Ui.View.Weighted.share
              (styled_text ~size:16. ~color:text_secondary "Search in mail")
          ; Ui.View.Weighted.fixed
              (Ui.View.frame
                 ~width:40.
                 ~height:40.
                 (Ui.View.background
                    ~color:primary_container
                    ~corner_radius:20.
                    (Ui.View.frame
                       ~max_width:Ui.Layout.Frame_limit.Fill
                       ~max_height:Ui.Layout.Frame_limit.Fill
                       (styled_text
                          ~size:14.
                          ~weight:Ui.Style.Font_weight.Semi_bold
                          ~color:primary
                          "BM"))))
          ; Ui.View.Weighted.fixed
              (Ui.View.frame ~width:8. (Ui.View.spacer ~min_length:0. ()))
          ]))
  |> Ui.View.with_test_id (Ui.Test_id.string "mail-search-header")
  |> Ui.View.semantics
       ~properties:(Ui.Semantics.create ~label:"Search in mail" ~role:Generic ())
;;

let compact_mail_extent = 88.
let card_outer_vertical_extent = 20.
let card_header_extent = 88.
let card_outline_vertical_extent = 16.
let card_outline_line_extent = 30.
let card_notice_extent = 48.
let card_divider_extent = 1.
let card_footer_extent = 56.

let rec flatten_outline ?(depth = 0) ?(prefix = []) nodes =
  List.concat
    (List.mapi
       (fun index node ->
          let path = prefix @ [ index ] in
          (path, depth, node)
          :: flatten_outline ~depth:(depth + 1) ~prefix:path node.children)
       nodes)
;;

let expanded_mail_extent message ~has_notice =
  let outline_count = List.length (flatten_outline message.outline) in
  card_outer_vertical_extent
  +. card_header_extent
  +. card_divider_extent
  +. card_outline_vertical_extent
  +. (Float.of_int outline_count *. card_outline_line_extent)
  +. (if has_notice then card_notice_extent else 0.)
  +. card_divider_extent
  +. card_footer_extent
;;

let outline_test_id message_id path =
  path
  |> List.map string_of_int
  |> String.concat "-"
  |> Printf.sprintf "mail-outline-%d-%s" message_id
;;

let render_outline_node message_id (path, depth, node) =
  let connector =
    if depth = 0
    then Ui.View.frame ~width:20. (Ui.View.spacer ~min_length:0. ())
    else
      Ui.View.spacer ~min_length:0. ()
      |> Ui.View.frame ~width:20. ~height:card_outline_line_extent
      |> Ui.View.overlay
           ~alignment:Top_start
           ~overlay:
             (Ui.View.spacer ~min_length:0. ()
              |> Ui.View.background ~color:primary_container
              |> Ui.View.frame
                   ~width:1.
                   ~min_height:0.
                   ~max_height:Ui.Layout.Frame_limit.Fill)
      |> Ui.View.overlay
           ~alignment:Top_start
           ~overlay:
             (Ui.View.spacer ~min_length:0. ()
              |> Ui.View.background ~color:primary_container
              |> Ui.View.frame ~width:20. ~height:1.
              |> Ui.View.offset ~y:14.)
  in
  let bullet =
    Ui.View.frame
      ~width:8.
      ~height:8.
      (Ui.View.background
         ~color:(if node.tone = Muted then text_secondary else primary)
         ~corner_radius:4.
         (Ui.View.spacer ~min_length:0. ()))
  in
  Ui.View.frame
    ~min_height:card_outline_line_extent
    (Ui.View.Weighted.row
       [ Ui.View.Weighted.fixed
           (Ui.View.frame
              ~width:(Float.of_int depth *. 28.)
              (Ui.View.spacer ~min_length:0. ()))
       ; Ui.View.Weighted.fixed connector
       ; Ui.View.Weighted.fixed bullet
       ; Ui.View.Weighted.share
           (padding
              ~horizontal:10.
              (styled_text
                 ~size:13.5
                 ~color:(if node.tone = Muted then text_secondary else text_primary)
                 node.text))
       ])
  |> Ui.View.with_test_id (Ui.Test_id.string (outline_test_id message_id path))
  |> Ui.View.semantics
       ~properties:
         (Ui.Semantics.create
            ~label:(Printf.sprintf "Outline level %d: %s" (depth + 1) node.text)
            ())
;;

let collapsed_mail_content ~large_text ~toggle_star ~expand message =
  let sender_weight = if message.read then Ui.Style.Font_weight.Normal else Semi_bold in
  let timestamp =
    styled_text ~size:11.5 ~color:text_secondary ~line_limit:1 message.timestamp
  in
  let text_column =
    Ui.View.column
      ~alignment:Leading
      ([ styled_text
           ~size:15.
           ~weight:sender_weight
           ~color:text_primary
           ~line_limit:1
           message.sender
       ; styled_text
           ~size:13.5
           ~weight:sender_weight
           ~color:text_primary
           ~line_limit:(if large_text then 2 else 1)
           message.subject
       ; styled_text
           ~size:13.
           ~color:text_secondary
           ~line_limit:(if large_text then 2 else 1)
           message.preview
       ]
       @ if large_text then [ timestamp ] else [])
  in
  let trailing =
    Ui.View.column
      ((if large_text then [] else [ timestamp ])
       @ [ star_control toggle_star message ~detail:false ])
  in
  let content =
    Ui.View.background
      ~color:(if message.read then surface else unread_surface)
      (Ui.View.frame
         ~min_height:compact_mail_extent
         (padding
            ~horizontal:16.
            ~vertical:8.
            (Ui.View.Weighted.row
               ((if large_text then [] else [ Ui.View.Weighted.fixed (avatar message) ])
                @ [ Ui.View.Weighted.share (padding ~horizontal:12. text_column)
                  ; Ui.View.Weighted.fixed trailing
                  ]))))
    |> Ui.View.with_test_id (Ui.Test_id.string (Printf.sprintf "mail-row-%d" message.id))
    |> Ui.View.semantics
         ~properties:
           (Ui.Semantics.create
              ~label:
                (Printf.sprintf
                   "%s message from %s"
                   (if message.read then "Read" else "Unread")
                   message.sender)
              ~hint:
                (Printf.sprintf
                   "%s, %s"
                   message.subject
                   (category_label message.category))
              ~value:"Collapsed"
              ~role:Ui.Semantics.Role.Button
              ())
    |> fun child ->
    Ui.View.button
      ~key:(Ui.Key.int message.id)
      ~style:Ui.View.Button_style.Plain
      ~child
      ~on_press:expand
      ()
    |> Ui.View.with_test_id
         (Ui.Test_id.string (Printf.sprintf "mail-button-%d" message.id))
  in
  content
;;

let expanded_mail_content
      ~large_text
      ~toggle_star
      ~collapse
      ~reply
      ~open_message
      ~notice
      message
  =
  let sender_weight = if message.read then Ui.Style.Font_weight.Normal else Semi_bold in
  let header_text =
    Ui.View.column
      ~alignment:Leading
      ([ styled_text
           ~size:15.
           ~weight:sender_weight
           ~color:text_primary
           ~line_limit:1
           ~truncation:Tail
           message.sender
       ; styled_text
           ~size:13.5
           ~weight:(if message.read then Normal else Semi_bold)
           ~color:text_primary
           ~line_limit:(if large_text then 2 else 1)
           ~truncation:Tail
           message.subject
       ]
       @
       if large_text
       then [ styled_text ~size:11.5 ~color:text_secondary message.timestamp ]
       else [])
  in
  let collapsible_header =
    Ui.View.frame
      ~min_height:card_header_extent
      (padding
         ~horizontal:12.
         ~vertical:8.
         (Ui.View.Weighted.row
            ((if large_text then [] else [ Ui.View.Weighted.fixed (avatar message) ])
             @ [ Ui.View.Weighted.share (padding ~horizontal:12. header_text) ]
             @
             if large_text
             then []
             else
               [ Ui.View.Weighted.fixed
                   (styled_text ~size:11.5 ~color:text_secondary message.timestamp)
               ])))
    |> Ui.View.semantics
         ~properties:
           (Ui.Semantics.create
              ~label:
                (Printf.sprintf
                   "%s message from %s"
                   (if message.read then "Read" else "Unread")
                   message.sender)
              ~hint:
                (Printf.sprintf
                   "%s, %s"
                   message.subject
                   (category_label message.category))
              ~value:"Expanded"
              ~role:Ui.Semantics.Role.Button
              ())
    |> fun child ->
    Ui.View.button ~style:Ui.View.Button_style.Plain ~child ~on_press:collapse ()
    |> Ui.View.with_test_id
         (Ui.Test_id.string (Printf.sprintf "mail-card-header-%d" message.id))
  in
  let collapse_button =
    semantic_icon_button
      ~test_id:(Printf.sprintf "mail-card-collapse-%d" message.id)
      ~label:(Printf.sprintf "Collapse message from %s" message.sender)
      ~selected:false
      ~on_press:collapse
      ~name:"chevron.up"
      ~color:primary
  in
  let header =
    collapsible_header
    |> Ui.View.overlay
         ~alignment:Bottom_end
         ~overlay:
           (star_control toggle_star message ~detail:false
            |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.only ~trailing:48. ()))
    |> Ui.View.overlay ~alignment:Bottom_end ~overlay:collapse_button
  in
  let outline =
    message.outline
    |> flatten_outline
    |> List.map (render_outline_node message.id)
    |> Ui.View.column
    |> padding ~horizontal:12. ~vertical:8.
  in
  let notice_widget =
    Option.map
      (fun notice ->
         Ui.View.frame
           ~min_height:card_notice_extent
           (padding
              ~horizontal:16.
              ~vertical:6.
              (Ui.View.background
                 ~color:primary_container
                 ~corner_radius:12.
                 (Ui.View.frame
                    ~max_width:Ui.Layout.Frame_limit.Fill
                    ~max_height:Ui.Layout.Frame_limit.Fill
                    (styled_text ~size:12.5 ~color:primary notice))))
         |> Ui.View.with_test_id
              (Ui.Test_id.string (Printf.sprintf "mail-card-notice-%d" message.id))
         |> Ui.View.semantics
              ~properties:(Ui.Semantics.create ~label:notice ~live_region:true ()))
      notice
  in
  let action ~test_id ~label ~semantic_label handler =
    Ui.View.button
      ~style:Ui.View.Button_style.Plain
      ~on_press:handler
      ~child:(styled_text ~size:14. ~weight:Medium ~color:primary label)
      ()
    |> Ui.View.with_test_id (Ui.Test_id.string test_id)
    |> Ui.View.semantics
         ~properties:
           (Ui.Semantics.create ~label:semantic_label ~role:Ui.Semantics.Role.Button ())
    |> Ui.View.frame ~min_height:card_footer_extent
  in
  let separator =
    Ui.View.frame
      ~width:1.
      ~height:card_footer_extent
      (Ui.View.background ~color:primary_container (Ui.View.spacer ~min_length:0. ()))
  in
  let footer =
    Ui.View.Weighted.row
      [ Ui.View.Weighted.share
          (action
             ~test_id:(Printf.sprintf "mail-card-reply-%d" message.id)
             ~label:"Reply"
             ~semantic_label:(Printf.sprintf "Reply to %s" message.sender)
             reply)
      ; Ui.View.Weighted.fixed separator
      ; Ui.View.Weighted.share
          (action
             ~test_id:(Printf.sprintf "mail-card-open-%d" message.id)
             ~label:"Open"
             ~semantic_label:(Printf.sprintf "Open message from %s" message.sender)
             open_message)
      ]
  in
  let divider = Ui.View.frame ~height:card_divider_extent (Ui.View.divider ()) in
  let blocks =
    [ Some header; Some divider; Some outline; notice_widget; Some divider; Some footer ]
    |> List.filter_map Fun.id
  in
  Ui.View.column blocks
  |> Ui.View.with_test_id (Ui.Test_id.string (Printf.sprintf "mail-card-%d" message.id))
;;

let with_swipe_actions ~swipe_actions message content =
  let archive, (trash, read) = swipe_actions in
  let action ~key ~side ~title ~background ~symbol ?(full_swipe = false) ~on_press () =
    Ui.View.Swipe_actions.action
      ~key:(Ui.Key.string (Printf.sprintf "mail-swipe-%s-%d" key message.id))
      ~side
      ~title
      ~background
      ~full_swipe
      ~on_press
      ~child:
        (Ui.View.column
           ~spacing:8.
           [ icon ~size:24. ~color:surface symbol; Ui.View.text title ])
      ()
  in
  let archive_action =
    action
      ~key:"archive"
      ~side:Start
      ~title:"Archive"
      ~background:archive_surface
      ~symbol:"archivebox"
      ~full_swipe:true
      ~on_press:archive
      ()
  in
  let trash_action =
    action
      ~key:"trash"
      ~side:Start
      ~title:"Trash"
      ~background:trash_surface
      ~symbol:"trash"
      ~on_press:trash
      ()
  in
  let read_action =
    action
      ~key:"read"
      ~side:End
      ~title:(if message.read then "Mark unread" else "Mark read")
      ~background:primary
      ~symbol:"envelope"
      ~on_press:read
      ()
  in
  Ui.View.Swipe_actions.create
    ~key:(Ui.Key.int message.id)
    ~group:"mail-inbox"
    ~actions:[ archive_action; trash_action; read_action ]
    ~content
    ()
  |> Ui.View.with_test_id (Ui.Test_id.string (Printf.sprintf "mail-swipe-%d" message.id))
;;

let render_mail_row
      ~large_text
      ~toggle_star
      ~expand
      ~collapse
      ~reply
      ~open_message
      ~swipe_actions
      ~expanded
      ~notice
      message
  =
  let content =
    Ui.View.Morphing_surface.create
      ~expanded
      ~compact_content:(collapsed_mail_content ~large_text ~toggle_star ~expand message)
      ~expanded_content:
        (expanded_mail_content
           ~large_text
           ~toggle_star
           ~collapse
           ~reply
           ~open_message
           ~notice
           message)
      ()
  in
  with_swipe_actions ~swipe_actions message content
  |> Ui.View.Keyed.create ~key:(Ui.Key.int message.id)
;;

let mail_row handlers set_state large_text message_id row_data _graph =
  let dependencies = Bonsai.Cont.both set_state message_id in
  let equal_dependencies (left_set_state, left_id) (right_set_state, right_id) =
    left_set_state == right_set_state && Int.equal left_id right_id
  in
  let toggle_star =
    Driver.Handler.create
      handlers
      ~name:"mail-toggle-star"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update_message state message_id (fun message ->
            { message with starred = not message.starred })
          |> sanitize_expansion))
  in
  let expand =
    Driver.Handler.create
      handlers
      ~name:"mail-expand-message"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) payload ->
        match payload with
        | Ui.Event.Payload.Unit ->
          set_state (fun state ->
            { state with expanded_id = Some message_id; card_notice = None })
        | _ -> Bonsai.Effect.Ignore)
  in
  let collapse =
    Driver.Handler.create
      handlers
      ~name:"mail-collapse-message"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) payload ->
        match payload with
        | Ui.Event.Payload.Unit ->
          set_state (fun state -> clear_expansion_if state message_id)
        | _ -> Bonsai.Effect.Ignore)
  in
  let reply =
    Driver.Handler.create
      handlers
      ~name:"mail-card-reply"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) payload ->
        match payload with
        | Ui.Event.Payload.Unit ->
          set_state (fun state ->
            if state.expanded_id = Some message_id
            then
              { state with
                card_notice = Some "Composing is outside the scope of this demo."
              }
            else state)
        | _ -> Bonsai.Effect.Ignore)
  in
  let open_message =
    Driver.Handler.create
      handlers
      ~name:"mail-open-message"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) payload ->
        match payload with
        | Ui.Event.Payload.Unit ->
          set_state (fun state ->
            update_message state message_id (fun message -> { message with read = true })
            |> fun state ->
            { state with
              selected_id = Some message_id
            ; compact_column = Ui.Navigation.Split_column.Detail
            ; notice = None
            ; card_notice = None
            })
        | _ -> Bonsai.Effect.Ignore)
  in
  let swipe_action name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state -> update state message_id))
  in
  let archive =
    swipe_action "mail-swipe-archive" (fun state id ->
      update_message state id (fun message -> { message with mailbox = Archived })
      |> fun state -> clear_expansion_if state id)
  in
  let trash =
    swipe_action "mail-swipe-trash" (fun state id ->
      update_message state id (fun message -> { message with mailbox = Trash })
      |> fun state -> clear_expansion_if state id)
  in
  let read =
    swipe_action "mail-swipe-read" (fun state id ->
      update_message state id (fun message -> { message with read = not message.read }))
  in
  let swipe_actions = Bonsai.Cont.both archive (Bonsai.Cont.both trash read) in
  let events =
    Bonsai.Cont.map2
      (Bonsai.Cont.map2
         (Bonsai.Cont.both toggle_star expand)
         (Bonsai.Cont.both collapse reply)
         ~f:(fun (toggle_star, expand) (collapse, reply) ->
           toggle_star, expand, collapse, reply))
      (Bonsai.Cont.both open_message swipe_actions)
      ~f:(fun (toggle_star, expand, collapse, reply) (open_message, swipe_actions) ->
        toggle_star, expand, collapse, reply, open_message, swipe_actions)
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both row_data large_text)
    events
    ~f:
      (fun
        ((message, expanded, notice), large_text)
        (toggle_star, expand, collapse, reply, open_message, swipe_actions)
      ->
      render_mail_row
        ~large_text
        ~toggle_star
        ~expand
        ~collapse
        ~reply
        ~open_message
        ~swipe_actions
        ~expanded
        ~notice
        message)
;;

let messages_for_destination state = List.filter (message_is_visible state) state.messages

let expanded_extent_override state =
  match state.expanded_id with
  | None -> []
  | Some expanded_id ->
    let rec find index = function
      | [] -> []
      | message :: tail ->
        if Int.equal message.id expanded_id
        then (
          let override : Ui.View.Collection.extent =
            { index
            ; extent =
                expanded_mail_extent
                  message
                  ~has_notice:(Option.is_some state.card_notice)
            }
          in
          [ override ])
        else find (index + 1) tail
    in
    find 0 (messages_for_destination state)
;;

let mail_destination_title = function
  | Inbox_view -> "Inbox"
  | Starred_view -> "Starred"
  | Archived_view -> "Archived"
  | Trash_view -> "Trash"
  | Settings_view -> "Settings"
;;

let placeholder destination =
  let verb = if String.equal destination "Settings" then "are" else "is" in
  Ui.View.frame
    ~max_width:Ui.Layout.Frame_limit.Fill
    ~max_height:Ui.Layout.Frame_limit.Fill
    (padding
       ~horizontal:24.
       (styled_text
          ~size:17.
          ~color:text_secondary
          (Printf.sprintf
             "%s %s outside the scope of this local mail demo."
             destination
             verb)
        |> Ui.View.semantics
             ~properties:(Ui.Semantics.create ~label:(destination ^ " placeholder") ())))
;;

let loading_more_row =
  Ui.View.frame
    ~height:88.
    (Ui.View.frame
       ~max_width:Ui.Layout.Frame_limit.Fill
       ~max_height:Ui.Layout.Frame_limit.Fill
       (Ui.View.progress ~style:Ui.View.Progress_style.Circular ()
        |> Ui.View.frame ~width:24. ~height:24.))
  |> Ui.View.with_test_id (Ui.Test_id.string "mail-loading-more")
  |> Ui.View.semantics
       ~properties:
         (Ui.Semantics.create ~label:"Loading more messages" ~live_region:true ())
  |> Ui.View.Keyed.create ~key:(Ui.Key.string "mail-loading-more")
;;

let has_loading_row state =
  match state.load_state, state.selected_mail_destination with
  | Loading_more _, Inbox_view -> true
  | Idle, Inbox_view -> false
  | (Idle | Loading_more _), (Starred_view | Archived_view | Trash_view | Settings_view)
    -> false
;;

let collection_catalog ~large_text state =
  let keys =
    List.map (fun message -> Ui.Key.int message.id) (messages_for_destination state)
    @ if has_loading_row state then [ Ui.Key.string "mail-loading-more" ] else []
  in
  Ui.View.Collection.Catalog.create
    ~keys
    ~default_extent:compact_mail_extent
    ~sizing:
      (Ui.View.Collection.Measured
         { revision =
             Int64.logor
               (Int64.shift_left state.layout_revision 1)
               (if large_text then 1L else 0L)
         })
    ~overrides:(expanded_extent_override state)
    ~overscan:4
    ~expand_duration_ms:240
    ~collapse_duration_ms:190
    ()
;;

let materialized_window state ~catalog =
  let total_count = Ui.View.Collection.Catalog.count catalog in
  let visible_last_exclusive = min state.painted_last_exclusive total_count in
  let visible_first_index = min state.painted_first_index visible_last_exclusive in
  Ui.View.Collection.Window.create ~catalog ~visible_first_index ~visible_last_exclusive
;;

let render_mail_body ~state ~catalog ~rows ~open_menu ~on_visible_range =
  match state.selected_mail_destination with
  | Settings_view -> Ui.View.Body.static (placeholder "Settings")
  | (Inbox_view | Starred_view | Archived_view | Trash_view) as destination ->
    let rows =
      match rows with
      | `Ok rows -> rows
      | `Duplicate_key message_id ->
        invalid_arg (Printf.sprintf "Mail: duplicate message ID %d" message_id)
    in
    let has_loading_row = has_loading_row state in
    let message_count =
      Ui.View.Collection.Catalog.count catalog - if has_loading_row then 1 else 0
    in
    let window = materialized_window state ~catalog in
    let rows =
      if has_loading_row && window.last_exclusive > message_count
      then rows @ [ loading_more_row ]
      else rows
    in
    let list =
      Ui.View.Collection.vertical
        ~key:(Ui.Key.string ("mail-collection-" ^ mail_destination_title destination))
        ~catalog
        ~first_index:window.first_index
        ~items:rows
        ~on_visible_range
        ()
      |> Ui.View.Viewport.Vertical.with_test_id (Ui.Test_id.string "mail-virtual-list")
      |> Ui.View.Viewport.Vertical.background ~color:surface ~corner_radius:26.
    in
    let title = mail_destination_title destination in
    Ui.View.Body.Vertical.create
      [ Ui.View.Body.Vertical.fixed
          (padding ~horizontal:16. ~vertical:10. (search_header open_menu))
      ; Ui.View.Body.Vertical.fixed
          (padding
             ~horizontal:20.
             ~vertical:8.
             (styled_text
                ~size:15.
                ~weight:Ui.Style.Font_weight.Semi_bold
                ~color:text_primary
                title
              |> Ui.View.semantics
                   ~properties:
                     (Ui.Semantics.create
                        ~label:title
                        ~role:Ui.Semantics.Role.Header
                        ~heading_level:1
                        ())))
      ; Ui.View.Body.Vertical.fill list
      ]
;;

let drawer_item ~test_id ~label ~selected ~on_press ~name =
  Ui.View.button
    ~style:Ui.View.Button_style.Plain
    ~on_press
    ~child:
      (Ui.View.Weighted.row
         [ Ui.View.Weighted.fixed (icon ~size:21. ~color:primary name)
         ; Ui.View.Weighted.share
             (padding
                ~horizontal:16.
                (styled_text
                   ~size:15.
                   ~weight:
                     (if selected
                      then Ui.Style.Font_weight.Semi_bold
                      else Ui.Style.Font_weight.Normal)
                   ~color:text_primary
                   label))
         ])
    ()
  |> Ui.View.with_test_id (Ui.Test_id.string test_id)
  |> Ui.View.semantics
       ~properties:
         (Ui.Semantics.create ~label ~role:Ui.Semantics.Role.Button ~selected ())
;;

let render_drawer state ~inbox ~starred ~archived ~trash ~settings =
  let item destination test_id label handler name =
    drawer_item
      ~test_id
      ~label
      ~selected:(state.selected_mail_destination = destination)
      ~on_press:handler
      ~name
  in
  Ui.View.column
    [ padding
        ~horizontal:20.
        ~vertical:20.
        (Ui.View.column
           [ styled_text
               ~size:22.
               ~weight:Ui.Style.Font_weight.Semi_bold
               ~color:primary
               "Bonsai Mail"
           ; styled_text ~size:13. ~color:text_secondary "BM • local@example.test"
           ])
    ; item Inbox_view "mail-drawer-inbox" "Inbox" inbox "tray"
    ; item Starred_view "mail-drawer-starred" "Starred" starred "star.fill"
    ; item Archived_view "mail-drawer-archived" "Archived" archived "archivebox"
    ; item Trash_view "mail-drawer-trash" "Trash" trash "trash"
    ; item Settings_view "mail-drawer-settings" "Settings" settings "gearshape"
    ]
;;

let toolbar_action ~test_id ~label ~on_press name =
  semantic_icon_button
    ~test_id
    ~label
    ~selected:false
    ~on_press
    ~name
    ~color:text_secondary
;;

let reply_action on_press ~test_id ~label name =
  Ui.View.button
    ~style:Ui.View.Button_style.Plain
    ~on_press
    ~child:
      (Ui.View.Weighted.row
         [ Ui.View.Weighted.fixed (icon ~size:18. ~color:primary name)
         ; Ui.View.Weighted.share
             (padding
                ~horizontal:4.
                (styled_text
                   ~size:13.
                   ~weight:Ui.Style.Font_weight.Medium
                   ~color:primary
                   ~line_limit:1
                   ~truncation:Tail
                   label))
         ])
    ()
  |> Ui.View.with_test_id (Ui.Test_id.string test_id)
  |> Ui.View.semantics
       ~properties:(Ui.Semantics.create ~label ~role:Ui.Semantics.Role.Button ())
;;

let render_detail_page
      ~back
      ~archive
      ~delete
      ~mark_unread
      ~toggle_star
      ~reply
      ~notice
      message
  =
  let toolbar =
    Ui.View.row
      [ toolbar_action ~test_id:"mail-back" ~label:"Back" ~on_press:back "arrow.left"
      ; Ui.View.Weighted.row
          [ Ui.View.Weighted.fixed
              (toolbar_action
                 ~test_id:"mail-archive"
                 ~label:"Archive"
                 ~on_press:archive
                 "archivebox")
          ; Ui.View.Weighted.fixed
              (toolbar_action
                 ~test_id:"mail-delete"
                 ~label:"Delete"
                 ~on_press:delete
                 "trash")
          ; Ui.View.Weighted.fixed
              (toolbar_action
                 ~test_id:"mail-mark-unread"
                 ~label:"Mark unread"
                 ~on_press:mark_unread
                 "envelope")
          ]
      ]
  in
  let subject =
    Ui.View.Weighted.row
      [ Ui.View.Weighted.share
          (styled_text
             ~size:23.
             ~weight:Ui.Style.Font_weight.Medium
             ~spacing:6.
             ~color:text_primary
             ~line_limit:2
             ~truncation:Tail
             message.subject
           |> Ui.View.semantics
                ~properties:
                  (Ui.Semantics.create
                     ~label:message.subject
                     ~role:Ui.Semantics.Role.Header
                     ~heading_level:1
                     ()))
      ; Ui.View.Weighted.fixed (star_control toggle_star message ~detail:true)
      ]
  in
  let sender =
    Ui.View.Weighted.row
      [ Ui.View.Weighted.fixed (avatar message)
      ; Ui.View.Weighted.share
          (padding
             ~horizontal:12.
             (Ui.View.column
                [ styled_text
                    ~size:15.
                    ~weight:Ui.Style.Font_weight.Semi_bold
                    ~color:text_primary
                    message.sender
                ; styled_text ~size:12. ~color:text_secondary message.address
                ; styled_text ~size:12. ~color:text_secondary "to me"
                ]))
      ; Ui.View.Weighted.fixed
          (styled_text ~size:12. ~color:text_secondary message.timestamp)
      ]
    |> Ui.View.with_test_id (Ui.Test_id.string "mail-sender-header")
  in
  let body =
    styled_text ~size:15.5 ~spacing:8. ~color:text_primary message.body
    |> Ui.View.with_test_id (Ui.Test_id.string "mail-body")
  in
  let attachment =
    Option.map
      (fun attachment ->
         Ui.View.background
           ~color:primary_container
           ~corner_radius:16.
           (padding
              ~horizontal:14.
              ~vertical:12.
              (Ui.View.Weighted.row
                 [ Ui.View.Weighted.fixed (icon ~size:24. ~color:primary "paperclip")
                 ; Ui.View.Weighted.share
                     (padding
                        ~horizontal:12.
                        (Ui.View.column
                           [ styled_text
                               ~size:13.5
                               ~weight:Ui.Style.Font_weight.Medium
                               ~color:text_primary
                               attachment.name
                           ; styled_text
                               ~size:12.
                               ~color:text_secondary
                               (attachment.kind ^ " • " ^ attachment.size)
                           ]))
                 ]))
         |> Ui.View.with_test_id (Ui.Test_id.string "mail-attachment")
         |> Ui.View.semantics
              ~properties:
                (Ui.Semantics.create
                   ~label:
                     (Printf.sprintf
                        "Attachment %s, %s, %s"
                        attachment.name
                        attachment.kind
                        attachment.size)
                   ()))
      message.attachment
  in
  let notice =
    Option.map
      (fun notice ->
         Ui.View.background
           ~color:primary_container
           ~corner_radius:16.
           (padding
              ~horizontal:14.
              ~vertical:12.
              (styled_text ~size:13. ~color:primary notice))
         |> Ui.View.with_test_id (Ui.Test_id.string "mail-inline-notice")
         |> Ui.View.semantics
              ~properties:(Ui.Semantics.create ~label:notice ~live_region:true ()))
      notice
  in
  let replies =
    Ui.View.Weighted.row
      [ Ui.View.Weighted.share
          (reply_action
             reply
             ~test_id:"mail-reply"
             ~label:"Reply"
             "arrowshape.turn.up.left")
      ; Ui.View.Weighted.share
          (reply_action
             reply
             ~test_id:"mail-reply-all"
             ~label:"Reply all"
             "arrowshape.turn.up.left.2")
      ; Ui.View.Weighted.share
          (reply_action
             reply
             ~test_id:"mail-forward"
             ~label:"Forward"
             "arrowshape.turn.up.right")
      ]
  in
  let blocks =
    [ Some (padding ~horizontal:20. ~vertical:12. subject)
    ; Some (padding ~horizontal:20. ~vertical:12. sender)
    ; Some
        (Ui.View.background
           ~color:surface
           ~corner_radius:20.
           (padding ~horizontal:20. ~vertical:20. body))
    ; Option.map (padding ~horizontal:20. ~vertical:10.) attachment
    ; Option.map (padding ~horizontal:20. ~vertical:10.) notice
    ; Some (padding ~horizontal:12. ~vertical:16. replies)
    ]
    |> List.filter_map Fun.id
  in
  Ui.View.Body.Vertical.create
    ~key:(Ui.Key.string (Printf.sprintf "mail-detail-%d" message.id))
    [ Ui.View.Body.Vertical.fixed toolbar
    ; Ui.View.Body.Vertical.fill (Ui.View.Scroll.vertical (Ui.View.column blocks))
    ]
  |> Ui.View.Body.background ~color:background
  |> Ui.View.Body.with_test_id (Ui.Test_id.string "mail-detail-page")
;;

let detail_page handlers set_state message_id detail _graph =
  let dependencies = Bonsai.Cont.both set_state message_id in
  let equal_dependencies (left_set_state, left_id) (right_set_state, right_id) =
    left_set_state == right_set_state && Int.equal left_id right_id
  in
  let back =
    Driver.Handler.create
      handlers
      ~name:"mail-back"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state ->
          { state with
            selected_id = None
          ; notice = None
          ; compact_column = Ui.Navigation.Split_column.Content
          }))
  in
  let close ?(clear_card = false) name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update state message_id
          |> fun state ->
          let state = if clear_card then clear_expansion_if state message_id else state in
          { state with
            selected_id = None
          ; notice = None
          ; compact_column = Ui.Navigation.Split_column.Content
          }))
  in
  let archive =
    close ~clear_card:true "mail-archive" (fun state message_id ->
      update_message state message_id (fun message -> { message with mailbox = Archived }))
  in
  let delete =
    close ~clear_card:true "mail-delete" (fun state message_id ->
      update_message state message_id (fun message -> { message with mailbox = Trash }))
  in
  let mark_unread =
    close "mail-mark-unread" (fun state message_id ->
      update_message state message_id (fun message -> { message with read = false }))
  in
  let toggle_star =
    Driver.Handler.create
      handlers
      ~name:"mail-toggle-star"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (set_state, message_id) _ ->
        set_state (fun state ->
          update_message state message_id (fun message ->
            { message with starred = not message.starred })
          |> sanitize_expansion))
  in
  let reply =
    Driver.Handler.create
      handlers
      ~name:"mail-reply-scope-notice"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state ->
          { state with notice = Some "Composing is outside the scope of this demo." }))
  in
  let toolbar_handlers =
    Bonsai.Cont.map2
      (Bonsai.Cont.both back archive)
      (Bonsai.Cont.both delete mark_unread)
      ~f:(fun (back, archive) (delete, mark_unread) -> back, archive, delete, mark_unread)
  in
  let message_actions =
    Bonsai.Cont.map2 toggle_star reply ~f:(fun toggle_star reply -> toggle_star, reply)
  in
  let page_events =
    Bonsai.Cont.map2
      toolbar_handlers
      message_actions
      ~f:(fun (back, archive, delete, mark_unread) (toggle_star, reply) ->
        back, archive, delete, mark_unread, toggle_star, reply)
  in
  Bonsai.Cont.map2
    detail
    page_events
    ~f:(fun (message, notice) (back, archive, delete, mark_unread, toggle_star, reply) ->
      render_detail_page
        ~back
        ~archive
        ~delete
        ~mark_unread
        ~toggle_star
        ~reply
        ~notice
        message)
;;

let rec drop count values =
  if count <= 0
  then values
  else (
    match values with
    | [] -> []
    | _ :: tail -> drop (count - 1) tail)
;;

let rec take count values =
  if count <= 0
  then []
  else (
    match values with
    | [] -> []
    | head :: tail -> head :: take (count - 1) tail)
;;

let window_messages state ~catalog =
  let messages = messages_for_destination state in
  let message_count = List.length messages in
  let window = materialized_window state ~catalog in
  messages
  |> drop window.first_index
  |> take (min message_count window.last_exclusive - window.first_index)
;;

let app_destination_key = function
  | Mail -> "mail"
  | Chat -> "chat"
  | Spaces -> "spaces"
  | Meet -> "meet"
;;

let split_state state =
  Ui.Navigation.Split_state.create
    ~visibility:state.split_visibility
    ~compact_column:state.compact_column
    ?selection_key:
      (Option.map
         (fun id -> ID.Navigation.Page_key.of_string (Printf.sprintf "mail-detail-%d" id))
         state.selected_id)
    ()
;;

let render_mail_page
      state
      rows
      ~catalog
      ~visible_range
      ~open_menu
      ~split_changed
      ~tab_changed
      ~inbox
      ~starred
      ~archived
      ~trash
      ~settings
      ~detail
  =
  let mail_body =
    render_mail_body ~state ~catalog ~rows ~open_menu ~on_visible_range:visible_range
    |> Ui.View.Body.background ~color:background
    |> Ui.View.Body.with_test_id (Ui.Test_id.string "mail-list-page")
  in
  let sidebar =
    render_drawer state ~inbox ~starred ~archived ~trash ~settings
    |> Ui.View.Scroll.vertical
    |> fun viewport ->
    Ui.View.Body.Vertical.create [ Ui.View.Body.Vertical.fill viewport ]
  in
  let split =
    Ui.View.Navigation_split.create
      ~key:(Ui.Key.string "mail-navigation-split")
      ~state:(split_state state)
      ~sidebar_title:"Mailboxes"
      ~content_title:(mail_destination_title state.selected_mail_destination)
      ~detail_title:"Message"
      ~on_change:split_changed
      ~sidebar
      ~content:mail_body
      ~detail
      ()
    |> Ui.View.with_test_id (Ui.Test_id.string "mail-navigation-split")
  in
  let item destination title symbol body =
    Ui.View.Tabs.item
      ~page_key:(ID.Navigation.Page_key.of_string (app_destination_key destination))
      ~title
      ~symbol
      body
  in
  Ui.View.Tabs.create
    ~key:(Ui.Key.string "mail-tabs")
    ~selection:
      (ID.Navigation.Page_key.of_string
         (app_destination_key state.selected_app_destination))
    ~on_change:tab_changed
    [ item Mail "Mail" "tray" (Ui.View.Body.static split)
    ; item
        Chat
        "Chat"
        "bubble.left.and.bubble.right"
        (Ui.View.Body.static (placeholder "Chat"))
    ; item Spaces "Spaces" "person.3" (Ui.View.Body.static (placeholder "Spaces"))
    ; item Meet "Meet" "video" (Ui.View.Body.static (placeholder "Meet"))
    ]
  |> Ui.View.with_test_id (Ui.Test_id.string "mail-tabs")
  |> Ui.View.frame
       ~max_width:Ui.Layout.Frame_limit.Fill
       ~max_height:Ui.Layout.Frame_limit.Fill
;;

let component handlers graph =
  let large_text =
    App.Context.environment handlers
    |> Bonsai.Cont.map ~f:(fun environment -> environment.Environment.text_scale >= 1.5)
    |> Bonsai.Cont.cutoff ~equal:Bool.equal
  in
  let state, set_state = Bonsai_v017.state ~equal:equal_state initial graph in
  let set_state =
    Bonsai.Cont.map set_state ~f:(fun set_state update ->
      set_state (fun state ->
        let next = update state in
        if
          next.messages == state.messages
          && next.expanded_id = state.expanded_id
          && next.card_notice = state.card_notice
        then next
        else
          { next with
            layout_revision =
              (if state.layout_revision = Int64.shift_right_logical Int64.max_int 1
               then 0L
               else Int64.succ state.layout_revision)
          }))
  in
  let sleep = Bonsai.Cont.Clock.sleep graph in
  let catalog =
    state
    |> Bonsai.Cont.cutoff ~equal:(fun left right ->
      left.messages == right.messages
      && left.selected_mail_destination = right.selected_mail_destination
      && left.expanded_id = right.expanded_id
      && left.card_notice = right.card_notice
      && has_loading_row left = has_loading_row right)
    |> fun state ->
    Bonsai.Cont.map2 state large_text ~f:(fun state large_text ->
      collection_catalog ~large_text state)
  in
  let visible_messages =
    Bonsai.Cont.map2 state catalog ~f:(fun state catalog ->
      window_messages state ~catalog
      |> List.map (fun message ->
        let expanded = state.expanded_id = Some message.id in
        message, expanded, if expanded then state.card_notice else None))
  in
  let rows =
    Bonsai.Cont.assoc_list
      (module Core.Int)
      visible_messages
      ~get_key:(fun (message, _, _) -> message.id)
      ~f:(mail_row handlers set_state large_text)
      graph
  in
  let visible_range_dependencies =
    Bonsai.Cont.map2
      state
      (Bonsai.Cont.both set_state sleep)
      ~f:(fun state (set_state, sleep) -> state, set_state, sleep)
  in
  let visible_range =
    Driver.Handler.create
      handlers
      ~name:"mail-visible-range"
      ~equal:(fun (left, left_set, left_sleep) (right, right_set, right_sleep) ->
        equal_state left right && left_set == right_set && left_sleep == right_sleep)
      visible_range_dependencies
      ~f:(fun (snapshot, set_state, sleep) payload ->
        match Ui.View.Collection.visible_range_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some { first_index; last_exclusive } ->
          let count = List.length (messages_for_destination snapshot) in
          let bounded value = Int64.to_int (Int64.min value (Int64.of_int count)) in
          let first_index = bounded first_index in
          let last_exclusive = bounded last_exclusive in
          let should_load =
            snapshot.selected_mail_destination = Inbox_view
            && snapshot.load_state = Idle
            && last_exclusive >= max 0 (count - 8)
          in
          if should_load
          then (
            let generation = snapshot.next_generation in
            let cursor = snapshot.next_cursor in
            Bonsai.Effect.Many
              [ set_state (fun state ->
                  if
                    state.load_state = Idle
                    && state.selected_mail_destination = Inbox_view
                    && Int.equal state.next_cursor cursor
                  then
                    { state with
                      painted_first_index = first_index
                    ; painted_last_exclusive = last_exclusive
                    ; load_state = Loading_more { generation; cursor }
                    ; next_generation = generation + 1
                    }
                  else state)
              ; Bonsai.Effect.bind
                  (sleep (Core.Time_ns.Span.of_ms 750.))
                  ~f:(fun () ->
                    set_state (fun state ->
                      match state.load_state with
                      | Loading_more loading
                        when Int.equal loading.generation generation
                             && Int.equal loading.cursor cursor ->
                        { state with
                          messages = state.messages @ messages_for_cursor cursor
                        ; next_cursor = cursor + 1
                        ; load_state = Idle
                        }
                      | Idle | Loading_more _ -> state))
              ])
          else
            set_state (fun state ->
              { state with
                painted_first_index = first_index
              ; painted_last_exclusive = last_exclusive
              }))
  in
  let open_menu =
    Driver.Handler.create
      handlers
      ~name:"mail-open-sidebar"
      ~equal:( == )
      set_state
      ~f:(fun set_state _ ->
        set_state (fun state ->
          if state.selected_app_destination = Mail
          then
            { state with
              split_visibility = Ui.Navigation.Split_visibility.All
            ; compact_column = Ui.Navigation.Split_column.Sidebar
            }
          else state))
  in
  let split_changed =
    Driver.Handler.create
      handlers
      ~name:"mail-split-changed"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Navigation_split_changed requested ->
        set_state (fun state ->
          let module Split = Ui.Navigation.Split_state in
          if
            not
              (Option.equal
                 ID.Navigation.Page_key.equal
                 (Split.selection_key requested)
                 (Split.selection_key (split_state state)))
          then state
          else (
            let compact_column = Split.compact_column requested in
            let returned =
              state.compact_column = Ui.Navigation.Split_column.Detail
              && compact_column <> Ui.Navigation.Split_column.Detail
            in
            { state with
              split_visibility = Split.visibility requested
            ; compact_column
            ; selected_id = (if returned then None else state.selected_id)
            ; notice = (if returned then None else state.notice)
            }))
      | _ -> Bonsai.Effect.Ignore)
  in
  let mailbox_handler name destination =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state (fun state ->
        let next_generation, load_state =
          match state.load_state with
          | Idle -> state.next_generation, Idle
          | Loading_more _ -> state.next_generation + 1, Idle
        in
        { state with
          selected_mail_destination = destination
        ; selected_id = None
        ; notice = None
        ; compact_column = Ui.Navigation.Split_column.Content
        ; expanded_id = None
        ; card_notice = None
        ; painted_first_index = 0
        ; painted_last_exclusive = 20
        ; next_generation
        ; load_state
        }))
  in
  let inbox = mailbox_handler "mail-drawer-inbox" Inbox_view in
  let starred = mailbox_handler "mail-drawer-starred" Starred_view in
  let archived = mailbox_handler "mail-drawer-archived" Archived_view in
  let trash = mailbox_handler "mail-drawer-trash" Trash_view in
  let settings = mailbox_handler "mail-drawer-settings" Settings_view in
  let tab_changed =
    Driver.Handler.create
      handlers
      ~name:"mail-tab-changed"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Tab_selected key ->
        let destination =
          match ID.Navigation.Page_key.to_string key with
          | "mail" -> Some Mail
          | "chat" -> Some Chat
          | "spaces" -> Some Spaces
          | "meet" -> Some Meet
          | _ -> None
        in
        (match destination with
         | None -> Bonsai.Effect.Ignore
         | Some destination ->
           set_state (fun state -> { state with selected_app_destination = destination }))
      | _ -> Bonsai.Effect.Ignore)
  in
  let mailbox_handlers =
    Bonsai.Cont.map2
      (Bonsai.Cont.both inbox starred)
      (Bonsai.Cont.map2
         (Bonsai.Cont.both archived trash)
         settings
         ~f:(fun (archived, trash) settings -> archived, trash, settings))
      ~f:(fun (inbox, starred) (archived, trash, settings) ->
        inbox, starred, archived, trash, settings)
  in
  let shell_handlers =
    Bonsai.Cont.both
      (Bonsai.Cont.both open_menu split_changed)
      (Bonsai.Cont.both tab_changed mailbox_handlers)
  in
  let selected_details =
    Bonsai.Cont.map state ~f:(fun state ->
      match state.selected_id with
      | None -> []
      | Some message_id ->
        (match find_message state.messages message_id with
         | None -> []
         | Some message -> [ message, state.notice ]))
  in
  let detail_pages =
    Bonsai.Cont.assoc_list
      (module Core.Int)
      selected_details
      ~get_key:(fun (message, _) -> message.id)
      ~f:(detail_page handlers set_state)
      graph
  in
  let detail =
    Bonsai.Cont.map detail_pages ~f:(function
      | `Ok [ detail ] -> detail
      | `Ok [] ->
        Ui.View.Body.static
          (Ui.View.column
             [ icon ~size:40. ~color:text_secondary "envelope.open"
             ; styled_text ~size:20. ~color:text_secondary "Select a message"
             ]
           |> Ui.View.frame
                ~max_width:Ui.Layout.Frame_limit.Fill
                ~max_height:Ui.Layout.Frame_limit.Fill
           |> Ui.View.with_test_id (Ui.Test_id.string "mail-detail-placeholder"))
      | `Ok _ -> invalid_arg "Mail: multiple selected details"
      | `Duplicate_key id ->
        invalid_arg (Printf.sprintf "Mail: duplicate selected message ID %d" id))
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both (Bonsai.Cont.both state catalog) rows)
    (Bonsai.Cont.both detail (Bonsai.Cont.both visible_range shell_handlers))
    ~f:
      (fun
        ((state, catalog), rows)
        ( detail
        , ( visible_range
          , ( (open_menu, split_changed)
            , (tab_changed, (inbox, starred, archived, trash, settings)) ) ) ) ->
      render_mail_page
        state
        rows
        ~catalog
        ~visible_range
        ~open_menu
        ~split_changed
        ~tab_changed
        ~inbox
        ~starred
        ~archived
        ~trash
        ~settings
        ~detail)
;;

let application_theme = Ui.Theme.create ~mode:Light ~tint:primary ()

let application_component handlers graph =
  Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body:(Ui.View.Body.static body))
;;

let app = App.create ~name:"Bonsai Mail" application_component

module For_testing = struct
  let initial_inbox_ids = List.map (fun message -> message.id) initial_messages
end
