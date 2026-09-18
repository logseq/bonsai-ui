module Ui = Bonsai_swiftui_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let row = Ui.View.text "Row"
let keyed_row = Ui.View.Keyed.create ~key:(Ui.Key.string "row") row

let vertical =
  Ui.View.Scroll.vertical row
  |> Ui.View.Viewport.Vertical.padding ~insets:(Ui.Layout.Edge_insets.all 8.)
  |> Ui.View.Viewport.Vertical.with_test_id (Ui.Test_id.string "feed")
  |> Ui.View.Viewport.Vertical.semantics
       ~properties:(Ui.Semantics.create ~label:"Feed" ())
  |> Ui.View.Viewport.Vertical.safe_area_padding ~insets:(Ui.Layout.Edge_insets.all 4.)
  |> Ui.View.Viewport.Vertical.theme ~data:(Ui.Theme.create ~mode:Ui.Theme.Light ())
;;

let horizontal = Ui.View.Scroll.horizontal row

let form =
  Ui.View.Form.vertical
    [ Ui.View.Keyed.create
        ~key:(Ui.Key.string "diagnostics")
        (Ui.View.Section.create ~header:(Ui.View.text "Diagnostics") [ keyed_row ])
    ]
;;

let (_ : Ui.View.Body.t) =
  Ui.View.Body.Vertical.create [ Ui.View.Body.Vertical.fill form ]
;;

let keyed_collection =
  let catalog =
    Ui.View.Collection.Catalog.create ~keys:[ Ui.Key.string "row" ] ~default_extent:48. ()
  in
  Ui.View.Collection.vertical
    ~catalog
    ~first_index:0
    ~items:[ keyed_row ]
    ~on_visible_range:handler
    ()
;;

let (_ : Ui.View.Body.t) =
  Ui.View.Body.Vertical.create
    [ Ui.View.Body.Vertical.fixed (Ui.View.text "Search")
    ; Ui.View.Body.Vertical.fill ~weight:2. vertical
    ]
;;

let (_ : Ui.View.t) = Ui.View.Viewport.Horizontal.with_width ~width:240. horizontal
let (_ : Ui.View.t) = Ui.View.Viewport.Vertical.with_height ~height:240. keyed_collection

let (_ : Ui.View.Body.t) =
  Ui.View.Body.Horizontal.create
    [ Ui.View.Body.Horizontal.fixed (Ui.View.text "Leading")
    ; Ui.View.Body.Horizontal.fill horizontal
    ]
;;

let (_ : Ui.View.Body.t) = Ui.View.Body.static (Ui.View.text "Static body")

let (_ : Ui.View.t) =
  let page_key = Bonsai_swiftui_spec.Id.Navigation.Page_key.of_string "feed" in
  Ui.View.Tabs.create
    ~selection:page_key
    ~on_change:handler
    [ Ui.View.Tabs.item
        ~page_key
        ~title:"Feed"
        ~symbol:"tray"
        (Ui.View.Body.Vertical.create [ Ui.View.Body.Vertical.fill vertical ])
    ]
;;

let (_ : Ui.View.t) =
  Ui.View.Navigation_split.create
    ~state:(Ui.Navigation.Split_state.create ())
    ~sidebar_title:"Folders"
    ~content_title:"Messages"
    ~detail_title:"Reading"
    ~on_change:handler
    ~sidebar:(Ui.View.Body.static (Ui.View.text "Folders"))
    ~content:(Ui.View.Body.Vertical.create [ Ui.View.Body.Vertical.fill vertical ])
    ~detail:(Ui.View.Body.Horizontal.create [ Ui.View.Body.Horizontal.fill horizontal ])
    ()
;;

let (_ : Ui.View.t) =
  Ui.View.Navigation_stack.create
    ~title:"Root"
    ~on_path_change:handler
    ~path:
      [ Ui.View.Navigation_stack.destination
          ~page_key:(Bonsai_swiftui_spec.Id.Navigation.Page_key.of_string "details")
          ~title:"Details"
          (Ui.View.Body.Horizontal.create [ Ui.View.Body.Horizontal.fill horizontal ])
      ]
    (Ui.View.Body.Vertical.create [ Ui.View.Body.Vertical.fill vertical ])
;;

let _ =
  let catalog =
    Ui.View.Collection.Catalog.create
      ~keys:[ Ui.Key.string "row" ]
      ~default_extent:120.
      ()
  in
  Ui.View.Body.Horizontal.create
    [ Ui.View.Body.Horizontal.fill
        (Ui.View.Collection.horizontal
           ~catalog
           ~first_index:0
           ~items:[ Ui.View.Keyed.create ~key:(Ui.Key.string "row") (Ui.View.text "Row") ]
           ~on_visible_range:(Ui.Event.Handler.create (fun _ -> ()))
           ())
    ]
;;
