# Native Table

`View.Table` replaces `Material.Data_table`. It returns `View.Body.t`, so an
application can use it directly in a finite application/navigation slot or give
it explicit dimensions with `View.Body.with_size` before embedding it in ordinary
content. The renderer uses SwiftUI Table at regular width and labeled rows with
selection and sorting commands at compact width.

## Public composition

```ocaml
let columns =
  [ View.Table.column ~id:1L ~title:"Name" ~sortable:true ()
  ; View.Table.column ~id:2L ~title:"Score" ~numeric:true ()
  ]

let rows =
  [ View.Table.row ~id:10L [ View.text "Ada"; View.text "42" ] ]

let body =
  View.Table.create
    ~columns ~rows ~selected_row_ids:[10L]
    ~on_sort ~on_row_selected ()
```

Columns have stable signed IDs, native text titles, numeric alignment, sortability,
optional help and arbitrary `details` content. The Column details disclosure
preserves rich header content and explanations alongside native text headers.
It can contain ordinary interactive controls; collapsed details do not admit
input, including activation through retained controls.

Rows have stable signed IDs, selection eligibility and one ordinary View per
column. Cell identity is scoped by the row/column ID pair. Cell actions use
ordinary keyed Button content. Placeholder styling and edit symbols are ordinary
cell compositions. Select-all and clear-selection commands are owned by the
application and operate on the current eligible rows.

There is one canonical selected-ID set, supplied by OCaml. Duplicate column,
row or selected IDs, absent selected rows, empty titles/help, incorrect row
widths, and absent or non-sortable selected sort columns are rejected. Column
count must be 1..65535 and row count at most 65535; the transport's frame and node
limits also apply. Table does not claim lazy OCaml row materialization merely
because SwiftUI virtualizes its native cells.

Sort callbacks carry `Int64_bool { id = column_id; value = ascending }`;
row-selection callbacks carry `Int64_bool { id = row_id; value = selected }`.
The application owns ordering and accepted/rejected changes. Native sort
comparators describe the supplied row ranks and do not sort business data.
A selection-disabled row retains its independent cell actions.

## Runtime and protocol

Table node 79 replaces Material_data_table node 131. The public Material
constructor, duplicate per-row selected flag, and per-cell transport flags are
removed. Semantic sort/row-membership events 37/38 remain; table-specific
select-all/cell-activation events 39/40 are removed. Ordinary Button commands
replace those events. Active OCaml/native paths reject node 131 and events 39/40;
there is no compatibility decoder.

The native controller keeps pending membership and sort intents until the
corresponding runtime batch is resolved after presentation. Rejected requests
and failed queue admission restore canonical state. Generation checks fence
bindings after metadata, child or handler replacement. The session checks the
presented configuration, visibility, activity and handler identity before
admitting an event. Row/column lookup metadata is indexed once per decoded frame.

Lazy native cell builders retain the child snapshot belonging to their table
properties. Without this snapshot, a delayed builder for an old row could index
into the new, shorter children array after deletion; the first compact runtime
scenario exposed that crash, and the snapshot fixes it without retaining the
removed row as active input.

## Real-runtime verification

`examples/gallery/ocaml/table_catalog.ml` supplies the controlled Gallery scene.
The same scene is registered in the native fixture as `native-table`. The native
App tests render its actual OCaml state and invoke native cell controls plus
native selection/sort bindings. They verify:

- Mixed sortable/non-sortable native columns and all labeled compact cell values.
- Multiple selection, sorting by Rank, stable selection through the resulting
  row reorder, and independent actions on the ineligible row.
- Rejected selection/sort changes, application-owned select-all/clear commands,
  row removal, column reorder, empty data and reset.
- Opening and closing rich column details, action delivery while open, and
  rejection of retained input after closing.

The separate runtime test verifies invalid/disabled row and sort intents, stale
bindings after row removal, removed cell actions, full queue rejection, hidden
application input and disposal. It initially fails because hidden details accept
activation; adding the expansion-state gate makes the test pass.

```sh
python3 native/test/test_table_window.py
swift test --scratch-path _build/swift --filter tableFencesHiddenDetailsAndRetainsControlledSelection
```

The native and forced-compact macOS scenarios pass in 26.568 seconds
(`/tmp/table-window-final.log`); the lifecycle test passes
(`/tmp/table-lifecycle-green.log`). These tests use native property setters for
selection and sort bindings, not mouse/header/keyboard gestures. The forced
compact macOS presentation is not physical iOS execution. Physical iOS layout,
touch interaction, VoiceOver and keyboard/header-click acceptance remain open.
Full regression and platform results are recorded in the implementation ledger.
No Table or Mail screenshot was produced by this unit.

## Earlier independent API experiment

The following evidence preceded the OCaml integration. It remains reproducible
with `python3 tool/test_swiftui_table_api.py`; the independent probe is not itself
production or Bonsai integration evidence.

### Verified native API

`tool/probe_swiftui_table.swift` creates an independent SwiftUI Table with three
dynamic columns: sortable Name, non-sortable Action, and sortable Rank. Its
macOS assertions inspect the actual native table and cell views. The shared
Table view also typechecks for physical iOS 18 arm64.

The Xcode 26.1.1 SwiftUI module interface provides `TableColumnForEach` from
iOS 17.4 and macOS 14.4, and `TableRow.selectionDisabled` from iOS 17 and
macOS 14. Both fit the selected deployment targets without compatibility paths.

A direct `if/else` between a sortable and non-sortable TableColumn does not
compile: the two branches have different comparator types, the application
comparator and `Never`. Two mutually exclusive optional columns inside an
explicit `TableColumnBuilder<Row, Comparator>` do compile. Wrapping that builder
in `TableColumnForEach` produces exactly one native column per metadata entry,
in metadata order. This preserves interleaved sortable and non-sortable columns
without giving inactive columns dummy sort actions or grouping columns by type.

The diagnostic verifies:

- Native column titles, order, count, and sort-descriptor availability.
- Selection eligibility through the native outline view's selection delegate:
  the row with ID 9 is not selectable, while rows -7 and 13 are selectable.
- The disabled-selection row retains an enabled cell Button whose actual
  accessibility action reaches the Swift application model.
- Native multi-selection reaches the binding. A rejected selection request
  restores native selection after an observable resolution update.
- Reversing the canonical rows moves selected ID -7 from native row 0 to row 2
  without changing its identity or selection.
- Setting the native Rank sort descriptor submits the correct column and
  direction, while rendered rows remain in their supplied, reversed order.
  Table does not automatically apply the application's comparator to its data.
- Rejecting a subsequent Name sort request restores the accepted native sort
  descriptor, as well as preserving canonical sort state.
- Removing, inserting and reordering columns updates the native columns and
  their sortability without recreating the native table or losing selection.

The comparator in this diagnostic orders numeric row ranks; it is not a dummy
comparator. The application deliberately does not apply it to its rows. This
separates proof that the Table submits sorting intents from any future decision
about how OCaml should sort business data.
