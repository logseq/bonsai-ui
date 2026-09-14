import BonsaiSwiftUI
import SwiftUI

@main
struct ClockApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Clock", id: "main") {
        BonsaiApplicationView(entrypoint: "clock")
          .frame(minWidth: 420, minHeight: 360)
      }
      .defaultSize(width: 720, height: 800)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "clock") }
    #endif
  }
}
