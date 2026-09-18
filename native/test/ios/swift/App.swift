import BonsaiSwiftUI
import SwiftUI

@main
struct JournalNativeAcceptanceApplication: App {
  var body: some Scene {
    WindowGroup {
      BonsaiApplicationView(
        entrypoint: ProcessInfo.processInfo.environment["BONSAI_NATIVE_ENTRYPOINT"]
          ?? "native-confirmation")
    }
  }
}
