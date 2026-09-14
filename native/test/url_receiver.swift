import AppKit

@MainActor private final class ReceiverDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    do {
      guard let path = Bundle.main.object(forInfoDictionaryKey: "BonsaiReceiptPath") as? String
      else { throw CocoaError(.fileNoSuchFile) }
      let receipt = URL(fileURLWithPath: path)
      let previous =
        (try? Data(contentsOf: receipt)).flatMap {
          try? JSONDecoder().decode([String].self, from: $0)
        } ?? []
      try JSONEncoder().encode(previous + urls.map(\.absoluteString)).write(
        to: receipt, options: .atomic)
    } catch {
      print("URL receiver failed: \(error)")
      fflush(stdout)
      exit(1)
    }
  }
}

@main private struct URLReceiverApplication {
  @MainActor static func main() {
    let application = NSApplication.shared
    let delegate = ReceiverDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    // Bound the test process lifetime even if its parent exits unexpectedly.
    Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in exit(0) }
    withExtendedLifetime(delegate) { application.run() }
  }
}
