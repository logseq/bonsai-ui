import BonsaiSwiftUI
import SwiftUI

@main
struct MailApplication: App {
  var body: some Scene {
    #if os(macOS)
      Window("Bonsai Mail", id: "mail") {
        BonsaiApplicationView(entrypoint: "mail")
          .frame(minWidth: 900, minHeight: 500)
      }
      .defaultSize(width: 1200, height: 760)
    #else
      WindowGroup { BonsaiApplicationView(entrypoint: "mail") }
    #endif
  }
}
