import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualWorkflowSelectsStepsAndFencesInactiveContent() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ title: String, in node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties, text.value == title { return true }
      return node.children.contains { named(title, in: $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(title, in: $0) }
          return false
        })
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-workflow")
      #expect(try await session.presented(#require(session.ticket)))
      let edit = try button("Edit")
      let body = try button("Act in Edit")
      #expect(!named("Act in Review", in: try #require(session.tree.root)))
      #expect(!session.activate(try button("Locked")))
      try await press("Act in Edit")
      try await press("Continue")
      #expect(named("Workflow: 2; actions: 1", in: try #require(session.tree.root)))
      #expect(!session.activate(body))
      #expect(!named("Act in Edit", in: try #require(session.tree.root)))
      try await press("Act in Review")
      try await press("Back")
      #expect(named("Workflow: 1; actions: 2", in: try #require(session.tree.root)))
      let remountedBody = try button("Act in Edit")
      #expect(remountedBody !== body)
      try await press("Reverse workflow")
      #expect(try button("Edit") === edit)
      #expect(try button("Act in Edit") === remountedBody)
      try await press("Fix")
      #expect(named("Workflow: 3; actions: 2", in: try #require(session.tree.root)))
      try await press("Change workflow layout")
      try await press("Finish")
      try await press("Act in Finish")
      #expect(named("Workflow: 5; actions: 3", in: try #require(session.tree.root)))
      let finish = try button("Finish")
      session.isVisible = false
      #expect(!session.activate(finish))
      await session.close()
      #expect(!session.activate(finish))
    } catch {
      await session.close()
      throw error
    }
  }
}
