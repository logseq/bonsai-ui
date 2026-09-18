# Native List refresh

`View.Refresh.vertical` accepts an undecorated `View.Native_list.vertical`.
SwiftUI `List.refreshable` owns the gesture and indicator. The SDK does not measure
pull distance, add a threshold or insert a Refresh button row. macOS exposes a
standard toolbar action when the surrounding native navigation/window supports
it; applications can also trigger refresh through `show_token`.

```ocaml
Ui.View.Native_list.vertical
  [ Ui.View.Native_list.section ~key:(Ui.Key.string "items")
      [ Ui.View.Native_list.row ~key:(Ui.Key.string "first")
          (Ui.View.text "First item") ] ]
|> Ui.View.Refresh.vertical
     ~request_token:token ~request_state:phase ~on_request:request_handler
```

The application owns the request token and its `Ready`, `Pending`, `Completed`
state. One admitted request consumes its token. Pending acknowledges the request;
Completed releases that request's async action. A new request requires a new
token. Duplicate invocations wait for the same completion. Cancellation, removal,
scene inactivity and replacement settle native waiters; stale bindings cannot
submit a new token. Changing `show_token` triggers the same admission path.

Scroll, Scroll_sections, Collection and Scroll_targets are not refresh hosts.
No compatibility gesture is installed on them. Compose native List for standard
refresh and keep application data loading and pagination in OCaml.
