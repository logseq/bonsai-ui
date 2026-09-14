import BonsaiSwiftUI
import SwiftUI

@main
struct TodoApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Todo", id: "main") {
        BonsaiApplicationView(entrypoint: "todo")
          .frame(minWidth: 620, minHeight: 360)
      }
      .defaultSize(width: 840, height: 560)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "todo") }
    #endif
  }
}
