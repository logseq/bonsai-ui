import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualCompleteGalleryStartsAndDispatches() async throws {
    var views = BonsaiNativeViews()
    try views.register(
      kind: 1001, version: 1, capabilities: [.stateful, .resource, .semantics],
      decode: { data -> String in
        guard let value = String(data: data, encoding: .utf8) else {
          throw WireError.invalidHeader
        }
        return value
      },
      encodeEvent: { (_: Void) in BonsaiNativeEvent(id: 1) },
      makeResource: { () }, dispose: { _ in },
      content: { context in Button(context.properties) { _ = context.emit(()) } })
    let session = BonsaiSession(nativeViews: views)
    session.isVisible = true
    func named(_ title: String, in node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties, text.value == title { return true }
      return node.children.contains { named(title, in: $0) }
    }
    do {
      try await session.start(entrypoint: "full-gallery")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(
        named(
          "OCaml owns every value and handler on this page", in: try #require(session.tree.root)))
      let increment = try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named("Increment counter", in: $0) }
          return false
        })
      #expect(session.activate(increment))
      _ = try await session.refresh()
      #expect(try await session.presented(#require(session.ticket)))
      #expect(named("Persistent bottom content · Actions: 1", in: try #require(session.tree.root)))
      await session.close()
      #expect(!session.activate(increment))
    } catch {
      await session.close()
      throw error
    }
  }
}
