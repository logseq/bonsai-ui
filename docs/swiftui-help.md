# Native help text

`View.help ~message child` replaces `Material.Tooltip.plain`. It adds SwiftUI
`.help(Text(verbatim: message))` to its existing child. SwiftUI provides the native
macOS help tag and accessibility hint; iOS uses the platform accessibility
presentation. The OCaml message is already localized and is not interpreted as a
SwiftUI localization key. See [Apple's help documentation](https://developer.apple.com/documentation/swiftui/view/help%28_%3A%29-6oiyb).

```ocaml
View.help
  ~message:"Move this message to the archive"
  (View.button ~on_press:archive ~child:(View.text "Archive") ())
```

Help does not add an action, intercept activation or change a child's enabled
state. Updating its message retains the child identity. The message must contain
at least one character after OCaml `String.trim`; space, tab, newline, carriage
return and form feed are trimmed for validation. Other valid UTF-8 is preserved.
The OCaml constructor, codec and Swift decoder use the same rule. Both codecs
retain the existing UTF-8 and maximum string-size checks.

Node 63 (`help`) carries one string property with full mask 1, exactly one child
and no event bindings. Invalid updates are rejected transactionally, including
empty messages, missing/extra children, extra bindings and truncated payloads.

Gallery's `help_component` is embedded directly by `native-help`. The actual
OCaml/native integration test activates the help-bearing Button twice, updates
the Unicode hint, disables and re-enables the action, and verifies the resulting
OCaml count. Separate native-window tests verify the accessibility help text,
retained child identity and action routing after multiple updates. Malformed
frame tests preserve the previous committed revision. The initial tests failed
on unsupported native node 63 and the old expressive node 136. A Unicode-space
regression also failed before the Swift validation matched the OCaml contract.

## Rich help and remaining acceptance

Rich help now composes `View.Popover`, ordinary text and independent Buttons.
`Material.Tooltip.rich` and the remaining old renderer branch are removed. See
[controlled native popovers](swiftui-popover.md) for its OCaml-owned visibility,
native dismissal and interaction lifecycle.

The complete Gallery App, physical macOS hover presentation, VoiceOver and
physical iOS acceptance remain outstanding. Compilation is not device-runtime
acceptance, and no Simulator target is supported.
