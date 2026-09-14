import BonsaiSwiftUI
import SwiftUI

@main
struct NavigationApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Navigation", id: "main") {
        BonsaiApplicationView(entrypoint: "navigation")
          .frame(minWidth: 360, minHeight: 260)
      }
      .defaultSize(width: 520, height: 400)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "navigation") }
    #endif
  }
}
