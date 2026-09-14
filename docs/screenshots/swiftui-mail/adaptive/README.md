# Adaptive Mail captures

Captured on September 14, 2026 from the uncommitted SwiftUI migration.

- `macos-inbox.jpg` and `macos-expanded.jpg`: actual 1200 × 760 macOS
  application-window screenshots captured with Computer Use after restarting
  the latest Debug build. The expanded state follows the native accessibility
  action on Mara Vale's row and the resulting OCaml state update.
- `ios-normal-type.png` and `ios-accessibility-type.png`: 1170 × 2532 window
  images attached by the Release hosted XCTest on a physical iPhone 13 running
  iOS 26.6.1. These show `.large` and `.accessibility3` respectively; the latter
  uses two-line subjects and previews, with the timestamp beneath the preview.
  They are hosted-test window captures, not Simulator or system UI automation
  screenshots. Source result: `/tmp/swiftui-mail-large-ios-final.xcresult`,
  `testMailRowsGrowWithPhysicalDynamicType`, which passed in 7.080 seconds.

The native macOS acceptance run also verifies expansion, a column-width change
from 560 to 340 points, increased measured height, the stable top anchor and row
identity, collapse, re-expansion and Archive. Its log is
`/tmp/swiftui-mail-adaptive-columns.log` (passed, 16.976 seconds).

The original two-test iOS run had a subsequent startup/restart test failure;
that case passed alone but failed again after the UI test. The UI test now
unmounts Mail while it still owns the window, waits for the view update and
checks that its scroll views are gone before returning. With this teardown,
both tests pass consecutively: 2 tests, 0 failures, 8.660 seconds in
`/tmp/swiftui-mail-adaptive-teardown.xcresult` (matching `.log` file).
This result covers these two hosted tests only, not the remaining physical
gesture, IME or host-service acceptance gates.
