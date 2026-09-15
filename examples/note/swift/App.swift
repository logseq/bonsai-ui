import BonsaiSwiftUI
import SwiftUI

@main
struct NoteApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Bonsai Note", id: "note") {
        BonsaiApplicationView(entrypoint: "note")
          .frame(minWidth: 320, minHeight: 500)
      }
      .defaultSize(width: 520, height: 860)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "note") }
    #endif
  }
}
