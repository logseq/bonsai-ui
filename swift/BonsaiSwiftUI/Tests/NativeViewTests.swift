import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test func actualOcamlNativeViewEnvelopeStages() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-view")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let tree = try NodeStore().staging(WireFrame.decode(output.bytes)).tree
      let native = try #require(tree.nodes.values.first { $0.kind == NodeKindId.nativeWidget })
      #expect(native.children.count == 1)
      #expect(Set(native.bindings.keys) == [EventTagId.nativeEvent])
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}

private enum CardEvent { case activate, invalid, oversized }
@MainActor @Observable private final class CardResource {
  var localCount = 0
  var showsChild = true
}
@MainActor private final class CardTrace {
  var created = 0
  var disposed = 0
  var resource: CardResource?
  var emit: ((CardEvent) -> Bool)?
  var emissions: [String: (CardEvent) -> Bool] = [:]
  func registry() throws -> BonsaiNativeViews {
    var views = BonsaiNativeViews()
    for kind: UInt32 in [1001, 1002] {
      try views.register(
        kind: kind, version: 1, capabilities: [.stateful, .resource, .semantics],
        decode: { data -> String in
          guard let text = String(data: data, encoding: .utf8) else {
            throw WireError.invalidHeader
          }
          return text
        },
        encodeEvent: { (event: CardEvent) in
          switch event {
          case .activate: BonsaiNativeEvent(id: 1)
          case .invalid: BonsaiNativeEvent(id: 0)
          case .oversized:
            BonsaiNativeEvent(id: 1, payload: Data(count: ProtocolLimits.maxFrameBytes))
          }
        },
        makeResource: {
          self.created += 1
          let resource = CardResource()
          self.resource = resource
          return resource
        },
        dispose: { _ in self.disposed += 1 },
        content: { context in
          self.emit = context.emit
          self.emissions[context.properties] = context.emit
          return TestCardContent(context: context)
        })
    }
    return views
  }
}

private struct TestCardContent: View {
  let context: BonsaiNativeContext<String, CardEvent, CardResource>
  @State private var localCount = 0
  var body: some View {
    VStack {
      Text(context.properties)
      Button("Native activation") { _ = context.emit(.activate) }
      Button("Local state: \(localCount)") {
        localCount += 1
        context.resource.localCount = localCount
      }
      Button("Toggle native child") { context.resource.showsChild.toggle() }
      if context.resource.showsChild { ForEach(context.children) { $0 } }
    }
  }
}

@MainActor private func cardButton(_ session: BonsaiSession, _ title: String) throws
  -> RenderNodeState
{
  try #require(
    session.tree.nodes.values.first { node in
      node.kind == NodeKindId.button
        && node.children.contains {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        }
    })
}
@MainActor private func cardHasText(_ session: BonsaiSession, _ title: String) -> Bool {
  session.tree.nodes.values.contains {
    if case .text(let text) = $0.properties { return text.value == title }
    return false
  }
}
@MainActor private func settleCard(_ host: NSView) async throws {
  try await settleAccessibility(host)
}

extension NativeRuntimeTests {
  @Test @MainActor func registeredNativeViewRoutesEventsAndOwnsResources() async throws {
    initializeAccessibilityApplication()
    let trace = CardTrace()
    let session = BonsaiSession(nativeViews: try trace.registry())
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-view")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 600), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      try await settleCard(host)
      #expect(trace.created == 1)
      #expect(trace.disposed == 0)
      let beforePresentation = try #require(trace.emit)
      #expect(!beforePresentation(.activate))
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      let resource = try #require(trace.resource)
      let native = try #require(
        accessibilityElements(host).first {
          $0.role == "AXButton" && $0.label == "Native activation"
        })
      #expect(native.press())
      #expect(try await session.refresh())
      #expect(cardHasText(session, "Native events: 1"))
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      let local = try #require(
        accessibilityElements(host).first { $0.role == "AXButton" && $0.label == "Local state: 0" })
      #expect(local.press())
      try await settleCard(host)
      #expect(resource.localCount == 1)
      let old = try #require(trace.emit)
      #expect(session.activate(try cardButton(session, "Change native properties")))
      #expect(try await session.refresh())
      #expect(!old(.activate))
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      #expect(trace.resource === resource)
      #expect(resource.localCount == 1)
      #expect(trace.created == 1)
      #expect(
        accessibilityElements(host).contains {
          $0.role == "AXButton" && $0.label == "Local state: 1"
        })
      #expect(!old(.activate))
      let emit = try #require(trace.emit)
      #expect(!emit(.invalid))
      #expect(!emit(.oversized))
      let child = try cardButton(session, "Native child")
      #expect(session.activate(child))
      #expect(try await session.refresh())
      #expect(cardHasText(session, "Child events: 1"))
      #expect(try await session.presented(#require(session.ticket)))
      resource.showsChild = false
      try await settleCard(host)
      #expect(!session.activate(child))
      resource.showsChild = true
      try await settleCard(host)
      #expect(session.activate(child))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      let hidden = try #require(trace.emit)
      session.isVisible = false
      #expect(!hidden(.activate))
      #expect(!session.activate(child))
      session.isVisible = true
      try await settleCard(host)
      #expect(!hidden(.activate))
      #expect(trace.resource === resource)
      for action in ["Replace native handler", "Toggle logical child", "Toggle logical child"] {
        let stale = try #require(trace.emit)
        #expect(session.activate(try cardButton(session, action)))
        #expect(try await session.refresh())
        #expect(!stale(.activate))
        #expect(try await session.presented(#require(session.ticket)))
        try await settleCard(host)
        #expect(!stale(.activate))
        #expect(trace.resource === resource)
        #expect(trace.disposed == 0)
      }
      #expect(session.activate(try cardButton(session, "Replace native kind")))
      #expect(try await session.refresh())
      try await settleCard(host)
      #expect(trace.created == 2)
      #expect(trace.disposed == 1)
      #expect(trace.resource !== resource)
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      let replacementEmit = try #require(trace.emit)
      #expect(replacementEmit(.activate))
      #expect(try await session.refresh())
      #expect(cardHasText(session, "Native events: 2"))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try cardButton(session, "Toggle native card")))
      #expect(try await session.refresh())
      #expect(trace.disposed == 2)
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try cardButton(session, "Toggle native card")))
      #expect(try await session.refresh())
      #expect(trace.created == 3)
      await session.close()
      await session.close()
      #expect(trace.disposed == 3)
      #expect(!hidden(.activate))
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func nativeViewRejectsFramesAtomicallyAndBoundsQueue() async throws {
    for action in ["Unknown native kind", "Wrong native version", "Invalid native properties"] {
      let trace = CardTrace()
      let session = BonsaiSession(nativeViews: try trace.registry())
      session.isVisible = true
      do {
        try await session.start(entrypoint: "native-view")
        #expect(try await session.presented(#require(session.ticket)))
        let root = session.tree.root
        let revision = session.tree.revision
        #expect(session.activate(try cardButton(session, action)))
        await #expect(throws: (any Error).self) { try await session.refresh() }
        #expect(session.tree.root === root)
        #expect(session.tree.revision == revision)
        #expect(trace.created == 1)
        #expect(trace.disposed == 0)
        await session.close()
        #expect(trace.disposed == 1)
      } catch {
        await session.close()
        throw error
      }
    }
    let unregistered = BonsaiSession()
    unregistered.isVisible = true
    await #expect(throws: (any Error).self) {
      try await unregistered.start(entrypoint: "native-view")
    }
    #expect(unregistered.tree.root == nil)
    await unregistered.close()
    initializeAccessibilityApplication()
    let trace = CardTrace()
    let session = BonsaiSession(nativeViews: try trace.registry())
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-view")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 600), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      let emit = try #require(trace.emit)
      for _ in 0..<1024 { #expect(emit(.activate)) }
      #expect(!emit(.activate))
      #expect(try await session.refresh())
      #expect(cardHasText(session, "Native events: 1024"))
      await session.close()
      #expect(!emit(.activate))
      #expect(trace.disposed == 1)
    } catch {
      await session.close()
      throw error
    }
  }
}

private func nativeCardOperation(
  kind: UInt32 = 1001, version: UInt16 = 1, capabilities: UInt64 = 7,
  payload: Data = Data("Card".utf8), handler: UInt64 = 9
) -> WireOperation {
  TreeFixture.operation(OperationId.createNode) {
    $0.integer(UInt64(1))
    $0.integer(UInt16(NodeKindId.nativeWidget))
    $0.integer(kind)
    $0.integer(version)
    $0.integer(capabilities)
    $0.integer(UInt32(payload.count))
    $0.bytes.append(payload)
    $0.integer(UInt16(1))
    $0.integer(UInt16(EventTagId.nativeEvent))
    $0.integer(handler)
  }
}
struct NativeViewValidationTests {
  @Test @MainActor func nativeViewValidationAllocatesOnlyAfterCompleteFrameAcceptance() throws {
    let trace = CardTrace()
    let tree = RenderTree(nativeViews: try trace.registry())
    let frame = TreeFixture.frame([nativeCardOperation(), TreeFixture.root(1)])
    let store = try NodeStore().staging(frame).tree
    try tree.validate(store)
    #expect(trace.created == 0)
    tree.commit(store)
    #expect(trace.created == 1)
    let original = tree.root
    for operation in [
      nativeCardOperation(kind: 1003), nativeCardOperation(version: 2),
      nativeCardOperation(capabilities: 15), nativeCardOperation(payload: Data([255])),
    ] {
      let candidate = try NodeStore().staging(
        TreeFixture.frame([operation, TreeFixture.root(1)], epoch: 8)
      ).tree
      #expect(throws: (any Error).self) { try tree.validate(candidate) }
      #expect(tree.root === original)
      #expect(trace.created == 1)
      #expect(trace.disposed == 0)
    }
    let replacement = try NodeStore().staging(TreeFixture.frame(frame.operations, epoch: 9)).tree
    try tree.validate(replacement)
    tree.commit(replacement)
    #expect(tree.root !== original)
    #expect(trace.created == 2)
    #expect(trace.disposed == 1)
    tree.commit(NodeStore())
    tree.commit(NodeStore())
    #expect(trace.disposed == 2)
  }

  @Test func nativeViewMalformedEnvelopesRejectBeforePublication() throws {
    let valid = nativeCardOperation()
    _ = try NodeStore().staging(TreeFixture.frame([valid, TreeFixture.root(1)]))
    for operation in [
      nativeCardOperation(kind: 0), nativeCardOperation(kind: 65536),
      nativeCardOperation(version: 0), nativeCardOperation(capabilities: 32),
      nativeCardOperation(handler: 0),
    ] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(TreeFixture.frame([operation, TreeFixture.root(1)]))
      }
    }
    for length in 0..<valid.body.count {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([
            WireOperation(opcode: valid.opcode, body: valid.body.prefix(length)),
            TreeFixture.root(1),
          ]))
      }
    }
  }

  @Test @MainActor func registryRejectsDuplicateAndInvalidRegistrations() throws {
    var registry = try CardTrace().registry()
    for (kind, version, capabilities): (UInt32, UInt16, BonsaiNativeCapabilities) in [
      (1001, 1, []), (1001, 2, []), (0, 1, []), (65536, 1, []), (1004, 0, []),
      (1004, 1, BonsaiNativeCapabilities(rawValue: 32)),
    ] {
      #expect(throws: (any Error).self) {
        try registry.register(
          kind: kind, version: version, capabilities: capabilities,
          decode: { _ in () }, encodeEvent: { (_: Bool) in BonsaiNativeEvent(id: 1) },
          makeResource: { () }, dispose: { _ in }, content: { _ in Text("Invalid registration") })
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nestedNativeViewsBecomePresentedInOneAcknowledgment() async throws {
    let trace = CardTrace()
    let session = BonsaiSession(nativeViews: try trace.registry())
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-view-nested")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 900), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      try await settleCard(host)
      #expect(trace.created == 9)
      #expect(try await session.presented(#require(session.ticket)))
      try await settleCard(host)
      #expect(trace.emissions.count == 9)
      for emit in trace.emissions.values { #expect(emit(.activate)) }
      #expect(try await session.refresh())
      #expect(cardHasText(session, "Native events: 9"))
      await session.close()
      #expect(trace.disposed == 9)
    } catch {
      await session.close()
      throw error
    }
  }
}
