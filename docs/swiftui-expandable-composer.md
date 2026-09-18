# Expandable message composer

`Native_widget.Expandable_message_composer` is a native launcher and system sheet
sharing one ephemeral editor draft. Its standard native registration is kind 7,
version 3. The sheet uses NavigationStack and system toolbar placements. Close is
a cancellation toolbar button; interactive dismissal belongs to the sheet.

Actions declare `role:Action`, `Confirmation` or `Cancellation`; Action is the
default. They retain their positive unique ID, tooltip, visibility, enabled state
and native child label. `position` and `style` are removed from the expandable
composer contract. Filled appearance never implies submission. For example:

```ocaml
Ui.Native_widget.Expandable_message_composer.button
  ~id:1 ~tooltip:"Send" ~role:Confirmation ~visibility:When_non_empty
  ~child:(Ui.View.symbol ~name:"arrow.up" ()) ()
```

Confirmation emits the action ID and current editor text. It does not clear the
draft or assume application save semantics. Closing and reopening retain text and
UTF-16 selection under a stable key; changing the key resets the draft. Closing
ends editing before suspending event admission, allowing final IME delivery.
Stale sheet generations reject close and action callbacks.

The inline Message_composer remains kind 6, version 1. Its expansion/collapse
interaction and inline action placement are separate from modal dismissal. Both
composers keep the existing native text adapter and draft ownership.
