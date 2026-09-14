import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryTagActionsSelectionsAndRemovalRemainIndependent() async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    func label(_ title: String) -> RenderNodeState? {
      session.tree.nodes.values.first {
        if case .text(let text) = $0.properties { return text.value == title }
        return false
      }
    }
    func control(_ title: String) throws -> RenderNodeState {
      var node = try #require(label(title))
      while node.booleanControlController == nil {
        if case .button = node.properties { return node }
        let child = node
        node = try #require(
          session.tree.nodes.values.first { $0.children.contains { $0 === child } })
      }
      return node
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try control(title)))
      try await flush()
    }
    func select(_ node: RenderNodeState, _ value: Bool) throws -> Bool {
      try #require(node.booleanControlController).request(value, emit: node.emit)
    }
    do {
      try await session.start(entrypoint: "native-tags")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(label("Actions: 0") != nil)
      #expect(session.tree.nodes.values.contains { $0.kind == 56 })
      #expect(label("Remove Pinned") == nil)
      #expect(
        session.tree.nodes.values.contains {
          if case .symbol = $0.properties { return true }
          return false
        })
      try await press("Assist")
      try await press("Suggestion")
      #expect(label("Actions: 2") != nil)
      let filter = try control("Filter")
      let suggested = try control("Suggested")
      let work = try control("Work")
      let personal = try control("Personal")
      let remove = try control("Remove Personal")
      #expect(suggested.booleanControlController?.value == true)
      #expect(try select(filter, true))
      #expect(try select(suggested, false))
      #expect(try select(work, true))
      try await flush()
      #expect(filter.booleanControlController?.value == true)
      #expect(suggested.booleanControlController?.value == false)
      #expect(label("Actions: 2") != nil)
      let workLabel = work.children[0]
      try await press("Reverse tags")
      #expect(try control("Work") === work)
      #expect(work.children[0] === workLabel)
      try await press("Ignore tag changes")
      for _ in 0..<2 {
        #expect(try select(work, false))
        #expect(session.activate(remove))
        #expect(!(try await session.refresh()))
        #expect(work.booleanControlController?.value == true)
        #expect(try control("Personal") === personal)
      }
      try await press("Accept tag changes")
      let stale = try #require(work.booleanControlController).binding(emit: work.emit)
      try await press("Disable tags")
      #expect(!session.activate(remove))
      #expect(!session.activate(try control("Assist")))
      #expect(try !select(work, false))
      try await press("Enable tags")
      stale.wrappedValue = false
      #expect(!(try await session.refresh()))
      #expect(try select(personal, true))
      #expect(session.activate(remove))
      try await flush()
      #expect(label("Personal") == nil)
      #expect(label("Remove Personal") == nil)
      #expect(work.booleanControlController?.value == true)
      #expect(label("Actions: 2") != nil)
      #expect(!session.activate(remove))
      #expect(try !select(personal, true))
      try await press("Restore tags")
      let restored = try control("Personal")
      #expect(restored !== personal)
      #expect(restored.booleanControlController?.value == false)
      #expect(!session.activate(remove))
      await session.close()
      #expect(try !select(work, true))
    } catch {
      await session.close()
      throw error
    }
  }
}
