# Mail captures from committed SwiftUI source

Captured on September 14, 2026 from source commit
`11d75d45e5006b281faa2656ee029e83c336491a`, using the ad-hoc-signed macOS
Debug application. The app links the real OCaml Mail program and was restarted
after rebuilding the native SwiftUI host.

| Capture | Observed state |
| --- | --- |
| [Inbox](macos-inbox.jpg) | Fresh launch with the initial messages. |
| [Expanded](macos-expanded.jpg) | An ordinary mouse click expands Mara's inline preview. |
| [Attachment detail](macos-detail-attachment.jpg) | Open Juniper's message; its body and PDF attachment are visible. |
| [Swipe actions](macos-swipe-actions.jpg) | A mouse drag reveals Archive and Trash without expanding Mara. |
| [Archived](macos-archived.jpg) | Click the exposed Archive button; Mara moves into Archived through OCaml. |

Each image is the original 1200 × 760 CUA application-window JPEG. No crop,
resize, retouching or generated image content was applied. The app owns its
light palette; system appearance was not changed. Native capture indicators,
pointer highlights and inactive-window appearance remain in the captured pixels.

The [manifest](capture-manifest.json) records the source revision, app binary,
native object, build log and image hashes. The OCaml object comes from the
verified clean source export of the parent migration commit; its relevant
sources are unchanged by the macOS gesture fix. The final
[accessibility state](archived-accessibility.txt) confirms the Archived mailbox
and the retained Mara message.

The initial capture attempt exposed a real Button/pan arbitration defect.
The fix and failing/passing tests are described in
[the swipe contract](../../../swiftui-swipe-actions.md). All images here were
replaced after the fix, including a successful CUA mouse drag and Archive click.
The native Mail regression passes under light and dark host appearances;
LTR/RTL/vertical swipe, eight directional removal cases and ten focused Swift
tests also pass. A subsequent complete Swift regression passed all 489 tests
in 107 suites in 486.197 seconds against the same runtime source; its result
is recorded separately in the manifest. These captures do not establish physical-iOS acceptance or
remote source/SDK publication.

Rebuild from the example directory using the public CLI and the verified
macOS OCaml complete object:

```sh
BONSAI_SWIFTUI_SOURCE_ROOT="$REPOSITORY_ROOT" \
  "$REPOSITORY_ROOT/_build/default/bonsai_swiftui_tool/bin/main.exe" \
  build macos --profile debug --native-object "$MAIL_NATIVE_OBJECT"
```

Restart the resulting Debug `BonsaiMail.app`. Capture Inbox, drag Mara to the
right, close actions, click to expand and collapse it, then expand and open
Juniper. Return to the list, drag Mara again, click Archive and select Archived.
The manifest identifies the exact build input used for these captures.
