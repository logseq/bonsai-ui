import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class SwipeWindowModel {
  let tree = RenderTree()
  var events: [UInt64] = []
  var contentFrame: CGRect = .zero
  let vertical = CommandLine.arguments.contains("--vertical")
  let rtl = CommandLine.arguments.contains("--rtl")
  init() {
    var operations = TreeFixture.swipeTree(vertical: vertical ? 1 : 0)
    operations += [
      TreeFixture.operation(OperationId.createNode) {
        $0.integer(UInt64(7))
        $0.integer(UInt16(NodeKindId.frame))
        $0.integer(UInt8(1))
        $0.integer(Double(320).bitPattern)
        $0.integer(UInt8(1))
        $0.integer(Double(100).bitPattern)
        for _ in 0..<6 { $0.integer(UInt8(0)) }
        $0.integer(UInt8(4))
        $0.integer(UInt16(0))
      }, TreeFixture.children(7, [2]), TreeFixture.children(1, [7, 3, 5]),
    ]
    tree.commit(try! NodeStore().staging(TreeFixture.frame(operations)).tree)
    tree.onInput = { [weak self] node, _ in
      self?.events.append(node.id.node)
      return true
    }
  }
}
@main struct SwipeWindowAcceptance: App {
  @State private var model = SwipeWindowModel()
  var body: some Scene {
    Window("Swipe Acceptance", id: "swipe") {
      NativeNodeView(node: model.tree.root!, activate: { _ in })
        .frame(width: 320, height: 100)
        .environment(\.layoutDirection, model.rtl ? .rightToLeft : .leftToRight)
        .environment(\.scenePhase, .active)
        .allowsWindowActivationEvents(true)
        .onGeometryChange(for: CGRect.self) {
          $0.frame(in: .global)
        } action: {
          model.contentFrame = $0
        }
        .task { await verify(model) }
    }.defaultSize(width: 320, height: 100)
  }
}
@MainActor private func verify(_ model: SwipeWindowModel) async {
  do {
    let window = try require(NSApp.windows.first(where: { $0.contentView != nil }))
    let host = try require(window.contentView)
    window.makeKeyAndOrderFront(nil)
    window.setContentSize(CGSize(width: 320, height: 100))
    try await settleAccessibility(host)
    func point(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(x: model.contentFrame.minX + x, y: model.contentFrame.minY + y)
    }
    try await localMouseDrag(
      host, from: point(30, 15),
      to: model.vertical ? point(100, 20) : point(35, 85))
    guard model.events.isEmpty else { throw error("Cross-axis gesture activated an action") }
    guard model.tree.root!.swipeController!.offset == 0 else {
      throw error("Cross-axis gesture revealed a pane")
    }
    let from = model.vertical ? point(160, 3) : point(model.rtl ? 300 : 25, 50)
    let to = model.vertical ? point(160, 98) : point(model.rtl ? 25 : 300, 50)
    try await localMouseDrag(host, from: from, to: to)
    guard model.events == [3] else {
      throw error(
        "Expected one Archive action: \(model.events); size: \(model.tree.root!.swipeController!.size); offset: \(model.tree.root!.swipeController!.offset)"
      )
    }
    print("PASS: native swipe axis arbitration and full action")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func error(_ text: String) -> NSError {
  NSError(domain: "SwipeWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
private func require<T>(_ value: T?) throws -> T {
  guard let value else { throw error("Missing native object") }
  return value
}

@MainActor private func localMouseDrag(_ host: NSView, from: CGPoint, to: CGPoint) async throws {
  let window = try require(host.window)
  let start = ProcessInfo.processInfo.systemUptime
  var events: [NSEvent] = []
  for step in 0...12 {
    let fraction = CGFloat(step) / 12
    let point = host.convert(
      CGPoint(
        x: from.x + (to.x - from.x) * fraction,
        y: from.y + (to.y - from.y) * fraction), to: nil)
    let type: NSEvent.EventType =
      step == 0 ? .leftMouseDown : step == 12 ? .leftMouseUp : .leftMouseDragged
    events.append(
      try require(
        NSEvent.mouseEvent(
          with: type, location: point, modifierFlags: [],
          timestamp: start + Double(step) * 0.016, windowNumber: window.windowNumber,
          context: nil, eventNumber: step, clickCount: 1, pressure: step == 12 ? 0 : 1)))
  }
  for event in events { NSApp.postEvent(event, atStart: false) }
  try await settleAccessibility(host)
}
