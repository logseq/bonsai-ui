import AppKit
import SwiftUI
@testable import BonsaiSwiftUI

@main struct Main {
  @MainActor static func main() async throws {
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.finishLaunching()
    var registry = BonsaiNativeViews()
    var snapshots: [Int: BonsaiNativeContext<Int, String, Void>] = [:]
    try registry.register(kind: 2101, version: 1, capabilities: [.semantics],
      decode: { Int(String(decoding: $0, as: UTF8.self))! },
      encodeEvent: { BonsaiNativeEvent(id: 1, payload: Data($0.utf8)) },
      makeResource: { () }, dispose: { _ in }, content: { context in
        snapshots[context.properties] = context
        return context.navigationLink(to: "open") { Text("Open") }
      })
    let session = BonsaiSession(nativeViews: registry)
    session.isVisible = true
    try await session.start(entrypoint: "native-link")
    let root = session.tree.root!
    let node = session.tree.nativeViewNodes.first!
    let stack = root.navigationController!
    let host = NSHostingController(rootView: NativeNodeView(node: root, activate: { _ in }))
    let window = NSWindow(contentViewController: host)
    window.setContentSize(NSSize(width: 400, height: 300)); window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(150))
    _ = try await session.presented(session.ticket!)
    try await Task.sleep(for: .milliseconds(150))
    let handler = node.bindings[EventTagId.nativeEvent]!
    let original = snapshots[0]!.makeNavigationEvent("open")!
    precondition(original.1())
    let _ = try await session.refresh()
    let start = ContinuousClock.now
    print("gap original=\(original.1()) corePermission=\(session.tree.onInteractionPermission!(node)) sameHandler=\(node.bindings[EventTagId.nativeEvent] == handler) routeCount=\(stack.path.count)")
    precondition(!session.tree.onInteractionPermission!(node))
    precondition(node.bindings[EventTagId.nativeEvent] == handler)
    _ = try await session.presented(session.ticket!)
    try await Task.sleep(for: .milliseconds(30))
    print("ready elapsed=\(start.duration(to: .now)) corePermission=\(session.tree.onInteractionPermission!(node)) oldSnapshot=\(original.1())")
    precondition(session.tree.onInteractionPermission!(node))
    precondition(!original.1())
    let renewed = snapshots[1]!.makeNavigationEvent("open")!
    precondition(renewed.1())
    let _ = try await session.refresh()
    _ = try await session.presented(session.ticket!)
    print("committed destinations=\(stack.path.count)")
    precondition(stack.path.count == 1)
    await session.close(); window.orderOut(nil)
  }
}
