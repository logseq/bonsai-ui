# Native search composition

Material.search_bar, Material.Search_anchor and Material.App_bar.search are
removed. Search now composes the existing native View.text_field, suggestion
Buttons, Toolbar and presentation primitives. OCaml owns the query, selected
suggestion, eligible results and presentation state. No search-specific node,
text controller or native data model is added.

## Presentation and editing

An inline search region combines a field and results in ordinary layout. An
anchored search uses View.Popover around its opening Button. Full-screen search
uses View.Sheet.full_screen: native fullScreenCover on iOS and a native sheet on
macOS. Put a page's search command in View.Toolbar when appropriate. Leading
icons, clear controls and other actions use ordinary row/label composition,
rather than Material slot counts and centering flags.

The field retains the same revisioned input contract as other native text fields:
stable session, increasing local revisions, explicit OCaml acknowledgment,
UTF-16 selection, marked text, read-only/enabled state, autofocus, submit behavior
and UTF-8 length limits. Use Text_editing.Keyboard and Submit_label; the unused
legacy keyboard_type and input_action enums are removed. Use Text_editor for
multiline content rather than a multiline search-bar variant.

A clear-query command increments the document revision and explicitly replaces
the native value. Accepted edits return Ack with their local revision and exact
selection/marked ranges. Opening or closing does not clear the canonical query.
Suggestions are keyed by application ID; each handler checks the current query,
available suggestions and enabled state before applying its action. Removed or
filtered native controls cannot revive an old choice.

Open and close are application state transitions. Repeated opening does not
increment an open counter again. An explicit close command and a native Boolean
presentation-dismissal request can use the same application policy, including
rejection. Suggestion selection can update application state and close search.
There are no separate Search_opened or Search_closed wire events. Native sheet
and popover lifetime, modal input and stale-presentation rules still apply.

## Removed protocol surface

SearchBar node 129 and the now-unproduced generic Material expressive node 136
are removed, including their OCaml property bags, private constructors, driver
translation and encoders/decoders. Every former expressive component is rejected
at the node-kind boundary; there is no component whitelist compatibility decoder.
Events 48 and 49 are removed. Relevant Dart registry and codec branches and their
obsolete tests are deleted. The root Flutter tree and all eleven old example
hosts have since been removed; no active Dart backend remains.

The migration exposed an existing native text-input defect: the OCaml dispatcher
omitted Text_limit_reached although the codec and native field emitted it. The
new search window tests observed Limits: 0 after an over-limit edit in every
presentation. Adding the tag and Unit-payload conversion restores delivery; no
new event or text-editing protocol was needed.

## Gallery and verification

Search_catalog.component is shared by Gallery and three actual runtime entrypoints:
native-search-0 (inline), native-search-1 (anchored) and native-search-2 (full-screen).
It filters a small in-memory mailbox catalog using ASCII-case-insensitive UTF-8
substring matching. Unicode text is preserved; this is not locale-aware case
folding or a production mail search service. The sample provides a disabled
suggestion, read-only/enabled controls, a 16-byte field limit, close rejection,
explicit clear, submit state and open/close counts. Mail's existing search
placeholder is unchanged.

`native/test/test_search_window.py` launches an actual SwiftUI App linked to OCaml
for each presentation. Native accessibility controls open, clear and close the
surface and choose suggestions; actual AppKit field-editor mutations verify
filtering, empty results, CJK/emoji marked text and UTF-16 selection, submission,
length-limit delivery and query restoration after reopening. Native fields retain
identity during query changes. Read-only and disabled native states, stale removed
suggestion controls and rejected explicit close are checked.

The initial harness passed plain numeric process arguments, which macOS treated
as files to open, leaving the App without its initial window. Those timeouts were
not counted as functional RED. Using --inline/--anchored/--fullscreen starts the
window normally; all three cases then failed on the missing search state before
implementation. After the dispatcher fix, all three native cases pass.

Protocol tests reject retired node kinds and search event IDs. Existing core
text/presentation tests cover their shared lifecycle beyond these search cases.
The tests do not establish physical iOS touch/keyboard/IME, VoiceOver, native
interactive-dismiss gestures, actual full-screen presentation on a device, or
visual acceptance. Full standalone Gallery and the overall migration remain open.
