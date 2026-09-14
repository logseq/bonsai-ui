import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualSidebarOwnsGroupedSelectionActionsAndModalPresentation() async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-sidebar")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 1050, height: 720),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func contains(_ title: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        }
      }
      func texts(_ node: RenderNodeState) -> [String] {
        if case .text(let text) = node.properties { return [text.value] }
        return node.children.flatMap(texts)
      }
      func button(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first {
            if case .button = $0.properties { return texts($0).contains(title) }
            return false
          })
      }
      func settle(_ predicate: () -> Bool = { true }) async throws {
        for _ in 0..<50 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
          if predicate() { return }
        }
        #expect(predicate())
      }
      func press(_ title: String) async throws {
        #expect(session.activate(try button(title)))
        try await settle()
      }
      func element(_ title: String) throws -> AccessibilityElement {
        try #require(
          accessibilityElements(host).first {
            $0.role == "AXButton" && $0.label == title
          })
      }
      func rect(_ title: String) throws -> CGRect {
        let object = try element(title).object
        let selector = NSSelectorFromString("accessibilityFrame")
        #expect(object.responds(to: selector))
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
      }
      func modalWindow() -> NSWindow? {
        NSApp.windows.first {
          $0 !== window && $0.isVisible
            && accessibilityElements($0).contains {
              $0.role == "AXButton" && $0.label == "Close sidebar"
            }
        }
      }
      try await settle()
      let split = try #require(session.tree.nodes.values.first { $0.kind == 15 })
      #expect(split.children.count == 2)
      #expect(contains("Mailboxes") && contains("Account"))
      #expect(contains("Selected destination: Inbox"))
      let inbox = try button("Inbox")
      let archive = try button("Archive")
      let compose = try button("Compose")
      #expect(!session.activate(try button("Unavailable")))
      #expect(try element("Archive").press())
      try await settle()
      #expect(contains("Selected destination: Archive"))
      try await press("Increment detail")
      #expect(contains("Detail count: 1"))
      try await press("Inbox")
      #expect(contains("Detail count: 0"))
      try await press("Archive")
      #expect(contains("Detail count: 1"))
      try await press("Reverse destinations")
      #expect(try button("Inbox") === inbox && button("Archive") === archive)
      try await press("Ignore changes")
      try await press("Inbox")
      #expect(contains("Selected destination: Archive"))
      try await press("Accept changes")
      try await press("Compose")
      try await press("Sidebar help")
      #expect(contains("Sidebar actions: 2"))
      try await press("Disable compose")
      #expect(!session.activate(compose))
      let pinnedHelp = try rect("Sidebar help")
      try await press("Move trailing content")
      #expect(try rect("Sidebar help").minY > pinnedHelp.minY + 100)
      try await press("Sidebar help")
      #expect(contains("Sidebar actions: 3"))
      #expect(contains("Trailing: after destinations"))
      try await press("Move trailing content")
      #expect(contains("Trailing: bottom"))
      #expect(try abs(rect("Sidebar help").minY - pinnedHelp.minY) < 1)
      let controller = try #require(split.splitController)
      var hidden = controller.state
      hidden.visibility = 3
      #expect(controller.request(hidden, emit: split.emit))
      try await settle()
      #expect(controller.state.visibility == 3)
      try await press("Show sidebar")
      #expect(controller.state.visibility == 1)
      window.setContentSize(CGSize(width: 1200, height: 800))
      try await settle()
      #expect(try button("Inbox") === inbox && button("Archive") === archive)
      try await press("Open modal sidebar")
      try await settle { modalWindow() != nil }
      #expect(!session.activate(try button("Increment detail")))
      #expect(!session.activate(inbox))
      let native = try #require(modalWindow())
      let choice = try #require(
        accessibilityElements(native).first {
          $0.role == "AXButton" && $0.label == "Inbox"
        })
      #expect(choice.press())
      try await settle { contains("Selected destination: Inbox") }
      let modalInbox = try button("Inbox")
      let sheet = try #require(session.tree.nodes.values.first { $0.kind == 73 })
      let presentation = try #require(sheet.presentationController)
      #expect(presentation.nativeVisible)
      native.cancelOperation(nil)
      try await settle { modalWindow() == nil && !presentation.nativeVisible }
      #expect(!session.activate(modalInbox))
      try await press("Show sidebar")
      try await settle { modalWindow() != nil && presentation.nativeVisible }
      #expect(try button("Inbox") === modalInbox)
      try await press("Archive")
      #expect(contains("Detail count: 1"))
      try await press("Close sidebar")
      try await settle { modalWindow() == nil }
      try await press("Use split sidebar")
      #expect(contains("Selected destination: Archive") && contains("Sidebar actions: 3"))
      #expect(!session.activate(modalInbox))
      session.isVisible = false
      #expect(!session.activate(try button("Archive")))
      await session.close()
      #expect(!session.activate(archive))
    } catch {
      await session.close()
      throw error
    }
  }
}
