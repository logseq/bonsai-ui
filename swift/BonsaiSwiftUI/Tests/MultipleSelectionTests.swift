import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryMultipleSelectionCombinesIndependentIntents() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func control(_ title: String) throws -> RenderNodeState {
      let label = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      var node = label
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
    func request(_ node: RenderNodeState, _ value: Bool) throws -> Bool {
      try #require(node.booleanControlController).request(value, emit: node.emit)
    }
    do {
      try await session.start(entrypoint: "native-multiple-selection")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(
        session.tree.nodes.values.filter {
          if case .symbol = $0.properties { return true }
          return false
        }.count == 4)
      let first = try control("Buttons First")
      let second = try control("Buttons Second")
      let disabled = try control("Buttons Disabled")
      let firstCheckbox = try control("Checkboxes First")
      let secondCheckbox = try control("Checkboxes Second")
      #expect(session.tree.nodes.values.filter { $0.booleanControlController != nil }.count == 6)
      #expect(try request(first, true))
      #expect(try request(second, true))
      try await flush()
      #expect(firstCheckbox.booleanControlController?.value == true)
      #expect(secondCheckbox.booleanControlController?.value == true)
      #expect(try request(first, false))
      #expect(try await session.refresh())
      let response = try #require(session.ticket)
      #expect(try request(second, false))
      #expect(try request(first, true))
      #expect(try await session.presented(response))
      try await flush()
      #expect(firstCheckbox.booleanControlController?.value == true)
      #expect(secondCheckbox.booleanControlController?.value == false)
      let firstLabel = first.children[0]
      try await press("Reverse choices")
      #expect(try control("Buttons First") === first)
      #expect(first.children[0] === firstLabel)
      #expect(try request(firstCheckbox, false))
      try await flush()
      #expect(first.booleanControlController?.value == false)
      try await press("Ignore choices")
      for _ in 0..<2 {
        #expect(try request(first, true))
        #expect(!(try await session.refresh()))
        #expect(first.booleanControlController?.value == false)
      }
      try await press("Accept choices")
      let stale = try #require(first.booleanControlController).binding(emit: first.emit)
      try await press("Disable choices")
      #expect(!first.emit(.valueChanged(true)))
      #expect(try !request(first, true))
      #expect(try !request(disabled, true))
      try await press("Enable choices")
      stale.wrappedValue = true
      #expect(!(try await session.refresh()))
      #expect(try request(second, true))
      try await flush()
      try await press("Clear choices")
      #expect(
        session.tree.nodes.values.filter { $0.booleanControlController != nil }.allSatisfy {
          $0.booleanControlController?.value == false
        })
      await session.close()
      #expect(try !request(first, true))
    } catch {
      await session.close()
      throw error
    }
  }
}
