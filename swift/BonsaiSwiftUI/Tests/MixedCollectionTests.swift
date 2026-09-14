import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class MixedHostSize {
  var value: CGSize
  init(horizontal: Bool) {
    value = CGSize(width: horizontal ? 820 : 480, height: horizontal ? 450 : 850)
  }
}

private struct MixedHostView: View {
  let session: BonsaiSession
  let size: MixedHostSize
  var body: some View {
    if let root = session.tree.root {
      NativeNodeView(node: root, activate: { session.activate($0) })
        .frame(width: size.value.width, height: size.value.height)
    }
  }
}

@MainActor private func mixedScrolls(_ root: NSView) -> [NSScrollView] {
  (root as? NSScrollView).map { [$0] } ?? root.subviews.flatMap(mixedScrolls)
}

extension NativeRuntimeTests {
  @Test func mixedWindowChangesDoNotRepublishCatalog() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-mixed-v")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var owner: UInt64 = 0
      var handler: UInt64 = 0
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        if try reader.integer(UInt16.self) == 7 {
          owner = id
          var bindings = WireReader(operation.body.suffix(12))
          handler = try #require(bindings.bindings()[EventTagId.visibleRangeChanged])
        }
      }
      #expect(owner > 0 && initial.bytes.count > 50000)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let event = NativeEvent(
        sequence: 1, displayedRevision: frame.revision, nodeID: owner,
        handlerID: handler, payload: .visibleRange(7500..<7515))
      let next = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: frame.epoch, events: [event]))
      var kinds: [UInt16] = []
      for operation in try WireFrame.decode(next.bytes).operations
      where operation.opcode == OperationId.createNode
        || operation.opcode == OperationId.updateProps
      {
        var reader = WireReader(operation.body)
        _ = try reader.integer(UInt64.self)
        kinds.append(try reader.integer(UInt16.self))
      }
      #expect(!kinds.contains(7) && kinds.contains(8) && next.bytes.count < 16384)
      try await runtime.acknowledge(next, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test(arguments: [false, true], [false, true]) @MainActor
  func mixedCollectionKeepsOneViewportAndStableAnchor(horizontal: Bool, rightToLeft: Bool)
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: horizontal ? "native-mixed-h" : "native-mixed-v")
      let owner = try #require(session.tree.nodes.values.first { $0.collectionController != nil })
      let controller = try #require(owner.collectionController)
      let windowNode = try #require(owner.children.first)
      let size = MixedHostSize(horizontal: horizontal)
      let hosting = NSHostingView(
        rootView: MixedHostView(session: session, size: size)
          .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
      let nativeWindow = NSWindow(
        contentRect: CGRect(
          x: 0, y: 0, width: horizontal ? 820 : 480, height: horizontal ? 450 : 850),
        styleMask: [.borderless], backing: .buffered, defer: false)
      hosting.sizingOptions = []
      nativeWindow.contentView = hosting
      defer { nativeWindow.contentView = nil }
      func settle() async throws {
        for _ in 0..<10 {
          hosting.layoutSubtreeIfNeeded()
          hosting.displayIfNeeded()
          try await Task.sleep(for: .milliseconds(20))
        }
      }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      }
      func command(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first {
            guard $0.kind == NodeKindId.button, let child = $0.children.first,
              case .text(let text) = child.properties
            else { return false }
            return text.value == title
          })
      }
      func press(_ title: String) async throws {
        #expect(session.activate(try command(title)))
        try await flush()
        try await settle()
        try await flush()
      }
      try await settle()
      #expect(
        hosting.bounds.size == CGSize(width: horizontal ? 820 : 480, height: horizontal ? 450 : 850)
      )
      #expect(mixedScrolls(hosting).count == 1)
      let scroll = try #require(mixedScrolls(hosting).first)
      let document = try #require(scroll.documentView)
      func move(_ value: Double) {
        let x = rightToLeft ? document.frame.width - scroll.contentView.bounds.width - value : value
        scroll.contentView.scroll(to: horizontal ? CGPoint(x: x, y: 0) : CGPoint(x: 0, y: value))
        scroll.reflectScrolledClipView(scroll.contentView)
      }
      func offset() -> Double {
        let rect = scroll.documentVisibleRect
        return horizontal
          ? (rightToLeft ? max(0, document.frame.width - rect.maxX) : rect.minX) : rect.minY
      }
      #expect(controller.catalog.keys.count == 10003)
      let scale = horizontal ? 2.0 : 1.0
      #expect(abs(controller.catalog.geometry.totalExtent - 540260 * scale) < 1)
      #expect(
        abs(
          (horizontal ? document.frame.width : document.frame.height)
            - controller.catalog.geometry.totalExtent) < 1)
      #expect(try await session.presented(#require(session.ticket)))
      try await flush()
      try await settle()
      #expect(windowNode.children.count > 0 && windowNode.children.count < 64)
      let oldHeader = try command("Header action")
      #expect(session.activate(oldHeader))
      try await flush()
      let initialCatalog = controller.catalog
      let target = controller.catalog.geometry.offset(at: 7500) + 7
      move(target)
      try await settle()
      try await flush()
      try await settle()
      #expect(controller.catalog == initialCatalog)
      #expect(windowNode.children.count < 64 && session.tree.nodes.count < 250)
      #expect(!session.activate(oldHeader))
      let key = controller.catalog.keys[7500]
      let anchor = try #require(
        windowNode.children.first { node in
          guard case .collectionWindow(let window) = windowNode.properties,
            let position = windowNode.children.firstIndex(where: { $0 === node })
          else { return false }
          return window.keys[position] == key
        })
      #expect(abs(offset() - target) < 1)
      func expectAnchor() throws {
        let index = try #require(controller.catalog.indices[key])
        #expect(abs(offset() - controller.catalog.geometry.offset(at: index) - 7) < 1)
        #expect(windowNode.children.contains { $0 === anchor })
        #expect(mixedScrolls(hosting).first === scroll)
        #expect(owner.children.first === windowNode)
      }
      try await press("Expand mixed row")
      try await Task.sleep(for: .milliseconds(220))
      try await settle()
      try await flush()
      #expect(controller.catalog.geometry.extent(at: 3012) == 180 * scale)
      try expectAnchor()
      try await press("Resize mixed header")
      try await Task.sleep(for: .milliseconds(220))
      try await settle()
      try await flush()
      try expectAnchor()
      try await press("Remove mixed header")
      #expect(controller.catalog.keys.count == 10002)
      try expectAnchor()
      try await press("Swap mixed groups")
      try expectAnchor()
      size.value = CGSize(width: horizontal ? 980 : 540, height: horizontal ? 500 : 950)
      nativeWindow.setContentSize(size.value)
      try await settle()
      try await flush()
      try expectAnchor()
      func containsText(_ value: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == value }
          return false
        }
      }
      move(controller.catalog.geometry.offset(at: 7000) - 30 * scale)
      try await settle()
      try await flush()
      try await settle()
      #expect(containsText("Varied 6999"))
      #expect(containsText("Between groups") && containsText("Fixed 0"))
      move(controller.catalog.geometry.totalExtent - controller.viewport.visibleExtent)
      try await settle()
      try await flush()
      try await settle()
      try await press("Footer action")
      #expect(containsText("Mixed actions: 101"))
      #expect(windowNode.children.count < 64 && session.tree.nodes.count < 250)
      try await press("Clear mixed content")
      #expect(controller.catalog.keys.isEmpty && windowNode.children.isEmpty)
      #expect(abs(offset()) < 1)
      #expect(controller.viewport.visibleExtent > 300)
      try await press("Reset mixed content")
      #expect(controller.catalog.keys.count == 10003)
      #expect(windowNode.children.count > 0 && windowNode.children.count < 64)
      #expect(abs(offset()) < 1)
      #expect(try command("Header action") !== oldHeader)
      await session.close()
      #expect(!session.activate(oldHeader))
    } catch {
      await session.close()
      throw error
    }
  }
}
