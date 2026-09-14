import BonsaiSwiftUI
import SwiftUI

@main
struct HostNavigationApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Host Navigation", id: "main") {
        BonsaiApplicationView(entrypoint: "host_navigation")
          .frame(minWidth: 360, minHeight: 360)
      }
      .defaultSize(width: 640, height: 520)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "host_navigation") }
    #endif
  }
}
