import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualAppBarsKeepPageCommandsWithinTheirNavigationScope() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func button(_ label: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains {
              if case .text(let text) = $0.properties { return text.value == label }
              return false
            }
          }
          return false
        })
    }
    func hasText(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-app-bars")
      #expect(try await session.presented(#require(session.ticket)))
      let top = try button("Top action")
      let footer = try button("Bottom action")
      let scroll = try #require(session.tree.nodes.values.first { $0.kind == NodeKindId.scroll })
      #expect(session.activate(top))
      #expect(session.activate(footer))
      try await flush()
      #expect(hasText("Bar actions: 2"))
      #expect(session.activate(try button("Resize bottom content")))
      try await flush()
      #expect(session.tree.nodes[scroll.id.node] === scroll)
      #expect(session.activate(try button("Open bar details")))
      try await flush()
      #expect(!session.activate(top))
      #expect(!session.activate(footer))
      let detail = try button("Detail action")
      #expect(session.activate(detail))
      try await flush()
      #expect(hasText("Bar actions: 3"))
      #expect(session.activate(try button("Close bar details")))
      try await flush()
      #expect(!session.activate(detail))
      #expect(try button("Top action") === top)
      #expect(try button("Bottom action") === footer)
      #expect(session.tree.nodes[scroll.id.node] === scroll)
      #expect(session.activate(top))
      try await flush()
      #expect(hasText("Bar actions: 4"))
      session.isVisible = false
      #expect(!session.activate(top))
      await session.close()
      #expect(!session.activate(top))
    } catch {
      await session.close()
      throw error
    }
  }
}
