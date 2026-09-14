import Foundation

#if !BONSAI_STANDALONE_TEST
  import BonsaiSwiftUI
#endif

/// The example owns this two-byte version/tag prefix and its ASCII payloads.
@MainActor final class HostEffectsApplicationBridge {
  private var observer: NSObjectProtocol?

  var bridge: BonsaiApplicationBridge {
    BonsaiApplicationBridge(
      request: { request in
        guard request == Data([1, 1]) else {
          throw BonsaiApplicationError.handlerFailed("Unknown application request")
        }
        guard let identifier = Bundle.main.bundleIdentifier else {
          throw BonsaiApplicationError.unavailable
        }
        return Data([1, 1]) + Data(identifier.utf8)
      },
      connected: { [weak self] events in
        self?.observer = NotificationCenter.default.addObserver(
          forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { _ in
          MainActor.assumeIsolated {
            do {
              try events.send(Data([1, 2]) + Data(TimeZone.autoupdatingCurrent.identifier.utf8))
            } catch {
              // This example observes changes; a saturated or closed host does
              // not require retrying an obsolete time-zone notification.
            }
          }
        }
      },
      disconnected: { [weak self] in
        if let observer = self?.observer { NotificationCenter.default.removeObserver(observer) }
        self?.observer = nil
      })
  }
}
