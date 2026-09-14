import Foundation
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test func actualClockTimersAndPresentationWaitsUseNativeFrames() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "clock")
    do {
      var state = FrameState()
      var sequence: UInt64 = 0
      func texts(_ id: UInt64) -> [String] {
        guard let node = state.tree.nodes[id] else { return [] }
        if case .text(let value) = node.properties { return [value.value] }
        return node.children.flatMap(texts)
      }
      func allTexts() -> [String] {
        state.tree.nodes.values.compactMap {
          if case .text(let value) = $0.properties { return value.value }
          return nil
        }
      }
      func tick(_ seconds: Int64, press label: String? = nil) async throws {
        var events = Data()
        if let label {
          let button = try #require(
            state.tree.nodes.values.first {
              if case .button = $0.properties { return texts($0.id).contains(label) }
              return false
            })
          sequence += 1
          events = try EventBatch.encode(
            epoch: state.tree.epoch,
            events: [
              NativeEvent(
                sequence: sequence, displayedRevision: state.tree.revision, nodeID: button.id,
                handlerID: try #require(button.bindings[EventTagId.press]))
            ])
        }
        let output = try await runtime.pump(
          monotonicNanoseconds: seconds * 1_000_000_000, events: events)
        #expect(output.status != 2)
        if !output.bytes.isEmpty { state = try state.staging(WireFrame.decode(output.bytes)) }
        try await runtime.acknowledge(output, monotonicNanoseconds: seconds * 1_000_000_000)
      }
      try await tick(0)
      #expect(allTexts().contains("Manual sample: Not sampled"))
      let initialApproximate = try #require(allTexts().first { $0.hasPrefix("Approximate now:") })
      try await tick(1, press: "Sample now")
      #expect(
        allTexts().contains { $0.hasPrefix("Manual sample: ") && !$0.contains("Not sampled") })
      try await tick(2, press: "Arm 5s deadline")
      try await tick(2, press: "Sleep 3s")
      try await tick(2, press: "Wait until next 5s boundary")
      #expect(allTexts().contains { $0.hasPrefix("Absolute until: Waiting") })
      try await tick(2, press: "Wait for frame boundaries")
      try await tick(2)
      #expect(allTexts().contains("Before display: Completed"))
      #expect(allTexts().contains("After display: Completed"))
      try await tick(4)
      #expect(allTexts().contains { $0.hasPrefix("Relative sleep: Waiting") })
      #expect(allTexts().contains { $0.hasPrefix("Deadline: Before") })
      try await tick(5)
      #expect(allTexts().contains { $0.hasPrefix("Relative sleep: Completed") })
      // The native clock starts at wall time; the next UTC boundary is within five seconds.
      try await tick(7)
      #expect(allTexts().contains { $0.hasPrefix("Absolute until: Completed") })
      #expect(allTexts().contains { $0.hasPrefix("Deadline: After") })
      #expect(allTexts().first { $0.hasPrefix("Approximate now:") } != initialApproximate)
      for label in [
        "Wait after start", "Wait after finish", "Fixed cadence, overlapping",
        "Fixed cadence, skip busy beats",
      ] {
        let lane = try #require(
          state.tree.nodes.values.first { node in
            guard case .column = node.properties else { return false }
            let content = texts(node.id)
            return content.contains(label) && content.filter { $0.hasPrefix("Started:") }.count == 1
          })
        let content = texts(lane.id)
        #expect(content.contains { $0.hasPrefix("Started: ") && $0 != "Started: 0" })
        #expect(content.contains { $0.hasPrefix("Completed: ") && $0 != "Completed: 0" })
      }
      try await tick(7, press: "Restart schedules")
      #expect(
        allTexts().contains { $0.contains("Recurring schedules") && $0.contains("Restarted") })
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
