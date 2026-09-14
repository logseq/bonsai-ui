import BonsaiSwiftUI
import Foundation
import Observation
import SwiftUI

enum GalleryCardEvent { case activate }

@MainActor @Observable final class GalleryCardResource {
  var localActivations = 0
}

@MainActor enum GalleryNativeViews {
  static func make() throws -> BonsaiNativeViews {
    var views = BonsaiNativeViews()
    try views.register(
      kind: 1001, version: 1, capabilities: [.stateful, .resource, .semantics],
      decode: { data -> String in
        guard let value = String(data: data, encoding: .utf8) else {
          throw CocoaError(.coderReadCorrupt)
        }
        return value
      },
      encodeEvent: { (_: GalleryCardEvent) in BonsaiNativeEvent(id: 1) },
      makeResource: { GalleryCardResource() },
      dispose: { $0.localActivations = 0 },
      content: { context in GalleryCard(context: context) })
    return views
  }
}

private struct GalleryCard: View {
  let context: BonsaiNativeContext<String, GalleryCardEvent, GalleryCardResource>

  var body: some View {
    VStack {
      Button(context.properties) {
        if context.emit(.activate) { context.resource.localActivations += 1 }
      }
      .disabled(!context.isPresented)
      Text("Local activations: \(context.resource.localActivations)")
      ForEach(context.children) { $0 }
    }
  }
}
