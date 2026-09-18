import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

// A native toolbar can temporarily detach an unchanged control while moving its
// item. This lease spans that mount only; ordinary focus changes remain events.
@MainActor final class ToolbarFocusController {
  private weak var owner: RenderNodeState?
  private weak var focused: RenderNodeState?
  private var bindings: [Int: UInt64] = [:]
  private var sessionID: UInt64?
  private var expiry: Task<Void, Never>?
  private var scheduled = false
  #if os(macOS)
    private weak var window: NSWindow?
  #else
    private weak var window: UIWindow?
  #endif

  func synchronize(_ owner: RenderNodeState) { self.owner = owner }

  func beforeCommit(_ store: NodeStore) {
    guard let owner, store.epoch == owner.id.epoch, store.nodes[owner.id.node] != nil else {
      cancel()
      return
    }
    if let focused, !valid(focused, in: store) { cancel() }
    var pending = [owner]
    var changed = false
    while let node = pending.popLast() {
      guard let next = store.nodes[node.id.node] else {
        changed = true
        continue
      }
      if node.kind == NodeKindId.toolbar || node.properties.isToolbarStructure {
        changed =
          changed || node.properties != next.properties
          || node.children.map(\.id.node) != next.children
      }
      pending.append(contentsOf: node.children.filter { $0.properties.isToolbarStructure })
    }
    guard changed else { return }
    capture()
    if let focused, !valid(focused, in: store) { cancel() }
  }

  private func valid(_ node: RenderNodeState, in store: NodeStore) -> Bool {
    guard let next = store.nodes[node.id.node], next.bindings == bindings,
      next.properties.textEditing?.snapshot.sessionID == sessionID,
      next.properties.textEditing?.configuration.enabled == true,
      !store.accessibilityHiddenNodes.contains(node.id.node)
    else { return false }
    return true
  }

  func received(_ node: RenderNodeState, _ payload: NativeEventPayload) {
    guard expiry != nil, case .focusChanged(true) = payload, node !== focused else { return }
    cancel()
    capture()
  }

  private func capture() {
    guard let owner else { return }
    var pending = [owner]
    while let node = pending.popLast() {
      pending.append(contentsOf: node.children)
      #if os(macOS)
        let field = node.fieldController?.field
        let text = node.textController?.view ?? field?.currentEditor() as? NSTextView
        guard let text, let nativeWindow = text.window, nativeWindow.firstResponder === text else {
          continue
        }
      #else
        let view: UIView? = node.fieldController?.field ?? node.textController?.view
        guard let view, view.isFirstResponder, let nativeWindow = view.window else { continue }
      #endif
      guard
        node.fieldController?.beginToolbarFocusTransfer() == true
          || node.textController?.beginToolbarFocusTransfer() == true
      else { continue }
      if focused !== node { cancel() }
      focused = node
      bindings = node.bindings
      sessionID = node.properties.textEditing?.snapshot.sessionID
      window = nativeWindow
      expiry?.cancel()
      expiry = Task { [weak self] in
        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        self?.cancel()
      }
      return
    }
  }

  func mounted() {
    guard focused != nil, !scheduled else { return }
    scheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.scheduled = false
      self.restore()
    }
  }

  private func restore() {
    guard let node = focused, let window,
      node.bindings == bindings, node.properties.textEditing?.snapshot.sessionID == sessionID,
      node.fieldController?.hasToolbarFocusTransfer == true
        || node.textController?.hasToolbarFocusTransfer == true
    else {
      cancel()
      return
    }
    let value = node.fieldController?.session.value ?? node.textController!.session.value
    let selection = value.selection
    let composition = value.marked.map { (value.text, $0) }
    #if os(macOS)
      guard window.isVisible else {
        cancel()
        return
      }
      let field = node.fieldController?.field
      let text = node.textController?.view
      guard (field?.window ?? text?.window) === window else { return }
      let current = field?.currentEditor() ?? text
      guard window.firstResponder === window || window.firstResponder === current else {
        cancel()
        return
      }
      if window.firstResponder !== current {
        guard window.makeFirstResponder(field ?? text!) else {
          cancel()
          return
        }
      }
      if let editor = field?.currentEditor() as? NSTextView ?? text {
        if let (value, marked) = composition, editor.string == value, !editor.hasMarkedText() {
          editor.setMarkedText(
            (value as NSString).substring(with: marked),
            selectedRange: NSRange(
              location: selection.location - marked.location, length: selection.length),
            replacementRange: marked)
        }
        editor.setSelectedRange(selection)
      }
    #else
      let view: UIView? = node.fieldController?.field ?? node.textController?.view
      guard let view, view.window === window else { return }
      func firstResponder(_ root: UIView) -> UIView? {
        if root.isFirstResponder { return root }
        for child in root.subviews { if let current = firstResponder(child) { return current } }
        return nil
      }
      if let current = firstResponder(window), current !== view {
        cancel()
        return
      }
      guard view.isFirstResponder || view.becomeFirstResponder() else {
        cancel()
        return
      }
      let editable: (any UITextInput)? = node.fieldController?.field ?? node.textController?.view
      if let editable, let (value, marked) = composition, editable.markedTextRange == nil,
        (node.fieldController?.field.text ?? node.textController?.view.text) == value,
        let start = editable.position(from: editable.beginningOfDocument, offset: marked.location),
        let end = editable.position(from: start, offset: marked.length)
      {
        editable.selectedTextRange = editable.textRange(from: start, to: end)
        editable.setMarkedText(
          (value as NSString).substring(with: marked),
          selectedRange: NSRange(
            location: selection.location - marked.location, length: selection.length))
      }
      if let input = node.fieldController?.field,
        let start = input.position(from: input.beginningOfDocument, offset: selection.location),
        let end = input.position(from: start, offset: selection.length)
      {
        input.selectedTextRange = input.textRange(from: start, to: end)
      }
      node.textController?.view.selectedRange = selection
    #endif
    cancel()
  }

  func cancel() {
    let node = focused
    focused = nil
    window = nil
    expiry?.cancel()
    expiry = nil
    node?.fieldController?.endToolbarFocusTransfer()
    node?.textController?.endToolbarFocusTransfer()
  }
}
