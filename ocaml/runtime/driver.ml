module Protocol = Bonsai_swiftui_protocol
module Runtime = Bonsai_swiftui_runtime
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

module Handler = struct
  type t =
    { pending_effects : unit Bonsai.Effect.t Queue.t
    ; pending_before_display : (unit, unit) Bonsai.Effect.Private.Callback.t Queue.t
    ; host_effects : Host_effect.t
    ; application_platform : Host_effect.Application_platform.t
    ; environment : Environment.t
    }

  let create_with_dependencies ~equal dependencies ~f =
    dependencies |> Bonsai.Cont.cutoff ~equal |> Bonsai.Cont.map ~f
  ;;

  let create t ?name ~equal dependencies ~f =
    create_with_dependencies ~equal dependencies ~f:(fun dependencies ->
      Ui.Event.Handler.create ?name (fun payload ->
        Queue.add (f dependencies payload) t.pending_effects))
  ;;

  let create_native t ?name extension ~equal dependencies ~f =
    create_with_dependencies ~equal dependencies ~f:(fun dependencies ->
      Ui.Native_widget.event_handler ?name extension (fun event ->
        Queue.add (f dependencies event) t.pending_effects))
  ;;

  let host_effects t = t.host_effects
  let application_platform t = t.application_platform
  let environment t = t.environment

  let wait_before_display t =
    Bonsai.Effect.Private.make ~request:() ~evaluator:(fun callback ->
      Queue.add callback t.pending_before_display)
  ;;
end

module View = struct
  type t =
    { theme : Ui.Theme.t
    ; body : Ui.View.t
    }

  let create ~theme ~body = { theme; body = Ui.View.Body.Private.to_widget body }

  module Private = struct
    type view = t =
      { theme : Ui.Theme.t
      ; body : Ui.View.t
      }

    let view t = t
  end
end

type frame =
  { revision : ID.Runtime.renderer_revision
  ; frame_patch : Runtime.Frame_patch.t
  ; bytes : bytes
  ; stats : Protocol.Wire_frame.runtime_stats
  }

type error =
  | Runtime_error of Runtime.Runtime_error.t
  | Event_error of Runtime.Event_dispatcher.error
  | Codec_error of Protocol.Binary_codec.error
  | Unsupported_widget of string
  | Invalid_state of string
  | Lifecycle_error of string
  | Host_response_error of string
  | Application_platform_error of string
  | Shutdown

type pump_result =
  { presentation_id : ID.Runtime.presentation_id
  ; renderer_revision : ID.Runtime.renderer_revision
  ; frame : frame option
  ; recoverable_error : error option
  }

type rejection_reason =
  | Decode_failed
  | Frame_validation_failed
  | Renderer_epoch_mismatch
  | Renderer_revision_mismatch

let event_error_to_string = function
  | Runtime.Event_dispatcher.Invalid_event message -> "invalid event: " ^ message
  | Handler_error error -> Runtime.Runtime_error.to_string error
;;

let error_to_string = function
  | Runtime_error error -> Runtime.Runtime_error.to_string error
  | Event_error error -> event_error_to_string error
  | Codec_error error -> error.message
  | Unsupported_widget kind -> "unsupported widget in binary protocol: " ^ kind
  | Invalid_state message -> "invalid driver state: " ^ message
  | Lifecycle_error message -> "lifecycle failed: " ^ message
  | Host_response_error message -> "host response failed: " ^ message
  | Application_platform_error message -> "application platform failed: " ^ message
  | Shutdown -> "driver is shut down"
;;

type pending_presentation =
  { presentation_id : ID.Runtime.presentation_id
  ; renderer_revision : ID.Runtime.renderer_revision
  ; candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; candidate_application_theme : Ui.Theme.t
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; prepared_application_operations :
      Host_effect.Application_platform.Prepared_operations.t
  ; emitted_frame : frame option
  }

type t =
  { runtime_epoch : ID.Runtime.epoch
  ; application_title : string option
  ; trace : (string -> unit) option
  ; before_flush : schedule:(unit Bonsai.Effect.t -> unit) -> unit
  ; before_shutdown : unit -> unit
  ; time_source : Bonsai.Time_source.t
  ; logical_time_origin : Core.Time_ns.t
  ; bonsai : View.t Bonsai_runtime_adapter.t
  ; reconciler : Runtime.Reconciler.t
  ; handlers : Runtime.Handler_registry.t
  ; pending_effects : Handler.t
  ; host_effects : Host_effect.t
  ; application_platform : Host_effect.Application_platform.t
  ; environment : Environment.t
  ; mutable displayed_tree : Runtime.Mounted_tree.t option
  ; mutable displayed_handler_frame : Runtime.Handler_registry.Frame.t option
  ; mutable displayed_application_theme : Ui.Theme.t option
  ; mutable displayed_revision : ID.Runtime.renderer_revision
  ; mutable last_monotonic_ns : int64
  ; mutable last_event_sequence : ID.Runtime.event_sequence option
  ; mutable next_presentation_id : ID.Runtime.presentation_id
  ; mutable presentation_sequence_exhausted : bool
  ; mutable next_renderer_revision : ID.Runtime.renderer_revision
  ; mutable pending_presentation : pending_presentation option
  ; mutable force_full_snapshot_next : bool
  ; mutable terminal_error : error option
  ; mutable is_shutdown : bool
  ; mutable draining : bool
  ; mutable last_lifecycle_ns : int64
  ; mutable full_snapshot_count : int
  ; mutable resync_count : int
  }

let create
      ?trace
      ?(before_flush = fun ~schedule:_ -> ())
      ?(before_shutdown = fun () -> ())
      ?application_title
      ~runtime_epoch
      ~time_source
      component
  =
  if ID.Runtime.Epoch.compare runtime_epoch ID.Runtime.Epoch.zero <= 0
  then invalid_arg "Driver.create: runtime_epoch must be positive";
  let pending_queue = Queue.create () in
  let pending_before_display = Queue.create () in
  let host_effect_manager =
    Host_effect.Private.create ~schedule:(fun scheduled_effect ->
      Queue.add scheduled_effect pending_queue)
  in
  let application_platform_manager =
    Host_effect.Application_platform.Private.create ~schedule:(fun scheduled_effect ->
      Queue.add scheduled_effect pending_queue)
  in
  let environment_input = Environment.Private.create () in
  let pending_effects =
    Handler.
      { pending_effects = pending_queue
      ; pending_before_display
      ; host_effects = host_effect_manager
      ; application_platform = application_platform_manager
      ; environment = environment_input
      }
  in
  let bonsai = Bonsai_runtime_adapter.create ~time_source (component pending_effects) in
  { runtime_epoch
  ; application_title
  ; trace
  ; before_flush
  ; before_shutdown
  ; time_source
  ; logical_time_origin = Bonsai.Time_source.now time_source
  ; bonsai
  ; reconciler = Runtime.Reconciler.create ~runtime_epoch
  ; handlers = Runtime.Handler_registry.create ~runtime_epoch
  ; pending_effects
  ; host_effects = host_effect_manager
  ; application_platform = application_platform_manager
  ; environment = environment_input
  ; displayed_tree = None
  ; displayed_handler_frame = None
  ; displayed_application_theme = None
  ; displayed_revision = ID.Runtime.Renderer_revision.zero
  ; last_monotonic_ns = -1L
  ; last_event_sequence = None
  ; next_presentation_id = ID.Runtime.Presentation_id.one
  ; presentation_sequence_exhausted = false
  ; next_renderer_revision = ID.Runtime.Renderer_revision.one
  ; pending_presentation = None
  ; force_full_snapshot_next = false
  ; terminal_error = None
  ; is_shutdown = false
  ; draining = false
  ; last_lifecycle_ns = 0L
  ; full_snapshot_count = 0
  ; resync_count = 0
  }
;;

let trace_lazy t make_message =
  match t.trace with
  | None -> ()
  | Some sink ->
    (try sink (make_message ()) with
     | _ -> ())
;;

let now_ns () = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.)
let elapsed_ns start = Int64.sub (now_ns ()) start

let wire_frame_kind = function
  | Runtime.Frame_patch.Full_snapshot -> Protocol.Wire_frame.Full_snapshot
  | Incremental_frame -> Incremental_frame
;;

let wire_node_kind = function
  | Ui.View.Private.K_empty -> Ok Protocol.Wire_frame.Empty
  | K_spacer -> Ok Spacer
  | K_text -> Ok Text
  | K_rich_text -> Ok Rich_text
  | K_symbol -> Ok Symbol
  | K_image -> Ok Image
  | K_collection_catalog -> Ok Collection_catalog
  | K_collection_window -> Ok Collection_window
  | K_removal -> Ok Removal
  | K_native_list -> Ok Native_list
  | K_list_section -> Ok List_section
  | K_confirmation -> Ok Confirmation
  | K_context_menu -> Ok Context_menu
  | K_context_action -> Ok Context_action
  | K_context_menu_view -> Ok Context_menu_view
  | K_list_row_label -> Ok List_row_label
  | K_list_row -> Ok List_row
  | K_refresh -> Ok Refresh
  | K_scroll_targets -> Ok Scroll_targets
  | K_scroll -> Ok Scroll
  | K_text_editor -> Ok Text_editor
  | K_text_field -> Ok Text_field
  | K_secure_field -> Ok Secure_field
  | K_flow -> Ok Flow
  | K_row -> Ok Row
  | K_column -> Ok Column
  | K_weighted_row -> Ok Weighted_row
  | K_weighted_column -> Ok Weighted_column
  | K_stack -> Ok Stack
  | K_layout_priority -> Ok Layout_priority
  | K_offset -> Ok Offset
  | K_padding -> Ok Padding
  | K_frame -> Ok Frame
  | K_background -> Ok Background
  | K_clip -> Ok Clip
  | K_opacity -> Ok Opacity
  | K_animated_opacity -> Ok Animated_opacity
  | K_projection_effect -> Ok Projection_effect
  | K_gesture -> Ok Gesture
  | K_focus_scope -> Ok Focus_scope
  | K_hover_region -> Ok Hover_region
  | K_keyboard_listener -> Ok Keyboard_listener
  | K_button -> Ok Button
  | K_semantics -> Ok Semantics
  | K_theme -> Ok Theme
  | K_date_picker -> Ok Date_picker
  | K_time_picker -> Ok Time_picker
  | K_menu -> Ok Menu
  | K_picker -> Ok Picker
  | K_slider -> Ok Slider
  | K_range_slider -> Ok Range_slider
  | K_table -> Ok Table
  | K_divider -> Ok Divider
  | K_label -> Ok Label
  | K_form -> Ok Form
  | K_section -> Ok Section
  | K_labeled_content -> Ok Labeled_content
  | K_content_unavailable -> Ok Content_unavailable
  | K_text_selection -> Ok Text_selection
  | K_badge -> Ok Badge
  | K_sheet -> Ok Sheet
  | K_popover -> Ok Popover
  | K_scroll_sections -> Ok Scroll_sections
  | K_scroll_section -> Ok Scroll_section
  | K_toolbar -> Ok Toolbar
  | K_toolbar_entry -> Ok Toolbar_entry
  | K_toolbar_child -> Ok Toolbar_child
  | K_toolbar_body -> Ok Toolbar_body
  | K_help -> Ok Help
  | K_group_box -> Ok Group_box
  | K_progress -> Ok Progress
  | K_overlay -> Ok Overlay
  | K_disclosure_group -> Ok Disclosure_group
  | K_toggle -> Ok Toggle
  | K_swipe_actions -> Ok Swipe_actions
  | K_swipe_action -> Ok Swipe_action
  | K_morphing_surface -> Ok Morphing_surface
  | K_tabs -> Ok Tabs
  | K_tab -> Ok Tab
  | K_navigation_split -> Ok Navigation_split
  | K_navigation_link -> Ok Navigation_link
  | K_navigation_stack -> Ok Navigation_stack
  | K_navigation_destination -> Ok Navigation_destination
  | K_ignores_safe_area -> Ok Ignores_safe_area
  | K_safe_area_padding -> Ok Safe_area_padding
  | K_control_size -> Ok Control_size
  | K_native_widget -> Ok Native_widget
;;

let wire_theme (view : Ui.Theme.Private.view) : Protocol.Wire_frame.theme =
  { mode =
      (match view.mode with
       | Ui.Theme.System -> System
       | Light -> Light
       | Dark -> Dark)
  ; tint = view.tint
  ; font_family = view.font_family
  ; control_size =
      (match view.control_size with
       | None -> 5
       | Some Ui.Theme.Control_size.Mini -> 0
       | Some Small -> 1
       | Some Regular -> 2
       | Some Large -> 3
       | Some Extra_large -> 4)
  ; defaults = Bytes.copy view.defaults
  }
;;

let wire_application_theme theme = wire_theme (Ui.Theme.Private.view theme)

let wire_node_props (type k) (node : k Ui.View.Private.node) =
  match node with
  | Ui.View.Private.Empty -> Ok Protocol.Wire_frame.Empty_props
  | Spacer { min_length } -> Ok (Spacer_props { min_length })
  | Stack { alignment } ->
    let alignment : Protocol.Wire_frame.alignment =
      match alignment with
      | Ui.Layout.Alignment.Top_start -> Top_start
      | Top_center -> Top_center
      | Top_end -> Top_end
      | Center_start -> Center_start
      | Center -> Center
      | Center_end -> Center_end
      | Bottom_start -> Bottom_start
      | Bottom_center -> Bottom_center
      | Bottom_end -> Bottom_end
    in
    Ok (Stack_props { alignment })
  | Layout_priority { priority } -> Ok (Layout_priority_props { priority })
  | Offset { x; y } -> Ok (Offset_props { x; y })
  | Text { value; style; text_align; line_limit; truncation } ->
    let style =
      Option.map
        (fun (style : Ui.Style.Text_style.Private.view) ->
           let font_weight =
             Option.map
               (function
                 | Ui.Style.Font_weight.Normal -> Protocol.Wire_frame.Normal
                 | Medium -> Medium
                 | Semi_bold -> Semi_bold
                 | Bold -> Bold)
               style.font_weight
           in
           Protocol.Wire_frame.
             { font_size = style.font_size
             ; font_weight
             ; line_spacing = style.line_spacing
             ; color = style.color
             ; role = style.role
             ; foreground = style.foreground
             ; italic = style.italic
             })
        style
    in
    let text_align =
      match text_align with
      | Ui.Style.Text_align.Start -> Protocol.Wire_frame.Start
      | Center -> Center_text
      | End -> End
    in
    let truncation =
      match truncation with
      | Ui.Style.Text_truncation.Tail -> Protocol.Wire_frame.Tail
      | Head -> Head
      | Middle -> Middle
    in
    Ok (Text_props { value; style; text_align; line_limit; truncation })
  | Rich_text { spans } ->
    let spans =
      List.map
        (fun (span : Ui.Style.Text_span.Private.view) ->
           let font_weight =
             Option.map
               (function
                 | Ui.Style.Font_weight.Normal -> Protocol.Wire_frame.Normal
                 | Medium -> Medium
                 | Semi_bold -> Semi_bold
                 | Bold -> Bold)
               span.font_weight
           in
           Protocol.Wire_frame.
             { value = span.value
             ; font_size = span.font_size
             ; font_weight
             ; color = span.color
             ; italic = span.italic
             ; underline = span.underline
             ; strikethrough = span.strikethrough
             })
        spans
    in
    Ok (Rich_text_props { spans })
  | Symbol { name; size; color; rendering } ->
    let rendering =
      match rendering with
      | None -> 3
      | Some Ui.View.Symbol_rendering.Monochrome -> 0
      | Some Hierarchical -> 1
      | Some Multicolor -> 2
    in
    Ok (Symbol_props { name; size; color; rendering })
  | Removal
      { request_token; request_state; vertical; collapse_vertical; title; duration_ms } ->
    Ok
      (Removal_props
         { request_token; request_state; vertical; collapse_vertical; title; duration_ms })
  | Native_list { style; scroll_request } ->
    let scroll_request =
      Option.map
        (fun (token, section_key, row_path, anchor, animated) ->
           Protocol.Wire_frame.{ token; section_key; row_path; anchor; animated })
        scroll_request
    in
    Ok (Native_list_props { style; scroll_request })
  | List_section { has_header; has_footer; separator; section_key } ->
    Ok (List_section_props { has_header; has_footer; separator; section_key })
  | Confirmation { style; request_token; title; message; actions } ->
    Ok (Confirmation_props { style; request_token; title; message; actions })
  | Context_menu { enabled } -> Ok (Context_menu_props { enabled })
  | Context_action { action_key; title; enabled; role; symbol } ->
    Ok (Context_action_props { action_key; title; enabled; role; symbol })
  | Context_menu_view -> Ok Context_menu_view_props
  | List_row_label -> Ok List_row_label_props
  | List_row { separator; row_key; expanded } ->
    Ok (List_row_props { separator; row_key; expanded })
  | Refresh { request_token; request_state; show_token } ->
    Ok (Refresh_props { request_token; request_state; show_token })
  | Scroll_targets
      { vertical
      ; ids
      ; position
      ; fraction
      ; spacing
      ; alignment
      ; snapping
      ; enabled
      ; shows_indicators
      } ->
    Ok
      (Scroll_targets_props
         { vertical
         ; ids
         ; position
         ; fraction
         ; spacing
         ; alignment
         ; snapping
         ; enabled
         ; shows_indicators
         })
  | Scroll { vertical; shows_indicators; fill_viewport; initial_anchor } ->
    Ok (Scroll_props { vertical; shows_indicators; fill_viewport; initial_anchor })
  | Collection_catalog fields ->
    Ok
      (Collection_catalog_props
         { keys = Array.to_list fields.keys
         ; default_extent = fields.default_extent
         ; overrides = fields.overrides
         ; overscan = fields.overscan
         ; expand_duration_ms = fields.expand_duration_ms
         ; collapse_duration_ms = fields.collapse_duration_ms
         ; vertical = fields.vertical
         ; initial_anchor = fields.initial_anchor
         ; initial_key = fields.initial_key
         ; measurement_revision = fields.measurement_revision
         })
  | Collection_window fields ->
    Ok
      (Collection_window_props
         { first_index = fields.first_index; keys = Array.to_list fields.keys })
  | Text_editor fields ->
    let wire_range range =
      Protocol.Wire_frame.
        { start_utf16 = Ui.Text_editing.Range.start_utf16 range
        ; end_utf16 = Ui.Text_editing.Range.end_utf16 range
        }
    in
    let value =
      Protocol.Wire_frame.
        { text = Ui.Text_editing.Value.text fields.value
        ; selection = wire_range (Ui.Text_editing.Value.selection fields.value)
        ; composing = Option.map wire_range (Ui.Text_editing.Value.composing fields.value)
        }
    in
    let update_mode =
      match fields.update_mode with
      | Ui.Text_editing.Ack -> Protocol.Wire_frame.Ack
      | Correction -> Correction
      | Force_replace -> Force_replace
    in
    Ok
      (Text_editor_props
         { editing =
             { session_id = fields.session_id
             ; document_revision = fields.document_revision
             ; accepted_local_revision = fields.accepted_local_revision
             ; update_mode
             ; value
             ; enabled = fields.enabled
             ; read_only = fields.read_only
             ; submit_on_return = fields.submit_on_return
             ; max_utf8_bytes = fields.max_utf8_bytes
             }
         ; autofocus = fields.autofocus
         })
  | Text_field fields ->
    let wire_range range =
      Protocol.Wire_frame.
        { start_utf16 = Ui.Text_editing.Range.start_utf16 range
        ; end_utf16 = Ui.Text_editing.Range.end_utf16 range
        }
    in
    let value =
      Protocol.Wire_frame.
        { text = Ui.Text_editing.Value.text fields.value
        ; selection = wire_range (Ui.Text_editing.Value.selection fields.value)
        ; composing = Option.map wire_range (Ui.Text_editing.Value.composing fields.value)
        }
    in
    let update_mode =
      match fields.update_mode with
      | Ui.Text_editing.Ack -> Protocol.Wire_frame.Ack
      | Correction -> Correction
      | Force_replace -> Force_replace
    in
    Ok
      (Text_field_props
         { label = fields.label
         ; prompt = fields.prompt
         ; secure = fields.secure
         ; keyboard =
             (match fields.keyboard with
              | Ui.Text_editing.Keyboard.Text -> 0
              | Number -> 1
              | Email -> 2
              | Phone -> 3
              | Url -> 4)
         ; submit_label =
             (match fields.submit_label with
              | Ui.Text_editing.Submit_label.Done -> 0
              | Next -> 1
              | Search -> 2
              | Send -> 3
              | Go -> 4
              | Continue -> 5)
         ; appearance =
             (match fields.appearance with
              | Ui.Text_editing.Field_appearance.Rounded -> 0
              | Plain -> 1)
         ; autofocus = fields.autofocus
         ; editing =
             { session_id = fields.session_id
             ; document_revision = fields.document_revision
             ; accepted_local_revision = fields.accepted_local_revision
             ; update_mode
             ; value
             ; enabled = fields.enabled
             ; read_only = fields.read_only
             ; submit_on_return = fields.submit_on_return
             ; max_utf8_bytes = fields.max_utf8_bytes
             }
         })
  | Image { source; sizing; scale } ->
    let source =
      match source with
      | Ui.Style.Image_source.Resource name -> Protocol.Wire_frame.Resource name
      | Remote url -> Remote url
    in
    let sizing =
      match sizing with
      | Ui.Style.Image_sizing.Original -> Protocol.Wire_frame.Original
      | Stretch -> Stretch
      | Fit -> Fit
      | Fill -> Fill
    in
    Ok (Image_props { source; sizing; scale })
  | Flow { spacing; line_spacing; alignment } ->
    let alignment =
      match alignment with
      | Ui.Layout.Horizontal_alignment.Leading -> 0
      | Center -> 1
      | Trailing -> 2
    in
    Ok (Flow_props { spacing; line_spacing; alignment })
  | Row { spacing; alignment } ->
    let alignment =
      match alignment with
      | Ui.Layout.Vertical_alignment.Top -> 0
      | Center -> 1
      | Bottom -> 2
      | First_text_baseline -> 3
      | Last_text_baseline -> 4
    in
    Ok (Row_props { spacing; alignment })
  | Column { spacing; alignment } ->
    let alignment =
      match alignment with
      | Ui.Layout.Horizontal_alignment.Leading -> 0
      | Center -> 1
      | Trailing -> 2
    in
    Ok (Column_props { spacing; alignment })
  | Weighted_row { spacing; alignment; items } ->
    let alignment =
      match alignment with
      | Ui.Layout.Vertical_alignment.Top -> 0
      | Center -> 1
      | Bottom -> 2
      | First_text_baseline -> 3
      | Last_text_baseline -> 4
    in
    let items =
      List.map
        (function
          | Ui.View.Private.Intrinsic -> Protocol.Wire_frame.Intrinsic
          | Share { weight; fills } -> Protocol.Wire_frame.Share { weight; fills })
        items
    in
    Ok (Weighted_row_props { spacing; alignment; items })
  | Weighted_column { spacing; alignment; items } ->
    let alignment =
      match alignment with
      | Ui.Layout.Horizontal_alignment.Leading -> 0
      | Center -> 1
      | Trailing -> 2
    in
    let items =
      List.map
        (function
          | Ui.View.Private.Intrinsic -> Protocol.Wire_frame.Intrinsic
          | Share { weight; fills } -> Protocol.Wire_frame.Share { weight; fills })
        items
    in
    Ok (Weighted_column_props { spacing; alignment; items })
  | Button { enabled; role; style; autofocus } ->
    let role =
      match role with
      | Ui.View.Button_role.Normal -> 0
      | Cancel -> 1
      | Destructive -> 2
    in
    let style =
      match style with
      | Ui.View.Button_style.Automatic -> 0
      | Plain -> 1
      | Bordered -> 2
      | Prominent -> 3
    in
    Ok (Button_props { enabled; role; style; autofocus })
  | Padding { leading; top; trailing; bottom } ->
    Ok (Padding_props { leading; top; trailing; bottom })
  | Frame
      { width
      ; height
      ; min_width
      ; ideal_width
      ; max_width
      ; min_height
      ; ideal_height
      ; max_height
      ; alignment
      } ->
    let alignment : Protocol.Wire_frame.alignment =
      match alignment with
      | Ui.Layout.Alignment.Top_start -> Protocol.Wire_frame.Top_start
      | Top_center -> Top_center
      | Top_end -> Top_end
      | Center_start -> Center_start
      | Center -> Center
      | Center_end -> Center_end
      | Bottom_start -> Bottom_start
      | Bottom_center -> Bottom_center
      | Bottom_end -> Bottom_end
    in
    let limit =
      Option.map (function
        | Ui.Layout.Frame_limit.Points value -> Protocol.Wire_frame.Points value
        | Fill -> Protocol.Wire_frame.Fill_space)
    in
    Ok
      (Frame_props
         { width
         ; height
         ; min_width
         ; ideal_width
         ; max_width = limit max_width
         ; min_height
         ; ideal_height
         ; max_height = limit max_height
         ; alignment
         })
  | Background { color; corner_radius } -> Ok (Background_props { color; corner_radius })
  | Clip { corner_radius; antialiased } -> Ok (Clip_props { corner_radius; antialiased })
  | Opacity { opacity } -> Ok (Opacity_props { opacity })
  | Animated_opacity { opacity; animation } ->
    let curve : Protocol.Wire_frame.animation_curve =
      match Ui.Animation.Private.curve animation with
      | Linear -> Linear
      | Ease_in -> Ease_in
      | Ease_out -> Ease_out
      | Ease_in_out -> Ease_in_out
    in
    let animation =
      { Protocol.Wire_frame.id = Ui.Animation.Private.id animation
      ; duration_ms = Ui.Animation.Private.duration_ms animation
      ; curve
      }
    in
    Ok (Animated_opacity_props { opacity; animation })
  | Projection_effect { matrix3 } ->
    Ok (Projection_effect_props { matrix3 = Array.copy matrix3 })
  | Gesture -> Ok Gesture_props
  | Focus_scope { autofocus } -> Ok (Focus_scope_props { autofocus })
  | Hover_region { blocks_behind } -> Ok (Hover_region_props { blocks_behind })
  | Keyboard_listener { autofocus; key_policy } ->
    let key_policy =
      match key_policy with
      | Ui.Event.Key_policy.Handled -> Protocol.Wire_frame.Handled
      | Ignored -> Ignored
    in
    Ok (Keyboard_listener_props { autofocus; key_policy })
  | Semantics properties ->
    let role =
      match properties.role with
      | Ui.Semantics.Role.Generic -> Protocol.Wire_frame.Generic
      | Button -> Semantics_button
      | Link -> Link
      | Image -> Image
      | Header -> Header
      | Toggle -> Semantics_toggle
      | Static_text -> Static_text
    in
    let children =
      match properties.children with
      | Ui.Semantics.Children.Combine -> 0
      | Contain -> 1
      | Ignore -> 2
    in
    Ok
      (Semantics_props
         { label = properties.label
         ; hint = properties.hint
         ; value = properties.value
         ; role
         ; selected = properties.selected
         ; children
         ; hidden = properties.hidden
         ; live_region = properties.live_region
         ; heading_level = properties.heading_level
         ; sort_priority = properties.sort_priority
         ; identifier = properties.identifier
         ; actions =
             List.map
               (fun action ->
                  Ui.Semantics.Action.id action, Ui.Semantics.Action.label action)
               properties.actions
         })
  | Theme data -> Ok (Theme_props (wire_theme data))
  | Date_picker { selected; first; last; label; enabled } ->
    let date (date : Ui.View.Date.t) : Protocol.Wire_frame.civil_date =
      { year = date.year; month = date.month; day = date.day }
    in
    Ok
      (Date_picker_props
         { selected = date selected
         ; first = date first
         ; last = date last
         ; label
         ; enabled
         })
  | Time_picker { value; format; label; enabled } ->
    Ok
      (Time_picker_props
         { value = { hour = value.hour; minute = value.minute }; format; label; enabled })
  | Menu { items; enabled } ->
    Ok
      (Menu_props
         { enabled
         ; items =
             List.map
               (fun (item : Ui.View.Private.menu_item) ->
                  Protocol.Wire_frame.
                    { menu_id = item.menu_id
                    ; kind = item.kind
                    ; enabled = item.enabled
                    ; selected = item.selected
                    ; role = item.role
                    ; has_label = item.has_label
                    ; child_count = item.child_count
                    })
               items
         })
  | Picker { selected_id; options; label; style; enabled } ->
    Ok
      (Picker_props
         { label
         ; style
         ; enabled
         ; selected_id
         ; options =
             List.map
               (fun (option : Ui.View.Private.picker_option) ->
                  Protocol.Wire_frame.
                    { option_id = option.option_id
                    ; enabled = option.enabled
                    ; has_label = option.has_label
                    })
               options
         })
  | Slider { value; min; max; step; label; enabled; vertical; has_on_change } ->
    Ok (Slider_props { value; min; max; step; label; enabled; vertical; has_on_change })
  | Range_slider
      { start
      ; end_
      ; min
      ; max
      ; step
      ; label_start
      ; label_end
      ; enabled
      ; vertical
      ; has_on_change
      } ->
    Ok
      (Range_slider_props
         { start
         ; end_
         ; min
         ; max
         ; step
         ; label_start
         ; label_end
         ; enabled
         ; vertical
         ; has_on_change
         })
  | Table fields ->
    Ok
      (Table_props
         { columns =
             List.map
               (fun (value : Ui.View.Private.table_column) ->
                  Protocol.Wire_frame.
                    { column_id = value.column_id
                    ; title = value.title
                    ; has_details = value.has_details
                    ; tooltip = value.tooltip
                    ; numeric = value.numeric
                    ; sortable = value.sortable
                    })
               fields.columns
         ; rows =
             List.map
               (fun (value : Ui.View.Private.table_row) ->
                  Protocol.Wire_frame.
                    { row_id = value.row_id; selection_enabled = value.selection_enabled })
               fields.rows
         ; sort_column_id = fields.sort_column_id
         ; sort_ascending = fields.sort_ascending
         ; selected_row_ids = fields.selected_row_ids
         ; has_on_sort = fields.has_on_sort
         ; has_on_row_selected = fields.has_on_row_selected
         })
  | Divider -> Ok Divider_props
  | Label -> Ok Label_props
  | Form -> Ok Form_props
  | Section { has_header; has_footer } -> Ok (Section_props { has_header; has_footer })
  | Labeled_content -> Ok Labeled_content_props
  | Content_unavailable -> Ok Content_unavailable_props
  | Text_selection { enabled } -> Ok (Text_selection_props { enabled })
  | Badge { count; alignment; visible } ->
    let alignment =
      match alignment with
      | Ui.Layout.Horizontal_alignment.Leading -> 0
      | Center -> 1
      | Trailing -> 2
    in
    Ok (Badge_props { count = Option.map Int64.of_int count; alignment; visible })
  | Sheet
      { presented
      ; fullscreen
      ; detents
      ; initial
      ; interactive
      ; indicator
      ; sizing
      ; fraction
      } ->
    Ok
      (Sheet_props
         { presented
         ; fullscreen
         ; detents
         ; initial
         ; interactive
         ; indicator
         ; sizing
         ; fraction
         })
  | Popover { presented; edge } -> Ok (Popover_props { presented; edge })
  | Scroll_sections
      { vertical; pin_headers; pin_footers; spacing; shows_indicators; initial_anchor } ->
    Ok
      (Scroll_sections_props
         { vertical; pin_headers; pin_footers; spacing; shows_indicators; initial_anchor })
  | Scroll_section { has_header; has_footer; hero_height; stretch } ->
    Ok (Scroll_section_props { has_header; has_footer; hero_height; stretch })
  | Toolbar -> Ok Toolbar_props
  | Toolbar_entry { entry_key; placement; kind } ->
    Ok (Toolbar_entry_props { entry_key; placement; kind })
  | Toolbar_child { child_key } -> Ok (Toolbar_child_props { child_key })
  | Toolbar_body -> Ok Toolbar_body_props
  | Help { message } -> Ok (Help_props { message })
  | Group_box { has_label } -> Ok (Group_box_props { has_label })
  | Progress { value; style } ->
    Ok
      (Progress_props
         { value
         ; style =
             (match style with
              | Ui.View.Progress_style.Linear -> 0
              | Circular -> 1
              | Automatic -> 2)
         })
  | Overlay { alignment } ->
    let alignment =
      match alignment with
      | Ui.Layout.Alignment.Top_start -> Protocol.Wire_frame.Top_start
      | Top_center -> Top_center
      | Top_end -> Top_end
      | Center_start -> Center_start
      | Center -> Center
      | Center_end -> Center_end
      | Bottom_start -> Bottom_start
      | Bottom_center -> Bottom_center
      | Bottom_end -> Bottom_end
    in
    Ok (Overlay_props { alignment })
  | Disclosure_group { expanded; enabled } ->
    Ok (Disclosure_group_props { expanded; enabled })
  | Toggle { value; enabled; style } -> Ok (Toggle_props { value; enabled; style })
  | Swipe_actions { enabled; allows_full_swipe } ->
    Ok (Swipe_actions_props { enabled; allows_full_swipe })
  | Swipe_action { title; side; enabled; role; background; symbol } ->
    Ok (Swipe_action_props { title; side; enabled; role; background; symbol })
  | Morphing_surface { expanded; expand_duration_ms; collapse_duration_ms } ->
    Ok (Morphing_surface_props { expanded; expand_duration_ms; collapse_duration_ms })
  | Tabs { selection } -> Ok (Tabs_props { selection })
  | Tab { page_key; title; symbol; badge; accessibility_label } ->
    Ok (Tab_props { page_key; title; symbol; badge; accessibility_label })
  | Navigation_split { state; sidebar_title; content_title; detail_title } ->
    let visibility, compact_column, selection_key =
      Ui.Navigation.Split_state.Private.to_codes state
    in
    Ok
      (Navigation_split_props
         { state = { visibility; compact_column; selection_key }
         ; sidebar_title
         ; content_title
         ; detail_title
         })
  | Navigation_link { activation_id; enabled } ->
    Ok (Navigation_link_props { activation_id; enabled })
  | Navigation_stack { title } -> Ok (Navigation_stack_props { title })
  | Navigation_destination { page_key; title; can_pop } ->
    Ok (Navigation_destination_props { page_key; title; can_pop })
  | Control_size { size } ->
    let size =
      match size with
      | Ui.View.Control_size.Mini -> 0
      | Small -> 1
      | Regular -> 2
      | Large -> 3
      | Extra_large -> 4
    in
    Ok (Control_size_props { size })
  | Ignores_safe_area { regions; edges } ->
    let regions =
      match regions with
      | Ui.View.Safe_area_regions.Container -> 0
      | Keyboard -> 1
      | All -> 2
    in
    Ok (Ignores_safe_area_props { regions; edges })
  | Safe_area_padding insets ->
    let leading, top, trailing, bottom = Ui.Layout.Edge_insets.Private.to_sides insets in
    Ok (Safe_area_padding_props { leading; top; trailing; bottom })
  | Native_widget { kind_id; version; capabilities; payload } ->
    Ok (Native_widget_props { kind_id; version; capabilities; payload })
;;

let wire_event_tag =
  let module Tag = Protocol.Generated_protocol.Event_tag in
  function
  | Ui.Event.Tag.Press -> Tag.press
  | Long_press -> Tag.long_press
  | Tap -> Tag.tap
  | Double_tap -> Tag.double_tap
  | Pointer_enter -> Tag.pointer_enter
  | Pointer_leave -> Tag.pointer_leave
  | Pointer_down -> Tag.pointer_down
  | Pointer_up -> Tag.pointer_up
  | Key -> Tag.key
  | Focus_changed -> Tag.focus_changed
  | Text_edit -> Tag.text_edit
  | Text_submit -> Tag.text_submit
  | Text_limit_reached -> Tag.text_limit_reached
  | Scroll_notification -> Tag.scroll_notification
  | Visible_range_changed -> Tag.visible_range_changed
  | Animation_completed -> Tag.animation_completed
  | Tab_selected -> Tag.tab_selected
  | Navigation_split_changed -> Tag.navigation_split_changed
  | Navigation_path_changed -> Tag.navigation_path_changed
  | Layout_observed -> Tag.layout_observed
  | Value_changed -> Tag.value_changed
  | Native_event -> Tag.native_event
  | Semantics_action -> Tag.semantics_action
  | Navigation_destination_selected -> Tag.navigation_destination_selected
  | Radio_selected -> Tag.radio_selected
  | Removal_requested -> Tag.removal_requested
  | Removal_completed -> Tag.removal_completed
  | List_scroll_completed -> Tag.list_scroll_completed
  | Refresh_request -> Tag.refresh_request
  | Scroll_position_changed -> Tag.scroll_position_changed
  | Menu_action -> Tag.menu_action
  | Confirmation_response -> Tag.confirmation_response
  | Picker_selected -> Tag.picker_selected
  | Slider_changed -> Tag.slider_changed
  | Slider_change_end -> Tag.slider_change_end
  | Range_slider_changed -> Tag.range_slider_changed
  | Range_slider_change_end -> Tag.range_slider_change_end
  | Table_sort_requested -> Tag.table_sort_requested
  | Table_row_selected -> Tag.table_row_selected
  | Civil_date_changed -> Tag.civil_date_changed
  | Civil_time_changed -> Tag.civil_time_changed
;;

let wire_bindings bindings =
  Array.to_list bindings
  |> List.map (fun (binding : Runtime.Mounted_tree.Mounted_binding.t) ->
    Protocol.Wire_frame.
      { event_tag = wire_event_tag binding.event_tag; handler_id = binding.handler_id })
;;

let wire_operation = function
  | Runtime.Frame_patch.Operation.Create_node
      { node_id; node_tag; widget; event_bindings; _ } ->
    let (Av view) = Ui.View.Private.view widget in
    (match wire_node_kind node_tag, wire_node_props view.node with
     | Ok kind, Ok props ->
       Ok
         (Protocol.Wire_frame.Create_node
            { node_id; kind; props; event_bindings = wire_bindings event_bindings })
     | Error error, _ | _, Error error -> Error error)
  | Update_node { node_id; widget } ->
    let (Av view) = Ui.View.Private.view widget in
    (match wire_node_props view.node with
     | Ok props -> Ok (Protocol.Wire_frame.Update_props { node_id; props })
     | Error error -> Error error)
  | Update_event_bindings { node_id; event_bindings } ->
    Ok
      (Protocol.Wire_frame.Update_event_bindings
         { node_id; event_bindings = wire_bindings event_bindings })
  | Set_children { node_id; children } ->
    Ok (Protocol.Wire_frame.Set_children { node_id; children = Array.to_list children })
  | Set_root node_id -> Ok (Protocol.Wire_frame.Set_root node_id)
  | Drop_node node_id -> Ok (Protocol.Wire_frame.Drop_node node_id)
;;

let wire_operations operations =
  let rec loop reversed = function
    | [] -> Ok (List.rev reversed)
    | operation :: rest ->
      (match wire_operation operation with
       | Ok operation -> loop (operation :: reversed) rest
       | Error error -> Error error)
  in
  loop [] operations
;;

let drain_effects t =
  while not (Queue.is_empty t.pending_effects.pending_effects) do
    Bonsai_runtime_adapter.schedule_event
      t.bonsai
      (Queue.take t.pending_effects.pending_effects)
  done
;;

let flush_before_display t =
  let rec loop () =
    if not (Queue.is_empty t.pending_effects.pending_before_display)
    then (
      while not (Queue.is_empty t.pending_effects.pending_before_display) do
        let callback = Queue.take t.pending_effects.pending_before_display in
        Bonsai_runtime_adapter.schedule_event
          t.bonsai
          (Bonsai.Effect.Private.Callback.respond_to callback ())
      done;
      Bonsai_runtime_adapter.flush t.bonsai;
      loop ())
  in
  loop ()
;;

let frame_kind_name = function
  | Runtime.Frame_patch.Full_snapshot -> "full_snapshot"
  | Incremental_frame -> "incremental_frame"
;;

let operation_summary operations =
  let create_node = ref 0 in
  let update_props = ref 0 in
  let update_event_bindings = ref 0 in
  let set_children = ref 0 in
  let set_root = ref 0 in
  let drop_node = ref 0 in
  let host_request = ref 0 in
  let cancel_host_request = ref 0 in
  let application_request = ref 0 in
  List.iter
    (function
      | Protocol.Wire_frame.Create_node _ -> incr create_node
      | Update_props _ -> incr update_props
      | Update_event_bindings _ -> incr update_event_bindings
      | Set_children _ -> incr set_children
      | Set_root _ -> incr set_root
      | Set_application_theme _ -> ()
      | Drop_node _ -> incr drop_node
      | Host_request _ -> incr host_request
      | Cancel_host_request _ -> incr cancel_host_request
      | Application_request _ -> incr application_request
      | Runtime_stats _ -> ())
    operations;
  Printf.sprintf
    "createNode=%d updateProps=%d updateEventBindings=%d setChildren=%d setRoot=%d \
     dropNode=%d hostRequest=%d cancelHostRequest=%d applicationRequest=%d"
    !create_node
    !update_props
    !update_event_bindings
    !set_children
    !set_root
    !drop_node
    !host_request
    !cancel_host_request
    !application_request
;;

type widget_change =
  { node_id : Runtime.Node_id.t
  ; mutable operations : string list
  ; mutable widget : Ui.View.t option
  }

let find_source_widget mounted_tree node_id =
  let rec find (node : Runtime.Mounted_tree.Private.node) =
    if Runtime.Node_id.equal node.node_id node_id
    then Some node.source_widget
    else Array.find_map find node.children
  in
  Option.bind mounted_tree (fun tree -> find (Runtime.Mounted_tree.Private.root tree))
;;

let incremental_widget_diff ~old_tree ~new_tree operations =
  let changes_by_node = Hashtbl.create (List.length operations) in
  let changes = ref [] in
  let add operation node_id mounted_tree =
    let widget = find_source_widget mounted_tree node_id in
    match Hashtbl.find_opt changes_by_node node_id with
    | Some change ->
      if not (List.mem operation change.operations)
      then change.operations <- change.operations @ [ operation ];
      if Option.is_none change.widget then change.widget <- widget
    | None ->
      let change = { node_id; operations = [ operation ]; widget } in
      Hashtbl.add changes_by_node node_id change;
      changes := change :: !changes
  in
  List.iter
    (function
      | Runtime.Frame_patch.Operation.Create_node { node_id; _ } ->
        add "createNode" node_id new_tree
      | Update_node { node_id; _ } -> add "updateNode" node_id new_tree
      | Update_event_bindings { node_id; _ } -> add "updateEventBindings" node_id new_tree
      | Set_children { node_id; _ } -> add "setChildren" node_id new_tree
      | Set_root node_id -> add "setRoot" node_id new_tree
      | Drop_node node_id -> add "dropNode" node_id old_tree)
    operations;
  List.rev !changes
  |> List.map (fun change ->
    let description =
      match change.widget with
      | Some widget -> Ui.Debug.dump_widget widget
      | None -> "<widget unavailable>"
    in
    Printf.sprintf
      "  %s node=%Ld %s"
      (String.concat "+" change.operations)
      (Runtime.Node_id.to_int64 change.node_id)
      description)
  |> String.concat "\n"
;;

let trace_widget_diff t ~target_revision ~widget ~old_tree output =
  let frame_patch = output.Runtime.Reconciler.frame_patch in
  match t.trace with
  | None -> ()
  | Some _ when Runtime.Frame_patch.is_empty frame_patch -> ()
  | Some _ ->
    trace_lazy t (fun () ->
      let frame_kind = Runtime.Frame_patch.kind frame_patch in
      let diff =
        match frame_kind with
        | Runtime.Frame_patch.Full_snapshot -> Ui.Debug.dump_tree widget
        | Incremental_frame ->
          incremental_widget_diff
            ~old_tree
            ~new_tree:(Some output.mounted_tree)
            (Runtime.Frame_patch.operations frame_patch)
      in
      Printf.sprintf
        "[widget-diff] targetRevision=%Ld kind=%s\n%s"
        (ID.Runtime.Renderer_revision.to_int64 target_revision)
        (frame_kind_name frame_kind)
        diff)
;;

type produced_candidate =
  { candidate_tree : Runtime.Mounted_tree.t
  ; candidate_handler_frame : Runtime.Handler_registry.Frame.t option
  ; candidate_application_theme : Ui.Theme.t
  ; prepared_host_operations : Host_effect.Prepared_operations.t
  ; prepared_application_operations :
      Host_effect.Application_platform.Prepared_operations.t
  ; renderer_revision : ID.Runtime.renderer_revision
  ; emitted_frame : frame option
  }

let produce_candidate t ~event_batch_size ~bonsai_flush_ns ~force_full_snapshot =
  if
    ID.Runtime.Renderer_revision.equal
      t.next_renderer_revision
      ID.Runtime.Renderer_revision.max_value
  then Error (Invalid_state "renderer revision counter exhausted")
  else (
    let target_revision = t.next_renderer_revision in
    let result_started = now_ns () in
    let view = Bonsai_runtime_adapter.result t.bonsai |> View.Private.view in
    let widget = view.body in
    let application_theme = view.theme in
    let theme_changed =
      force_full_snapshot
      ||
      match t.displayed_application_theme with
      | None -> true
      | Some displayed -> not (Ui.Theme.Private.equal application_theme displayed)
    in
    let result_read_ns = elapsed_ns result_started in
    let reconcile_started = now_ns () in
    match
      Runtime.Reconciler.reconcile
        t.reconciler
        ~base_revision:t.displayed_revision
        ~target_revision
        ~old:(if force_full_snapshot then None else t.displayed_tree)
        ~base_handler_frame:
          (if force_full_snapshot then None else t.displayed_handler_frame)
        widget
    with
    | Error error -> Error (Runtime_error error)
    | Ok output ->
      let reconcile_ns = elapsed_ns reconcile_started in
      trace_widget_diff t ~target_revision ~widget ~old_tree:t.displayed_tree output;
      let prepared_host_operations = Host_effect.prepare_operations t.host_effects in
      let host_operations =
        Host_effect.Prepared_operations.operations prepared_host_operations
      in
      let prepared_application_operations =
        Host_effect.Application_platform.prepare_operations t.application_platform
      in
      let application_operations =
        Host_effect.Application_platform.Prepared_operations.operations
          prepared_application_operations
      in
      if
        Runtime.Frame_patch.is_empty output.frame_patch
        && (not theme_changed)
        && host_operations = []
        && application_operations = []
      then
        Ok
          { candidate_tree = output.mounted_tree
          ; candidate_handler_frame = None
          ; candidate_application_theme = application_theme
          ; prepared_host_operations
          ; prepared_application_operations
          ; renderer_revision = t.displayed_revision
          ; emitted_frame = None
          }
      else (
        match wire_operations (Runtime.Frame_patch.operations output.frame_patch) with
        | Error _ as error -> error
        | Ok ui_operations ->
          let theme_operations =
            if theme_changed
            then
              [ Protocol.Wire_frame.Set_application_theme
                  { title = t.application_title
                  ; theme = wire_application_theme application_theme
                  }
              ]
            else []
          in
          let operations =
            theme_operations @ ui_operations @ host_operations @ application_operations
          in
          let frame_kind = Runtime.Frame_patch.kind output.frame_patch in
          let base_revision =
            match frame_kind with
            | Runtime.Frame_patch.Full_snapshot -> ID.Runtime.Renderer_revision.zero
            | Incremental_frame -> t.displayed_revision
          in
          if frame_kind = Runtime.Frame_patch.Full_snapshot
          then t.full_snapshot_count <- t.full_snapshot_count + 1;
          if force_full_snapshot then t.resync_count <- t.resync_count + 1;
          let stats : Protocol.Wire_frame.runtime_stats =
            { event_batch_size
            ; bonsai_flush_ns
            ; result_read_ns
            ; reconcile_ns
            ; encode_ns = 0L
            ; patch_count = List.length operations
            ; patch_bytes = 0
            ; lifecycle_ns = t.last_lifecycle_ns
            ; full_snapshot_count = t.full_snapshot_count
            ; resync_count = t.resync_count
            }
          in
          let wire_frame stats =
            Protocol.Wire_frame.
              { runtime_epoch = t.runtime_epoch
              ; base_revision
              ; target_revision
              ; kind = wire_frame_kind frame_kind
              ; operations = operations @ [ Runtime_stats stats ]
              }
          in
          let encode_started = now_ns () in
          (match Protocol.Binary_codec.encode_runtime_frame (wire_frame stats) with
           | Error error -> Error (Codec_error error)
           | Ok encoded ->
             let bytes = Protocol.Binary_codec.Runtime_encoded_frame.bytes encoded in
             let stats =
               { stats with
                 encode_ns = elapsed_ns encode_started
               ; patch_bytes = Bytes.length bytes
               }
             in
             (match
                Protocol.Binary_codec.patch_runtime_stats
                  encoded
                  ~encode_ns:stats.encode_ns
                  ~patch_bytes:stats.patch_bytes
              with
              | Error error -> Error (Codec_error error)
              | Ok () ->
                let frame =
                  { revision = target_revision
                  ; frame_patch = output.frame_patch
                  ; bytes
                  ; stats
                  }
                in
                t.next_renderer_revision
                <- ID.Runtime.Renderer_revision.succ target_revision;
                trace_lazy t (fun () ->
                  Printf.sprintf
                    "[outbound-frame] direction=ocaml->swiftui epoch=%Ld kind=%s \
                     baseRevision=%Ld targetRevision=%Ld operations=%d bytes=%d\n\
                    \  operationSummary=%s"
                    (ID.Runtime.Epoch.to_int64 t.runtime_epoch)
                    (frame_kind_name frame_kind)
                    (ID.Runtime.Renderer_revision.to_int64 base_revision)
                    (ID.Runtime.Renderer_revision.to_int64 target_revision)
                    (List.length operations)
                    (Bytes.length bytes)
                    (operation_summary operations));
                Ok
                  { candidate_tree = output.mounted_tree
                  ; candidate_handler_frame = Some output.handler_frame
                  ; candidate_application_theme = application_theme
                  ; prepared_host_operations
                  ; prepared_application_operations
                  ; renderer_revision = target_revision
                  ; emitted_frame = Some frame
                  }))))
;;

let event_tag_name event_tag =
  match Protocol.Generated_protocol.Event_tag.debug_name event_tag with
  | Some name -> name
  | None -> Printf.sprintf "unknown(%d)" (ID.Protocol.Event_tag.to_int event_tag)
;;

let pointer_kind_name = function
  | Protocol.Inbound_event.Mouse -> "mouse"
  | Touch -> "touch"
  | Stylus -> "stylus"
  | Inverted_stylus -> "inverted_stylus"
  | Trackpad -> "trackpad"
  | Unknown_pointer -> "unknown"
;;

let key_action_name = function
  | Protocol.Inbound_event.Key_down -> "down"
  | Key_up -> "up"
  | Key_repeat -> "repeat"
;;

let host_response_status_name = function
  | Protocol.Inbound_event.Host_ok -> "ok"
  | Host_error -> "error"
  | Host_cancelled -> "cancelled"
;;

let payload_summary = function
  | Protocol.Inbound_event.Confirmation_response { token; action_key } ->
    Printf.sprintf
      "confirmation_response(%Ld,%S)"
      token
      (Option.value action_key ~default:"dismissed")
  | Protocol.Inbound_event.Unit -> "unit"
  | Bool value -> Printf.sprintf "bool(%b)" value
  | Float value -> Printf.sprintf "float(%g)" value
  | Float_range { start; end_ } -> Printf.sprintf "float_range(%g,%g)" start end_
  | Text value -> Printf.sprintf "text(bytes=%d)" (String.length value)
  | Text_edit edit ->
    Printf.sprintf
      "text_edit(session=%Ld localRevision=%Ld baseDocumentRevision=%Ld bytes=%d)"
      (ID.Text_input.Session_id.to_int64 edit.session_id)
      (ID.Text_input.Local_revision.to_int64 edit.local_revision)
      (ID.Text_input.Document_revision.to_int64 edit.base_document_revision)
      (String.length edit.text)
  | Int64 value -> Printf.sprintf "int64(%Ld)" value
  | Int64_bool { id; value } -> Printf.sprintf "int64_bool(%Ld,%b)" id value
  | Int64_pair { first; second } -> Printf.sprintf "int64_pair(%Ld,%Ld)" first second
  | Civil_date { year; month; day } ->
    Printf.sprintf "civil_date(%04d-%02d-%02d)" year month day
  | Civil_time { hour; minute } -> Printf.sprintf "civil_time(%02d:%02d)" hour minute
  | Tap tap ->
    Printf.sprintf
      "tap(local=%g,%g global=%g,%g pointer=%s)"
      tap.local_x
      tap.local_y
      tap.global_x
      tap.global_y
      (pointer_kind_name tap.pointer_kind)
  | Pointer pointer ->
    Printf.sprintf
      "pointer(id=%Ld local=%g,%g global=%g,%g pointer=%s buttons=%d)"
      (ID.Input.Pointer_id.to_int64 pointer.pointer_id)
      pointer.local_x
      pointer.local_y
      pointer.global_x
      pointer.global_y
      (pointer_kind_name pointer.pointer_kind)
      pointer.buttons
  | Key key ->
    Printf.sprintf
      "key(logical=%Ld physical=%Ld action=%s modifiers=%d)"
      (ID.Input.Logical_key.to_int64 key.logical_key)
      (ID.Input.Physical_key.to_int64 key.physical_key)
      (key_action_name key.action)
      key.modifiers
  | Scroll { pixels; delta } -> Printf.sprintf "scroll(pixels=%g delta=%g)" pixels delta
  | Visible_range { first_index; last_exclusive } ->
    Printf.sprintf "visible_range(first=%Ld lastExclusive=%Ld)" first_index last_exclusive
  | Tab_selected key ->
    Printf.sprintf "tab_selected(%S)" (ID.Navigation.Page_key.to_string key)
  | Navigation_split_changed state ->
    Printf.sprintf
      "navigation_split_changed(visibility=%d column=%d)"
      state.visibility
      state.compact_column
  | Navigation_path_changed keys ->
    Printf.sprintf "navigation_path_changed(count=%d)" (List.length keys)
  | Host_response response ->
    Printf.sprintf
      "host_response(request=%Ld status=%s bytes=%d)"
      (ID.Host.Request_id.to_int64 response.request_id)
      (host_response_status_name response.status)
      (Bytes.length response.value)
  | Application_response response ->
    Printf.sprintf
      "application_response(request=%Ld bytes=%d)"
      response.request_id
      (Bytes.length response.payload)
  | Application_request_error response ->
    Printf.sprintf "application_request_error(request=%Ld)" response.request_id
  | Application_event payload ->
    Printf.sprintf "application_event(bytes=%d)" (Bytes.length payload)
  | Environment_changed environment ->
    Printf.sprintf
      "environment_changed(platform=%S locale=%S viewport=%gx%g)"
      environment.platform
      environment.locale
      environment.viewport_width
      environment.viewport_height
  | Native_event event ->
    Printf.sprintf
      "native_event(kind=%d version=%d event=%d bytes=%d)"
      (ID.Native_widget.Kind_id.to_int event.kind_id)
      event.version
      (ID.Native_widget.Event_id.to_int event.event_id)
      (Bytes.length event.payload)
;;

let trace_inbound_event_batch t (batch : Protocol.Inbound_event.batch) =
  trace_lazy t (fun () ->
    let output = Buffer.create 256 in
    Printf.bprintf
      output
      "[inbound-event-batch] direction=swiftui->ocaml epoch=%Ld events=%d"
      (ID.Runtime.Epoch.to_int64 batch.runtime_epoch)
      (List.length batch.events);
    List.iter
      (fun (event : Protocol.Inbound_event.t) ->
         Printf.bprintf
           output
           "\n  sequence=%Ld displayedRevision=%Ld node=%Ld handler=%Ld tag=%s payload=%s"
           (ID.Runtime.Event_sequence.to_int64 event.sequence)
           (ID.Runtime.Renderer_revision.to_int64 event.displayed_revision)
           (ID.Ui.Node_id.to_int64 event.node_id)
           (ID.Ui.Handler_id.to_int64 event.handler_id)
           (event_tag_name event.event_tag)
           (payload_summary event.payload))
      batch.events;
    Buffer.contents output)
;;

let environment_of_protocol (environment : Protocol.Inbound_event.environment)
  : Environment.snapshot
  =
  let edge_insets (insets : Protocol.Inbound_event.edge_insets) =
    Environment.
      { left = insets.left
      ; top = insets.top
      ; right = insets.right
      ; bottom = insets.bottom
      }
  in
  { viewport_width = environment.viewport_width
  ; viewport_height = environment.viewport_height
  ; device_pixel_ratio = environment.device_pixel_ratio
  ; text_scale = environment.text_scale
  ; brightness =
      (match environment.brightness with
       | Protocol.Inbound_event.Environment_light -> Environment.Light
       | Environment_dark -> Dark)
  ; platform = environment.platform
  ; locale = environment.locale
  ; safe_area = edge_insets environment.safe_area
  ; keyboard_insets = edge_insets environment.keyboard_insets
  ; accessible_navigation = environment.accessible_navigation
  ; bold_text = environment.bold_text
  ; invert_colors = environment.invert_colors
  ; disable_animations = environment.disable_animations
  ; reduced_motion = environment.reduced_motion
  ; high_contrast = environment.high_contrast
  ; orientation =
      (match environment.orientation with
       | Protocol.Inbound_event.Portrait -> Environment.Portrait
       | Landscape -> Landscape)
  ; pointer_kinds = environment.pointer_kinds
  }
;;

let exception_message exception_ =
  match exception_ with
  | Failure message | Invalid_argument message -> message
  | _ -> Printexc.to_string exception_
;;

type validated_control =
  | Validated_host_response of Host_effect.Private.Validated_response.t
  | Validated_application_input of
      Host_effect.Application_platform.Private.Validated_input.t
  | Validated_environment of Environment.snapshot
  | Validated_resync

type validated_input =
  { ui_events : Runtime.Event_dispatcher.Validated_batch.t option
  ; controls : validated_control list
  ; last_event_sequence : ID.Runtime.event_sequence option
  ; force_full_snapshot : bool
  }

let terminal t error =
  t.terminal_error <- Some error;
  error
;;

let active_error t = if t.is_shutdown then Some Shutdown else t.terminal_error

let logical_time t monotonic_now_ns =
  if Int64.compare monotonic_now_ns 0L < 0
  then Error (Invalid_state "monotonic time must be nonnegative")
  else if Int64.compare monotonic_now_ns t.last_monotonic_ns < 0
  then Error (Invalid_state "monotonic time moved backwards")
  else (
    try
      let span =
        monotonic_now_ns |> Core.Int63.of_int64_exn |> Core.Time_ns.Span.of_int63_ns
      in
      let target = Core.Time_ns.add t.logical_time_origin span in
      if Core.Time_ns.compare target t.logical_time_origin < 0
      then Error (Invalid_state "logical time overflow")
      else Ok target
    with
    | _ -> Error (Invalid_state "monotonic time is not representable"))
;;

let valid_environment (environment : Protocol.Inbound_event.environment) =
  let finite_nonnegative value = Float.is_finite value && Float.compare value 0. >= 0 in
  let valid_insets (insets : Protocol.Inbound_event.edge_insets) =
    finite_nonnegative insets.left
    && finite_nonnegative insets.top
    && finite_nonnegative insets.right
    && finite_nonnegative insets.bottom
  in
  finite_nonnegative environment.viewport_width
  && finite_nonnegative environment.viewport_height
  && finite_nonnegative environment.device_pixel_ratio
  && finite_nonnegative environment.text_scale
  && valid_insets environment.safe_area
  && valid_insets environment.keyboard_insets
;;

let is_application_platform_tag event_tag =
  event_tag = Protocol.Generated_protocol.Event_tag.application_response
  || event_tag = Protocol.Generated_protocol.Event_tag.application_request_error
  || event_tag = Protocol.Generated_protocol.Event_tag.application_event
;;

let validate_input t (batch : Protocol.Inbound_event.batch) =
  if not (ID.Runtime.Epoch.equal batch.runtime_epoch t.runtime_epoch)
  then
    if
      List.exists
        (fun (event : Protocol.Inbound_event.t) ->
           is_application_platform_tag event.event_tag)
        batch.events
    then Error (Application_platform_error "runtime epoch mismatch")
    else Error (Host_response_error "runtime epoch mismatch")
  else (
    let seen_host_responses = Hashtbl.create 8 in
    let seen_application_responses = Hashtbl.create 8 in
    let rec validate_events reversed_ui reversed_controls last_sequence force = function
      | [] ->
        let ui_events = List.rev reversed_ui in
        let ui_batch = Protocol.Inbound_event.{ batch with events = ui_events } in
        let validated_ui =
          match ui_events with
          | [] -> Ok None
          | _ ->
            (match Runtime.Event_dispatcher.validate_batch t.handlers ui_batch with
             | Ok validated -> Ok (Some validated)
             | Error error -> Error (Event_error error))
        in
        (match validated_ui with
         | Error _ as error -> error
         | Ok ui_events ->
           Ok
             { ui_events
             ; controls = List.rev reversed_controls
             ; last_event_sequence = last_sequence
             ; force_full_snapshot = force
             })
      | (event : Protocol.Inbound_event.t) :: rest ->
        if
          match last_sequence with
          | Some previous ->
            ID.Runtime.Event_sequence.compare event.sequence previous <= 0
          | None -> false
        then
          Error
            (Host_response_error
               (Printf.sprintf
                  "duplicate or out-of-order event sequence %Ld"
                  (ID.Runtime.Event_sequence.to_int64 event.sequence)))
        else (
          let next_sequence = Some event.sequence in
          let is_host_response =
            event.event_tag = Protocol.Generated_protocol.Event_tag.host_response
          in
          let is_environment =
            event.event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
          in
          let is_resync =
            event.event_tag = Protocol.Generated_protocol.Event_tag.resync_requested
          in
          let is_application_response =
            event.event_tag = Protocol.Generated_protocol.Event_tag.application_response
            || event.event_tag
               = Protocol.Generated_protocol.Event_tag.application_request_error
          in
          let is_application_event =
            event.event_tag = Protocol.Generated_protocol.Event_tag.application_event
          in
          if
            is_host_response
            || is_environment
            || is_resync
            || is_application_response
            || is_application_event
          then
            if
              (not (ID.Ui.Node_id.equal event.node_id ID.Ui.Node_id.zero))
              || (not (ID.Ui.Handler_id.equal event.handler_id ID.Ui.Handler_id.zero))
              || not
                   (ID.Runtime.Renderer_revision.equal
                      event.displayed_revision
                      t.displayed_revision)
            then
              if is_application_response || is_application_event
              then
                Error (Application_platform_error "malformed application control event")
              else Error (Host_response_error "malformed runtime control event")
            else if is_host_response
            then (
              match event.payload with
              | Host_response response ->
                if Hashtbl.mem seen_host_responses response.request_id
                then
                  Error
                    (Host_response_error
                       (Printf.sprintf
                          "duplicate host response ID %Ld"
                          (ID.Host.Request_id.to_int64 response.request_id)))
                else (
                  Hashtbl.add seen_host_responses response.request_id ();
                  match Host_effect.Private.validate_response t.host_effects response with
                  | Error message -> Error (Host_response_error message)
                  | Ok response ->
                    validate_events
                      reversed_ui
                      (Validated_host_response response :: reversed_controls)
                      next_sequence
                      force
                      rest)
              | _ -> Error (Host_response_error "malformed host response event"))
            else if is_application_response || is_application_event
            then (
              match
                Host_effect.Application_platform.Private.validate_input
                  t.application_platform
                  event.payload
              with
              | Error message -> Error (Application_platform_error message)
              | Ok validated ->
                (match
                   Host_effect.Application_platform.Private.Validated_input.request_id
                     validated
                 with
                 | Some request_id when Hashtbl.mem seen_application_responses request_id
                   ->
                   Error
                     (Application_platform_error
                        (Printf.sprintf
                           "duplicate application response ID %Ld"
                           request_id))
                 | Some request_id ->
                   Hashtbl.add seen_application_responses request_id ();
                   validate_events
                     reversed_ui
                     (Validated_application_input validated :: reversed_controls)
                     next_sequence
                     force
                     rest
                 | None ->
                   validate_events
                     reversed_ui
                     (Validated_application_input validated :: reversed_controls)
                     next_sequence
                     force
                     rest))
            else if is_environment
            then (
              match event.payload with
              | Environment_changed environment when valid_environment environment ->
                validate_events
                  reversed_ui
                  (Validated_environment (environment_of_protocol environment)
                   :: reversed_controls)
                  next_sequence
                  force
                  rest
              | _ -> Error (Host_response_error "malformed environment event"))
            else (
              match event.payload with
              | Unit ->
                validate_events
                  reversed_ui
                  (Validated_resync :: reversed_controls)
                  next_sequence
                  true
                  rest
              | _ -> Error (Host_response_error "malformed resync event"))
          else
            validate_events
              (event :: reversed_ui)
              reversed_controls
              next_sequence
              force
              rest)
    in
    validate_events [] [] t.last_event_sequence false batch.events)
;;

let execute_validated_input t validated =
  let execute_ui =
    match validated.ui_events with
    | None -> Ok ()
    | Some ui_events ->
      (match Runtime.Event_dispatcher.dispatch_validated t.handlers ui_events with
       | Ok () -> Ok ()
       | Error error -> Error (Event_error error))
  in
  match execute_ui with
  | Error _ as error -> error
  | Ok () ->
    let rec execute_controls = function
      | [] ->
        t.last_event_sequence <- validated.last_event_sequence;
        Ok ()
      | Validated_host_response response :: rest ->
        (match Host_effect.Private.resolve_validated t.host_effects response with
         | Ok () -> execute_controls rest
         | Error message -> Error (Host_response_error message))
      | Validated_application_input input :: rest ->
        (match
           Host_effect.Application_platform.Private.resolve_validated
             t.application_platform
             input
         with
         | Ok () -> execute_controls rest
         | Error message -> Error (Application_platform_error message))
      | Validated_environment environment :: rest ->
        ignore (Environment.Private.update t.environment environment);
        execute_controls rest
      | Validated_resync :: rest -> execute_controls rest
    in
    execute_controls validated.controls
;;

let reserve_presentation_id t =
  if t.presentation_sequence_exhausted
  then Error (Invalid_state "presentation ID counter exhausted")
  else (
    let presentation_id = t.next_presentation_id in
    if
      ID.Runtime.Presentation_id.equal
        presentation_id
        ID.Runtime.Presentation_id.max_value
    then t.presentation_sequence_exhausted <- true
    else t.next_presentation_id <- ID.Runtime.Presentation_id.succ presentation_id;
    Ok presentation_id)
;;

let pump t ~monotonic_now_ns ?events () =
  Option.iter (trace_inbound_event_batch t) events;
  match active_error t with
  | Some error -> Error error
  | None when t.draining -> Error (Invalid_state "runtime is draining")
  | None ->
    (match t.pending_presentation with
     | Some _ -> Error (Invalid_state "a presentation is already pending")
     | None ->
       (match logical_time t monotonic_now_ns with
        | Error _ as error -> error
        | Ok logical_time ->
          let validated_input, recoverable_error =
            match events with
            | None -> None, None
            | Some events ->
              (match validate_input t events with
               | Ok validated -> Some validated, None
               | Error error -> None, Some error)
          in
          let force_full_snapshot =
            t.force_full_snapshot_next
            ||
            match validated_input with
            | Some validated -> validated.force_full_snapshot
            | None -> false
          in
          (try
             Bonsai_runtime_adapter.advance_clock t.bonsai ~to_:logical_time;
             ignore (Bonsai.Time_source.now t.time_source);
             t.last_monotonic_ns <- monotonic_now_ns;
             (match validated_input with
              | None -> ()
              | Some validated ->
                (match execute_validated_input t validated with
                 | Ok () -> ()
                 | Error error -> raise (Failure (error_to_string error))));
             t.before_flush ~schedule:(fun scheduled_effect ->
               Queue.add scheduled_effect t.pending_effects.pending_effects);
             drain_effects t;
             let flush_started = now_ns () in
             Bonsai_runtime_adapter.flush t.bonsai;
             flush_before_display t;
             let bonsai_flush_ns = elapsed_ns flush_started in
             let event_batch_size =
               match events with
               | None -> 0
               | Some events -> List.length events.Protocol.Inbound_event.events
             in
             match
               produce_candidate t ~event_batch_size ~bonsai_flush_ns ~force_full_snapshot
             with
             | Error error -> Error (terminal t error)
             | Ok candidate ->
               (match reserve_presentation_id t with
                | Error error -> Error (terminal t error)
                | Ok presentation_id ->
                  let pending =
                    { presentation_id
                    ; renderer_revision = candidate.renderer_revision
                    ; candidate_tree = candidate.candidate_tree
                    ; candidate_handler_frame = candidate.candidate_handler_frame
                    ; candidate_application_theme = candidate.candidate_application_theme
                    ; prepared_host_operations = candidate.prepared_host_operations
                    ; prepared_application_operations =
                        candidate.prepared_application_operations
                    ; emitted_frame = candidate.emitted_frame
                    }
                  in
                  t.pending_presentation <- Some pending;
                  Ok
                    { presentation_id
                    ; renderer_revision = candidate.renderer_revision
                    ; frame = candidate.emitted_frame
                    ; recoverable_error
                    })
           with
           | exception_ ->
             let error = Invalid_state (exception_message exception_) in
             Error (terminal t error))))
;;

(* Terminal transport work never commits a renderer revision or lifecycles. *)
let shutdown_pump t ~monotonic_now_ns ?events () =
  match active_error t with
  | Some error -> Error error
  | None ->
    (match logical_time t monotonic_now_ns with
     | Error _ as error -> error
     | Ok logical_time ->
       let validated =
         match events with
         | None -> Ok None
         | Some (batch : Protocol.Inbound_event.batch) ->
           if
             List.exists
               (fun (event : Protocol.Inbound_event.t) ->
                  not (is_application_platform_tag event.event_tag))
               batch.events
           then
             Error (Application_platform_error "shutdown accepts only application input")
           else Result.map Option.some (validate_input t batch)
       in
       (match validated with
        | Error _ as error -> error
        | Ok validated ->
          (try
             if not t.draining
             then (
               t.draining <- true;
               t.pending_presentation <- None;
               Host_effect.Application_platform.Private.begin_shutdown
                 t.application_platform;
               Host_effect.Private.shutdown t.host_effects);
             Bonsai_runtime_adapter.advance_clock t.bonsai ~to_:logical_time;
             t.last_monotonic_ns <- monotonic_now_ns;
             Option.iter
               (fun input ->
                  match execute_validated_input t input with
                  | Ok () -> ()
                  | Error error -> failwith (error_to_string error))
               validated;
             t.before_flush ~schedule:(fun scheduled ->
               Queue.add scheduled t.pending_effects.pending_effects);
             drain_effects t;
             Bonsai_runtime_adapter.flush t.bonsai;
             flush_before_display t;
             (* One request per native turn bounds Swift's serial shutdown provider.
              Uncommitted application operations from a pending frame stay queued. *)
             let prepared =
               Host_effect.Application_platform.prepare_operations
                 ~maximum_count:1
                 t.application_platform
             in
             let operations =
               Host_effect.Application_platform.Prepared_operations.operations prepared
             in
             let buffer = Buffer.create 64 in
             Buffer.add_string buffer "BSSD";
             Buffer.add_int32_le buffer (Int32.of_int (List.length operations));
             List.iter
               (function
                 | Protocol.Wire_frame.Application_request { request_id; payload } ->
                   Buffer.add_int64_le buffer request_id;
                   Buffer.add_int32_le buffer (Int32.of_int (Bytes.length payload));
                   Buffer.add_bytes buffer payload
                 | _ -> failwith "unexpected shutdown transport operation")
               operations;
             match
               Host_effect.Application_platform.commit_operations
                 t.application_platform
                 prepared
             with
             | Error message -> Error (terminal t (Invalid_state message))
             | Ok () -> Ok (Bytes.of_string (Buffer.contents buffer), t.displayed_revision)
           with
           | exception_ ->
             Error (terminal t (Invalid_state (exception_message exception_))))))
;;

let exact_pending t ~presentation_id ~renderer_revision =
  match t.pending_presentation with
  | None -> Error (Invalid_state "no presentation is pending")
  | Some pending ->
    if not (ID.Runtime.Presentation_id.equal pending.presentation_id presentation_id)
    then Error (Invalid_state "presentation ID does not match the pending token")
    else if
      not (ID.Runtime.Renderer_revision.equal pending.renderer_revision renderer_revision)
    then Error (Invalid_state "renderer revision does not match the pending token")
    else Ok pending
;;

let retain_list_scroll_snapshots handlers handler_frame patch =
  let module H = Runtime.Handler_registry in
  if Runtime.Frame_patch.kind patch = Runtime.Frame_patch.Full_snapshot
  then H.clear_list_scroll_completions handlers;
  List.iter
    (function
      | Runtime.Frame_patch.Operation.Drop_node id ->
        H.dispose_list_scroll_owner handlers id
      | Create_node { node_id; widget; _ } | Update_node { node_id; widget } ->
        let (Av view) = Ui.View.Private.view widget in
        (match view.node with
         | Native_list { scroll_request = Some (token, _, _, _, _); _ } ->
           (match H.Frame.find_list_scroll_completion handler_frame node_id with
            | Some entry ->
              H.retain_list_scroll_completion
                handlers
                ~revision:(H.Frame.revision handler_frame)
                ~token
                entry
            | None -> invalid_arg "List scroll request has no completion binding")
         | _ -> ())
      | _ -> ())
    (Runtime.Frame_patch.operations patch)
;;

let presentation_succeeded t ~presentation_id ~renderer_revision ~monotonic_now_ns =
  match active_error t with
  | Some error -> Error error
  | None ->
    (match exact_pending t ~presentation_id ~renderer_revision with
     | Error _ as error -> error
     | Ok pending ->
       (match logical_time t monotonic_now_ns with
        | Error _ as error -> error
        | Ok logical_time ->
          Option.iter
            (fun _ ->
               trace_lazy t (fun () ->
                 Printf.sprintf
                   "[presentation-ack] presentationId=%Ld revision=%Ld \
                    direction=swiftui->ocaml"
                   (ID.Runtime.Presentation_id.to_int64 presentation_id)
                   (ID.Runtime.Renderer_revision.to_int64 renderer_revision)))
            pending.emitted_frame;
          let fail_fatal error = Error (terminal t error) in
          (match
             Host_effect.commit_operations t.host_effects pending.prepared_host_operations
           with
           | Error message -> fail_fatal (Invalid_state message)
           | Ok () ->
             (match
                Host_effect.Application_platform.commit_operations
                  t.application_platform
                  pending.prepared_application_operations
              with
              | Error message -> fail_fatal (Invalid_state message)
              | Ok () ->
                let commit_handler =
                  match pending.emitted_frame, pending.candidate_handler_frame with
                  | None, None ->
                    Ok (t.displayed_revision, t.displayed_handler_frame, false)
                  | Some frame, Some handler_frame ->
                    (match Runtime.Handler_registry.install t.handlers handler_frame with
                     | Error error -> Error (Runtime_error error)
                     | Ok () ->
                       (match
                          Runtime.Handler_registry.mark_displayed_revision
                            t.handlers
                            ~revision:renderer_revision
                        with
                        | Error error -> Error (Runtime_error error)
                        | Ok () ->
                          retain_list_scroll_snapshots
                            t.handlers
                            handler_frame
                            frame.frame_patch;
                          Ok (renderer_revision, Some handler_frame, true)))
                  | None, Some _ | Some _, None ->
                    Error
                      (Invalid_state
                         "candidate frame and handler metadata are inconsistent")
                in
                (match commit_handler with
                 | Error error -> fail_fatal error
                 | Ok (displayed_revision, displayed_handler_frame, retire_handlers) ->
                   t.displayed_tree <- Some pending.candidate_tree;
                   t.displayed_handler_frame <- displayed_handler_frame;
                   t.displayed_application_theme
                   <- Some pending.candidate_application_theme;
                   t.displayed_revision <- displayed_revision;
                   if retire_handlers
                   then
                     Runtime.Handler_registry.retire_superseded
                       t.handlers
                       ~displayed_revision;
                   (try
                      Bonsai_runtime_adapter.advance_clock t.bonsai ~to_:logical_time;
                      ignore (Bonsai.Time_source.now t.time_source);
                      t.last_monotonic_ns <- monotonic_now_ns;
                      t.pending_presentation <- None;
                      t.force_full_snapshot_next <- false;
                      let lifecycle_started = now_ns () in
                      Bonsai_runtime_adapter.trigger_lifecycles t.bonsai;
                      t.last_lifecycle_ns <- elapsed_ns lifecycle_started;
                      Ok ()
                    with
                    | exception_ ->
                      fail_fatal (Lifecycle_error (exception_message exception_))))))))
;;

let presentation_rejected t ~presentation_id ~renderer_revision ~reason:_ =
  match active_error t with
  | Some error -> Error error
  | None ->
    (match exact_pending t ~presentation_id ~renderer_revision with
     | Error _ as error -> error
     | Ok _ ->
       trace_lazy t (fun () ->
         Printf.sprintf
           "[presentation-rejected] presentationId=%Ld revision=%Ld"
           (ID.Runtime.Presentation_id.to_int64 presentation_id)
           (ID.Runtime.Renderer_revision.to_int64 renderer_revision));
       t.pending_presentation <- None;
       t.force_full_snapshot_next <- true;
       Ok ())
;;

let shutdown ?(application_error = Host_effect.Application_platform.Shutdown) t =
  if not t.is_shutdown
  then (
    t.before_shutdown ();
    t.is_shutdown <- true;
    Host_effect.Private.shutdown t.host_effects;
    Host_effect.Application_platform.Private.shutdown
      t.application_platform
      application_error;
    (try
       drain_effects t;
       Bonsai_runtime_adapter.flush t.bonsai
     with
     | _ -> ());
    Queue.clear t.pending_effects.pending_effects;
    Queue.clear t.pending_effects.pending_before_display;
    Runtime.Handler_registry.clear t.handlers;
    t.displayed_handler_frame <- None;
    t.displayed_application_theme <- None;
    Bonsai_runtime_adapter.shutdown t.bonsai)
;;

let is_shutdown t = t.is_shutdown

module For_testing = struct
  let create_widget_component
        ?trace
        ?before_flush
        ?before_shutdown
        ~runtime_epoch
        ~time_source
        component
    =
    let theme = Ui.Theme.create () in
    create
      ?trace
      ?before_flush
      ?before_shutdown
      ~runtime_epoch
      ~time_source
      (fun handlers graph ->
         Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
           View.create ~theme ~body:(Ui.View.Body.static body)))
  ;;

  let runtime_epoch t = t.runtime_epoch
  let revision t = t.displayed_revision

  let snapshot t =
    match t.pending_presentation with
    | Some pending -> Some (Runtime.Mounted_tree.snapshot pending.candidate_tree)
    | None -> Option.map Runtime.Mounted_tree.snapshot t.displayed_tree
  ;;

  let environment t = Environment.Private.current t.environment
  let pending_host_effect_count t = Host_effect.Private.pending_count t.host_effects

  let pending_application_request_count t =
    Host_effect.Application_platform.Private.pending_count t.application_platform
  ;;

  let retained_handler_frame_count t =
    Runtime.Handler_registry.retained_frame_count t.handlers
  ;;

  let set_next_presentation_id t value =
    t.next_presentation_id <- value;
    t.presentation_sequence_exhausted <- false
  ;;

  let set_next_renderer_revision t value = t.next_renderer_revision <- value
end
