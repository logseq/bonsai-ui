import BonsaiSwiftUI
import SwiftUI

@main struct HostEffectsApplication: App {
  #if os(macOS)
    @NSApplicationDelegateAdaptor(HostEffectsDelegate.self) private var delegate
    private var applicationBridge: HostEffectsApplicationBridge { delegate.applicationBridge }
  #else
    private let applicationBridge = HostEffectsApplicationBridge()
  #endif
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

#if os(macOS)
  @MainActor final class HostEffectsDelegate: NSObject, NSApplicationDelegate {
    let applicationBridge = HostEffectsApplicationBridge()
    private var quitTask: Task<Void, Never>?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
      if quitTask != nil { return .terminateLater }
      do {
        guard let shutdown = try applicationBridge.beginShutdown() else { return .terminateNow }
        quitTask = Task {
          let outcome = await shutdown.result
          if outcome != .completed {
            NSLog("Cooperative shutdown: %@", String(describing: outcome))
          }
          sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
      } catch {
        NSLog("Unable to begin cooperative shutdown: %@", String(describing: error))
        return .terminateCancel
      }
    }
  }
#endif
