# Scroll and list API review

The [inventory](swiftui-widget-inventory.json) adds individual mappings for
39 values and 28 named constructors. They cover Sliver/Scroll_view, sparse
extent transitions, card lists, Carousel, disclosure lists, per-item removal,
refresh, contextual selection and Table.

| Baseline family | Current API | Ownership and callback change |
| --- | --- | --- |
| Sliver fixed/varied extent and Window | Collection Catalog/Window | Ordered keys and extents are independent of bounded materialization; visible-range callbacks remain half-open painted bounds. |
| Sliver box/list/padding | Mixed catalog or Scroll_sections | Flatten virtual records into one global index space, or use finite keyed native sections. |
| Sliver fill | Scroll with fill_viewport and Weighted content | Native minimum document extent replaces the special Sliver node. |
| Scroll_view | Scroll, Scroll_sections or Collection | Explicit content model; optional native scroll observation replaces mandatory inert handlers. |
| Sparse extent transitions | Catalog durations | Native expansion/collapse curves; application-owned configuration replaces the transition object/getters. |
| Card list | GroupBox and Button in ordinary/scroll/windowed layout | Keyed Unit actions capture IDs instead of list-owned selection events. |
| Carousel | Scroll_targets | Controlled position requests are independent of item Button actions. |
| Expansion_panel_list and Expandable_list | Keyed DisclosureGroups | Per-item Bool requests update an OCaml expanded-ID set. |
| Dismissible_list | Keyed Removal controls | Each item owns a token/state; completion precedes canonical OCaml removal. |
| Refresh_indicator | Refresh.vertical | Tokened native async action attached to Native_list.vertical; arbitrary scroll hosts are rejected. |
| Selection | Toggle and contextual Toolbar | Each requested Bool updates current membership; batch commands read current state. |
| Data_table | Table returning Body | Canonical sort/selection remain in OCaml; normal Buttons replace cell/select-all events. |

Initial Start/End positioning does not reverse source order or change the native
coordinate system. Applications order their records explicitly. Flutter reverse,
primary-scroll and cache-extent flags are removed. The catalog retains explicit
row extents, including overrides outside the visible window; it does not claim
native self-sizing measurements. Mixed content uses one animation policy and
one visible-range index space. Native pinned sections are a separate capability.

Single/multiple disclosure is application state, and header activation follows
native DisclosureGroup behavior. Collapsed content stays logically retained while
collapsed input and accessibility are excluded. A removal control instead keeps
the item present through Pending/Rejected and emits one completion after an
Accepted collapse. Applications then update records, selection and catalog keys.

Carousel Hero/Contained/Uncontained, configurable sparse-animation curves and
Material refresh variants are removed. Table cell flags become ordinary content;
rich column content is available in details alongside native text headers.
Table and scroll targets do not imply bounded OCaml materialization.

## Evidence and limits

Current declaration, renderer, test and real Gallery fixture references were
checked. The referenced Swift source/test hashes match the complete 482-test
macOS regression, which was reused without rerunning it. Existing mixed-catalog
tests cover 10,003 logical records with fewer than 64 materialized items, both
axes, RTL, distant jumps, expansion, reordering and retained identity. This is
boundedness evidence, not a measured frame-time or memory performance budget.

`_build/validation/swiftui-list-api-review.json` records hashes and review scope.
Physical gestures/refresh, accessibility, self-sizing/Dynamic Type work and
remaining performance acceptance are still open. No runtime implementation
changed, and no API review is promoted to complete widget acceptance.
