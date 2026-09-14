# Native file panel acceptance

September 14, 2026, macOS 26.6.2 arm64, current Debug Host Effects application.
The application was rebuilt through `bonsai-swiftui build macos --profile debug`.
Its OCaml program supplies the import request and export bytes, then displays
the result returned through the production native runtime.

- [Two selected files](import-selection.jpg)
- [OCaml import result](import-result.jpg)
- [System overwrite confirmation](overwrite-confirmation.jpg)
- [OCaml export result](export-result.jpg)

These are original CUA JPEG bytes, without cropping or re-encoding. The result
captures show the application's file section after scrolling; other example
sections are outside the viewport. The capture provider's pointer highlight is
retained. The [manifest](capture-manifest.json) records source, binary, fixture,
copy, export and capture hashes. Source remains uncommitted.

## Reproduce

1. Create a private test directory with `inputs` and `exports` subdirectories.
   In `inputs`, create `Bonsai 中文.txt` containing the UTF-8 string
   `Imported through SwiftUI: 中文 👩🏽‍💻` followed by a newline. Create
   `Bonsai bytes.bin` containing bytes 0 through 255 followed by
   `00 ff 42 6f 6e 73 61 69` in hexadecimal.
2. In Host Effects, select Import files. Use the system Go to Folder command
   to open `inputs`. Focus its file list, press Down then Shift-Down to select
   both files, and choose Open. Confirm `Imported 2 files` in the application.
3. Verify the two session-owned `BonsaiImport-*` copies have the same SHA-256
   hashes as the original fixtures. The original files must remain unchanged.
4. Select Export file and choose `exports`. Keep the suggested name `Bonsai`;
   the saved file is `Bonsai.txt`. Confirm `File exported` and exactly the bytes
   `Exported by Bonsai SwiftUI`, with no newline.
5. Change only that generated export to `Existing test content to replace`.
   Export again to the same destination and choose Replace in the system
   confirmation. Verify that the OCaml export bytes replace the marker.
6. Open and cancel both an import and an export. Confirm `File import cancelled`
   and `File export cancelled`; verify that the original fixtures, imported
   copies and completed export remain unchanged.

Only generated test files were selected or overwritten. This is actual macOS
local-file interaction evidence; it does not establish physical-iOS provider
behavior, every file type, application termination cleanup or all host services.
