import AppKit
import ApplicationServices
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func semantics(
    _ id: UInt64 = 1, label: String? = "Mail item", role: UInt8 = 1,
    selected: UInt8 = 0, children: UInt8 = 0, hidden: UInt8 = 0,
    heading: UInt8? = nil, priority: Double? = nil, liveRegion: Bool = false,
    actions: [(UInt64, String)] = [], update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) { writer in
      writer.integer(id)
      writer.integer(UInt16(64))
      if update { writer.integer(UInt64(4095)) }
      for text in [label, "Open details", "Expanded"] {
        writer.integer(UInt8(text == nil ? 0 : 1))
        if let text { try! writer.string(text) }
      }
      writer.integer(role)
      writer.integer(selected)
      writer.integer(children)
      writer.integer(hidden)
      writer.integer(UInt8(liveRegion ? 1 : 0))
      writer.integer(UInt8(heading == nil ? 0 : 1))
      if let heading { writer.integer(heading) }
      writer.integer(UInt8(priority == nil ? 0 : 1))
      if let priority { writer.integer(priority.bitPattern) }
      writer.integer(UInt8(1))
      try! writer.string("native-item")
      writer.integer(UInt16(actions.count))
      for (id, label) in actions {
        writer.integer(id)
        try! writer.string(label)
      }
      if !update {
        writer.integer(UInt16(actions.isEmpty ? 0 : 1))
        if !actions.isEmpty {
          writer.integer(UInt16(22))
          writer.integer(UInt64(20))
        }
      }
    }
  }
}

struct SemanticsNodeTests {
  @Test func nativeSemanticsRejectsMalformedFieldsAndActionIdentitiesAtomically() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.semantics(), TreeFixture.text(2, "Visible text"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    for invalid in [
      TreeFixture.semantics(role: 7, update: true),
      TreeFixture.semantics(selected: 3, update: true),
      TreeFixture.semantics(children: 3, update: true),
      TreeFixture.semantics(hidden: 2, update: true),
      TreeFixture.semantics(heading: 0, update: true),
      TreeFixture.semantics(heading: 7, update: true),
      TreeFixture.semantics(priority: .nan, update: true),
      TreeFixture.semantics(actions: [(0, "Archive")], update: true),
      TreeFixture.semantics(actions: [(UInt64(Int64.max) + 1, "Archive")], update: true),
      TreeFixture.semantics(actions: (1...1025).map { (UInt64($0), "Action") }, update: true),
      TreeFixture.semantics(actions: [(1, "")], update: true),
      TreeFixture.semantics(actions: [(1, "Archive"), (1, "Delete")], update: true),
      TreeFixture.children(1, []),
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
      }
      #expect(initial.revision == 1)
    }
    let update = TreeFixture.semantics(update: true)
    for length in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [WireOperation(opcode: update.opcode, body: update.body.prefix(length))], base: 1,
            revision: 2))
      }
    }
  }

  @Test func liveRegionsRespectPresentationHistoryAndAncestorVisibility() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.semantics(1, label: "Container", role: 0),
        TreeFixture.semantics(2, label: "Initial status", role: 0, liveRegion: true),
        TreeFixture.text(3, "Status"), TreeFixture.children(1, [2]),
        TreeFixture.children(2, [3]), TreeFixture.root(1),
      ])
    ).tree
    #expect(initial.liveAnnouncements(since: NodeStore()).isEmpty)
    let changed = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.semantics(2, label: "Updated status", role: 0, liveRegion: true, update: true)
        ], base: 1, revision: 2)
    ).tree
    #expect(changed.liveAnnouncements(since: initial) == ["Updated status, Expanded"])
    #expect(changed.liveAnnouncements(since: changed).isEmpty)
    let hidden = try changed.staging(
      TreeFixture.frame(
        [
          TreeFixture.semantics(1, label: "Container", role: 0, hidden: 1, update: true),
          TreeFixture.semantics(2, label: "Hidden status", role: 0, liveRegion: true, update: true),
        ], base: 2, revision: 3)
    ).tree
    #expect(hidden.liveAnnouncements(since: changed).isEmpty)
    #expect(hidden.accessibilityHiddenNodes.contains(2))
    let restored = try hidden.staging(
      TreeFixture.frame(
        [
          TreeFixture.semantics(1, label: "Container", role: 0, update: true)
        ], base: 3, revision: 4)
    ).tree
    #expect(restored.liveAnnouncements(since: hidden) == ["Hidden status, Expanded"])
    let ignored = try restored.staging(
      TreeFixture.frame(
        [
          TreeFixture.semantics(1, label: "Container", role: 0, children: 2, update: true),
          TreeFixture.semantics(
            2, label: "Ignored status", role: 0, liveRegion: true, update: true),
        ], base: 4, revision: 5)
    ).tree
    #expect(ignored.accessibilityHiddenNodes.contains(2))
    #expect(ignored.liveAnnouncements(since: restored).isEmpty)

  }

  @Test @MainActor func nativeAccessibilityMetadataUpdatesWithoutReplacingContent() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.semantics(), TreeFixture.text(2, "Visible text"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    tree.commit(initial)
    let child = try #require(tree.nodes[2])
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let item = try #require(accessibilityElements(host).first { $0.identifier == "native-item" })
    #expect(item.label == "Mail item")
    #expect(item.help == "Open details")
    #expect(item.value == "Expanded")
    tree.commit(
      try initial.staging(
        TreeFixture.frame(
          [TreeFixture.semantics(label: "Updated item", selected: 2, update: true)], base: 1,
          revision: 2)
      ).tree)
    try await settleAccessibility(host)
    let changed = try #require(accessibilityElements(host).first { $0.identifier == "native-item" })
    #expect(changed.label == "Updated item")
    #expect(changed.selected)
    #expect(tree.nodes[2] === child)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryAccessibilityActionsReachOcamlAndAnnounceAfterPresentation()
    async throws
  {
    initializeAccessibilityApplication()
    var announcements: [String] = []
    let session = BonsaiSession(announce: { announcements.append($0) })
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-semantics")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      #expect(try await session.presented(#require(session.ticket)))
      #expect(announcements.isEmpty)
      let item = try #require(
        accessibilityElements(host).first { $0.identifier == "gallery-accessibility-item" })
      #expect(item.press())
      #expect(try await session.refresh())
      #expect(announcements.isEmpty)
      #expect(try await session.presented(#require(session.ticket)))
      #expect(announcements == ["Action 1"])
      try await settleAccessibility(host)
      let updated = try #require(
        accessibilityElements(host).first { $0.identifier == "gallery-accessibility-item" })
      let archive = try #require(updated.actions.first { $0.name == "Archive" })
      let archiveHandler = try #require(archive.handler)
      #expect(archiveHandler())
      #expect(try await session.refresh())
      #expect(announcements == ["Action 1"])
      #expect(try await session.presented(#require(session.ticket)))
      #expect(announcements == ["Action 1", "Action 41"])
      #expect(try await !session.refresh())
      #expect(announcements == ["Action 1", "Action 41"])
      try await settleAccessibility(host)
      let hide = try #require(
        accessibilityElements(host).first { $0.identifier == "gallery-hide-button" })
      #expect(hide.press())
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      try await settleAccessibility(host)
      #expect(
        !accessibilityElements(host).contains { $0.identifier == "gallery-accessibility-item" })
      _ = archiveHandler()
      #expect(try await !session.refresh())
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
