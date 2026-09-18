# Native forms and diagnostic content

`View.Form.vertical` renders a grouped SwiftUI Form on iOS 26 and macOS 26.
Rows and sections have explicit sibling keys. The result is a vertical viewport:
place it in a bounded Body slot, or explicitly supply a finite height.

```ocaml
let keyed key = View.Keyed.create ~key:(Key.string key) in
let diagnostics =
  View.Section.create
    ~header:(View.text "Diagnostics")
    ~footer:(View.text "Application-owned, selectable values")
    [ keyed "revision"
        (View.labeled_content
           ~label:(View.text "Revision")
           ~value:(View.text "abc123" |> View.text_selection ~enabled:true)
           ())
    ]
in
let unavailable =
  View.content_unavailable
    ~label:(View.label
              ~title:(View.text "No entries")
              ~icon:(View.symbol ~name:"book.closed" ()) ())
    ~description:(View.text "Create your first journal entry")
    ~actions:(View.button ~on_press:create ~child:(View.text "Create entry") ())
    ()
in
View.Body.Vertical.create
  [ View.Body.Vertical.fill
      (View.Form.vertical
         [ keyed "diagnostics" diagnostics; keyed "unavailable" unavailable ])
  ]
```

`Section.create` is also an ordinary view and can be reused outside a Form.
Its header/footer are optional ordinary views and its content is keyed. Header
and footer slots have independent structural ownership; toggling their presence
does not shift row identity. Reordering sibling keys retains their mounted nodes.
Duplicate sibling keys are rejected. Put a Section directly in Form to preserve
its native grouping, and place row decoration inside its content slots.

`labeled_content` uses independent label/value slots. `content_unavailable` uses
label, optional description, and optional actions. These slots can contain normal
OCaml buttons, including disabled and destructive buttons. Their state and
handlers remain in OCaml; these display containers do not synthesize commands.

`text_selection ~enabled:true` applies native selection to descendant text. A
nearer `~enabled:false` disables it. Selection does not introduce an editable
field or write to the application value. Use the existing text editor/field APIs
when editing is intended.

Wire nodes are Form 140 (no properties), Section 141 (header/footer flags),
LabeledContent 142 and ContentUnavailableView 143 (no properties), and
TextSelection 144 (enabled flag). The decoder validates slot arity and forbids
bindings on display containers before publication. Retired node 136 stays
rejected. No Dune files or protected spec interfaces are changed.

`NativeFormTests` verifies actual SwiftUI Section structure through the erased
renderer using `Group(sections:)`; native Form accessibility and geometry match a
direct SwiftUI reference within one point. It verifies one scroll container,
noneditable diagnostics, ordinary button activation, keyed reordering, malformed
input rejection, and real OCaml state changes. The `native-form` runtime fixture
and Gallery exercise the public constructors. iOS interaction and text-selection
gestures still need device evidence; typechecking alone is not interaction proof.

Controlled destructive decisions use [native confirmations](swiftui-confirmation.md).
