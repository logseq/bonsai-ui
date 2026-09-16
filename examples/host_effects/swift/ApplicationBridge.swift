import Foundation

#if !BONSAI_STANDALONE_TEST
  import BonsaiSwiftUI
#endif

/// The example owns this two-byte version/tag prefix and its ASCII payloads.
@MainActor final class HostEffectsApplicationBridge {
  private var observer: NSObjectProtocol?
  private var events: BonsaiApplicationEvents?

  /// Called by the application delegate before releasing native Quit deferral.
  func beginShutdown() throws -> BonsaiApplicationShutdown? {
    try events?.beginShutdown(
      event: Data([1, 12]), timeout: .seconds(4),
      accepting: { $0 == Data([1, 13]) },
      request: { _ in .finish(Data([1, 13])) })
  }

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
        self?.events = events
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
        self?.events = nil
      })
  }
}
