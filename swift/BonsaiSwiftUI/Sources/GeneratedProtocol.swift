// Generated from protocol/schema.sexp. Do not edit.

public enum ProtocolVersion {
  public static let protocolMajor = 4
  public static let protocolMinor = 0
}

public enum ProtocolLimits {
  public static let headerBytes = 48
  public static let maxFrameBytes = 16777216
  public static let maxStringBytes = 1048576
  public static let maxApplicationPayloadBytes = 1048576
  public static let maxOperations = 1000000
  public static let maxNodes = 1000000
}

public enum FrameKindId {
    public static let `handshake` = 1
    public static let `fullSnapshot` = 2
    public static let `incrementalFrame` = 3
    public static let `eventBatch` = 4
    public static let `runtimeError` = 5

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "handshake"
        case 2: return "full_snapshot"
        case 3: return "incremental_frame"
        case 4: return "event_batch"
        case 5: return "runtime_error"
        default: return nil
        }
    }
}

public enum OperationId {
    public static let `beginFrame` = 1
    public static let `createNode` = 2
    public static let `updateProps` = 3
    public static let `updateEventBindings` = 4
    public static let `setChildren` = 5
    public static let `setRoot` = 6
    public static let `dropNode` = 7
    public static let `hostRequest` = 8
    public static let `runtimeNotification` = 9
    public static let `endFrame` = 10
    public static let `applicationRequest` = 11
    public static let `setApplicationTheme` = 12

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "begin_frame"
        case 2: return "create_node"
        case 3: return "update_props"
        case 4: return "update_event_bindings"
        case 5: return "set_children"
        case 6: return "set_root"
        case 7: return "drop_node"
        case 8: return "host_request"
        case 9: return "runtime_notification"
        case 10: return "end_frame"
        case 11: return "application_request"
        case 12: return "set_application_theme"
        default: return nil
        }
    }
}

public enum NodeKindId {
    public static let `empty` = 1
    public static let `text` = 2
    public static let `richText` = 3
    public static let `symbol` = 4
    public static let `image` = 5
    public static let `textEditor` = 6
    public static let `textField` = 47
    public static let `secureField` = 49
    public static let `collectionCatalog` = 7
    public static let `collectionWindow` = 8
    public static let `scroll` = 9
    public static let `progress` = 10
    public static let `ignoresSafeArea` = 11
    public static let `safeAreaPadding` = 12
    public static let `navigationStack` = 13
    public static let `navigationDestination` = 14
    public static let `navigationSplit` = 15
    public static let `flow` = 56
    public static let `label` = 57
    public static let `badge` = 58
    public static let `datePicker` = 59
    public static let `timePicker` = 60
    public static let `menu` = 61
    public static let `removal` = 78
    public static let `refresh` = 77
    public static let `scrollTargets` = 62
    public static let `help` = 63
    public static let `popover` = 72
    public static let `sheet` = 73
    public static let `toolbar` = 74
    public static let `scrollSections` = 75
    public static let `scrollSection` = 76
    public static let `row` = 16
    public static let `column` = 17
    public static let `weightedRow` = 18
    public static let `stack` = 19
    public static let `weightedColumn` = 20
    public static let `padding` = 21
    public static let `frame` = 22
    public static let `spacer` = 23
    public static let `layoutPriority` = 24
    public static let `offset` = 25
    public static let `background` = 26
    public static let `clip` = 27
    public static let `opacity` = 28
    public static let `projectionEffect` = 29
    public static let `tabs` = 31
    public static let `tab` = 40
    public static let `morphingSurface` = 41
    public static let `swipeActions` = 42
    public static let `swipeAction` = 43
    public static let `toggle` = 44
    public static let `gesture` = 48
    public static let `focusScope` = 51
    public static let `hoverRegion` = 52
    public static let `keyboardListener` = 53
    public static let `button` = 54
    public static let `controlSize` = 55
    public static let `semantics` = 64
    public static let `overlay` = 65
    public static let `theme` = 69
    public static let `animatedOpacity` = 71
    public static let `divider` = 105
    public static let `groupBox` = 106
    public static let `reservedNodeKind107` = 107
    public static let `picker` = 116
    public static let `slider` = 45
    public static let `rangeSlider` = 46
    public static let `nativeWidget` = 128
    public static let `table` = 79
    public static let `disclosureGroup` = 133

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "empty"
        case 2: return "text"
        case 3: return "rich_text"
        case 4: return "symbol"
        case 5: return "image"
        case 6: return "text_editor"
        case 47: return "text_field"
        case 49: return "secure_field"
        case 7: return "collection_catalog"
        case 8: return "collection_window"
        case 9: return "scroll"
        case 10: return "progress"
        case 11: return "ignores_safe_area"
        case 12: return "safe_area_padding"
        case 13: return "navigation_stack"
        case 14: return "navigation_destination"
        case 15: return "navigation_split"
        case 56: return "flow"
        case 57: return "label"
        case 58: return "badge"
        case 59: return "date_picker"
        case 60: return "time_picker"
        case 61: return "menu"
        case 78: return "removal"
        case 77: return "refresh"
        case 62: return "scroll_targets"
        case 63: return "help"
        case 72: return "popover"
        case 73: return "sheet"
        case 74: return "toolbar"
        case 75: return "scroll_sections"
        case 76: return "scroll_section"
        case 16: return "row"
        case 17: return "column"
        case 18: return "weighted_row"
        case 19: return "stack"
        case 20: return "weighted_column"
        case 21: return "padding"
        case 22: return "frame"
        case 23: return "spacer"
        case 24: return "layout_priority"
        case 25: return "offset"
        case 26: return "background"
        case 27: return "clip"
        case 28: return "opacity"
        case 29: return "projection_effect"
        case 31: return "tabs"
        case 40: return "tab"
        case 41: return "morphing_surface"
        case 42: return "swipe_actions"
        case 43: return "swipe_action"
        case 44: return "toggle"
        case 48: return "gesture"
        case 51: return "focus_scope"
        case 52: return "hover_region"
        case 53: return "keyboard_listener"
        case 54: return "button"
        case 55: return "control_size"
        case 64: return "semantics"
        case 65: return "overlay"
        case 69: return "theme"
        case 71: return "animated_opacity"
        case 105: return "divider"
        case 106: return "group_box"
        case 107: return "reserved_node_kind_107"
        case 116: return "picker"
        case 45: return "slider"
        case 46: return "range_slider"
        case 128: return "native_widget"
        case 79: return "table"
        case 133: return "disclosure_group"
        default: return nil
        }
    }
}

public enum EventTagId {
    public static let `press` = 1
    public static let `longPress` = 2
    public static let `tap` = 3
    public static let `doubleTap` = 4
    public static let `pointerEnter` = 5
    public static let `pointerLeave` = 6
    public static let `pointerDown` = 7
    public static let `pointerUp` = 8
    public static let `key` = 9
    public static let `focusChanged` = 10
    public static let `textEdit` = 11
    public static let `textSubmit` = 12
    public static let `scrollNotification` = 13
    public static let `visibleRangeChanged` = 14
    public static let `animationCompleted` = 15
    public static let `layoutObserved` = 17
    public static let `valueChanged` = 18
    public static let `hostResponse` = 19
    public static let `environmentChanged` = 20
    public static let `nativeEvent` = 21
    public static let `semanticsAction` = 22
    public static let `resyncRequested` = 23
    public static let `textLimitReached` = 24
    public static let `applicationResponse` = 25
    public static let `applicationRequestError` = 26
    public static let `applicationEvent` = 27
    public static let `navigationDestinationSelected` = 28
    public static let `radioSelected` = 29
    public static let `pickerSelected` = 53
    public static let `menuAction` = 54
    public static let `scrollPositionChanged` = 55
    public static let `refreshRequest` = 56
    public static let `removalRequested` = 57
    public static let `removalCompleted` = 58
    public static let `sliderChanged` = 30
    public static let `sliderChangeEnd` = 31
    public static let `rangeSliderChanged` = 32
    public static let `rangeSliderChangeEnd` = 33
    public static let `tableSortRequested` = 37
    public static let `tableRowSelected` = 38
    public static let `civilDateChanged` = 46
    public static let `civilTimeChanged` = 47
    public static let `navigationPathChanged` = 50
    public static let `navigationSplitChanged` = 51
    public static let `tabSelected` = 52

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "press"
        case 2: return "long_press"
        case 3: return "tap"
        case 4: return "double_tap"
        case 5: return "pointer_enter"
        case 6: return "pointer_leave"
        case 7: return "pointer_down"
        case 8: return "pointer_up"
        case 9: return "key"
        case 10: return "focus_changed"
        case 11: return "text_edit"
        case 12: return "text_submit"
        case 13: return "scroll_notification"
        case 14: return "visible_range_changed"
        case 15: return "animation_completed"
        case 17: return "layout_observed"
        case 18: return "value_changed"
        case 19: return "host_response"
        case 20: return "environment_changed"
        case 21: return "native_event"
        case 22: return "semantics_action"
        case 23: return "resync_requested"
        case 24: return "text_limit_reached"
        case 25: return "application_response"
        case 26: return "application_request_error"
        case 27: return "application_event"
        case 28: return "navigation_destination_selected"
        case 29: return "radio_selected"
        case 53: return "picker_selected"
        case 54: return "menu_action"
        case 55: return "scroll_position_changed"
        case 56: return "refresh_request"
        case 57: return "removal_requested"
        case 58: return "removal_completed"
        case 30: return "slider_changed"
        case 31: return "slider_change_end"
        case 32: return "range_slider_changed"
        case 33: return "range_slider_change_end"
        case 37: return "table_sort_requested"
        case 38: return "table_row_selected"
        case 46: return "civil_date_changed"
        case 47: return "civil_time_changed"
        case 50: return "navigation_path_changed"
        case 51: return "navigation_split_changed"
        case 52: return "tab_selected"
        default: return nil
        }
    }
}

public enum HostRequestId {
    public static let `clipboardRead` = 1
    public static let `clipboardWrite` = 2
    public static let `openUrl` = 3
    public static let `pickFiles` = 4
    public static let `saveFile` = 5
    public static let `requestFocus` = 6
    public static let `clearFocus` = 7
    public static let `scrollTo` = 8
    public static let `setWindowTitle` = 9
    public static let `setWindowSize` = 10
    public static let `showNativeMenu` = 11
    public static let `hapticFeedback` = 12
    public static let `platformInformation` = 13
    public static let `measureLayout` = 14
    public static let `showNotice` = 15
    public static let `pickDate` = 16
    public static let `pickDateRange` = 17
    public static let `pickTime` = 18

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "clipboard_read"
        case 2: return "clipboard_write"
        case 3: return "open_url"
        case 4: return "pick_files"
        case 5: return "save_file"
        case 6: return "request_focus"
        case 7: return "clear_focus"
        case 8: return "scroll_to"
        case 9: return "set_window_title"
        case 10: return "set_window_size"
        case 11: return "show_native_menu"
        case 12: return "haptic_feedback"
        case 13: return "platform_information"
        case 14: return "measure_layout"
        case 15: return "show_notice"
        case 16: return "pick_date"
        case 17: return "pick_date_range"
        case 18: return "pick_time"
        default: return nil
        }
    }
}

public enum RuntimeErrorId {
    public static let `protocolError` = 1
    public static let `revisionMismatch` = 2
    public static let `duplicateKey` = 3
    public static let `unsupportedNodeKind` = 4
    public static let `invalidProp` = 5
    public static let `handlerMissing` = 6
    public static let `staleEvent` = 7
    public static let `hostEffectFailure` = 8
    public static let `ocamlException` = 9
    public static let `swiftuiRendererException` = 10
    public static let `lifecycleException` = 11
    public static let `nativeLibraryLoadingError` = 12

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "protocol_error"
        case 2: return "revision_mismatch"
        case 3: return "duplicate_key"
        case 4: return "unsupported_node_kind"
        case 5: return "invalid_prop"
        case 6: return "handler_missing"
        case 7: return "stale_event"
        case 8: return "host_effect_failure"
        case 9: return "ocaml_exception"
        case 10: return "swiftui_renderer_exception"
        case 11: return "lifecycle_exception"
        case 12: return "native_library_loading_error"
        default: return nil
        }
    }
}

public enum CommonPropId {
    public static let `testId` = 1
    public static let `semantics` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "test_id"
        case 2: return "semantics"
        default: return nil
        }
    }
}

public enum ScrollSectionsPropId {
    public static let `vertical` = 1
    public static let `pinHeaders` = 2
    public static let `pinFooters` = 3
    public static let `spacing` = 4
    public static let `showsIndicators` = 5
    public static let `initialAnchor` = 6

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "vertical"
        case 2: return "pin_headers"
        case 3: return "pin_footers"
        case 4: return "spacing"
        case 5: return "shows_indicators"
        case 6: return "initial_anchor"
        default: return nil
        }
    }
}

public enum ScrollSectionPropId {
    public static let `hasHeader` = 1
    public static let `hasFooter` = 2
    public static let `heroHeight` = 3
    public static let `stretch` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "has_header"
        case 2: return "has_footer"
        case 3: return "hero_height"
        case 4: return "stretch"
        default: return nil
        }
    }
}

public enum ToolbarPropId {
    public static let `placements` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "placements"
        default: return nil
        }
    }
}

public enum SheetPropId {
    public static let `presented` = 1
    public static let `fullscreen` = 2
    public static let `detents` = 3
    public static let `initial` = 4
    public static let `interactive` = 5
    public static let `indicator` = 6
    public static let `sizing` = 7

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "presented"
        case 2: return "fullscreen"
        case 3: return "detents"
        case 4: return "initial"
        case 5: return "interactive"
        case 6: return "indicator"
        case 7: return "sizing"
        default: return nil
        }
    }
}

public enum PopoverPropId {
    public static let `presented` = 1
    public static let `edge` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "presented"
        case 2: return "edge"
        default: return nil
        }
    }
}

public enum HelpPropId {
    public static let `message` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "message"
        default: return nil
        }
    }
}

public enum TogglePropId {
    public static let `value` = 1
    public static let `enabled` = 2
    public static let `style` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "value"
        case 2: return "enabled"
        case 3: return "style"
        default: return nil
        }
    }
}

public enum SwipeActionsPropId {
    public static let `enabled` = 1
    public static let `vertical` = 2
    public static let `closeOnScroll` = 3
    public static let `group` = 4
    public static let `closeWhenOpened` = 5
    public static let `closeWhenTapped` = 6

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "enabled"
        case 2: return "vertical"
        case 3: return "close_on_scroll"
        case 4: return "group"
        case 5: return "close_when_opened"
        case 6: return "close_when_tapped"
        default: return nil
        }
    }
}

public enum SwipeActionPropId {
    public static let `title` = 1
    public static let `side` = 2
    public static let `enabled` = 3
    public static let `role` = 4
    public static let `extent` = 5
    public static let `background` = 6
    public static let `autoClose` = 7
    public static let `fullSwipe` = 8

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "title"
        case 2: return "side"
        case 3: return "enabled"
        case 4: return "role"
        case 5: return "extent"
        case 6: return "background"
        case 7: return "auto_close"
        case 8: return "full_swipe"
        default: return nil
        }
    }
}

public enum MorphingSurfacePropId {
    public static let `expanded` = 1
    public static let `expandDurationMs` = 2
    public static let `collapseDurationMs` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "expanded"
        case 2: return "expand_duration_ms"
        case 3: return "collapse_duration_ms"
        default: return nil
        }
    }
}

public enum TabsPropId {
    public static let `selection` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "selection"
        default: return nil
        }
    }
}

public enum TabPropId {
    public static let `pageKey` = 1
    public static let `title` = 2
    public static let `symbol` = 3
    public static let `badge` = 4
    public static let `accessibilityLabel` = 5

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "page_key"
        case 2: return "title"
        case 3: return "symbol"
        case 4: return "badge"
        case 5: return "accessibility_label"
        default: return nil
        }
    }
}

public enum NavigationSplitPropId {
    public static let `visibility` = 1
    public static let `compactColumn` = 2
    public static let `selectionKey` = 3
    public static let `sidebarTitle` = 4
    public static let `contentTitle` = 5
    public static let `detailTitle` = 6

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "visibility"
        case 2: return "compact_column"
        case 3: return "selection_key"
        case 4: return "sidebar_title"
        case 5: return "content_title"
        case 6: return "detail_title"
        default: return nil
        }
    }
}

public enum NavigationStackPropId {
    public static let `title` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "title"
        default: return nil
        }
    }
}

public enum NavigationDestinationPropId {
    public static let `pageKey` = 1
    public static let `title` = 2
    public static let `canPop` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "page_key"
        case 2: return "title"
        case 3: return "can_pop"
        default: return nil
        }
    }
}

public enum TextPropId {
    public static let `value` = 1
    public static let `textStyle` = 2
    public static let `textAlign` = 3
    public static let `lineLimit` = 4
    public static let `truncation` = 5

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "value"
        case 2: return "text_style"
        case 3: return "text_align"
        case 4: return "line_limit"
        case 5: return "truncation"
        default: return nil
        }
    }
}

public enum RichTextPropId {
    public static let `spans` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "spans"
        default: return nil
        }
    }
}

public enum SymbolPropId {
    public static let `name` = 1
    public static let `size` = 2
    public static let `color` = 3
    public static let `rendering` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "name"
        case 2: return "size"
        case 3: return "color"
        case 4: return "rendering"
        default: return nil
        }
    }
}

public enum ScrollPropId {
    public static let `vertical` = 1
    public static let `showsIndicators` = 2
    public static let `fillViewport` = 3
    public static let `initialAnchor` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "vertical"
        case 2: return "shows_indicators"
        case 3: return "fill_viewport"
        case 4: return "initial_anchor"
        default: return nil
        }
    }
}

public enum CollectionCatalogPropId {
    public static let `keys` = 1
    public static let `defaultExtent` = 2
    public static let `overrides` = 3
    public static let `overscan` = 4
    public static let `expandDurationMs` = 5
    public static let `collapseDurationMs` = 6
    public static let `vertical` = 7
    public static let `initialAnchor` = 8
    public static let `initialKey` = 9
    public static let `measurementRevision` = 10

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "keys"
        case 2: return "default_extent"
        case 3: return "overrides"
        case 4: return "overscan"
        case 5: return "expand_duration_ms"
        case 6: return "collapse_duration_ms"
        case 7: return "vertical"
        case 8: return "initial_anchor"
        case 9: return "initial_key"
        case 10: return "measurement_revision"
        default: return nil
        }
    }
}

public enum CollectionWindowPropId {
    public static let `firstIndex` = 1
    public static let `keys` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "first_index"
        case 2: return "keys"
        default: return nil
        }
    }
}

public enum TextFieldPropId {
    public static let `sessionId` = 1
    public static let `documentRevision` = 2
    public static let `acceptedLocalRevision` = 3
    public static let `updateMode` = 4
    public static let `value` = 5
    public static let `enabled` = 6
    public static let `readOnly` = 7
    public static let `submitOnReturn` = 8
    public static let `maxUtf8Bytes` = 9
    public static let `label` = 10
    public static let `prompt` = 11
    public static let `keyboard` = 12
    public static let `submitLabel` = 13
    public static let `autofocus` = 14

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "session_id"
        case 2: return "document_revision"
        case 3: return "accepted_local_revision"
        case 4: return "update_mode"
        case 5: return "value"
        case 6: return "enabled"
        case 7: return "read_only"
        case 8: return "submit_on_return"
        case 9: return "max_utf8_bytes"
        case 10: return "label"
        case 11: return "prompt"
        case 12: return "keyboard"
        case 13: return "submit_label"
        case 14: return "autofocus"
        default: return nil
        }
    }
}

public enum SecureFieldPropId {
    public static let `sessionId` = 1
    public static let `documentRevision` = 2
    public static let `acceptedLocalRevision` = 3
    public static let `updateMode` = 4
    public static let `value` = 5
    public static let `enabled` = 6
    public static let `readOnly` = 7
    public static let `submitOnReturn` = 8
    public static let `maxUtf8Bytes` = 9
    public static let `label` = 10
    public static let `prompt` = 11
    public static let `keyboard` = 12
    public static let `submitLabel` = 13
    public static let `autofocus` = 14

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "session_id"
        case 2: return "document_revision"
        case 3: return "accepted_local_revision"
        case 4: return "update_mode"
        case 5: return "value"
        case 6: return "enabled"
        case 7: return "read_only"
        case 8: return "submit_on_return"
        case 9: return "max_utf8_bytes"
        case 10: return "label"
        case 11: return "prompt"
        case 12: return "keyboard"
        case 13: return "submit_label"
        case 14: return "autofocus"
        default: return nil
        }
    }
}

public enum TextEditorPropId {
    public static let `sessionId` = 1
    public static let `documentRevision` = 2
    public static let `acceptedLocalRevision` = 3
    public static let `updateMode` = 4
    public static let `value` = 5
    public static let `enabled` = 6
    public static let `readOnly` = 7
    public static let `submitOnReturn` = 8
    public static let `maxUtf8Bytes` = 9

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "session_id"
        case 2: return "document_revision"
        case 3: return "accepted_local_revision"
        case 4: return "update_mode"
        case 5: return "value"
        case 6: return "enabled"
        case 7: return "read_only"
        case 8: return "submit_on_return"
        case 9: return "max_utf8_bytes"
        default: return nil
        }
    }
}

public enum ImagePropId {
    public static let `source` = 1
    public static let `sizing` = 2
    public static let `scale` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "source"
        case 2: return "sizing"
        case 3: return "scale"
        default: return nil
        }
    }
}

public enum FlowPropId {
    public static let `spacing` = 1
    public static let `lineSpacing` = 2
    public static let `alignment` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "spacing"
        case 2: return "line_spacing"
        case 3: return "alignment"
        default: return nil
        }
    }
}

public enum RowPropId {
    public static let `spacing` = 1
    public static let `alignment` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "spacing"
        case 2: return "alignment"
        default: return nil
        }
    }
}

public enum ColumnPropId {
    public static let `spacing` = 1
    public static let `alignment` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "spacing"
        case 2: return "alignment"
        default: return nil
        }
    }
}

public enum WeightedRowPropId {
    public static let `spacing` = 1
    public static let `alignment` = 2
    public static let `items` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "spacing"
        case 2: return "alignment"
        case 3: return "items"
        default: return nil
        }
    }
}

public enum WeightedColumnPropId {
    public static let `spacing` = 1
    public static let `alignment` = 2
    public static let `items` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "spacing"
        case 2: return "alignment"
        case 3: return "items"
        default: return nil
        }
    }
}

public enum StackPropId {
    public static let `alignment` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "alignment"
        default: return nil
        }
    }
}

public enum LayoutPriorityPropId {
    public static let `priority` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "priority"
        default: return nil
        }
    }
}

public enum OffsetPropId {
    public static let `x` = 1
    public static let `y` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "x"
        case 2: return "y"
        default: return nil
        }
    }
}

public enum PaddingPropId {
    public static let `insets` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "insets"
        default: return nil
        }
    }
}

public enum SpacerPropId {
    public static let `minLength` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "min_length"
        default: return nil
        }
    }
}

public enum FramePropId {
    public static let `width` = 1
    public static let `height` = 2
    public static let `minWidth` = 3
    public static let `idealWidth` = 4
    public static let `maxWidth` = 5
    public static let `minHeight` = 6
    public static let `idealHeight` = 7
    public static let `maxHeight` = 8
    public static let `alignment` = 9

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "width"
        case 2: return "height"
        case 3: return "min_width"
        case 4: return "ideal_width"
        case 5: return "max_width"
        case 6: return "min_height"
        case 7: return "ideal_height"
        case 8: return "max_height"
        case 9: return "alignment"
        default: return nil
        }
    }
}

public enum BackgroundPropId {
    public static let `color` = 1
    public static let `cornerRadius` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "color"
        case 2: return "corner_radius"
        default: return nil
        }
    }
}

public enum ClipPropId {
    public static let `cornerRadius` = 1
    public static let `antialiased` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "corner_radius"
        case 2: return "antialiased"
        default: return nil
        }
    }
}

public enum OpacityPropId {
    public static let `opacity` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "opacity"
        default: return nil
        }
    }
}

public enum AnimatedOpacityPropId {
    public static let `opacity` = 1
    public static let `animationId` = 2
    public static let `durationMs` = 3
    public static let `curve` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "opacity"
        case 2: return "animation_id"
        case 3: return "duration_ms"
        case 4: return "curve"
        default: return nil
        }
    }
}

public enum ProjectionEffectPropId {
    public static let `matrix3` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "matrix3"
        default: return nil
        }
    }
}

public enum FocusScopePropId {
    public static let `autofocus` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "autofocus"
        default: return nil
        }
    }
}

public enum HoverRegionPropId {
    public static let `blocksBehind` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "blocks_behind"
        default: return nil
        }
    }
}

public enum KeyboardListenerPropId {
    public static let `autofocus` = 1
    public static let `keyPolicy` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "autofocus"
        case 2: return "key_policy"
        default: return nil
        }
    }
}

public enum SemanticsPropId {
    public static let `label` = 1
    public static let `hint` = 2
    public static let `value` = 3
    public static let `role` = 4
    public static let `selected` = 5
    public static let `children` = 6
    public static let `hidden` = 7
    public static let `liveRegion` = 8
    public static let `headingLevel` = 9
    public static let `sortPriority` = 10
    public static let `identifier` = 11
    public static let `actions` = 12

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "label"
        case 2: return "hint"
        case 3: return "value"
        case 4: return "role"
        case 5: return "selected"
        case 6: return "children"
        case 7: return "hidden"
        case 8: return "live_region"
        case 9: return "heading_level"
        case 10: return "sort_priority"
        case 11: return "identifier"
        case 12: return "actions"
        default: return nil
        }
    }
}

public enum ThemePropId {
    public static let `data` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "data"
        default: return nil
        }
    }
}

public enum RemovalPropId {
    public static let `requestToken` = 1
    public static let `requestState` = 2
    public static let `vertical` = 3
    public static let `collapseVertical` = 4
    public static let `title` = 5
    public static let `durationMs` = 6

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "request_token"
        case 2: return "request_state"
        case 3: return "vertical"
        case 4: return "collapse_vertical"
        case 5: return "title"
        case 6: return "duration_ms"
        default: return nil
        }
    }
}

public enum RefreshPropId {
    public static let `requestToken` = 1
    public static let `requestState` = 2
    public static let `showToken` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "request_token"
        case 2: return "request_state"
        case 3: return "show_token"
        default: return nil
        }
    }
}

public enum ScrollTargetsPropId {
    public static let `vertical` = 1
    public static let `ids` = 2
    public static let `position` = 3
    public static let `fraction` = 4
    public static let `spacing` = 5
    public static let `alignment` = 6
    public static let `snapping` = 7
    public static let `enabled` = 8
    public static let `showsIndicators` = 9

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "vertical"
        case 2: return "ids"
        case 3: return "position"
        case 4: return "fraction"
        case 5: return "spacing"
        case 6: return "alignment"
        case 7: return "snapping"
        case 8: return "enabled"
        case 9: return "shows_indicators"
        default: return nil
        }
    }
}

public enum MenuPropId {
    public static let `items` = 1
    public static let `enabled` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "items"
        case 2: return "enabled"
        default: return nil
        }
    }
}

public enum PickerPropId {
    public static let `selectedId` = 1
    public static let `options` = 2
    public static let `label` = 3
    public static let `style` = 4
    public static let `enabled` = 5

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "selected_id"
        case 2: return "options"
        case 3: return "label"
        case 4: return "style"
        case 5: return "enabled"
        default: return nil
        }
    }
}

public enum SliderPropId {
    public static let `value` = 1
    public static let `min` = 2
    public static let `max` = 3
    public static let `step` = 4
    public static let `enabled` = 5
    public static let `vertical` = 6
    public static let `hasOnChange` = 7
    public static let `label` = 8

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "value"
        case 2: return "min"
        case 3: return "max"
        case 4: return "step"
        case 5: return "enabled"
        case 6: return "vertical"
        case 7: return "has_on_change"
        case 8: return "label"
        default: return nil
        }
    }
}

public enum RangeSliderPropId {
    public static let `start` = 1
    public static let `endValue` = 2
    public static let `min` = 3
    public static let `max` = 4
    public static let `step` = 5
    public static let `enabled` = 6
    public static let `vertical` = 7
    public static let `hasOnChange` = 8
    public static let `labelStart` = 9
    public static let `labelEnd` = 10

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "start"
        case 2: return "end_value"
        case 3: return "min"
        case 4: return "max"
        case 5: return "step"
        case 6: return "enabled"
        case 7: return "vertical"
        case 8: return "has_on_change"
        case 9: return "label_start"
        case 10: return "label_end"
        default: return nil
        }
    }
}

public enum DividerPropId {

    public static func debugName(_ id: Int) -> String? {
        switch id {
        default: return nil
        }
    }
}

public enum LabelPropId {

    public static func debugName(_ id: Int) -> String? {
        switch id {
        default: return nil
        }
    }
}

public enum DatePickerPropId {
    public static let `selected` = 1
    public static let `first` = 2
    public static let `last` = 3
    public static let `selectableDates` = 4
    public static let `label` = 5
    public static let `enabled` = 6

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "selected"
        case 2: return "first"
        case 3: return "last"
        case 4: return "selectable_dates"
        case 5: return "label"
        case 6: return "enabled"
        default: return nil
        }
    }
}

public enum TimePickerPropId {
    public static let `value` = 1
    public static let `format` = 2
    public static let `label` = 3
    public static let `enabled` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "value"
        case 2: return "format"
        case 3: return "label"
        case 4: return "enabled"
        default: return nil
        }
    }
}

public enum BadgePropId {
    public static let `count` = 1
    public static let `alignment` = 2
    public static let `visible` = 3

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "count"
        case 2: return "alignment"
        case 3: return "visible"
        default: return nil
        }
    }
}

public enum GroupBoxPropId {
    public static let `hasLabel` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "has_label"
        default: return nil
        }
    }
}

public enum ProgressPropId {
    public static let `value` = 1
    public static let `circular` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "value"
        case 2: return "circular"
        default: return nil
        }
    }
}

public enum TablePropId {
    public static let `columns` = 1
    public static let `rows` = 2
    public static let `sortColumnId` = 3
    public static let `sortAscending` = 4
    public static let `selectedRowIds` = 5
    public static let `hasOnSort` = 6
    public static let `hasOnRowSelected` = 7

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "columns"
        case 2: return "rows"
        case 3: return "sort_column_id"
        case 4: return "sort_ascending"
        case 5: return "selected_row_ids"
        case 6: return "has_on_sort"
        case 7: return "has_on_row_selected"
        default: return nil
        }
    }
}

public enum DisclosureGroupPropId {
    public static let `expanded` = 1
    public static let `enabled` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "expanded"
        case 2: return "enabled"
        default: return nil
        }
    }
}

public enum OverlayPropId {
    public static let `alignment` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "alignment"
        default: return nil
        }
    }
}

public enum IgnoresSafeAreaPropId {
    public static let `regions` = 1
    public static let `edges` = 2

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "regions"
        case 2: return "edges"
        default: return nil
        }
    }
}

public enum SafeAreaPaddingPropId {
    public static let `insets` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "insets"
        default: return nil
        }
    }
}

public enum ControlSizePropId {
    public static let `size` = 1

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "size"
        default: return nil
        }
    }
}

public enum ButtonPropId {
    public static let `enabled` = 1
    public static let `role` = 2
    public static let `style` = 3
    public static let `autofocus` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "enabled"
        case 2: return "role"
        case 3: return "style"
        case 4: return "autofocus"
        default: return nil
        }
    }
}

public enum NativeWidgetPropId {
    public static let `kindId` = 1
    public static let `version` = 2
    public static let `capabilities` = 3
    public static let `payload` = 4

    public static func debugName(_ id: Int) -> String? {
        switch id {
        case 1: return "kind_id"
        case 2: return "version"
        case 3: return "capabilities"
        case 4: return "payload"
        default: return nil
        }
    }
}
