import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func animatedOpacity(
    _ id: UInt64, opacity: Double = 1, animation: UInt64 = 0,
    duration: UInt32 = 1200, curve: UInt8 = 0, update: Bool = false, bound: Bool = true
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(71))
      if update { $0.integer(UInt64(15)) }
      $0.integer(opacity.bitPattern)
      $0.integer(animation)
      $0.integer(duration)
      $0.integer(curve)
      if !update {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.animationCompleted))
          $0.integer(UInt64(9))
        }
      }
    }
  }
}

@MainActor struct AnimatedOpacityTests {
  @Test func initialMountUsesItsTargetWithoutChangingNativeLayout() throws {
    let model = RenderTree()
    model.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.animatedOpacity(1, opacity: 0.4),
          TreeFixture.symbol(2, name: "star.fill", size: 30),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ])
      ).tree)
    let actual = NativeNodeView(node: try #require(model.root), activate: { _ in })
    let expected = NativeNodeView(node: try #require(model.nodes[2]), activate: { _ in }).opacity(
      0.4)
    #expect(try raster(actual).matches(raster(expected)))
  }

  @Test func invalidAnimationPropertiesAndBindingsRejectTheWholeTransaction() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.animatedOpacity(1), TreeFixture.text(2, "Original"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    var invalid = [
      TreeFixture.animatedOpacity(1, animation: UInt64.max, update: true),
      TreeFixture.animatedOpacity(1, curve: 4, update: true), TreeFixture.children(1, []),
      TreeFixture.children(1, [2, 2]),
    ]
    for value in [-0.1, 1.1, Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.animatedOpacity(1, opacity: value, update: true))
    }
    let update = TreeFixture.animatedOpacity(1, update: true)
    for count in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(count)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true), operation], base: 1, revision: 2))
      }
      #expect(initial.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.animatedOpacity(1, bound: false), TreeFixture.text(2, "Missing binding"),
          TreeFixture.children(1, [2]), TreeFixture.root(1),
        ]))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualOpacityWaitsForPresentationAndCompletesOnceThroughOcaml() async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled],
      backing: .buffered, defer: false)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    func has(_ title: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == title }
        return false
      }
    }
    func button(_ title: String) throws -> RenderNodeState {
      let text = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      return try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties { return node.children.contains { $0 === text } }
          return false
        })
    }
    do {
      try await session.start(entrypoint: "native-opacity")
      let host = NSHostingView(
        rootView: NativeNodeView(node: try #require(session.tree.root), activate: { _ in }))
      window.contentView = host
      window.orderFront(nil)
      try await settleAccessibility(host)
      #expect(try await session.presented(#require(session.ticket)))
      let animated = try #require(session.tree.nodes.values.first { $0.kind == 71 })
      #expect(
        session.tree.parents[animated.id.node].flatMap {
          session.tree.nodes[$0]?.booleanControlController
        }
          != nil)
      #expect(session.activate(try button("Fade out")))
      _ = try await session.refresh()
      let ticket = try #require(session.ticket)
      try await Task.sleep(for: .milliseconds(1400))
      #expect(has("Completed: none"))
      #expect(session.tree.nodes[animated.id.node] === animated)
      let start = ContinuousClock.now
      #expect(try await session.presented(ticket))
      for _ in 0..<150 {
        try await Task.sleep(for: .milliseconds(20))
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
        if has("Completed: 1") { break }
      }
      #expect(has("Completed: 1"))
      #expect(start.duration(to: .now) >= .milliseconds(800))
      for _ in 0..<3 { _ = try await session.refresh() }
      #expect(has("Completed: 1"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension AnimatedOpacityTests {
  @Test func saturatedEventQueueRetainsOnlyTheLatestUnadmittedCompletion() async throws {
    initializeAccessibilityApplication()
    var queue = NativeEventQueue(maximumCount: 1)
    let filled = queue.append(
      NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 99, handlerID: 9))
    #expect(filled)
    let model = RenderTree()
    var attempts = 0
    model.onInput = { node, payload in
      attempts += 1
      return queue.append(
        NativeEvent(
          sequence: 2, displayedRevision: 2,
          nodeID: node.id.node, handlerID: 9, payload: payload))
    }
    var snapshot = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.animatedOpacity(1), TreeFixture.symbol(2, name: "star.fill", size: 30),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    model.commit(snapshot)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(model.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 160, height: 120), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let controller = try #require(model.root?.opacityController)
    for id in UInt64(1)...2 {
      snapshot = try snapshot.staging(
        TreeFixture.frame(
          [
            TreeFixture.animatedOpacity(
              1, opacity: 0.2 + Double(id) / 10, animation: id, duration: 0, update: true)
          ], base: id, revision: id + 1)
      ).tree
      model.commit(snapshot)
      controller.setPresentationActive(true)
      for _ in 0..<50 {
        try await Task.sleep(for: .milliseconds(20))
        if controller.canComplete(id) { break }
      }
      #expect(controller.canComplete(id))
      #expect(!controller.canComplete(3 - id))
    }
    let refused = attempts
    #expect(refused >= 2)
    #expect(queue.events.count == 1 && queue.events[0].payload == .press)
    queue.removeAll()
    controller.setPresentationActive(true)
    #expect(queue.events.count == 1 && queue.events[0].payload == .animationCompleted(2))
    controller.setPresentationActive(true)
    #expect(attempts == refused + 1)
    controller.dispose()
    #expect(!controller.canComplete(2))
  }
}

extension AnimatedOpacityTests {
  @Test(arguments: ["reduceMotion", "reactivate", "repeat", "instant", "coalesced"])
  func cancellationResetsNativeInterpolationBeforeTheOriginalDuration(
    reason: String
  ) async throws {
    initializeAccessibilityApplication()
    let model = RenderTree()
    let trace = OpacityInterpolationTrace()
    var completions: [UInt64] = []
    var completionValues: [Double] = []
    model.onInput = { _, payload in
      if case .animationCompleted(let id) = payload {
        completions.append(id)
        completionValues.append(trace.value)
      }
      return true
    }
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.animatedOpacity(1), TreeFixture.symbol(2, name: "square.fill", size: 80),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    model.commit(initial)
    let root = try #require(model.root)
    let child = try #require(model.nodes[2])
    let controller = try #require(root.opacityController)
    let host = NSHostingView(
      rootView: ObservedOpacity(controller: controller, trace: trace)
        .overlay(NativeNodeView(node: root, activate: { _ in })))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 160, height: 160), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(trace.value == 1)
    model.commit(
      try initial.staging(
        TreeFixture.frame(
          [
            TreeFixture.animatedOpacity(1, opacity: 0.2, animation: 1, duration: 2000, update: true)
          ], base: 1, revision: 2)
      ).tree)
    controller.setPresentationActive(true)
    try await Task.sleep(for: .milliseconds(350))
    let intermediate = trace.value
    // SwiftUI must actually interpolate before cancellation is exercised.
    try #require(intermediate > 0.35 && intermediate < 0.98)
    #expect(completions.isEmpty)
    let target = reason == "instant" ? 0.6 : 0.2
    let completion: UInt64 = ["repeat", "instant"].contains(reason) ? 2 : 1
    if reason == "reduceMotion" {
      controller.setReducedMotion(true)
    } else if reason == "coalesced" {
      for _ in 0..<2 {
        controller.setPresentationActive(false)
        controller.setPresentationActive(true)
      }
    } else if reason == "reactivate" {
      controller.setPresentationActive(false)
      try await Task.sleep(for: .milliseconds(40))
      #expect(completions.isEmpty)
      controller.setPresentationActive(true)
    } else {
      controller.replace(
        RenderAnimatedOpacity(
          opacity: target, animationID: completion,
          milliseconds: reason == "instant" ? 0 : 2000, curve: 0))
      controller.setPresentationActive(true)
    }
    try await Task.sleep(for: .milliseconds(120))
    let settled = trace.value
    #expect(abs(settled - target) < 0.03)
    #expect(completions == [completion])
    #expect(completionValues.allSatisfy { abs($0 - target) < 0.03 })
    #expect(model.root === root && model.nodes[2] === child)
    try await Task.sleep(for: .milliseconds(1800))
    #expect(abs(trace.value - target) < 0.03)
    #expect(completions == [completion])
  }
}

// This companion effect observes SwiftUI interpolation in the controller's
// transaction. It is not a framebuffer capture or a model-target assertion.
@MainActor private final class OpacityInterpolationTrace {
  var value: Double = 1
}

@MainActor private struct ObservedOpacity: View {
  let controller: AnimatedOpacityController
  let trace: OpacityInterpolationTrace
  var body: some View {
    Color.black.frame(width: 160, height: 160)
      .modifier(OpacityInterpolationProbe(value: controller.value, trace: trace))
  }
}

private struct OpacityInterpolationProbe: AnimatableModifier {
  nonisolated var value: AnimatablePair<Double, Double>
  let trace: OpacityInterpolationTrace
  nonisolated var animatableData: AnimatablePair<Double, Double> {
    get { value }
    set { value = newValue }
  }
  func body(content: Content) -> some View {
    trace.value = value.first
    return content.opacity(value.first)
  }
}
