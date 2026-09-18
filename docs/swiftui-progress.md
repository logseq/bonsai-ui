# System progress

`View.progress` renders SwiftUI `ProgressView`. Control size, tint, accessibility,
Reduce Motion and scene animation policy are owned by the system. It installs no
SDK TimelineView or custom progress style. Use semantics to supply an activity label.

| Style | Value | iOS 26+ and macOS 26+ contract |
| --- | --- | --- |
| Automatic (default) | omitted | System activity indicator |
| Automatic | 0…1 | System determinate progress |
| Linear | 0…1 | System linear determinate progress |
| Circular | omitted | System circular activity indicator |
| Linear | omitted | Rejected |
| Circular | supplied | Rejected |

Values must be finite and in 0…1. Unsupported combinations fail at construction
and decoding. They never silently become indefinite activity. Apple documents
that circular progress can become indeterminate when a determinate circular style
is unavailable: [circular style](https://developer.apple.com/documentation/swiftui/progressviewstyle/circular).
The portable SDK contract therefore reserves Circular for activity.

```ocaml
Ui.View.progress ()
Ui.View.progress ~style:Ui.View.Progress_style.Linear ~value:0.4 ()
Ui.View.progress ~style:Ui.View.Progress_style.Circular ()
```

A changing style retains logical node identity. Presentation is intentionally
platform dependent. Exact animation frames are not a public SDK guarantee.
