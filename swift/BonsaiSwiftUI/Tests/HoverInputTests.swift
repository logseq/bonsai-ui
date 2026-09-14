import Foundation
import Testing

@testable import BonsaiSwiftUI

struct HoverInputTests {
  private func sample(_ id: UInt64 = 0, x: Double = 12, buttons: UInt32 = 0) -> HoverSample {
    HoverSample(
      id: id, kind: id == 0 ? .mouse : .stylus, position: CGPoint(x: x, y: 20), buttons: buttons)
  }

  @Test func pressedMouseOwnsSamplesUntilReleaseAndHoverResumesWithoutRegression() {
    var input = HoverInput()
    let hover = sample()
    let initial = input.hover(hover, present: true)
    #expect(initial == HoverInput.Change(sample: hover, present: true))
    let paused = input.hover(sample(buttons: 1), present: false)
    #expect(paused == nil)
    let held = sample(x: -10, buttons: 1)
    let drag = input.mouseContact(held, phase: .active)
    #expect(drag == HoverInput.Change(sample: held, present: true))
    let staleHover = input.hover(hover, present: true)
    let staleEnd = input.hover(hover, present: false)
    #expect(staleHover == nil && staleEnd == nil)
    let secondaryHeld = sample(x: 30, buttons: 2)
    _ = input.mouseContact(secondaryHeld, phase: .ended)
    let stillPaused = input.hover(hover, present: true)
    #expect(stillPaused == nil)
    let released = sample(x: 40)
    let end = input.mouseContact(released, phase: .ended)
    #expect(end == HoverInput.Change(sample: released, present: true))
    let resumed = sample(x: 50)
    let next = input.hover(resumed, present: true)
    #expect(next == HoverInput.Change(sample: resumed, present: true))
    let left = input.hover(resumed, present: false)
    #expect(left == HoverInput.Change(sample: resumed, present: false))
  }

  @Test func cancellationAndResetKeepOtherPointersIndependent() {
    var input = HoverInput()
    let pencil = sample(1)
    let mouse = sample(buttons: 3)
    #expect(input.hover(pencil, present: true) == HoverInput.Change(sample: pencil, present: true))
    _ = input.mouseContact(mouse, phase: .active)
    let cancelled = input.mouseContact(mouse, phase: .cancelled)
    #expect(cancelled == HoverInput.Change(sample: mouse, present: false))
    #expect(
      input.hover(pencil, present: false) == HoverInput.Change(sample: pencil, present: false))
    let mouseAgain = input.hover(sample(), present: true)
    #expect(mouseAgain != nil)
    _ = input.mouseContact(mouse, phase: .active)
    input.reset()
    let fresh = input.hover(sample(), present: true)
    #expect(fresh != nil)
  }

  @Test func invalidSamplesCannotChangeContactOwnership() {
    var input = HoverInput()
    let valid = sample(buttons: UInt32.max)
    _ = input.mouseContact(valid, phase: .active)
    let invalid = [
      HoverSample(id: UInt64.max, kind: .mouse, position: .zero, buttons: 0),
      HoverSample(id: 0, kind: .mouse, position: CGPoint(x: Double.nan, y: 0), buttons: 0),
      HoverSample(id: 0, kind: .mouse, position: CGPoint(x: 0, y: Double.infinity), buttons: 0),
    ]
    for sample in invalid {
      let hover = input.hover(sample, present: true)
      let cancelled = input.mouseContact(sample, phase: .cancelled)
      #expect(hover == nil && cancelled == nil)
    }
    let wrongDevice = input.mouseContact(sample(1), phase: .cancelled)
    #expect(wrongDevice == nil)
    let stillOwned = input.hover(sample(), present: true)
    #expect(stillOwned == nil)
  }
}

extension NativeRuntimeTests {
  @Test func mergedHoverAndMouseContactReachActualOcamlInOrder() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-pointer-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var node: UInt64 = 0
      var bindings: [Int: UInt64] = [:]
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        guard try reader.integer(UInt16.self) == NodeKindId.hoverRegion else { continue }
        node = id
        _ = try reader.integer(UInt8.self)
        for _ in 0..<(try reader.integer(UInt16.self)) {
          let tag = Int(try reader.integer(UInt16.self))
          bindings[tag] = try reader.integer(UInt64.self)
        }
      }
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      var input = HoverInput()
      var transitions = HoverTransitions()
      var events: [NativeEvent] = []
      func apply(_ change: HoverInput.Change?) throws {
        guard let change else { return }
        let sample = change.sample
        let pointer = NativePointer(
          id: sample.id, localX: sample.position.x, localY: sample.position.y,
          globalX: sample.position.x, globalY: sample.position.y,
          kind: sample.kind, buttons: sample.buttons)
        guard
          let payload = transitions.update(
            pointer,
            inside: change.present
              && CGRect(x: 0, y: 0, width: 80, height: 80).contains(sample.position))
        else { return }
        events.append(
          NativeEvent(
            sequence: UInt64(events.count + 1), displayedRevision: frame.revision,
            nodeID: node, handlerID: try #require(bindings[payload.tag]), payload: payload))
      }
      let mouse = HoverSample(id: 0, kind: .mouse, position: CGPoint(x: 12, y: 20), buttons: 0)
      let pencil = HoverSample(id: 1, kind: .stylus, position: CGPoint(x: 15, y: 20), buttons: 0)
      try apply(input.hover(mouse, present: true))
      try apply(input.hover(pencil, present: true))
      try apply(
        input.mouseContact(
          HoverSample(id: 0, kind: .mouse, position: CGPoint(x: -10, y: 20), buttons: 3),
          phase: .active))
      try apply(input.hover(mouse, present: true))
      try apply(
        input.mouseContact(
          HoverSample(id: 0, kind: .mouse, position: CGPoint(x: 30, y: 20), buttons: 3),
          phase: .active))
      let released = HoverSample(id: 0, kind: .mouse, position: CGPoint(x: 30, y: 20), buttons: 0)
      try apply(input.mouseContact(released, phase: .ended))
      try apply(input.hover(released, present: true))
      try apply(input.hover(pencil, present: false))
      try apply(
        input.hover(
          HoverSample(id: 0, kind: .mouse, position: CGPoint(x: 90, y: 20), buttons: 0),
          present: false))
      #expect(events.count == 6)
      let updated = try await runtime.pump(
        monotonicNanoseconds: 3, events: EventBatch.encode(epoch: frame.epoch, events: events))
      let expected =
        "enter:0:12.000:20.000:12.000:20.000:mouse:0;"
        + "enter:1:15.000:20.000:15.000:20.000:stylus:0;"
        + "leave:0:-10.000:20.000:-10.000:20.000:mouse:3;"
        + "enter:0:30.000:20.000:30.000:20.000:mouse:3;"
        + "leave:1:15.000:20.000:15.000:20.000:stylus:0;"
        + "leave:0:90.000:20.000:90.000:20.000:mouse:0;"
      #expect(updated.bytes.range(of: Data(expected.utf8)) != nil)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
