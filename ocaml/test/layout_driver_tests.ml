module ID = Bonsai_swiftui_spec.Id
module Ui = Bonsai_swiftui_ui

let require condition message = if not condition then failwith message

let component handlers _graph =
  let noop =
    Driver.Handler.create
      handlers
      ~name:"noop"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ -> Bonsai.Effect.return ())
  in
  Bonsai.Cont.map noop ~f:(fun noop ->
    Ui.View.animated_opacity
      ~animation:
        (Ui.Animation.create
           ~id:(ID.Ui.Animation_id.of_int64 7001L)
           ~duration_ms:250
           ~curve:Ui.Animation.Curve.Ease_in_out
           ())
      ~opacity:0.75
      ~on_completed:noop
      (Ui.View.overlay
         ~alignment:Top_start
         ~overlay:
           (Ui.View.button ~on_press:noop ~child:(Ui.View.text "Overlay") ()
            |> Ui.View.padding
                 ~insets:(Ui.Layout.Edge_insets.only ~leading:8. ~top:12. ()))
         (Ui.View.Weighted.row
            [ Ui.View.Weighted.share (Ui.View.text "Expanded")
            ; Ui.View.Weighted.fixed (Ui.View.text "Fixed")
            ])))
;;

let () =
  let driver =
    Driver.For_testing.create_widget_component
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 99L)
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      component
  in
  let frame =
    match Driver.pump driver ~monotonic_now_ns:0L () with
    | Ok { frame = Some frame; _ } -> frame
    | Ok { frame = None; _ } -> failwith "initial layout frame was empty"
    | Error error -> failwith (Driver.error_to_string error)
  in
  let wire =
    match Bonsai_swiftui_protocol.Binary_codec.decode frame.bytes with
    | Ok frame -> frame
    | Error error -> failwith error.message
  in
  let saw_overlay, saw_expanded, saw_insets, saw_animation =
    List.fold_left
      (fun (saw_overlay, saw_expanded, saw_insets, saw_animation) -> function
         | Bonsai_swiftui_protocol.Wire_frame.Create_node
             { kind; props; event_bindings; _ } ->
           let saw_overlay =
             saw_overlay || kind = Bonsai_swiftui_protocol.Wire_frame.Overlay
           in
           let saw_expanded =
             saw_expanded
             ||
             match props with
             | Weighted_row_props
                 { items = [ Share { weight = 1.; fills = true }; Intrinsic ]; _ } -> true
             | _ -> false
           in
           let saw_insets =
             saw_insets
             ||
             match props with
             | Padding_props { leading = 8.; top = 12.; trailing = 0.; bottom = 0. } ->
               true
             | _ -> false
           in
           let saw_animation =
             saw_animation
             ||
             match props, event_bindings with
             | ( Animated_opacity_props
                   { opacity = 0.75
                   ; animation = { id; duration_ms = 250; curve = Ease_in_out }
                   }
               , [ { event_tag; _ } ] ) ->
               ID.Ui.Animation_id.equal id (ID.Ui.Animation_id.of_int64 7001L)
               && event_tag
                  = Bonsai_swiftui_protocol.Generated_protocol.Event_tag
                    .animation_completed
             | _ -> false
           in
           saw_overlay, saw_expanded, saw_insets, saw_animation
         | _ -> saw_overlay, saw_expanded, saw_insets, saw_animation)
      (false, false, false, false)
      wire.operations
  in
  require saw_overlay "Overlay was not encoded as a native core node";
  require saw_expanded "Weighted share was not serialized";
  require saw_insets "Overlay insets were not serialized";
  require saw_animation "Semantic animation intent was not serialized"
;;
