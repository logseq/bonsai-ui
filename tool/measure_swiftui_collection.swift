// Measures the real OCaml mixed collection and Swift render pipeline. This is
// a diagnostic, not a frame-rate benchmark or a performance pass/fail budget.
import AppKit
import Darwin
import SwiftUI

@testable import BonsaiSwiftUI

private func nanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
private func milliseconds(since start: UInt64) -> Double {
  Double(nanoseconds() - start) / 1_000_000
}

private func residentBytes() throws -> UInt64 {
  var info = mach_task_basic_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  guard result == KERN_SUCCESS else { throw MeasurementError.invalid("task_info failed") }
  return UInt64(info.resident_size)
}

private enum MeasurementError: Error { case invalid(String) }

@MainActor private func scrollView(in view: NSView) -> NSScrollView? {
  if let scroll = view as? NSScrollView { return scroll }
  return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
}

@MainActor private struct MeasuredCollection: View {
  let tree: RenderTree
  var body: some View {
    if let root = tree.root {
      NativeNodeView(node: root, activate: { _ in }).frame(width: 820, height: 850)
    }
  }
}

@main private struct CollectionMeasurement {
  @MainActor static func main() async throws {
    let axis = CommandLine.arguments.dropFirst().first ?? "vertical"
    guard ["vertical", "horizontal"].contains(axis) else {
      throw MeasurementError.invalid("Expected vertical or horizontal")
    }
    _ = NSApplication.shared
    let before = try residentBytes()
    let openStart = nanoseconds()
    let runtime = try await NativeRuntime.open(
      entrypoint: axis == "vertical" ? "native-mixed-v" : "native-mixed-h")
    let openMS = milliseconds(since: openStart)
    do {
      var state = FrameState()
      let tree = RenderTree()
      let hosting = NSHostingView(rootView: MeasuredCollection(tree: tree))
      hosting.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 820, height: 850),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = hosting
      defer { window.contentView = nil }
      var clock: Int64 = 0
      var samples: [[String: Any]] = []
      var ownerID: UInt64 = 0
      var sequence: UInt64 = 0
      // Initial snapshot, 20 warm-up windows, then 100 adjacent and 100 distant
      // windows. Each requested range has 15 rows plus the fixture's overscan.
      let ranges: [Int?] =
        [nil] + (0..<20).map { $0 * 15 }
        + (0..<100).map { 3000 + $0 }
        + (0..<100).map { ($0 * 7919 + 7500) % 9988 }
      for (index, first) in ranges.enumerated() {
        var events = Data()
        if let first {
          guard let handler = tree.nodes[ownerID]?.bindings[EventTagId.visibleRangeChanged] else {
            throw MeasurementError.invalid("Missing visible-range handler")
          }
          sequence += 1
          events = try EventBatch.encode(
            epoch: state.tree.epoch,
            events: [
              NativeEvent(
                sequence: sequence, displayedRevision: state.tree.revision,
                nodeID: ownerID, handlerID: handler, payload: .visibleRange(first..<(first + 15)))
            ])
        }
        let totalStart = nanoseconds()
        clock += 1
        let pumpStart = nanoseconds()
        let output = try await runtime.pump(monotonicNanoseconds: clock, events: events)
        let pumpMS = milliseconds(since: pumpStart)
        guard output.status == 0, !output.bytes.isEmpty else {
          throw MeasurementError.invalid("Expected a successful changed frame")
        }
        let applyStart = nanoseconds()
        state = try state.staging(WireFrame.decode(output.bytes))
        try tree.validate(state.tree)
        tree.commit(state.tree)
        let applyMS = milliseconds(since: applyStart)
        let layoutStart = nanoseconds()
        hosting.layoutSubtreeIfNeeded()
        if let first {
          guard let scroll = scrollView(in: hosting),
            let controller = tree.nodes[ownerID]?.collectionController
          else { throw MeasurementError.invalid("Missing native scroll viewport") }
          let offset = controller.catalog.geometry.offset(at: first)
          scroll.contentView.scroll(
            to: axis == "vertical"
              ? CGPoint(x: 0, y: offset) : CGPoint(x: offset, y: 0))
          scroll.reflectScrolledClipView(scroll.contentView)
          hosting.layoutSubtreeIfNeeded()
          let actual =
            axis == "vertical" ? scroll.documentVisibleRect.minY : scroll.documentVisibleRect.minX
          guard abs(actual - offset) < 1 else {
            throw MeasurementError.invalid("Native viewport did not reach the requested range")
          }
        }
        hosting.displayIfNeeded()
        let layoutMS = milliseconds(since: layoutStart)
        let ackStart = nanoseconds()
        clock += 1
        try await runtime.acknowledge(output, monotonicNanoseconds: clock)
        let ackMS = milliseconds(since: ackStart)
        let totalMS = milliseconds(since: totalStart)
        guard let owner = tree.nodes.values.first(where: { $0.collectionController != nil }),
          let controller = owner.collectionController, controller.catalog.keys.count == 10003,
          let rendered = owner.children.first,
          case .collectionWindow(let windowProperties) = rendered.properties
        else { throw MeasurementError.invalid("Missing real 10003-item collection") }
        ownerID = owner.id.node
        if let first {
          let expected = Array(controller.catalog.keys[max(0, first - 3)..<min(10003, first + 18)])
          guard windowProperties.keys == expected, rendered.children.count == expected.count,
            tree.nodes.count < 250
          else { throw MeasurementError.invalid("Requested range was not materialized correctly") }
        }
        samples.append([
          "phase": index == 0
            ? "initial"
            : index <= 20
              ? "warmup"
              : index <= 120 ? "adjacent" : "distant",
          "first_index": first ?? 0, "pump_ms": pumpMS, "decode_apply_ms": applyMS,
          "synchronous_layout_display_ms": layoutMS, "ack_ms": ackMS, "total_ms": totalMS,
          "frame_bytes": output.bytes.count, "render_nodes": tree.nodes.count,
          "materialized_rows": rendered.children.count, "resident_bytes": try residentBytes(),
        ])
        // Allow deferred AppKit/SwiftUI work between samples. This delay is
        // excluded from the reported times; no display-link/FPS claim is made.
        try await Task.sleep(for: .milliseconds(2))
      }
      await runtime.close()
      let report: [String: Any] = [
        "axis": axis, "logical_items": 10003, "viewport_points": [820, 850],
        "open_ms": openMS, "resident_before_open_bytes": before, "samples": samples,
        "resident_after_runtime_close_bytes": try residentBytes(),
        "scope":
          "Debug OCaml pump, frame decode/stage/render commit, programmatic NSScrollView movement, "
          + "synchronous NSHostingView layout/display and acknowledgment. Synthetic visible-range intents "
          + "bypass input sampling; no physical gestures, compositor frame rate, allocation/leak proof or "
          + "iOS claim. Render tree and window remain alive at the final memory sample.",
      ]
      let bytes = try JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      FileHandle.standardOutput.write(bytes)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      await runtime.close()
      throw error
    }
  }
}
