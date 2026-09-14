import BonsaiSwiftUI
import SwiftUI

@main
struct GalleryApplication: App {
  private let nativeViews = try! GalleryNativeViews.make()

  var body: some Scene {
    #if os(macOS)
      Window("Bonsai SwiftUI Gallery", id: "gallery") {
        BonsaiApplicationView(entrypoint: "gallery", nativeViews: nativeViews)
          .frame(minWidth: 900, minHeight: 600)
      }
      .defaultSize(width: 1200, height: 800)
    #else
      WindowGroup {
        BonsaiApplicationView(entrypoint: "gallery", nativeViews: nativeViews)
      }
    #endif
  }
}
