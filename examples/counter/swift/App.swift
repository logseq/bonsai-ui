import BonsaiSwiftUI
import SwiftUI

@main
struct CounterApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Counter", id: "main") {
        BonsaiApplicationView(entrypoint: "counter")
          .frame(minWidth: 320, minHeight: 240)
      }
      .defaultSize(width: 440, height: 320)
    #else
      WindowGroup {
        BonsaiApplicationView(entrypoint: "counter")
      }
    #endif
  }
}
