import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class NodeServiceScene {
  let session: BonsaiSession
  let window: NSWindow
  let windowHost = NativeWindowHost()
  let owner = NSView()
  private var events: BonsaiApplicationEvents?
  private var hosting: NSView?

  init() {
    initializeAccessibilityApplication()
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 500, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    var connect: ((BonsaiApplicationEvents) -> Void)?
    session = BonsaiSession(
      windowHost: windowHost,
      applicationBridge: BonsaiApplicationBridge(
        request: { $0 }, connected: { connect?($0) }))
    connect = { [weak self] in self?.events = $0 }
    session.isVisible = true
  }

  func start() async throws {
    try await session.start(entrypoint: "native-node-services")
    let root = try #require(session.tree.root)
    let view = NSHostingView(
      rootView: NativeNodeView(
        node: root,
        activate: { [session] in
          _ = session.activate($0)
        }
      ).frame(maxWidth: .infinity, maxHeight: .infinity).modifier(
        NativeLayoutObserver(tree: session.tree))
    )
    hosting = view
    window.contentView = view
    window.orderFront(nil)
    windowHost.attach(window: window, title: "Node Services", owner: owner)
    try await settleAccessibility(view)
    _ = try await session.presented(#require(session.ticket))
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let value) = $0.properties, value.value.hasPrefix("Nodes") {
        return value.value
      }
      return nil
    }.joined()
  }
  func settle(until condition: () -> Bool) async throws {
    for _ in 0..<150 {
      if condition() { return }
      _ = try await session.refresh()
      if let hosting { hosting.layoutSubtreeIfNeeded() }
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      try await Task.sleep(for: .milliseconds(5))
    }
    try #require(condition())
  }
  func send(_ command: String) throws { try #require(events).send(Data(command.utf8)) }
  func perform(_ command: String) async throws -> String {
    let before = status
    try send(command)
    try await settle { status != before }
    return String(status.dropFirst(before.count).dropFirst("Nodes: ".count).dropLast())
  }
  func field(_ label: String) throws -> RenderNodeState {
    try #require(
      session.tree.nodes.values.first {
        if case .textField(let field) = $0.properties { return field.label == label }
        return false
      })
  }
  func close() async {
    await session.close()
    window.orderOut(nil)
    window.contentView = nil
    window.close()
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func hostFocusRequestsReachActualFieldsAndClearOnlyTheirWindow() async throws {
    let scene = NodeServiceScene()
    let other = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 200, height: 80),
      styleMask: [.titled], backing: .buffered, defer: false)
    other.isReleasedWhenClosed = false
    let otherField = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
    other.contentView = otherField
    other.orderFront(nil)
    other.makeFirstResponder(otherField)
    let otherEditor = try #require(otherField.currentEditor())
    defer {
      other.orderOut(nil)
      other.contentView = nil
      other.close()
    }
    do {
      try await scene.start()
      #expect(try await scene.perform("clear") == "ok")
      for name in ["Plain", "Secure"] {
        let node = try scene.field(name)
        #expect(try await scene.perform("focus:\(node.id.node)") == "ok")
        let editor = try #require(node.fieldController?.field.currentEditor())
        #expect(scene.window.firstResponder === editor)
        #expect(try await scene.perform("focus:\(scene.field("Disabled").id.node)") == "error")
        #expect(scene.window.firstResponder === editor)
        #expect(try await scene.perform("clear") == "ok")
        #expect(scene.window.firstResponder !== editor)
        #expect(other.firstResponder === otherEditor)
      }
      #expect(try await scene.perform("focus:9223372036854775807") == "error")
      let multiline = try #require(
        scene.session.tree.nodes.values.first { $0.textController != nil })
      #expect(try await scene.perform("focus:\(multiline.id.node)") == "ok")
      #expect(scene.window.firstResponder === multiline.textController?.view)
      #expect(try await scene.perform("clear") == "ok")
      #expect(scene.window.firstResponder !== multiline.textController?.view)
      let old = try scene.field("Plain").id.node
      try scene.send("remove")
      try await scene.settle { scene.session.tree.nodes[old] == nil }
      #expect(try await scene.perform("focus:\(old)") == "error")
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func nodeServicesWaitForPresentationAndRejectDetachedWindows() async throws {
    let scene = NodeServiceScene()
    do {
      try await scene.start()
      #expect(try await scene.perform("clear") == "ok")
      let field = try scene.field("Plain")
      let before = scene.status
      try scene.send("focus:\(field.id.node)")
      _ = try await scene.session.refresh()
      for _ in 0..<10 { await Task.yield() }
      #expect(scene.status == before)
      #expect(field.fieldController?.field.currentEditor() == nil)
      scene.session.isActive = false
      #expect(!(try await scene.session.presented(#require(scene.session.ticket))))
      scene.windowHost.detach(owner: scene.owner)
      scene.session.isActive = true
      try await scene.settle { scene.status != before }
      #expect(scene.status.hasSuffix("Nodes: error;"))
      #expect(field.fieldController?.field.currentEditor() == nil)
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hostMeasurementUsesSwiftUIPointsAndRejectsRemovedNodes() async throws {
    let scene = NodeServiceScene()
    do {
      try await scene.start()
      let target = try #require(
        scene.session.tree.nodes.values.first {
          if case .frame(let frame) = $0.properties {
            return frame.width == 120 && frame.height == 40
          }
          return false
        })
      let first = try await scene.perform("measure:\(target.id.node)")
      let values = first.split(separator: ",").compactMap { Double($0) }
      try #require(values.count == 4)
      #expect(values.allSatisfy { $0.isFinite })
      #expect(values[2] == 120 && values[3] == 40)
      scene.window.setFrameOrigin(CGPoint(x: 125, y: 250))
      #expect(try await scene.perform("measure:\(target.id.node)") == first)
      #expect(try await scene.perform("measure:9223372036854775807") == "error")
      try scene.send("remove")
      try await scene.settle { scene.session.tree.nodes[target.id.node] == nil }
      #expect(try await scene.perform("measure:\(target.id.node)") == "error")
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
}
