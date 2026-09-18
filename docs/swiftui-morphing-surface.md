# Native Morphing Surfaces

`View.Morphing_surface.create ~expanded ~content ()` renders one active content
subtree. OCaml owns expansion and the content supplied for that state. Shared
content can retain keyed identity; details that are absent from `content` are
removed from the wire and native trees. Durable drafts, selection and counters
belong in OCaml. Removed controls immediately release native editing, focus and
accessibility ownership.

The surface animates corner radius and shadow around the active content. Its
expanded endpoint has 8-point horizontal and 6-point vertical insets and a
16-point corner radius. The collapsed endpoint has no inset, radius or shadow.
The system background follows the surrounding appearance. This contract does
not retain an invisible subtree or crossfade two live copies of content.

Standalone surfaces measure active content at its target size and interpolate
the displayed height. A rapid reversal starts from the current displayed extent.
Inside a Collection, the surface reports its target extent and the collection
coordinates row height and neighbor placement. Surface styling does not feed
intermediate padding or height samples back into collection measurement.

Expansion defaults to 240 ms with an ease-out cubic curve; collapse defaults to
190 ms with an ease-in-out cubic curve. Durations are unsigned 32-bit milliseconds;
zero disables interpolation. Initial mounting uses the current endpoint.
Reduce Motion, inactive scenes, hidden sessions and disappearance finish at the
target. Animation tasks do not emit OCaml events.

Input remains revision fenced: content changed by an unacknowledged expansion
cannot receive events until that candidate is presented. Removed native controls
cannot accept stale input while waiting for the next presentation.

BSFR 5.0 replaces the previous two-child contract. Node 41 retains its surface
kind and its three properties (expanded, expansion duration, collapse duration),
but requires exactly one child and no event bindings. Older protocol frames,
invalid booleans, malformed child graphs and truncated property updates fail
before publication. There is no legacy decoder or constructor.

Swift regressions exercise native endpoint sizing, shared identity, editor
removal, reversal, zero duration, scene inactivity and empty active content.
The real OCaml Gallery fixture verifies that counters survive content removal
through OCaml state, and that events remain presentation fenced. Mail now uses native List with self-sized surface content; its row identity,
expansion and collapsed-detail cleanup have native tests. Historical Collection
animation and broader performance work are tracked in the
[Mail Rendering Performance decision](agent-guide/proposed/architecture/2026-09-14-mail-rendering-performance.md).
