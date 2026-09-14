import AppKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualHostNavigationRetainsClipboardAcrossSettingsAndFencesHiddenInput()
    async throws
  {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let service = DelayedClipboardService(pasteboard)
    let session = BonsaiSession(hostService: service)
    session.isVisible = true
    func contains(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    func button(_ title: String) throws -> RenderNodeState {
      let label = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      return try #require(session.tree.nodes.values.first { $0.children.contains { $0 === label } })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func settle(_ text: String) async throws {
      for _ in 0..<100 {
        try await flush()
        if contains(text) { return }
        try await Task.sleep(for: .milliseconds(5))
      }
      Issue.record("Missing Host Navigation state: \(text.prefix(100))")
    }
    do {
      try await session.start(entrypoint: "host_navigation")
      #expect(try await session.presented(#require(session.ticket)))
      let root = try #require(session.tree.root)
      let navigation = try #require(root.navigationController)
      let open = try button("Open settings")
      let read = try button("Read clipboard")
      #expect(contains("Clipboard not read"))
      pasteboard.setString("Retained 本地😀", forType: .string)
      service.holdReads = true
      #expect(session.activate(read))
      try await flush()
      for _ in 0..<20 { await Task.yield() }
      #expect(service.started.count == 1)
      #expect(session.activate(open))
      try await flush()
      #expect(navigation.path.count == 1)
      #expect(!session.activate(read))
      #expect(!session.activate(open))
      #expect(contains("Overlay owned by OCaml"))
      #expect(contains("Settings content owned by OCaml"))
      service.holdReads = false
      service.release()
      try await settle("Retained 本地😀")
      #expect(navigation.path.count == 1)
      let close = try button("Close settings")
      #expect(session.activate(close))
      try await flush()
      #expect(navigation.path.isEmpty)
      #expect(contains("Retained 本地😀"))
      #expect(session.tree.nodes[read.id.node] === read)
      #expect(!session.activate(close))

      #expect(session.activate(open))
      try await flush()
      let poppedClose = try button("Close settings")
      #expect(navigation.request([], emit: root.emit))
      #expect(!session.activate(read))
      #expect(!session.activate(poppedClose))
      try await flush()
      #expect(navigation.path.isEmpty)
      #expect(!navigation.request([], emit: root.emit))

      for (value, expected) in [
        ("", ""),
        (
          String(repeating: "界", count: ProtocolLimits.maxStringBytes / 3) + "x",
          String(repeating: "界", count: 1365) + "…"
        ),
        (
          String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1),
          "Clipboard request failed"
        ),
      ] {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #expect(session.activate(read))
        try await settle(expected)
      }
      await session.close()
      #expect(!root.emit(.navigationPath([])))
      try await session.start(entrypoint: "host_navigation")
      #expect(contains("Clipboard not read"))
      #expect(try #require(session.tree.root?.navigationController).path.isEmpty)
      await session.close()
    } catch {
      service.release()
      await session.close()
      throw error
    }
  }
}
