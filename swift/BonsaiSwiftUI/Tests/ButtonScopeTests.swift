import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryButtonScopesPreserveActivationAndIdentity() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ title: String, in node: RenderNodeState) -> Bool {
      switch node.properties {
      case .text(let text): if text.value == title { return true }
      case .semantics(let semantics): if semantics.label == title { return true }
      default: break
      }
      return node.children.contains { named(title, in: $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(title, in: $0) }
          return false
        })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      try await flush()
    }
    do {
      try await session.start(entrypoint: "native-buttons")
      #expect(try await session.presented(#require(session.ticket)))
      let automatic = try button("Automatic")
      let refresh = try button("Refresh")
      let original = [automatic, refresh, try button("Bordered"), try button("Prominent")]
      #expect(session.tree.nodes.values.contains { $0.kind == 55 })
      for (index, size) in ["Large", "Extra large", "Mini", "Small", "Regular"].enumerated() {
        try await press("Next control size")
        #expect(named("Size: \(size)", in: try #require(session.tree.root)))
        try await press("Automatic")
        try await press("Refresh")
        #expect(named("Button actions: \((index + 1) * 2)", in: try #require(session.tree.root)))
        #expect(try button("Automatic") === automatic)
        #expect(try button("Refresh") === refresh)
        #expect(original.allSatisfy { session.tree.nodes[$0.id.node] === $0 })
      }
      try await press("Disable buttons")
      #expect(!session.activate(automatic))
      #expect(!session.activate(refresh))
      try await press("Enable buttons")
      session.isVisible = false
      #expect(!session.activate(automatic))
      session.isVisible = true
      try await press("Bordered")
      #expect(named("Button actions: 11", in: try #require(session.tree.root)))
      await session.close()
      #expect(!session.activate(refresh))
    } catch {
      await session.close()
      throw error
    }
  }
}
