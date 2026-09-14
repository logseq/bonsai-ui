import BonsaiSwiftUI
import SwiftUI

@main struct HostEffectsApplication: App {
  private let applicationBridge = HostEffectsApplicationBridge()
  var body: some Scene {
    #if os(macOS)
      Window("Host Effects", id: "main") {
        BonsaiApplicationView(
          entrypoint: "host_effects", applicationBridge: applicationBridge.bridge
        )
        .frame(minWidth: 360, minHeight: 320)
      }.defaultSize(width: 640, height: 480)
    #else
      WindowGroup {
        BonsaiApplicationView(
          entrypoint: "host_effects", applicationBridge: applicationBridge.bridge)
      }
    #endif
  }
}
