<!-- Generated from protocol/schema.sexp. Do not edit. -->

# Protocol IDs

Protocol version: `6.0`

## Frame kind

| Name | ID |
|---|---:|
| `handshake` | 1 |
| `full_snapshot` | 2 |
| `incremental_frame` | 3 |
| `event_batch` | 4 |
| `runtime_error` | 5 |

## Operation

| Name | ID |
|---|---:|
| `begin_frame` | 1 |
| `create_node` | 2 |
| `update_props` | 3 |
| `update_event_bindings` | 4 |
| `set_children` | 5 |
| `set_root` | 6 |
| `drop_node` | 7 |
| `host_request` | 8 |
| `runtime_notification` | 9 |
| `end_frame` | 10 |
| `application_request` | 11 |
| `set_application_theme` | 12 |

## Node kind

| Name | ID |
|---|---:|
| `empty` | 1 |
| `text` | 2 |
| `rich_text` | 3 |
| `symbol` | 4 |
| `image` | 5 |
| `text_editor` | 6 |
| `text_field` | 47 |
| `secure_field` | 49 |
| `collection_catalog` | 7 |
| `collection_window` | 8 |
| `scroll` | 9 |
| `progress` | 10 |
| `ignores_safe_area` | 11 |
| `safe_area_padding` | 12 |
| `navigation_stack` | 13 |
| `navigation_destination` | 14 |
| `navigation_split` | 15 |
| `flow` | 56 |
| `label` | 57 |
| `badge` | 58 |
| `date_picker` | 59 |
| `time_picker` | 60 |
| `menu` | 61 |
| `removal` | 78 |
| `refresh` | 77 |
| `scroll_targets` | 62 |
| `help` | 63 |
| `popover` | 72 |
| `sheet` | 73 |
| `toolbar` | 74 |
| `scroll_sections` | 75 |
| `scroll_section` | 76 |
| `row` | 16 |
| `column` | 17 |
| `weighted_row` | 18 |
| `stack` | 19 |
| `weighted_column` | 20 |
| `padding` | 21 |
| `frame` | 22 |
| `spacer` | 23 |
| `layout_priority` | 24 |
| `offset` | 25 |
| `background` | 26 |
| `clip` | 27 |
| `opacity` | 28 |
| `projection_effect` | 29 |
| `tabs` | 31 |
| `tab` | 40 |
| `morphing_surface` | 41 |
| `swipe_actions` | 42 |
| `swipe_action` | 43 |
| `toggle` | 44 |
| `gesture` | 48 |
| `focus_scope` | 51 |
| `hover_region` | 52 |
| `keyboard_listener` | 53 |
| `button` | 54 |
| `control_size` | 55 |
| `semantics` | 64 |
| `overlay` | 65 |
| `theme` | 69 |
| `animated_opacity` | 71 |
| `divider` | 105 |
| `group_box` | 106 |
| `reserved_node_kind_107` | 107 |
| `picker` | 116 |
| `slider` | 45 |
| `range_slider` | 46 |
| `native_widget` | 128 |
| `table` | 79 |
| `disclosure_group` | 133 |

## Event tag

| Name | ID |
|---|---:|
| `press` | 1 |
| `long_press` | 2 |
| `tap` | 3 |
| `double_tap` | 4 |
| `pointer_enter` | 5 |
| `pointer_leave` | 6 |
| `pointer_down` | 7 |
| `pointer_up` | 8 |
| `key` | 9 |
| `focus_changed` | 10 |
| `text_edit` | 11 |
| `text_submit` | 12 |
| `scroll_notification` | 13 |
| `visible_range_changed` | 14 |
| `animation_completed` | 15 |
| `layout_observed` | 17 |
| `value_changed` | 18 |
| `host_response` | 19 |
| `environment_changed` | 20 |
| `native_event` | 21 |
| `semantics_action` | 22 |
| `resync_requested` | 23 |
| `text_limit_reached` | 24 |
| `application_response` | 25 |
| `application_request_error` | 26 |
| `application_event` | 27 |
| `navigation_destination_selected` | 28 |
| `radio_selected` | 29 |
| `picker_selected` | 53 |
| `menu_action` | 54 |
| `scroll_position_changed` | 55 |
| `refresh_request` | 56 |
| `removal_requested` | 57 |
| `removal_completed` | 58 |
| `slider_changed` | 30 |
| `slider_change_end` | 31 |
| `range_slider_changed` | 32 |
| `range_slider_change_end` | 33 |
| `table_sort_requested` | 37 |
| `table_row_selected` | 38 |
| `civil_date_changed` | 46 |
| `civil_time_changed` | 47 |
| `navigation_path_changed` | 50 |
| `navigation_split_changed` | 51 |
| `tab_selected` | 52 |

## Host request

| Name | ID |
|---|---:|
| `clipboard_read` | 1 |
| `clipboard_write` | 2 |
| `open_url` | 3 |
| `pick_files` | 4 |
| `save_file` | 5 |
| `request_focus` | 6 |
| `clear_focus` | 7 |
| `scroll_to` | 8 |
| `set_window_title` | 9 |
| `set_window_size` | 10 |
| `show_native_menu` | 11 |
| `haptic_feedback` | 12 |
| `platform_information` | 13 |
| `measure_layout` | 14 |
| `show_notice` | 15 |
| `pick_date` | 16 |
| `pick_date_range` | 17 |
| `pick_time` | 18 |

## Runtime error

| Name | ID |
|---|---:|
| `protocol_error` | 1 |
| `revision_mismatch` | 2 |
| `duplicate_key` | 3 |
| `unsupported_node_kind` | 4 |
| `invalid_prop` | 5 |
| `handler_missing` | 6 |
| `stale_event` | 7 |
| `host_effect_failure` | 8 |
| `ocaml_exception` | 9 |
| `swiftui_renderer_exception` | 10 |
| `lifecycle_exception` | 11 |
| `native_library_loading_error` | 12 |

## Common properties

| Name | ID | Encoding |
|---|---:|---|
| `test_id` | 1 | `optional_string` |
| `semantics` | 2 | `optional_semantics` |

## Scroll sections properties

| Name | ID | Encoding |
|---|---:|---|
| `vertical` | 1 | `bool` |
| `pin_headers` | 2 | `bool` |
| `pin_footers` | 3 | `bool` |
| `spacing` | 4 | `f64` |
| `shows_indicators` | 5 | `bool` |
| `initial_anchor` | 6 | `enum_u8` |

## Scroll section properties

| Name | ID | Encoding |
|---|---:|---|
| `has_header` | 1 | `bool` |
| `has_footer` | 2 | `bool` |
| `hero_height` | 3 | `optional_f64` |
| `stretch` | 4 | `bool` |

## Toolbar properties

| Name | ID | Encoding |
|---|---:|---|
| `placements` | 1 | `toolbar_placements` |

## Sheet properties

| Name | ID | Encoding |
|---|---:|---|
| `presented` | 1 | `bool` |
| `fullscreen` | 2 | `bool` |
| `detents` | 3 | `u8` |
| `initial` | 4 | `enum_u8` |
| `interactive` | 5 | `bool` |
| `indicator` | 6 | `bool` |
| `sizing` | 7 | `enum_u8` |
| `fraction` | 8 | `f64` |

## Popover properties

| Name | ID | Encoding |
|---|---:|---|
| `presented` | 1 | `bool` |
| `edge` | 2 | `enum_u8` |

## Help properties

| Name | ID | Encoding |
|---|---:|---|
| `message` | 1 | `string` |

## Toggle properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `bool` |
| `enabled` | 2 | `bool` |
| `style` | 3 | `enum_u8` |

## Swipe actions properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `vertical` | 2 | `bool` |
| `close_on_scroll` | 3 | `bool` |
| `group` | 4 | `optional_string` |
| `close_when_opened` | 5 | `bool` |
| `close_when_tapped` | 6 | `bool` |

## Swipe action properties

| Name | ID | Encoding |
|---|---:|---|
| `title` | 1 | `string` |
| `side` | 2 | `enum_u8` |
| `enabled` | 3 | `bool` |
| `role` | 4 | `enum_u8` |
| `extent` | 5 | `f64` |
| `background` | 6 | `u32` |
| `auto_close` | 7 | `bool` |
| `full_swipe` | 8 | `bool` |

## Morphing surface properties

| Name | ID | Encoding |
|---|---:|---|
| `expanded` | 1 | `bool` |
| `expand_duration_ms` | 2 | `u32` |
| `collapse_duration_ms` | 3 | `u32` |

## Tabs properties

| Name | ID | Encoding |
|---|---:|---|
| `selection` | 1 | `string` |

## Tab properties

| Name | ID | Encoding |
|---|---:|---|
| `page_key` | 1 | `string` |
| `title` | 2 | `string` |
| `symbol` | 3 | `string` |
| `badge` | 4 | `optional_string` |
| `accessibility_label` | 5 | `optional_string` |

## Navigation split properties

| Name | ID | Encoding |
|---|---:|---|
| `visibility` | 1 | `u8` |
| `compact_column` | 2 | `u8` |
| `selection_key` | 3 | `optional_string` |
| `sidebar_title` | 4 | `string` |
| `content_title` | 5 | `optional_string` |
| `detail_title` | 6 | `string` |

## Navigation stack properties

| Name | ID | Encoding |
|---|---:|---|
| `title` | 1 | `string` |

## Navigation destination properties

| Name | ID | Encoding |
|---|---:|---|
| `page_key` | 1 | `string` |
| `title` | 2 | `string` |
| `can_pop` | 3 | `bool` |

## Text properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `string` |
| `text_style` | 2 | `optional_text_style` |
| `text_align` | 3 | `text_align` |
| `line_limit` | 4 | `optional_u32` |
| `truncation` | 5 | `text_truncation` |

## Rich text properties

| Name | ID | Encoding |
|---|---:|---|
| `spans` | 1 | `text_span_list` |

## Symbol properties

| Name | ID | Encoding |
|---|---:|---|
| `name` | 1 | `string` |
| `size` | 2 | `optional_f64` |
| `color` | 3 | `optional_argb32` |
| `rendering` | 4 | `symbol_rendering` |

## Scroll properties

| Name | ID | Encoding |
|---|---:|---|
| `vertical` | 1 | `bool` |
| `shows_indicators` | 2 | `bool` |
| `fill_viewport` | 3 | `bool` |
| `initial_anchor` | 4 | `enum_u8` |

## Collection catalog properties

| Name | ID | Encoding |
|---|---:|---|
| `keys` | 1 | `string_list` |
| `default_extent` | 2 | `f64` |
| `overrides` | 3 | `collection_extents` |
| `overscan` | 4 | `u32` |
| `expand_duration_ms` | 5 | `u32` |
| `collapse_duration_ms` | 6 | `u32` |
| `vertical` | 7 | `bool` |
| `initial_anchor` | 8 | `enum_u8` |
| `initial_key` | 9 | `optional_string` |
| `measurement_revision` | 10 | `optional_i64` |

## Collection window properties

| Name | ID | Encoding |
|---|---:|---|
| `first_index` | 1 | `u32` |
| `keys` | 2 | `string_list` |

## Text field properties

| Name | ID | Encoding |
|---|---:|---|
| `session_id` | 1 | `u64` |
| `document_revision` | 2 | `u64` |
| `accepted_local_revision` | 3 | `u64` |
| `update_mode` | 4 | `text_update_mode` |
| `value` | 5 | `text_editing_value` |
| `enabled` | 6 | `bool` |
| `read_only` | 7 | `bool` |
| `submit_on_return` | 8 | `bool` |
| `max_utf8_bytes` | 9 | `optional_u32` |
| `label` | 10 | `string` |
| `prompt` | 11 | `string` |
| `keyboard` | 12 | `enum_u8` |
| `submit_label` | 13 | `enum_u8` |
| `autofocus` | 14 | `bool` |
| `appearance` | 15 | `enum_u8` |

## Secure field properties

| Name | ID | Encoding |
|---|---:|---|
| `session_id` | 1 | `u64` |
| `document_revision` | 2 | `u64` |
| `accepted_local_revision` | 3 | `u64` |
| `update_mode` | 4 | `text_update_mode` |
| `value` | 5 | `text_editing_value` |
| `enabled` | 6 | `bool` |
| `read_only` | 7 | `bool` |
| `submit_on_return` | 8 | `bool` |
| `max_utf8_bytes` | 9 | `optional_u32` |
| `label` | 10 | `string` |
| `prompt` | 11 | `string` |
| `keyboard` | 12 | `enum_u8` |
| `submit_label` | 13 | `enum_u8` |
| `autofocus` | 14 | `bool` |
| `appearance` | 15 | `enum_u8` |

## Text editor properties

| Name | ID | Encoding |
|---|---:|---|
| `session_id` | 1 | `u64` |
| `document_revision` | 2 | `u64` |
| `accepted_local_revision` | 3 | `u64` |
| `update_mode` | 4 | `text_update_mode` |
| `value` | 5 | `text_editing_value` |
| `enabled` | 6 | `bool` |
| `read_only` | 7 | `bool` |
| `submit_on_return` | 8 | `bool` |
| `max_utf8_bytes` | 9 | `optional_u32` |

## Image properties

| Name | ID | Encoding |
|---|---:|---|
| `source` | 1 | `image_source` |
| `sizing` | 2 | `image_sizing` |
| `scale` | 3 | `f64` |

## Flow properties

| Name | ID | Encoding |
|---|---:|---|
| `spacing` | 1 | `f64` |
| `line_spacing` | 2 | `f64` |
| `alignment` | 3 | `horizontal_alignment` |

## Row properties

| Name | ID | Encoding |
|---|---:|---|
| `spacing` | 1 | `optional_f64` |
| `alignment` | 2 | `vertical_alignment` |

## Column properties

| Name | ID | Encoding |
|---|---:|---|
| `spacing` | 1 | `optional_f64` |
| `alignment` | 2 | `horizontal_alignment` |

## Weighted row properties

| Name | ID | Encoding |
|---|---:|---|
| `spacing` | 1 | `optional_f64` |
| `alignment` | 2 | `vertical_alignment` |
| `items` | 3 | `weighted_items` |

## Weighted column properties

| Name | ID | Encoding |
|---|---:|---|
| `spacing` | 1 | `optional_f64` |
| `alignment` | 2 | `horizontal_alignment` |
| `items` | 3 | `weighted_items` |

## Stack properties

| Name | ID | Encoding |
|---|---:|---|
| `alignment` | 1 | `alignment` |

## Layout priority properties

| Name | ID | Encoding |
|---|---:|---|
| `priority` | 1 | `f64` |

## Offset properties

| Name | ID | Encoding |
|---|---:|---|
| `x` | 1 | `f64` |
| `y` | 2 | `f64` |

## Padding properties

| Name | ID | Encoding |
|---|---:|---|
| `insets` | 1 | `edge_insets` |

## Spacer properties

| Name | ID | Encoding |
|---|---:|---|
| `min_length` | 1 | `optional_f64` |

## Frame properties

| Name | ID | Encoding |
|---|---:|---|
| `width` | 1 | `optional_f64` |
| `height` | 2 | `optional_f64` |
| `min_width` | 3 | `optional_f64` |
| `ideal_width` | 4 | `optional_f64` |
| `max_width` | 5 | `optional_frame_limit` |
| `min_height` | 6 | `optional_f64` |
| `ideal_height` | 7 | `optional_f64` |
| `max_height` | 8 | `optional_frame_limit` |
| `alignment` | 9 | `alignment` |

## Background properties

| Name | ID | Encoding |
|---|---:|---|
| `color` | 1 | `argb32` |
| `corner_radius` | 2 | `f64` |

## Clip properties

| Name | ID | Encoding |
|---|---:|---|
| `corner_radius` | 1 | `f64` |
| `antialiased` | 2 | `bool` |

## Opacity properties

| Name | ID | Encoding |
|---|---:|---|
| `opacity` | 1 | `f64` |

## Animated opacity properties

| Name | ID | Encoding |
|---|---:|---|
| `opacity` | 1 | `f64` |
| `animation_id` | 2 | `u64` |
| `duration_ms` | 3 | `u32` |
| `curve` | 4 | `animation_curve` |

## Projection effect properties

| Name | ID | Encoding |
|---|---:|---|
| `matrix3` | 1 | `matrix3` |

## Focus scope properties

| Name | ID | Encoding |
|---|---:|---|
| `autofocus` | 1 | `bool` |

## Hover region properties

| Name | ID | Encoding |
|---|---:|---|
| `blocks_behind` | 1 | `bool` |

## Keyboard listener properties

| Name | ID | Encoding |
|---|---:|---|
| `autofocus` | 1 | `bool` |
| `key_policy` | 2 | `key_policy` |

## Semantics properties

| Name | ID | Encoding |
|---|---:|---|
| `label` | 1 | `optional_string` |
| `hint` | 2 | `optional_string` |
| `value` | 3 | `optional_string` |
| `role` | 4 | `semantics_role` |
| `selected` | 5 | `optional_bool` |
| `children` | 6 | `u8` |
| `hidden` | 7 | `bool` |
| `live_region` | 8 | `bool` |
| `heading_level` | 9 | `optional_u8` |
| `sort_priority` | 10 | `optional_f64` |
| `identifier` | 11 | `optional_string` |
| `actions` | 12 | `semantics_actions` |

## Theme properties

| Name | ID | Encoding |
|---|---:|---|
| `data` | 1 | `swiftui_environment` |

## Removal properties

| Name | ID | Encoding |
|---|---:|---|
| `request_token` | 1 | `i64` |
| `request_state` | 2 | `u8` |
| `vertical` | 3 | `bool` |
| `collapse_vertical` | 4 | `bool` |
| `title` | 5 | `string` |
| `duration_ms` | 6 | `u32` |

## Refresh properties

| Name | ID | Encoding |
|---|---:|---|
| `request_token` | 1 | `i64` |
| `request_state` | 2 | `u8` |
| `show_token` | 3 | `optional_i64` |

## Scroll targets properties

| Name | ID | Encoding |
|---|---:|---|
| `vertical` | 1 | `bool` |
| `ids` | 2 | `i64_list` |
| `position` | 3 | `optional_i64` |
| `fraction` | 4 | `f64` |
| `spacing` | 5 | `f64` |
| `alignment` | 6 | `u8` |
| `snapping` | 7 | `bool` |
| `enabled` | 8 | `bool` |
| `shows_indicators` | 9 | `bool` |

## Menu properties

| Name | ID | Encoding |
|---|---:|---|
| `items` | 1 | `menu_items` |
| `enabled` | 2 | `bool` |

## Picker properties

| Name | ID | Encoding |
|---|---:|---|
| `selected_id` | 1 | `optional_i64` |
| `options` | 2 | `picker_options` |
| `label` | 3 | `string` |
| `style` | 4 | `u8` |
| `enabled` | 5 | `bool` |

## Slider properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `f64` |
| `min` | 2 | `f64` |
| `max` | 3 | `f64` |
| `step` | 4 | `optional_f64` |
| `enabled` | 5 | `bool` |
| `vertical` | 6 | `bool` |
| `has_on_change` | 7 | `bool` |
| `label` | 8 | `string` |

## Range slider properties

| Name | ID | Encoding |
|---|---:|---|
| `start` | 1 | `f64` |
| `end_value` | 2 | `f64` |
| `min` | 3 | `f64` |
| `max` | 4 | `f64` |
| `step` | 5 | `optional_f64` |
| `enabled` | 6 | `bool` |
| `vertical` | 7 | `bool` |
| `has_on_change` | 8 | `bool` |
| `label_start` | 9 | `string` |
| `label_end` | 10 | `string` |

## Divider properties

| Name | ID | Encoding |
|---|---:|---|

## Label properties

| Name | ID | Encoding |
|---|---:|---|

## Date picker properties

| Name | ID | Encoding |
|---|---:|---|
| `selected` | 1 | `civil_date` |
| `first` | 2 | `civil_date` |
| `last` | 3 | `civil_date` |
| `selectable_dates` | 4 | `civil_dates` |
| `label` | 5 | `string` |
| `enabled` | 6 | `bool` |

## Time picker properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `civil_time` |
| `format` | 2 | `u8` |
| `label` | 3 | `string` |
| `enabled` | 4 | `bool` |

## Badge properties

| Name | ID | Encoding |
|---|---:|---|
| `count` | 1 | `optional_u64` |
| `alignment` | 2 | `u8` |
| `visible` | 3 | `bool` |

## Group box properties

| Name | ID | Encoding |
|---|---:|---|
| `has_label` | 1 | `bool` |

## Progress properties

| Name | ID | Encoding |
|---|---:|---|
| `value` | 1 | `optional_f64` |
| `circular` | 2 | `bool` |

## Table properties

| Name | ID | Encoding |
|---|---:|---|
| `columns` | 1 | `table_columns` |
| `rows` | 2 | `table_rows` |
| `sort_column_id` | 3 | `optional_i64` |
| `sort_ascending` | 4 | `bool` |
| `selected_row_ids` | 5 | `i64_list` |
| `has_on_sort` | 6 | `bool` |
| `has_on_row_selected` | 7 | `bool` |

## Disclosure group properties

| Name | ID | Encoding |
|---|---:|---|
| `expanded` | 1 | `bool` |
| `enabled` | 2 | `bool` |

## Overlay properties

| Name | ID | Encoding |
|---|---:|---|
| `alignment` | 1 | `alignment` |

## Ignores safe area properties

| Name | ID | Encoding |
|---|---:|---|
| `regions` | 1 | `u8` |
| `edges` | 2 | `u8` |

## Safe area padding properties

| Name | ID | Encoding |
|---|---:|---|
| `insets` | 1 | `edge_insets` |

## Control size properties

| Name | ID | Encoding |
|---|---:|---|
| `size` | 1 | `u8` |

## Button properties

| Name | ID | Encoding |
|---|---:|---|
| `enabled` | 1 | `bool` |
| `role` | 2 | `u8` |
| `style` | 3 | `u8` |
| `autofocus` | 4 | `bool` |

## Native widget properties

| Name | ID | Encoding |
|---|---:|---|
| `kind_id` | 1 | `u32` |
| `version` | 2 | `u16` |
| `capabilities` | 3 | `u64` |
| `payload` | 4 | `bytes` |

