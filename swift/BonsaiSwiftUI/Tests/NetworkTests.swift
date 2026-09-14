import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualNetworkWorkerApplicationStagesAndRestarts() async throws {
    for _ in 0..<2 {
      let session = BonsaiSession()
      session.isVisible = true
      do {
        try await session.start(entrypoint: "network")
        #expect(try await session.presented(#require(session.ticket)))
        let text = session.tree.nodes.values.compactMap { node -> String? in
          if case .text(let value) = node.properties { return value.value }
          return nil
        }
        #expect(text.contains("HTTPS: Idle") && text.contains("WebSocket: Idle"))
        let input = try #require(
          session.tree.nodes.values.first { node in
            if case .textField(let field) = node.properties {
              return field.label == "WebSocket message"
            }
            return false
          })
        #expect(input.fieldController?.field.isEnabled == false)
        await session.close()
        #expect(input.fieldController?.field.delegate == nil)
      } catch {
        await session.close()
        throw error
      }
    }
  }
}
