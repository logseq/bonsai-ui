module Ui = Bonsai_swiftui_ui

let component handlers graph =
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment =
    Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      set_count
      ~f:(fun set_count -> function
      | Ui.Event.Payload.Unit -> set_count (fun count -> count + 1)
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 count increment ~f:(fun count increment ->
    Ui.View.column
      [ Ui.View.text "Counter"
      ; Ui.View.text (Printf.sprintf "Count: %d" count)
      ; Ui.View.button
          ~style:Ui.View.Button_style.Prominent
          ~on_press:increment
          ~child:(Ui.View.text "Increment")
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "increment")
      ])
;;

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164) ()
;;

let application_component handlers graph =
  Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body:(Ui.View.Body.static body))
;;

let app = App.create ~name:"Counter" application_component
