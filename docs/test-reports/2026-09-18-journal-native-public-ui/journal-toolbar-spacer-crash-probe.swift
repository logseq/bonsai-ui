import AppKit
import Observation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class ToolbarProbeState {
  var order: [RenderNodeState] { willSet { captureFocus() } }
  var placement = ToolbarItemPlacement.primaryAction { willSet { captureFocus() } }
  var spacers = false { willSet { captureFocus() } }
  @ObservationIgnored private var focus: (RenderNodeState, NSTextField, NSWindow, NSRange)?
  @ObservationIgnored private var scheduled = false
  private func captureFocus() {
    for node in order {
      guard let field = node.fieldController?.field, let window = field.window,
        let editor = field.currentEditor() as? NSTextView, window.firstResponder === editor
      else { continue }
      focus = (node, field, window, editor.selectedRange())
    }
  }
  func mounted() {
    guard focus != nil, !scheduled else { return }
    scheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.scheduled = false
      guard let (node, field, window, selection) = self.focus else { return }
      guard self.order.contains(where: { $0 === node }), field.isEnabled else {
        self.focus = nil
        return
      }
      guard field.window === window else { return }
      guard window.firstResponder === window || field.currentEditor() === window.firstResponder
      else {
        self.focus = nil
        return
      }
      if field.currentEditor() == nil { window.makeFirstResponder(field) }
      (field.currentEditor() as? NSTextView)?.setSelectedRange(selection)
      self.focus = nil
    }
  }
  var hosts: [RenderIdentity: NSHostingView<AnyView>] = [:]
  init(_ order: [RenderNodeState]) {
    self.order = order
    for node in order {
      hosts[node.id] = NSHostingView(
        rootView: AnyView(NativeNodeView(node: node, activate: { _ in }).frame(width: 120)))
    }
  }
}

private struct ToolbarProbeContent: ToolbarContent {
  let nodes: [RenderNodeState]
  let placement: ToolbarItemPlacement
  let hosts: [RenderIdentity: NSHostingView<AnyView>]
  let mounted: () -> Void
  let spacers: Bool
  private func compose(_ nodes: ArraySlice<RenderNodeState>) -> any ToolbarContent {
    guard let node = nodes.first else {
      return ToolbarItemGroup(placement: placement) { EmptyView() }
    }
    let head = ToolbarItem(id: "group-\(node.id.node)", placement: placement) {
      ControlGroup {
        ToolbarProbeMount(host: hosts[node.id]!, mounted: mounted)
      }.id(node.id)
    }
    let tail = ToolbarContentBuilder.buildLimitedAvailability(compose(nodes.dropFirst()))
    if spacers {
      return ToolbarContentBuilder.buildBlock(
        head, ToolbarSpacer(.fixed, placement: placement), tail)
    }
    return ToolbarContentBuilder.buildBlock(head, tail)
  }
  var body: some ToolbarContent {
    ToolbarContentBuilder.buildLimitedAvailability(compose(nodes[...]))
  }
}

private struct ToolbarProbeMount: NSViewRepresentable {
  let host: NSHostingView<AnyView>
  let mounted: () -> Void
  final class Shell: NSView {
    var host: NSHostingView<AnyView>?
    var mounted: (() -> Void)?
    override var intrinsicContentSize: NSSize { host?.fittingSize ?? .zero }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      attach()
    }
    override func layout() {
      super.layout()
      attach()
    }
    func attach() {
      guard window != nil, let host else { return }
      if host.superview !== self {
        host.autoresizingMask = [.width, .height]
        addSubview(host)
      }
      host.frame = bounds
      mounted?()
    }
  }
  func makeNSView(context: Context) -> Shell { Shell() }
  func updateNSView(_ view: Shell, context: Context) {
    view.host = host
    view.mounted = mounted
    view.attach()
    view.invalidateIntrinsicContentSize()
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: Shell, context: Context) -> CGSize? {
    host.fittingSize
  }
}

private struct ToolbarProbeRoot: View {
  let state: ToolbarProbeState
  var body: some View {
    Text("Stable body").frame(width: 650, height: 300)
      .toolbar {
        ToolbarProbeContent(
          nodes: state.order, placement: state.placement, hosts: state.hosts,
          mounted: state.mounted, spacers: state.spacers)
      }
  }
}

@MainActor struct ToolbarIdentityTests {
  @Test(arguments: [UInt64(2), UInt64(3)])
  func nativeFrameworkFieldsRetainFocusAcrossKeyedGroupMoves(focused: UInt64) async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.create(1), TreeFixture.editor(2, kind: 47, label: "First", text: "One"),
          TreeFixture.editor(3, kind: 47, label: "Second", text: "Two", session: 2),
          TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
        ])
      ).tree)
    tree.onInput = { _, _ in true }
    let first = try #require(tree.nodes[2])
    let second = try #require(tree.nodes[3])
    let state = ToolbarProbeState([first, second])
    let host = NSHostingController(rootView: ToolbarProbeRoot(state: state))
    host.sceneBridgingOptions = .all
    let window = NSWindow(contentViewController: host)
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    try await settleAccessibility(host.view)
    let focus = try #require(tree.nodes[focused])
    let controller = try #require(focus.fieldController)
    let field = controller.field
    func verifyNativeOwnership() throws {
      let entries = try #require(window.toolbar).items.filter {
        $0.itemIdentifier.rawValue.hasPrefix("group-")
      }
      #expect(entries.map(\.itemIdentifier.rawValue) == state.order.map { "group-\($0.id.node)" })
      #expect(entries.allSatisfy { $0 is NSToolbarItemGroup })
      func views(_ items: [NSToolbarItem]) -> [NSView] {
        items.compactMap(\.view)
          + items.flatMap { ($0 as? NSToolbarItemGroup).map { views($0.subitems) } ?? [] }
      }
      let native = views(entries)
      for node in state.order {
        let view = try #require(node.fieldController?.field)
        #expect(native.contains { view.isDescendant(of: $0) })
      }
    }
    try verifyNativeOwnership()
    #expect(field.window === window)
    #expect(first.fieldController?.field.window === window)
    #expect(second.fieldController?.field.window === window)
    field.selectText(nil)
    let editor = try #require(field.currentEditor() as? NSTextView)
    editor.insertText("Local draft", replacementRange: NSRange(location: 0, length: 3))
    try await settleAccessibility(host.view)
    state.order = [second, first]
    try await settleAccessibility(host.view)
    #expect(focus.fieldController?.field === field)
    try verifyNativeOwnership()
    #expect(field.window === window)
    #expect(first.fieldController?.field.window === window)
    #expect(second.fieldController?.field.window === window)
    #expect(field.currentEditor() === editor)
    #expect(window.firstResponder === editor)
    #expect(controller.session.value.text == "Local draft")
    state.placement = .navigation
    try await settleAccessibility(host.view)
    try verifyNativeOwnership()
    #expect(field.window === window)
    #expect(first.fieldController?.field.window === window)
    #expect(second.fieldController?.field.window === window)
    #expect(field.currentEditor() === editor)
    #expect(window.firstResponder === editor)
    for spacers in [true, false] {
      state.spacers = spacers
      try await settleAccessibility(host.view)
      try verifyNativeOwnership()
      #expect(field.currentEditor() === editor)
      #expect(window.firstResponder === editor)
    }
    state.order.reverse()
    let other = try #require((focused == 2 ? second : first).fieldController?.field)
    other.selectText(nil)
    try await settleAccessibility(host.view)
    #expect(other.currentEditor() === window.firstResponder)
    #expect(field.currentEditor() == nil)
  }
}
