# Native Image Resources

`View.image` loads a bundle resource or an absolute HTTP(S) URL and renders
the decoded pixels with SwiftUI `Image`. OCaml owns the source and presentation
properties. The mounted Swift node owns loading, decoded frames and playback.

```ocaml
View.image
  ~source:(Style.Image_source.resource "gallery-demo.png")
  ~sizing:Style.Image_sizing.Fit
  ~scale:2.
  ()
|> View.frame ~width:240. ~height:80.
```

Use `Style.Image_source.remote "https://example.com/image.png"` for a network
image. Resource names are relative file paths beneath the application's
resource directory. Absolute paths, empty components, traversal, backslashes
and NUL are invalid. The native loader resolves symlinks and rejects paths
outside that directory. These are raw bundled files, not asset-catalog names;
there is no automatic `@2x` filename selection.

## Sizing

| Value | SwiftUI behavior |
| --- | --- |
| `Original` (default) | Preserve intrinsic pixel dimensions divided by `scale`. |
| `Stretch` | Apply `resizable()` and accept the proposed size. |
| `Fit` | Apply `resizable().aspectRatio(contentMode: .fit)`. |
| `Fill` | Apply `resizable().aspectRatio(contentMode: .fill)`. |

`scale` is a positive finite number of pixels per point and defaults to 1.
Compose frames and clipping explicitly. Fill may paint outside its frame;
the image does not install an implicit clip. Flutter's seven `Image_fit` modes
and image-specific width/height property bag have been removed.

Decoded images use SwiftUI's decorative image initializer. Loading presents a
native `ProgressView`; failure presents an SF Symbol with the accessibility
label `Image unavailable`. Meaningful application image descriptions belong
to the semantic accessibility wrapper, whose broader migration is unfinished.

## Loading and lifetime

ImageIO decoding and resource reads run outside the main actor. Network loading
uses URLSession and the platform's transport policy. The renderer does not
install insecure transport exceptions. Only successful HTTP status codes are
accepted. The request timeout is at most 30 seconds; URLSession's request
timeout is an inactivity timeout, not an overall elapsed-time deadline.

Each image has limits of 16 MiB encoded bytes, 16 million decoded pixels
(16 × 1024 × 1024, summed across frames), and 256 animation frames. These are
per-resource limits, not a process-wide cache or memory guarantee. Response
length is checked when available, and streamed bytes are bounded even when
the length is absent or misleading. Image dimensions are checked before
allocating decoded frames. ImageIO applies orientation metadata.

Each download owns its URLSession delegate and task. Completion or cancellation
resumes its continuation once, cancels the task and invalidates that session.
It does not invalidate a shared session. Changing the source cancels loading
and clears the old result. A generation check rejects late completion even if
the underlying loader ignores cancellation. Resizing and keyed reordering
retain the resource; removing or replacing its node, changing epochs, or
closing the application releases it.

The protocol stages properties without starting I/O. A resource is created
only when a validated frame is committed to `RenderTree`.

## Animated images

ImageIO GIF, APNG and WebP timing metadata selects decoded frames locally;
playback does not send per-frame events to OCaml. A monotonic clock prevents
wall-clock adjustments from changing playback. Timing defaults to 100 ms and
positive frame delays have a 20 ms minimum. A finite animation holds its final
frame; an infinite animation repeats. Same-source presentation updates retain
the playback position. Reduce Motion displays the first frame and pauses the
timeline. Other multipage formats display their first page.

The deterministic GIF fixture verifies two distinct frames, delays, looping,
finite completion selection, monotonic elapsed time and reduced-motion frame
selection. APNG and WebP metadata paths exist but do not yet have equivalent
format-specific fixtures; their full codec coverage is not claimed.

## Resources and verification

`tool/generate_gallery_images.py` generates the small PNG and animated GIF
under `examples/gallery/resources`; `--check` verifies reproducibility.
The macOS development builder copies an example's `resources` directory into
its bundle's `Contents/Resources`. Production CLI and iPhoneOS resource
packaging remain part of the wider migration.

Node kind 5 carries source (resource/remote tag plus UTF-8 location), sizing
(0–3), and scale (required f64). Full and incremental updates use mask 7.
OCaml constructors, codecs and Swift decoding reject invalid properties;
malformed updates cannot publish a partial tree. The node is a leaf.

Tests compare all four sizing modes and two scales with native SwiftUI in
LTR/RTL, exercise real OCaml property updates without remounting or reloading,
and load every image in the actual Gallery component. Network tests cover
finite images and unfinished responses with error status, excessive declared
length, or excessive streamed bytes; a local TCP server confirms connection
closure after rejection. Small unfinished responses can delay URLSession
response delivery: these cancellation tests use a 1024-byte unfinished prefix
under a 2048-byte test limit, rather than relying on one-byte response timing.

Gallery artifacts are `gallery-images-ltr.png` and `gallery-images-rtl.png`
under `_build/validation`, generated by
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`.
They use a fixed monotonic clock to capture the first animation frame. They
are offscreen component renders, not standalone application screenshots or
the required Mail captures.
