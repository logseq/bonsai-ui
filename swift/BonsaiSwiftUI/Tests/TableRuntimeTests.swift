import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func tableFencesHiddenDetailsAndRetainsControlledSelection() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func control(_ title: String) throws -> RenderNodeState {
      var node = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      while true {
        if case .button = node.properties { return node }
        let child = node
        node = try #require(
          session.tree.nodes.values.first { $0.children.contains { $0 === child } })
      }
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-table")
      #expect(try await session.presented(#require(session.ticket)))
      let node = try #require(session.tree.nodes.values.first { $0.tableController != nil })
      let controller = try #require(node.tableController)
      #expect(!session.activate(try control("Explain ranks")))
      #expect(controller.request(.tableSelection(-7, true), emit: node.emit))
      #expect(controller.request(.tableSelection(9, true), emit: node.emit))
      #expect(!controller.request(.tableSelection(13, true), emit: node.emit))
      #expect(!controller.request(.tableSelection(99, true), emit: node.emit))
      #expect(!controller.request(.tableSort(3, true), emit: node.emit))
      try await flush()
      #expect(controller.selection == [-7, 9])
      let stale = controller.selectionBinding(emit: node.emit)
      let first = try control("Open First item")
      #expect(session.activate(try control("Remove first table row")))
      try await flush()
      stale.wrappedValue = []
      #expect(controller.selection == [9])
      #expect(!session.activate(first))
      #expect(session.activate(try control("Clear table selection")))
      try await flush()
      let clear = try control("Clear table selection")
      for _ in 0..<1024 { #expect(session.activate(clear)) }
      #expect(!controller.request(.tableSelection(9, true), emit: node.emit))
      #expect(controller.selection.isEmpty)
      try await flush()
      session.isVisible = false
      #expect(!controller.request(.tableSelection(9, true), emit: node.emit))
      session.isVisible = true
      #expect(controller.request(.tableSelection(9, true), emit: node.emit))
      try await flush()
      #expect(controller.selection == [9])
      await session.close()
      #expect(!controller.request(.tableSelection(9, false), emit: node.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}
