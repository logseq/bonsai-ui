import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor struct HoverRouterTests {
  private func region(
    _ id: UInt64, order: Int, subtreeEnd: Int? = nil, blocks: Bool = true,
    rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100), binding: UInt64 = 1,
    emit: @escaping (NativeEventPayload) -> Bool
  ) -> HoverRouter.Region {
    HoverRouter.Region(
      id: RenderIdentity(epoch: 1, node: id),
      subtree: order..<(subtreeEnd ?? order + 1),
      order: order, blocksBehind: blocks,
      bindings: [EventTagId.pointerEnter: binding, EventTagId.pointerLeave: binding + 1],
      locate: { sample in
        let point = sample.pointer.position
        return HoverRouter.Hit(
          pointer: NativePointer(
            id: sample.pointer.id, localX: point.x - rect.minX, localY: point.y - rect.minY,
            globalX: point.x, globalY: point.y, kind: sample.pointer.kind,
            buttons: sample.pointer.buttons), inside: rect.contains(point))
      }, emit: emit)
  }

  private func move(_ router: HoverRouter, _ window: NSObject, x: Double = 50, present: Bool = true)
  {
    router.receive(
      HoverRouter.Sample(
        pointer: HoverSample(id: 0, kind: .mouse, position: CGPoint(x: x, y: 50), buttons: 3),
        window: ObjectIdentifier(window), present: present))
  }

  @Test func occlusionKeepsAncestorsAndPassThroughRegionsAndExitsBeforeEntering() {
    let router = HoverRouter()
    let window = NSObject()
    var events: [String] = []
    func sink(_ name: String) -> (NativeEventPayload) -> Bool {
      { payload in
        events.append("\(name):\(payload.tag)")
        return true
      }
    }
    let parent = region(1, order: 0, subtreeEnd: 3, emit: sink("parent"))
    let back = region(2, order: 1, emit: sink("back"))
    let front = region(3, order: 2, emit: sink("front"))
    router.replace([parent, back, front])
    move(router, window)
    #expect(events.isEmpty)
    router.setPresented(true)
    #expect(events == ["parent:5", "front:5"])
    router.replace([
      parent, back, region(3, order: 2, blocks: false, emit: sink("front")),
    ])
    router.refresh()
    #expect(events == ["parent:5", "front:5", "back:5"])
    router.replace([parent, back, front])
    router.refresh()
    #expect(events.last == "back:6")
    let moved = region(
      3, order: 2, rect: CGRect(x: 200, y: 0, width: 100, height: 100),
      emit: sink("front"))
    router.replace([parent, back, moved])
    router.refresh()
    #expect(Array(events.suffix(2)) == ["front:6", "back:5"])
    move(router, window, present: false)
    #expect(Array(events.suffix(2)) == ["back:6", "parent:6"])
  }

  @Test func presentationBindingReplacementRemovalAndResetFenceOldCallbacks() {
    let router = HoverRouter()
    let window = NSObject()
    var old: [Int] = []
    var next: [Int] = []
    router.replace([
      region(1, order: 0) {
        old.append($0.tag)
        return true
      }
    ])
    router.setPresented(true)
    move(router, window)
    #expect(old == [5])
    router.setPresented(false)
    move(router, window, x: 120)
    #expect(old == [5])
    router.setPresented(true)
    #expect(old == [5, 6])
    router.setPresented(false)
    router.replace([
      region(1, order: 0, binding: 10) {
        next.append($0.tag)
        return true
      }
    ])
    move(router, window)
    #expect(next.isEmpty)
    router.setPresented(true)
    #expect(old == [5, 6] && next == [5])
    router.replace([])
    router.refresh()
    #expect(next == [5])
    router.reset()
    move(router, window)
    #expect(next == [5])
  }

  @Test func rejectedTransitionsRetryWithoutLettingNewEntersOvertakeExits() {
    let router = HoverRouter()
    let window = NSObject()
    var accept = false
    var events: [String] = []
    let back = region(1, order: 0) {
      guard accept else { return false }
      events.append("back:\($0.tag)")
      return true
    }
    router.replace([back])
    router.setPresented(true)
    move(router, window)
    #expect(events.isEmpty)
    accept = true
    router.refresh()
    #expect(events == ["back:5"])
    accept = false
    let front = region(2, order: 1) {
      events.append("front:\($0.tag)")
      return true
    }
    router.replace([back, front])
    router.refresh()
    #expect(events == ["back:5"])
    accept = true
    router.refresh()
    #expect(events == ["back:5", "back:6", "front:5"])
    move(router, window)
    #expect(events.count == 3)
  }

  @Test func inactiveCaptureMustNotReplayCoordinatesFromThePreviousActivation() {
    let router = HoverRouter()
    let window = NSObject()
    var events: [Int] = []
    router.replace([
      region(1, order: 0) {
        events.append($0.tag)
        return true
      }
    ])
    router.setPresented(true)
    move(router, window)
    #expect(events == [5])
    router.discardSamples()
    router.setPresented(true)
    #expect(events == [5])
    move(router, window)
    #expect(events == [5, 5])
  }

  @Test func unrelatedWindowSamplesDoNotResetAnExistingPointer() {
    let router = HoverRouter()
    let window = NSObject()
    let foreign = NSObject()
    var events: [Int] = []
    let base = region(1, order: 0) {
      events.append($0.tag)
      return true
    }
    router.replace([
      HoverRouter.Region(
        id: base.id, subtree: base.subtree,
        order: base.order, blocksBehind: base.blocksBehind, bindings: base.bindings,
        locate: { sample in
          sample.window == ObjectIdentifier(window) ? base.locate(sample) : nil
        }, emit: base.emit)
    ])
    router.setPresented(true)
    move(router, window)
    #expect(events == [5])
    router.receive(
      HoverRouter.Sample(
        pointer: HoverSample(id: 1, kind: .stylus, position: CGPoint(x: 50, y: 50), buttons: 0),
        window: ObjectIdentifier(foreign), present: true))
    router.refresh()
    #expect(events == [5])
    move(router, window, present: false)
    #expect(events == [5, 6])
  }
}
