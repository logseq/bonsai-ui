import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func sheet(
    presented: UInt8 = 0, fullscreen: UInt8 = 0, detents: UInt8 = 2,
    initial: UInt8 = 1, interactive: UInt8 = 1, indicator: UInt8 = 1, update: Bool = false,
    bound: Bool = true, sizing: UInt8 = 0, fraction: Double = 0
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(73))
      if update { $0.integer(UInt64(255)) }
      for value in [presented, fullscreen, detents, initial, interactive, indicator, sizing] {
        $0.integer(value)
      }
      $0.integer(fraction.bitPattern)
      if !update {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.valueChanged))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func sheetTree(_ props: WireOperation = sheet()) -> [WireOperation] {
    [
      props, text(2, "Background"), button(3), text(4, "Sheet action"), children(3, [4]),
      children(1, [2, 3]), root(1),
    ]
  }
}

@MainActor struct SheetTests {
  @Test func fractionalSheetHeightsValidateBeforePresentation() throws {
    func decode(_ fraction: Double, detents: UInt8 = 4, initial: UInt8 = 2) throws {
      var writer = WireWriter()
      for value: UInt8 in [1, 0, detents, initial, 1, 0, 3] { writer.integer(value) }
      writer.integer(fraction.bitPattern)
      var reader = WireReader(writer.bytes)
      _ = try RenderSheet.decode(&reader)
      #expect(reader.remaining == 0)
    }
    try decode(0.98)
    try decode(0.5, detents: 7, initial: 0)
    for invalid in [0, -0.1, 1.01, Double.nan, .infinity] {
      #expect(throws: (any Error).self) { try decode(invalid) }
    }
    #expect(throws: (any Error).self) { try decode(0.98, detents: 2, initial: 1) }
    #expect(throws: (any Error).self) { try decode(0.98, detents: 4, initial: 1) }
  }

  @Test func sheetsValidateDetentsAndRetainInactiveContent() throws {
    let original = try NodeStore().staging(TreeFixture.frame(TreeFixture.sheetTree())).tree
    #expect(original.accessibilityHiddenNodes.contains(3))
    let tree = RenderTree()
    tree.commit(original)
    let retained = try #require(tree.nodes[3])
    let shown = try original.staging(
      TreeFixture.frame(
        [TreeFixture.sheet(presented: 1, detents: 3, initial: 0, update: true)], base: 1,
        revision: 2)
    ).tree
    tree.commit(shown)
    #expect(tree.nodes[3] === retained)
    #expect(!shown.accessibilityHiddenNodes.contains(3))
    #expect(shown.accessibilityHiddenNodes.contains(2))
    for sizing: UInt8 in 0...3 {
      _ = try original.staging(
        TreeFixture.frame([TreeFixture.sheet(update: true, sizing: sizing)], base: 1, revision: 2))
    }
    var invalid = [
      TreeFixture.sheet(presented: 2, update: true), TreeFixture.sheet(fullscreen: 2, update: true),
      TreeFixture.sheet(detents: 0, update: true), TreeFixture.sheet(detents: 4, update: true),
      TreeFixture.sheet(initial: 2, update: true),
      TreeFixture.sheet(detents: 1, initial: 1, update: true),
      TreeFixture.sheet(interactive: 2, update: true),
      TreeFixture.sheet(indicator: 2, update: true),
      TreeFixture.sheet(update: true, sizing: 4),
      TreeFixture.sheet(fullscreen: 1, interactive: 0, indicator: 0, update: true, sizing: 1),
      TreeFixture.sheet(fullscreen: 1, detents: 3, interactive: 0, indicator: 0, update: true),
      TreeFixture.sheet(fullscreen: 1, interactive: 1, indicator: 0, update: true),
      TreeFixture.sheet(fullscreen: 1, interactive: 0, indicator: 1, update: true),
      TreeFixture.children(1, [2]), TreeFixture.children(1, [2, 3, 4]),
    ]
    let valid = TreeFixture.sheet(update: true)
    for length in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(length)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try original.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
      #expect(original.revision == 1)
    }
    _ = try original.staging(
      TreeFixture.frame(
        [TreeFixture.sheet(fullscreen: 1, interactive: 0, indicator: 0, update: true)], base: 1,
        revision: 2))
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame(TreeFixture.sheetTree(TreeFixture.sheet(bound: false))))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualSheetsOwnModalInputAndRetainChoicesAcrossPresentations() async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-sheet")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 460), styleMask: [.titled],
        backing: .buffered, defer: false)
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
      func button(_ title: String) throws -> RenderNodeState {
        var node = try #require(
          session.tree.nodes.values.first {
            if case .text(let text) = $0.properties { return text.value == title }
            return false
          })
        while true {
          if case .button = node.properties { return node }
          let child = node
          node = try #require(
            session.tree.nodes.values.first { $0.children.contains { $0 === child } })
        }
      }
      func nativeWindow(_ title: String) -> NSWindow? {
        NSApp.windows.first { candidate in
          candidate !== window && candidate.isVisible
            && candidate.contentView.map {
              accessibilityElements($0).contains { $0.role == "AXButton" && $0.label == title }
            } == true
        }
      }
      func settle(line: UInt = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<35 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
          if condition() { return }
        }
        Issue.record("Sheet did not settle at line \(line)")
        throw NSError(domain: "SheetTests", code: 1)
      }
      func press(_ title: String) async throws {
        #expect(session.activate(try button(title)))
        try await settle { session.ticket == nil }
      }
      var actions = 0
      var dismissals = 0
      var sheetSizes: [Int: CGSize] = [:]
      for variant in 0..<5 {
        let action = try button("Sheet action")
        #expect(!session.activate(action))
        try await press("Open sheet")
        let owner = try #require(session.tree.nodes.values.first { $0.kind == 73 })
        let controller = try #require(owner.presentationController)
        try await settle { nativeWindow("Sheet action") != nil && controller.nativeVisible }
        sheetSizes[variant] = try #require(nativeWindow("Sheet action")?.contentView).bounds.size
        #expect(!session.activate(try button("Background action")))
        #expect(!session.activate(try button("Sibling action")))
        let native = try #require(nativeWindow("Sheet action")?.contentView)
        let primary = try #require(
          accessibilityElements(native).first {
            $0.role == "AXButton" && $0.label == "Sheet action"
          })
        _ = primary.press()
        _ = primary.press()
        actions += 2
        try await settle { contains("Sheet actions: \(actions)") }
        if variant == 1 {
          #expect(!session.activate(try button("Unavailable")))
          try await press("Work")
          actions += 1
          #expect(contains("Selected account: 13"))
          #expect(contains("Sheet actions: \(actions)"))
        }
        try await press("Show hint")
        try await settle { nativeWindow("Hint action") != nil }
        let hint = try #require(nativeWindow("Hint action")?.contentView)
        _ = try #require(
          accessibilityElements(hint).first { $0.role == "AXButton" && $0.label == "Hint action" }
        ).press()
        actions += 1
        try await settle { contains("Sheet actions: \(actions)") }
        try #require(nativeWindow("Hint action")).cancelOperation(nil)
        try await settle { nativeWindow("Hint action") == nil }
        #expect(contains("Sheet dismissals: \(dismissals)"))
        if variant != 4 {
          try await press("Lock dismissal")
          try await settle { controller.nativeVisible }
          try #require(nativeWindow("Sheet action")).cancelOperation(nil)
          for _ in 0..<5 { try await settleAccessibility(host) }
          #expect(nativeWindow("Sheet action") != nil)
          #expect(contains("Sheet dismissals: \(dismissals)"))
          try await press("Unlock dismissal")
          try await settle { controller.nativeVisible }
          try await press("Reject dismissal")
          try #require(nativeWindow("Sheet action")).cancelOperation(nil)
          dismissals += 1
          try await settle {
            contains("Sheet dismissals: \(dismissals)") && controller.nativeVisible
          }
          let old = controller.binding(emit: owner.emit)
          _ = old.wrappedValue
          try await press("Replace sheet handler")
          try await settle { controller.nativeVisible }
          _ = old.wrappedValue
          old.wrappedValue = false
          try await settle { controller.nativeVisible }
          #expect(contains("Sheet dismissals: \(dismissals)"))
          try await press("Accept dismissal")
          try #require(nativeWindow("Sheet action")).cancelOperation(nil)
          dismissals += 1
          try await settle { contains("Sheet: Closed") && nativeWindow("Sheet action") == nil }
        } else {
          try #require(nativeWindow("Sheet action")).cancelOperation(nil)
          for _ in 0..<5 { try await settleAccessibility(host) }
          #expect(nativeWindow("Sheet action") != nil)
          try await press("Close sheet")
          try await settle { nativeWindow("Sheet action") == nil }
        }
        #expect(!session.activate(action))
        #expect(try button("Sheet action") === action)
        if variant < 4 { try await press("Next presentation") }
      }
      #expect(contains("Selected account: 13"))
      let fitted = try #require(sheetSizes[0])
      let form = try #require(sheetSizes[1])
      let page = try #require(sheetSizes[2])
      #expect(abs(fitted.height - 420) < 1 && abs(fitted.width - 360) < 1)
      #expect(form.height >= 360 && page.height >= 360)
      #expect(form.height != fitted.height)
      #expect(page.height != fitted.height)
      try await press("Open sheet")
      try await settle { nativeWindow("Sheet action") != nil }
      session.isVisible = false
      for _ in 0..<5 { try await settleAccessibility(host) }
      #expect(nativeWindow("Sheet action") == nil)
      #expect(!session.activate(try button("Sheet action")))
      session.isVisible = true
      try await settle { nativeWindow("Sheet action") != nil }
      #expect(contains("Sheet dismissals: \(dismissals)"))
      await session.close()
      for _ in 0..<5 { try await settleAccessibility(host) }
      #expect(nativeWindow("Sheet action") == nil)
    } catch {
      await session.close()
      throw error
    }
  }
}

extension SheetTests {
  @Test func rebindingSheetActionsPreservesNativeEditorMount() async throws {
    initializeAccessibilityApplication()
    let original = try NodeStore().staging(TreeFixture.frame([
      TreeFixture.sheet(presented: 1), TreeFixture.text(2, "Background"),
      TreeFixture.editor(3), TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
    ])).tree
    let tree = RenderTree()
    tree.onInput = { _, _ in true }
    tree.commit(original)
    let controller = try #require(tree.nodes[1]?.presentationController)
    let editor = try #require(tree.nodes[3]?.textController?.view)
    controller.setPresentationActive(true)
    let host = NSHostingView(rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer { tree.commit(NodeStore()); window.orderOut(nil); window.contentView = nil }
    for _ in 0..<10 { try await settleAccessibility(host); if controller.nativeVisible { break } }
    #expect(controller.nativeVisible)
    let scroll = try #require(editor.enclosingScrollView)
    let sheet = try #require(editor.window)
    #expect(sheet.makeFirstResponder(editor))
    let obsolete = controller.binding(emit: { _ in Issue.record("Stale dismissal"); return true })
    let rebind = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1)); $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.valueChanged)); $0.integer(UInt64(92))
    }
    tree.commit(try original.staging(TreeFixture.frame([rebind], base: 1, revision: 2)).tree)
    for _ in 0..<5 { try await settleAccessibility(host) }
    #expect(editor.enclosingScrollView === scroll)
    #expect(editor.window === sheet)
    #expect(sheet.firstResponder === editor)
    #expect(controller.nativeVisible)
    obsolete.wrappedValue = false
    #expect(controller.presented)
  }
}
