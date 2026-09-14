import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func contextualSelectionUsesCurrentIdsForMembershipAndBatchCommands()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    func contains(_ title: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == title }
        return false
      }
    }
    func control(_ title: String) throws -> RenderNodeState {
      var node = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      while node.booleanControlController == nil {
        if case .button = node.properties { return node }
        let child = node
        node = try #require(
          session.tree.nodes.values.first { $0.children.contains { $0 === child } })
      }
      return node
    }
    func request(_ node: RenderNodeState, _ value: Bool) throws -> Bool {
      try #require(node.booleanControlController).request(value, emit: node.emit)
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try control(title)))
      try await flush()
    }
    do {
      try await session.start(entrypoint: "native-contextual-selection")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(contains("Choose items"))
      let first = try control("First item")
      let second = try control("Second item")
      let disabled = try control("Unavailable item")
      #expect(try !request(disabled, true))
      #expect(try request(first, true))
      #expect(try request(second, true))
      try await flush()
      #expect(contains("Selected IDs: -7,9"))
      #expect(contains("2 selected"))
      #expect(try control("First item") === first)
      #expect(try control("Second item") === second)
      let oldArchive = try control("Archive selected")
      try await press("Clear selection")
      #expect(contains("Choose items"))
      #expect(!session.activate(oldArchive))
      #expect(try request(first, true))
      try await flush()
      try await press("Reverse items")
      #expect(try control("First item") === first)
      #expect(try control("Second item") === second)
      try await press("Reject selection changes")
      #expect(try request(second, true))
      try await flush()
      #expect(contains("Selected IDs: -7"))
      #expect(second.booleanControlController?.value == false)
      try await press("Select all items")
      #expect(contains("Selected IDs: -7"))
      try await press("Accept selection changes")
      try await press("Select all items")
      #expect(contains("Selected IDs: -7,9"))
      #expect(disabled.booleanControlController?.value == false)
      let archive = try control("Archive selected")
      try await press("Disable selection")
      #expect(try !request(first, false))
      #expect(!session.activate(archive))
      try await press("Enable selection")
      try await press("Remove first item")
      #expect(try !request(first, false))
      #expect(contains("Selected IDs: 9"))
      #expect(try control("Second item") === second)
      try await press("Archive selected")
      #expect(contains("Selected IDs: None"))
      #expect(contains("Archived IDs: 9"))
      #expect(try !request(second, true))
      #expect(contains("Choose items"))
      try await press("Reset items")
      let newFirst = try control("First item")
      let newSecond = try control("Second item")
      #expect(newFirst !== first)
      #expect(try request(newFirst, true))
      try await flush()
      let batch = try control("Archive selected")
      // The batch handler must read the set after the preceding queued membership intent.
      #expect(try request(newSecond, true))
      #expect(session.activate(batch))
      try await flush()
      #expect(contains("Archived IDs: -7,9"))
      #expect(contains("Selected IDs: None"))
      try await press("Reset items")
      let latest = try control("First item")
      session.isVisible = false
      #expect(try !request(latest, true))
      session.isVisible = true
      try await flush()
      #expect(try request(latest, true))
      try await flush()
      #expect(contains("Selected IDs: -7"))
      await session.close()
      #expect(try !request(latest, false))
    } catch {
      await session.close()
      throw error
    }
  }
}
