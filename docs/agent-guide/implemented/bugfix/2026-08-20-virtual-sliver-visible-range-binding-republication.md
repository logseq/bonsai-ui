# Virtual Sliver Visible Range Binding Republication

## Problem

`SliverFixedExtentHost` and `SliverVariedExtentHost` deduplicate
`visible_range_changed` publications using only the logical range. Their state
survives ordinary node rebuilds, event-binding updates, and some full-snapshot
replacements that reuse the same node identity.

If the event handler changes while the painted range stays unchanged, each host
schedules a report but suppresses it because `_lastRange` still matches. The new
handler receives no current range until scrolling or another layout change
produces different metrics. Both fixed- and varied-extent hosts exhibit this
behavior.

The same stale publication state can cross a runtime full snapshot when node
IDs, handler IDs, and the range are reused. A newly started OCaml runtime may
then wait indefinitely for the initial range that the renderer believes it has
already published to the previous runtime. Changing an event sink from absent
to present has the same state-publication requirement.

## Decision

Treat visible-range deduplication as scoped to one delivery identity, not only
to one range value.

Each virtual sliver host tracks the last successfully published range together
with enough delivery-generation information to identify its receiver. A change
to the visible-range binding, runtime generation, mounted node lifecycle, or
event-sink availability invalidates the previous publication. Once usable
geometry is available, the host publishes the unchanged current range exactly
once to the new receiver.

Do not use every `localRevision` change as the delivery identity: property and
child-window updates can increment the local revision while retaining the same
handler, and republishing on all such updates would turn normal materialization
catch-up into duplicate range traffic. Pass or derive an explicit stable
delivery generation where the existing widget inputs cannot distinguish a new
runtime from an ordinary rebuild.

Keep the zero-paint rule: unavailable geometry remains pending and is not
recorded as published. Keep varied-extent transition suppression: changing a
receiver during a suppressed transition marks publication pending, and the
settled current range is sent once after suppression ends.

## Alternatives considered

### Clear `_lastRange` on every widget update

This fixes handler replacement but emits redundant range events for unrelated
props, child-window, and local-revision changes. Those updates are common in the
application-owned materialization loop.

### Include only `handlerId` in the deduplication key

This covers ordinary binding replacement but not a new runtime that reuses the
same numeric handler ID, nor the transition from no event sink to an available
sink.

### Wait for the next scroll event

The current range is state required to bootstrap window ownership and
pagination. User interaction cannot be required to deliver it to a new
receiver.

## Consequences

- Fixed- and varied-extent widget tests replace the visible-range handler while
  keeping geometry unchanged and observe exactly one current-range event with
  the new handler ID.
- Adding a previously absent binding or event sink publishes the current range
  once when geometry is usable.
- Applying a full snapshot for a new runtime with reused node and handler IDs
  republishes the initial current range exactly once.
- Rebuilding with the same delivery identity and unchanged range emits no
  duplicate event, including repeated idle frames.
- A receiver change during zero paint remains pending until positive paint is
  available, without creating a frame loop.
- A receiver change during a varied-extent transition emits only the settled
  range after suppression ends.

### Operational risks

- Exposing a runtime or delivery generation to renderer hosts adds plumbing
  across `NodeHost`, `WidgetRegistry`, and the virtual-sliver widgets.
- Invalidating too broadly increases event traffic and can feed unnecessary
  OCaml frame updates; invalidating too narrowly recreates the stale-receiver
  bug.
