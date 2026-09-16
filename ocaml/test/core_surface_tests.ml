module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let check condition message = if not condition then failwith message
let handler = Ui.Event.Handler.create (fun _ -> ())
let child = Ui.View.text "child"

let widgets =
  [ Ui.View.badge ~count:3 child
  ; Ui.View.label ~title:(Ui.View.text "Inbox") ~icon:child ()
  ; Ui.View.rich_text (List.map Ui.Style.Text_span.create [ "Hello"; " world" ])
  ; Ui.View.symbol
      ~size:20.
      ~color:(Ui.Style.Color.rgb ~red:10 ~green:20 ~blue:30)
      ~name:"plus"
      ()
  ; Ui.View.image
      ~sizing:Ui.Style.Image_sizing.Fit
      ~source:(Ui.Style.Image_source.remote "https://example.invalid/image.png")
      ()
  ; Ui.View.frame
      ~max_width:Ui.Layout.Frame_limit.Fill
      ~max_height:Ui.Layout.Frame_limit.Fill
      ~alignment:Ui.Layout.Alignment.Bottom_end
      child
  ; Ui.View.frame ~width:100. ~height:40. child
  ; Ui.View.frame
      ~min_width:10.
      ~max_width:(Ui.Layout.Frame_limit.Points 100.)
      ~min_height:20.
      ~max_height:(Ui.Layout.Frame_limit.Points 200.)
      child
  ; Ui.View.background
      ~color:(Ui.Style.Color.rgb ~red:40 ~green:50 ~blue:60)
      ~corner_radius:8.
      child
  ; Ui.View.clip child
  ; Ui.View.opacity 0.5 child
  ; Ui.View.animated_opacity
      ~animation:
        (Ui.Animation.create ~id:(ID.Ui.Animation_id.of_int64 7L) ~duration_ms:250 ())
      ~opacity:0.75
      ~on_completed:handler
      child
  ; Ui.View.projection_effect ~transform:(Ui.Style.Projection.scale ~x:2. ~y:3. ()) child
  ; Ui.View.Scroll.vertical ~on_scroll:handler (Ui.View.column [ child ])
    |> Ui.View.Viewport.Vertical.with_height ~height:120.
  ; Ui.View.ignores_safe_area child
  ; Ui.View.safe_area_padding ~insets:(Ui.Layout.Edge_insets.all 4.) child
  ; Ui.View.gesture ~on_tap:handler ~on_double_tap:handler ~on_long_press:handler child
  ; Ui.View.focus_scope ~autofocus:true ~on_focus_changed:handler child
  ; Ui.View.hover_region ~on_enter:handler ~on_leave:handler child
  ; Ui.View.keyboard_listener
      ~autofocus:true
      ~key_policy:Ui.Event.Key_policy.Handled
      ~on_key:handler
      child
  ]
;;

let expected =
  [ "Badge"
  ; "Label"
  ; "Rich_text"
  ; "Symbol"
  ; "Image"
  ; "Frame"
  ; "Frame"
  ; "Frame"
  ; "Background"
  ; "Clip"
  ; "Opacity"
  ; "Animated_opacity"
  ; "Projection_effect"
  ; "Frame"
  ; "Ignores_safe_area"
  ; "Safe_area_padding"
  ; "Gesture"
  ; "Focus_scope"
  ; "Hover_region"
  ; "Keyboard_listener"
  ]
;;

let test_core_constructors () =
  let actual = List.map Ui.View.For_testing.kind_name widgets in
  check (actual = expected) "core constructors produced incorrect logical kinds"
;;

let test_overlay_constructor () =
  let overlay =
    Ui.View.overlay
      ~alignment:Ui.Layout.Alignment.Center
      ~overlay:(Ui.View.text "Overlay content")
      (Ui.View.text "Base content")
  in
  check
    (String.equal (Ui.View.For_testing.kind_name overlay) "Overlay")
    "overlay kind is not typed"
;;

let test_debug_tree () =
  let tree =
    Ui.View.column
      ~key:(Ui.Key.string "main")
      [ Ui.View.text "Count: 0"
      ; Ui.View.button
          ~on_press:(Ui.Event.Handler.create (fun _ -> ()))
          ~child:(Ui.View.text "Increment")
          ()
      ]
  in
  check
    (String.equal
       (Ui.Debug.dump_tree tree)
       "Column key=\"main\"\n\
       \  Text \"Count: 0\"\n\
       \  Button events=[press]\n\
       \    Text \"Increment\"")
    "debug tree is not deterministic"
;;

let test_semantics_properties () =
  let semantics =
    Ui.Semantics.create
      ~label:"Accept terms"
      ~hint:"Double tap to toggle"
      ~value:"Not accepted"
      ~role:Ui.Semantics.Role.Toggle
      ~selected:false
      ~live_region:true
      ~heading_level:2
      ~sort_priority:3.5
      ~actions:[ Ui.Semantics.Action.create ~id:41L ~label:"Archive" ]
      ()
  in
  let view = Ui.Semantics.Private.view semantics in
  check
    (view.role = Ui.Semantics.Role.Toggle
     && view.heading_level = Some 2
     && List.map Ui.Semantics.Action.id view.actions = [ 41L ])
    "semantics properties were not preserved"
;;

let test_styled_text_constructor_and_validation () =
  let color = Ui.Style.Color.rgb ~red:24 ~green:55 ~blue:88 in
  let style =
    Ui.Style.Text_style.create
      ~font_size:16.
      ~font_weight:Ui.Style.Font_weight.Semi_bold
      ~line_spacing:6.
      ~color
      ()
  in
  let text =
    Ui.View.text
      ~style
      ~text_align:Ui.Style.Text_align.End
      ~line_limit:2
      ~truncation:Ui.Style.Text_truncation.Tail
      "A long subject"
  in
  (let (Av view) = Ui.View.Private.view text in
   match view.node with
   | Text
       { value
       ; style =
           Some
             { font_size = Some font_size
             ; font_weight = Some Semi_bold
             ; line_spacing = Some line_spacing
             ; color = Some encoded_color
             ; role = 8
             ; foreground = None
             ; italic = None
             }
       ; text_align = End
       ; line_limit = Some line_limit
       ; truncation = Tail
       } ->
     check (String.equal value "A long subject") "styled text lost its value";
     check (Float.equal font_size 16.) "styled text lost its font size";
     check (Float.equal line_spacing 6.) "styled text lost its line spacing";
     check (Int32.equal encoded_color 0xff183758l) "styled text lost its color";
     check (Int.equal line_limit 2) "styled text lost its line limit"
   | _ -> failwith "styled text properties were not preserved");
  let expect_invalid create message =
    match create () with
    | exception Invalid_argument _ -> ()
    | _ -> failwith message
  in
  expect_invalid
    (fun () -> Ui.Style.Text_style.create ~font_size:0. ())
    "zero font size was accepted";
  List.iter
    (fun line_spacing ->
       let style = Ui.Style.Text_style.create ~line_spacing () in
       check
         ((Ui.Style.Text_style.Private.view style).line_spacing = Some line_spacing)
         "line spacing points changed")
    [ 0.; 6. ];
  List.iter
    (fun line_spacing ->
       expect_invalid
         (fun () -> Ui.Style.Text_style.create ~line_spacing ())
         "invalid line spacing was accepted")
    [ -1.; nan; infinity; neg_infinity ];
  expect_invalid
    (fun () -> Ui.View.text ~line_limit:0 "Invalid")
    "zero maximum lines was accepted"
;;

let expect_invalid create message =
  match create () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith message
;;

let test_typed_viewport_body_encoding () =
  let viewport = Ui.View.Scroll.vertical ~on_scroll:handler (Ui.View.text "Row") in
  let body =
    Ui.View.Body.Vertical.create
      [ Ui.View.Body.Vertical.fixed (Ui.View.text "Search")
      ; Ui.View.Body.Vertical.fill ~weight:2. viewport
      ]
  in
  let bounded = Ui.View.Body.with_size ~width:480. ~height:400. body in
  let column = (Ui.View.For_testing.children bounded).(0) in
  check
    (String.equal (Ui.View.For_testing.kind_name column) "Weighted_column")
    "vertical body did not encode as a weighted column";
  let (Av column_view) = Ui.View.Private.view column in
  let children = column_view.children in
  check (Array.length children = 2) "vertical body lost a child";
  (match column_view.node with
   | Ui.View.Private.Weighted_column
       { items = [ Intrinsic; Share { weight = 2.; fills = true } ]; _ } -> ()
   | _ -> failwith "vertical body encoded incorrect weighted allocation");
  let overlay =
    Ui.View.Body.overlay
      ~alignment:Bottom_end
      ~overlay:
        (Ui.View.text "Capture"
         |> Ui.View.padding
              ~insets:(Ui.Layout.Edge_insets.only ~trailing:16. ~bottom:16. ()))
      body
  in
  let bounded_overlay = Ui.View.Body.with_size ~width:480. ~height:400. overlay in
  let overlay = (Ui.View.For_testing.children bounded_overlay).(0) in
  check
    (String.equal (Ui.View.For_testing.kind_name overlay) "Overlay")
    "body overlay did not encode as a native overlay";
  let (Av overlay_view) = Ui.View.Private.view overlay in
  (match overlay_view.node with
   | Ui.View.Private.Overlay { alignment = Bottom_end } -> ()
   | _ -> failwith "body overlay lost its alignment");
  check (Array.length overlay_view.children = 2) "overlay lost its base or content";
  check
    (String.equal
       (Ui.View.For_testing.kind_name overlay_view.children.(0))
       "Weighted_column")
    "overlay lost its typed base";
  check
    (String.equal (Ui.View.For_testing.kind_name overlay_view.children.(1)) "Padding")
    "overlay lost its directional insets"
;;

let test_viewport_extent_and_body_validation () =
  let vertical = Ui.View.Scroll.vertical ~on_scroll:handler (Ui.View.empty ()) in
  List.iter
    (fun height ->
       expect_invalid
         (fun () -> Ui.View.Viewport.Vertical.with_height ~height vertical)
         "invalid explicit viewport height was accepted")
    [ nan; infinity; neg_infinity; 0.; -1. ];
  let horizontal = Ui.View.Scroll.horizontal ~on_scroll:handler (Ui.View.empty ()) in
  List.iter
    (fun width ->
       expect_invalid
         (fun () -> Ui.View.Viewport.Horizontal.with_width ~width horizontal)
         "invalid explicit viewport width was accepted")
    [ nan; infinity; neg_infinity; 0.; -1. ];
  expect_invalid
    (fun () -> Ui.View.Body.Vertical.fill ~weight:0. vertical)
    "zero body flex was accepted";
  expect_invalid
    (fun () -> Ui.View.Body.Vertical.create [])
    "empty vertical body was accepted";
  expect_invalid
    (fun () -> Ui.View.Body.Horizontal.create [])
    "empty horizontal body was accepted"
;;

let test_swiftui_environment_validation () =
  List.iter
    (fun font_family ->
       expect_invalid
         (fun () -> Ui.Theme.create ~font_family ())
         "SwiftUI environment accepted an empty font family")
    [ ""; "  "; "\t" ];
  ignore
    (Ui.Theme.create
       ~mode:Ui.Theme.Dark
       ~font_family:"Inter"
       ~control_size:Ui.Theme.Control_size.Large
       ())
;;

let test_symbols () =
  List.iter
    (fun rendering ->
       let symbol = Ui.View.symbol ~name:"envelope.fill" ~size:24. ~rendering () in
       check
         (String.equal (Ui.View.For_testing.kind_name symbol) "Symbol")
         "symbol did not produce the native Symbol node")
    Ui.View.Symbol_rendering.[ Monochrome; Hierarchical; Multicolor ];
  ignore (Ui.View.symbol ~name:"star" ());
  List.iter
    (fun name ->
       expect_invalid
         (fun () -> Ui.View.symbol ~name ())
         "symbol accepted an invalid system name")
    [ ""; " "; "star\000fill"; "star fill"; "star\n" ];
  List.iter
    (fun size ->
       expect_invalid
         (fun () -> Ui.View.symbol ~name:"star" ~size ())
         "symbol accepted a non-positive or non-finite size")
    [ 0.; -1.; nan; infinity; neg_infinity ]
;;

let test_frame_constructor () =
  let open Ui.Layout.Frame_limit in
  List.iter
    (fun make ->
       check
         (String.equal (Ui.View.For_testing.kind_name (make ())) "Frame")
         "frame did not produce the native Frame node")
    [ (fun () -> Ui.View.frame child)
    ; (fun () -> Ui.View.frame ~width:0. ~height:20. child)
    ; (fun () ->
        Ui.View.frame ~min_width:10. ~ideal_width:20. ~max_width:(Points 100.) child)
    ; (fun () -> Ui.View.frame ~width:40. ~min_height:0. ~max_height:Fill child)
    ; (fun () ->
        Ui.View.frame ~max_width:Fill ~max_height:Fill ~alignment:Bottom_end child)
    ];
  List.iter
    (fun value ->
       List.iter
         (fun make -> expect_invalid make "frame accepted an invalid dimension")
         [ (fun () -> Ui.View.frame ~width:value child)
         ; (fun () -> Ui.View.frame ~height:value child)
         ; (fun () -> Ui.View.frame ~min_width:value child)
         ; (fun () -> Ui.View.frame ~min_height:value child)
         ; (fun () -> Ui.View.frame ~ideal_width:value child)
         ; (fun () -> Ui.View.frame ~ideal_height:value child)
         ; (fun () -> Ui.View.frame ~max_width:(Points value) child)
         ; (fun () -> Ui.View.frame ~max_height:(Points value) child)
         ])
    [ -1.; nan; infinity; neg_infinity ];
  List.iter
    (fun make -> expect_invalid make "frame accepted conflicting dimensions")
    [ (fun () -> Ui.View.frame ~width:40. ~min_width:0. child)
    ; (fun () -> Ui.View.frame ~width:40. ~ideal_width:40. child)
    ; (fun () -> Ui.View.frame ~width:40. ~max_width:Fill child)
    ; (fun () -> Ui.View.frame ~height:40. ~min_height:0. child)
    ; (fun () -> Ui.View.frame ~height:40. ~ideal_height:40. child)
    ; (fun () -> Ui.View.frame ~height:40. ~max_height:Fill child)
    ; (fun () -> Ui.View.frame ~min_width:20. ~max_width:(Points 10.) child)
    ; (fun () -> Ui.View.frame ~min_height:20. ~max_height:(Points 10.) child)
    ; (fun () -> Ui.View.frame ~min_width:20. ~ideal_width:10. child)
    ; (fun () -> Ui.View.frame ~min_height:20. ~ideal_height:10. child)
    ; (fun () -> Ui.View.frame ~ideal_width:20. ~max_width:(Points 10.) child)
    ; (fun () -> Ui.View.frame ~ideal_height:20. ~max_height:(Points 10.) child)
    ]
;;

let test_spacer_constructor () =
  List.iter
    (fun make ->
       check
         (String.equal (Ui.View.For_testing.kind_name (make ())) "Spacer")
         "spacer did not produce the native Spacer node")
    [ (fun () -> Ui.View.spacer ())
    ; (fun () -> Ui.View.spacer ~min_length:0. ())
    ; (fun () -> Ui.View.spacer ~min_length:24. ())
    ];
  List.iter
    (fun min_length ->
       expect_invalid
         (fun () -> Ui.View.spacer ~min_length ())
         "spacer accepted an invalid minimum")
    [ -1.; nan; infinity; neg_infinity ]
;;

let test_surface_modifiers () =
  let color = Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160 in
  List.iter
    (fun corner_radius ->
       let background = Ui.View.background ~color ~corner_radius child in
       check
         (String.equal (Ui.View.For_testing.kind_name background) "Background")
         "background did not produce the native Background node")
    [ 0.; 12. ];
  List.iter
    (fun corner_radius ->
       expect_invalid
         (fun () -> Ui.View.background ~color ~corner_radius child)
         "background accepted an invalid radius")
    [ -1.; nan; infinity; neg_infinity ];
  List.iter
    (fun opacity ->
       expect_invalid
         (fun () -> Ui.View.opacity opacity child)
         "opacity accepted an invalid value")
    [ -1.; 1.1; nan; infinity; neg_infinity ];
  List.iter
    (fun value ->
       expect_invalid
         (fun () -> Ui.Layout.Edge_insets.all value)
         "padding accepted an invalid inset")
    [ nan; infinity; neg_infinity ]
;;

let test_rich_text_spans () =
  let span =
    Ui.Style.Text_span.create
      ~font_size:20.
      ~font_weight:Bold
      ~color:(Ui.Style.Color.rgb ~red:1 ~green:2 ~blue:3)
      ~italic:true
      ~underline:true
      ~strikethrough:true
      "世界 👩🏽‍💻"
  in
  let (Av view) = Ui.View.Private.view (Ui.View.rich_text [ span ]) in
  (match view.node with
   | Rich_text
       { spans =
           [ { value
             ; font_size = Some 20.
             ; font_weight = Some Bold
             ; color = Some color
             ; italic = Some true
             ; underline = true
             ; strikethrough = true
             }
           ]
       } ->
     check
       (String.equal value "世界 👩🏽‍💻" && Int32.equal color 0xff010203l)
       "rich text lost Unicode content or ARGB color"
   | _ -> failwith "rich text lost run attributes");
  List.iter
    (fun font_size ->
       expect_invalid
         (fun () -> Ui.Style.Text_span.create ~font_size "text")
         "rich text accepted an invalid font size")
    [ 0.; -1.; nan; infinity; neg_infinity ];
  expect_invalid
    (fun () -> Ui.View.rich_text (List.init 65536 (fun _ -> span)))
    "rich text exceeded its wire run limit"
;;

let test_native_image_validation () =
  List.iter
    (fun scale ->
       expect_invalid
         (fun () ->
            Ui.View.image ~scale ~source:(Ui.Style.Image_source.resource "image.png") ())
         "image accepted an invalid scale")
    [ 0.; -1.; nan; infinity; neg_infinity ];
  List.iter
    (fun path ->
       expect_invalid
         (fun () -> Ui.Style.Image_source.resource path)
         "image accepted an invalid resource path")
    [ ""
    ; "/absolute.png"
    ; "../outside.png"
    ; "a/../b.png"
    ; "a//b.png"
    ; "a\\b.png"
    ; "a\000b.png"
    ];
  List.iter
    (fun url ->
       expect_invalid
         (fun () -> Ui.Style.Image_source.remote url)
         "image accepted an invalid remote URL")
    [ ""; "relative.png"; "https://"; "file:///private/image.png"; "https://host/a b" ];
  let (Av view) =
    Ui.View.Private.view
      (Ui.View.image
         ~source:(Ui.Style.Image_source.resource "images/example.png")
         ~sizing:Fill
         ~scale:2.
         ())
  in
  match view.node with
  | Image { source = Resource "images/example.png"; sizing = Fill; scale = 2. } -> ()
  | _ -> failwith "image lost its native source, sizing or scale"
;;

let test_native_scroll_content () =
  List.iter
    (fun bounded ->
       let (Av view) = Ui.View.Private.view bounded in
       check
         (Ui.View.Private.kind_tag_to_string
            (Ui.View.Private.kind_tag_of_widget view.children.(0))
          = "Scroll")
         "ordinary scroll content was not wrapped by a native scroll node")
    [ Ui.View.Scroll.vertical child |> Ui.View.Viewport.Vertical.with_height ~height:200.
    ; Ui.View.Scroll.horizontal ~shows_indicators:false child
      |> Ui.View.Viewport.Horizontal.with_width ~width:200.
    ]
;;

let test_collection_catalog_and_window () =
  let module C = Ui.View.Collection in
  let keys = List.init 10000 Ui.Key.int in
  List.iter
    (fun duration ->
       expect_invalid
         (fun () ->
            C.Catalog.create ~keys ~default_extent:40. ~expand_duration_ms:duration ())
         "invalid expansion duration";
       expect_invalid
         (fun () ->
            C.Catalog.create ~keys ~default_extent:40. ~collapse_duration_ms:duration ())
         "invalid collapse duration")
    [ -1; 4_294_967_296 ];
  expect_invalid
    (fun () ->
       C.Catalog.create
         ~keys
         ~default_extent:40.
         ~sizing:(C.Measured { revision = -1L })
         ())
    "negative measurement revision";
  let catalog = C.Catalog.create ~keys ~default_extent:40. () in
  let empty_window =
    C.Window.create ~catalog ~visible_first_index:0 ~visible_last_exclusive:0
  in
  check
    (empty_window.first_index = 0 && empty_window.last_exclusive = 0)
    "empty collection range materialized rows";
  let window =
    C.Window.create ~catalog ~visible_first_index:7500 ~visible_last_exclusive:7515
  in
  check
    (window.first_index = 7496 && window.last_exclusive = 7519)
    "collection did not bound the materialized window";
  let item key = Ui.View.Keyed.create ~key (Ui.View.text "row") in
  let small =
    C.Catalog.create ~keys:[ Ui.Key.int 1; Ui.Key.string "1" ] ~default_extent:40. ()
  in
  ignore
    (C.vertical
       ~catalog:small
       ~first_index:0
       ~items:[ item (Ui.Key.int 1); item (Ui.Key.string "1") ]
       ~on_visible_range:handler
       ());
  ignore
    (C.horizontal
       ~catalog:small
       ~first_index:0
       ~items:[ item (Ui.Key.int 1); item (Ui.Key.string "1") ]
       ~on_visible_range:handler
       ());
  List.iter
    (fun height ->
       expect_invalid
         (fun () -> C.Catalog.create ~keys ~default_extent:height ())
         "collection accepted an invalid height")
    [ 0.; -1.; nan; infinity; Float.max_float ];
  expect_invalid
    (fun () ->
       C.Catalog.create ~keys:[ Ui.Key.int 1; Ui.Key.int 1 ] ~default_extent:40. ())
    "collection accepted duplicate keys";
  expect_invalid
    (fun () ->
       C.Catalog.create
         ~keys
         ~default_extent:40.
         ~overrides:[ { C.index = 10000; extent = 80. } ]
         ())
    "collection accepted an out-of-range extent";
  expect_invalid
    (fun () ->
       C.Catalog.create
         ~keys
         ~default_extent:40.
         ~overrides:[ { C.index = 3; extent = 80. }; { C.index = 2; extent = 80. } ]
         ())
    "collection accepted unordered extents";
  expect_invalid
    (fun () ->
       C.vertical
         ~catalog:small
         ~first_index:0
         ~items:[ item (Ui.Key.string "1") ]
         ~on_visible_range:handler
         ())
    "collection accepted a window with mismatched keys";
  expect_invalid
    (fun () ->
       C.vertical
         ~catalog:small
         ~first_index:2
         ~items:[ item (Ui.Key.int 1) ]
         ~on_visible_range:handler
         ())
    "collection accepted an out-of-range window";
  expect_invalid
    (fun () ->
       C.Window.create ~catalog:small ~visible_first_index:2 ~visible_last_exclusive:1)
    "collection accepted a reversed visible range"
;;

let () =
  test_native_scroll_content ();
  test_collection_catalog_and_window ();
  test_native_image_validation ();
  test_rich_text_spans ();
  test_surface_modifiers ();
  test_spacer_constructor ();
  test_frame_constructor ();
  test_symbols ();
  test_core_constructors ();
  test_overlay_constructor ();
  test_debug_tree ();
  test_semantics_properties ();
  test_styled_text_constructor_and_validation ();
  test_typed_viewport_body_encoding ();
  test_viewport_extent_and_body_validation ();
  test_swiftui_environment_validation ()
;;

let () =
  let key = ID.Navigation.Page_key.of_string in
  let item name =
    Ui.View.Tabs.item
      ~page_key:(key name)
      ~title:name
      ~symbol:"tray"
      (Ui.View.Body.Vertical.create
         [ Ui.View.Body.Vertical.fill (Ui.View.Scroll.vertical (Ui.View.text name)) ])
  in
  let create ?(selection = "mail") items =
    Ui.View.Tabs.create ~selection:(key selection) ~on_change:handler items
  in
  ignore (create [ item "mail"; item "chat" ]);
  ignore (create ~selection:"é" [ item "é"; item "e\204\129" ]);
  expect_invalid (fun () -> create []) "tabs accepted an empty page list";
  expect_invalid
    (fun () -> create [ item "mail"; item "mail" ])
    "tabs accepted duplicate keys";
  expect_invalid (fun () -> create [ item "chat" ]) "tabs accepted an unknown selection";
  expect_invalid (fun () -> item "") "tab accepted an empty key";
  expect_invalid
    (fun () ->
       Ui.View.Tabs.item
         ~page_key:(key "mail")
         ~title:"Mail"
         ~symbol:""
         (Ui.View.Body.static child))
    "tab accepted an empty symbol";
  expect_invalid
    (fun () ->
       create ~selection:"0" (List.init 257 (fun index -> item (string_of_int index))))
    "tabs exceeded the page limit"
;;

let () =
  List.iter (fun count -> ignore (Ui.View.badge ~count child)) [ 0; max_int ];
  match Ui.View.badge ~count:(-1) child with
  | _ -> failwith "badge accepted a negative count"
  | exception Invalid_argument _ -> ()
;;

let () =
  let module S = Ui.View.Scroll_targets in
  let items = [ S.item ~id:(-7L) child; S.item ~id:9L (Ui.View.text "second") ] in
  let create ?(fraction = 0.6) ?(spacing = 12.) ?(position = Some 9L) items =
    S.horizontal
      ~fraction
      ~spacing
      ~position
      ~alignment:S.Center
      ~on_position_changed:handler
      items
    |> Ui.View.Viewport.Horizontal.with_width ~width:400.
  in
  let content = (Ui.View.For_testing.children (create items)).(0) in
  check
    (Ui.View.For_testing.kind_name content = "Scroll_targets")
    "scroll targets used an obsolete node";
  let (Av value) = Ui.View.Private.view content in
  (match value.node with
   | Ui.View.Private.Scroll_targets { ids; position; fraction; alignment; _ } ->
     check
       (ids = [ -7L; 9L ] && position = Some 9L && fraction = 0.6 && alignment = 1)
       "scroll targets lost semantic position or layout"
   | _ -> failwith "missing scroll target properties");
  let children = Ui.View.For_testing.children content in
  check (Array.length children = 2) "scroll target content lost children";
  let expect_invalid f =
    match f () with
    | _ -> failwith "invalid scroll target configuration was accepted"
    | exception Invalid_argument _ -> ()
  in
  expect_invalid (fun () -> create ~position:None items);
  expect_invalid (fun () -> create ~position:(Some 100L) items);
  expect_invalid (fun () -> create [ S.item ~id:9L child; S.item ~id:9L child ]);
  expect_invalid (fun () -> create ~fraction:0. items);
  expect_invalid (fun () -> create ~fraction:1.1 items);
  expect_invalid (fun () -> create ~fraction:Float.nan items);
  expect_invalid (fun () -> create ~spacing:(-1.) items);
  ignore (create ~position:None [])
;;

let () =
  List.iter
    (fun message ->
       match Ui.View.help ~message child with
       | _ -> failwith "help accepted an empty message"
       | exception Invalid_argument _ -> ())
    [ ""; " \n\t" ];
  ignore (Ui.View.help ~message:"\194\160" child);
  let help = Ui.View.help ~message:"Archive 📬" child in
  check (Ui.View.For_testing.kind_name help = "Help") "help used a legacy node";
  check (Array.length (Ui.View.For_testing.children help) = 1) "help lost its child"
;;

let () =
  let module S = Ui.View.Sheet in
  let create ?initial_detent detents =
    S.create
      ~detents
      ?initial_detent
      ~presented:true
      ~on_presented_changed:handler
      ~content:child
      child
  in
  let invalid f =
    match f () with
    | _ -> failwith "invalid sheet detents were accepted"
    | exception Invalid_argument _ -> ()
  in
  invalid (fun () -> create []);
  invalid (fun () -> create [ S.Medium; S.Medium ]);
  invalid (fun () -> create ~initial_detent:S.Large [ S.Medium ]);
  List.iter
    (fun value -> invalid (fun () -> create [ S.Fraction value ]))
    [ 0.; -0.1; 1.01; nan; infinity ];
  invalid (fun () -> create [ S.Fraction 0.5; S.Fraction 0.98 ]);
  invalid (fun () -> create ~initial_detent:(S.Fraction 0.5) [ S.Fraction 0.98 ]);
  ignore (create [ S.Medium; S.Fraction 0.98; S.Large ]);
  ignore (create [ S.Fraction 1. ]);
  let sheet = create ~initial_detent:S.Medium [ S.Medium; S.Large ] in
  check (Ui.View.For_testing.kind_name sheet = "Sheet") "sheet used a legacy node";
  check (Array.length (Ui.View.For_testing.children sheet) = 2) "sheet lost content";
  ignore
    (S.full_screen ~presented:false ~on_presented_changed:handler ~content:child child)
;;

let () =
  let create compact_column =
    Ui.View.Navigation_split.two_columns
      ~state:(Ui.Navigation.Split_state.create ~compact_column ())
      ~sidebar_title:"Folders"
      ~detail_title:"Reading"
      ~on_change:handler
      ~sidebar:(Ui.View.Body.static child)
      ~detail:(Ui.View.Body.static child)
      ()
  in
  (match create Ui.Navigation.Split_column.Content with
   | _ -> failwith "two-column split accepted missing Content column"
   | exception Invalid_argument _ -> ());
  List.iter
    (fun column ->
       let split = create column in
       check
         (Array.length (Ui.View.For_testing.children split) = 2)
         "two-column split inserted an empty middle column")
    [ Ui.Navigation.Split_column.Sidebar; Ui.Navigation.Split_column.Detail ]
;;

let () =
  let create ?badge ?accessibility_label () =
    Ui.View.Tabs.item
      ?badge
      ?accessibility_label
      ~page_key:(ID.Navigation.Page_key.of_string "mail")
      ~title:"Mail"
      ~symbol:"tray"
      (Ui.View.Body.static child)
  in
  ignore (create ~badge:"0" ~accessibility_label:"Inbox messages" ());
  List.iter
    (fun invalid ->
       match invalid () with
       | _ -> failwith "tab accepted blank metadata"
       | exception Invalid_argument _ -> ())
    [ (fun () -> create ~badge:"" ()); (fun () -> create ~accessibility_label:" \n" ()) ]
;;

let () =
  let label = Ui.View.text "Action" in
  let default = Ui.View.button ~on_press:handler ~child:label () in
  let focus = Ui.View.button ~autofocus:true ~on_press:handler ~child:label () in
  check
    (not (Ui.View.Private.node_equal_widgets default focus))
    "button autofocus did not participate in property identity"
;;

let () =
  let color = Ui.Style.Color.rgb ~red:10 ~green:20 ~blue:30 in
  List.iter
    (fun create ->
       match create () with
       | _ -> failwith "invalid shared defaults accepted"
       | exception Invalid_argument _ -> ())
    [ (fun () -> Ui.Theme.Defaults.create ~symbol_size:0. ())
    ; (fun () -> Ui.Theme.Defaults.create ~column_spacing:(-1.) ())
    ; (fun () -> Ui.Theme.Defaults.create ~card_corner:Float.nan ())
    ; (fun () -> Ui.Theme.Defaults.create ~text_sizes:[ Body, Float.infinity ] ())
    ; (fun () -> Ui.Theme.Defaults.create ~colors:[ Primary, color; Primary, color ] ())
    ; (fun () -> Ui.Theme.Defaults.create ~text_sizes:[ Body, 18.; Body, 20. ] ())
    ; (fun () ->
        Ui.Theme.Defaults.create ~surface_opacities:[ Translucent_sheet, 1.1 ] ())
    ; (fun () -> Ui.Theme.Defaults.create ~surface_tint_alphas:[ Plain, -0.1 ] ())
    ; (fun () -> Ui.Theme.Defaults.create ~shadow_alpha:Float.nan ())
    ; (fun () -> Ui.Theme.Defaults.create ~material_alpha:1.1 ())
    ; (fun () -> Ui.Theme.Defaults.create ~text_italics:[ Hint, true; Hint, false ] ())
    ; (fun () ->
        Ui.Theme.Defaults.create ~surface_shapes:[ Plain, Rounded; Plain, Capsule ] ())
    ];
  ignore (Ui.Theme.Defaults.create ~column_spacing:0. ~border_width:0. ());
  let data =
    Ui.Theme.create ~defaults:(Ui.Theme.Defaults.create ~symbol_size:23. ()) ()
  in
  let same =
    Ui.Theme.create ~defaults:(Ui.Theme.Defaults.create ~symbol_size:23. ()) ()
  in
  let different =
    Ui.Theme.create ~defaults:(Ui.Theme.Defaults.create ~symbol_size:29. ()) ()
  in
  check (Ui.Theme.Private.equal data same) "equal sparse overrides changed theme identity";
  check
    (not (Ui.Theme.Private.equal data different))
    "changed defaults lost reactive identity"
;;

let () =
  check
    (not
       (Ui.View.Private.node_equal_widgets
          (Ui.View.symbol ~name:"star" ())
          (Ui.View.symbol ~name:"star" ~rendering:Monochrome ())))
    "omitted symbol rendering must remain distinguishable from explicit Monochrome";
  let text style = Ui.View.text ~style "Themed text" in
  check
    (not
       (Ui.View.Private.node_equal_widgets
          (text (Ui.Style.Text_style.create ()))
          (text (Ui.Style.Text_style.create ~role:Body ~italic:false ()))))
    "omitted typography must remain distinguishable from explicit Body/nonitalic"
;;
