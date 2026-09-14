import BonsaiSwiftUI
import SwiftUI

@main struct SQLiteWorkerApplication: App {
  private let startup = Result { try SQLiteWorkerStartup.prepare() }
  var body: some Scene {
    #if os(macOS)
      Window("SQLite Worker Todo", id: "main") {
        content.frame(minWidth: 360, minHeight: 500)
      }.defaultSize(width: 680, height: 900)
    #else
      WindowGroup { content }
    #endif
  }

  @ViewBuilder private var content: some View {
    switch startup {
    case .success(let payload):
      BonsaiApplicationView(entrypoint: "sqlite_worker", payload: payload)
    case .failure(let error):
      ContentUnavailableView(
        "Unable to open local storage", systemImage: "externaldrive.badge.exclamationmark",
        description: Text(error.localizedDescription))
    }
  }
}
