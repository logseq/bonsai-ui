import BonsaiSwiftUI
import SwiftUI

@main
struct TextInputApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Text Input", id: "main") {
        BonsaiApplicationView(entrypoint: "text_input")
          .frame(minWidth: 320, minHeight: 180)
      }
      .defaultSize(width: 640, height: 400)
    #else
      WindowGroup {
        BonsaiApplicationView(entrypoint: "text_input")
      }
    #endif
  }
}
