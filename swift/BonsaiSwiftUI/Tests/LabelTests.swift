import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func label(_ id: UInt64 = 1, update: Bool = false, bound: Bool = false) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(57))
      if update {
        $0.integer(UInt64(0))
      } else {
        $0.integer(UInt16(bound ? 1 : 0))
        if bound {
          $0.integer(UInt16(EventTagId.press))
          $0.integer(UInt64(91))
        }
      }
    }
  }
  static func labelTree(button: Bool = false) -> [WireOperation] {
    [
      label(), text(2, "Inbox"), symbol(3, name: "envelope", size: nil, color: nil),
      children(1, [2, 3]),
    ]
      + (button ? [Self.button(4, role: 0, style: 2), children(4, [1]), root(4)] : [root(1)])
  }
}

@MainActor struct LabelTests {
  @Test(arguments: [false, true], [false, true])
  func inheritsNativeLabelLayoutInButtonsAndBothDirections(button: Bool, rtl: Bool) throws {
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(TreeFixture.frame(TreeFixture.labelTree(button: button))).tree)
    let actual = NativeNodeView(node: try #require(tree.root), activate: { _ in })
    let label = Label {
      Text("Inbox")
    } icon: {
      Image(systemName: "envelope").accessibilityHidden(true)
    }
    let reference =
      button
      ? AnyView(
        Button {
        } label: {
          label
        }.buttonStyle(.bordered)) : AnyView(label)
    #expect(
      try raster(actual, rtl ? .rightToLeft : .leftToRight).matches(
        raster(reference, rtl ? .rightToLeft : .leftToRight)))
  }

  @Test func invalidLabelFramesCannotPublishPartialChanges() throws {
    let original = try NodeStore().staging(TreeFixture.frame(TreeFixture.labelTree())).tree
    let change = TreeFixture.label(update: true)
    var invalid = [
      TreeFixture.children(1, []), TreeFixture.children(1, [2]),
      TreeFixture.children(1, [2, 3, 2]),
    ]
    for count in 0..<change.body.count {
      invalid.append(WireOperation(opcode: change.opcode, body: change.body.prefix(count)))
    }
    invalid.append(WireOperation(opcode: change.opcode, body: change.body + Data([1])))
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try original.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true), operation], base: 1, revision: 2))
      }
      #expect(original.revision == 1)
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.label(bound: true), TreeFixture.text(2, "Inbox"), TreeFixture.text(3, "Icon"),
          TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
        ]))
    }
    let accepted = try original.staging(
      TreeFixture.frame(
        [change, TreeFixture.text(2, "Archive", update: true)], base: 1, revision: 2)
    ).tree
    #expect(accepted.revision == 2)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualLabelRowsKeepAccessoryActionsIndependentAndTitlesStable() async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ title: String, in node: RenderNodeState) -> Bool {
      if case .text(let value) = node.properties, value.value == title { return true }
      return node.children.contains { named(title, in: $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(title, in: $0) }
          return false
        })
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func appearance(_ headline: String, selected: Bool) throws {
      let actual = NativeNodeView(node: try button(headline), activate: { _ in }).frame(width: 320)
      let nativeButton = Button {
      } label: {
        Label {
          VStack(alignment: .leading, spacing: 3) {
            Text("Mailboxes").font(.system(size: 11))
            Text(headline)
            Text(headline == "Inbox" ? "Unread messages" : "Saved messages").font(.system(size: 12))
          }
        } icon: {
          Image(systemName: headline == "Inbox" ? "envelope" : "archivebox")
            .symbolRenderingMode(.monochrome).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      let reference =
        selected
        ? AnyView(nativeButton.buttonStyle(.borderedProminent))
        : AnyView(nativeButton.buttonStyle(.bordered))
      #expect(try raster(actual).matches(raster(reference.frame(width: 320))))
    }
    func status(_ value: String) throws {
      #expect(named(value, in: try #require(session.tree.root)))
    }
    do {
      try await session.start(entrypoint: "native-labels")
      let inbox = try button("Inbox")
      let title = try #require(
        session.tree.nodes.values.first {
          if case .text(let value) = $0.properties { return value.value == "Inbox" }
          return false
        })
      let info = try button("Info for Inbox")
      #expect(!session.activate(inbox))
      #expect(try await session.presented(#require(session.ticket)))
      try await press("Inbox")
      try status("Row: 1; opens: 1; info: 0")
      try appearance("Inbox", selected: true)
      try appearance("Archive", selected: false)
      try await press("Info for Inbox")
      try status("Row: 1; opens: 1; info: 1")
      try await press("Disable rows")
      #expect(!session.activate(inbox))
      try await press("Info for Inbox")
      try status("Row: 1; opens: 1; info: 2")
      try await press("Hide row details")
      #expect(!session.activate(info))
      #expect(session.tree.nodes[title.id.node] === title)
      try await press("Reverse rows")
      try await press("Show row details")
      #expect(try button("Inbox") === inbox)
      #expect(session.tree.nodes[title.id.node] === title)
      #expect(try button("Info for Inbox") !== info)
      #expect(!session.activate(info))
      try await press("Enable rows")
      try await press("Archive")
      try status("Row: 2; opens: 2; info: 2")
      try appearance("Inbox", selected: false)
      try appearance("Archive", selected: true)
      await session.close()
      #expect(!session.activate(inbox))
    } catch {
      await session.close()
      throw error
    }
  }
}
