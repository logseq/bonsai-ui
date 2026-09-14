import BonsaiSwiftUI
import SwiftUI

@main struct NetworkApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Secure Network Lab", id: "main") {
        BonsaiApplicationView(entrypoint: "network")
          .frame(minWidth: 360, minHeight: 440)
      }.defaultSize(width: 680, height: 900)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "network") }
    #endif
  }
}
