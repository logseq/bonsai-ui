import Foundation

struct TextEditorConfiguration: Equatable, Sendable {
  let enabled: Bool
  let readOnly: Bool
  let submitOnReturn: Bool
  let maxUTF8Bytes: Int?
  init(
    enabled: Bool = true, readOnly: Bool = false, submitOnReturn: Bool = false,
    maxUTF8Bytes: Int? = nil
  ) throws {
    if let maxUTF8Bytes, !(1...ProtocolLimits.maxStringBytes).contains(maxUTF8Bytes) {
      throw TextSessionError.invalidLimit
    }
    self.enabled = enabled
    self.readOnly = readOnly
    self.submitOnReturn = submitOnReturn
    self.maxUTF8Bytes = maxUTF8Bytes
  }
}

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor final class NativeTextController: NSObject {
  let view = NativeEditingTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
  private(set) var session: TextSession
  private var configuration: TextEditorConfiguration
  private var emit: (NativeEventPayload) -> Bool
  private var failed: (any Error) -> Void
  private var applying = false
  private var disposed = false
  private var focused = false
  private var hostEnabled = true

  init(
    snapshot: TextSnapshot, configuration: TextEditorConfiguration,
    emit: @escaping (NativeEventPayload) -> Bool, failed: @escaping (any Error) -> Void
  ) {
    session = TextSession(snapshot)
    self.configuration = configuration
    self.emit = emit
    self.failed = failed
    super.init()
    view.delegate = self
    view.changed = { [weak self] in self?.capture() }
    view.focusChanged = { [weak self] in self?.focus($0) }
    view.acceptsInput = { [weak self] in
      guard let self, !disposed else { return false }
      return applying
        || (self.hostEnabled && self.configuration.enabled && !self.configuration.readOnly)
    }
    #if os(macOS)
      view.isRichText = false
      view.importsGraphics = false
      view.drawsBackground = false
      view.font = .preferredFont(forTextStyle: .body)
      view.isVerticallyResizable = true
      view.isHorizontallyResizable = false
      view.textContainer?.widthTracksTextView = true
    #else
      view.backgroundColor = .clear
      view.font = .preferredFont(forTextStyle: .body)
      view.adjustsFontForContentSizeCategory = true
    #endif
    configure(configuration)
    replaceNativeValue()
  }

  @discardableResult func apply(_ snapshot: TextSnapshot) throws -> Bool {
    guard !disposed else { return false }
    let replace = try session.apply(snapshot)
    if replace { replaceNativeValue() }
    return replace
  }

  func configure(_ configuration: TextEditorConfiguration) {
    guard !disposed else { return }
    self.configuration = configuration
    updateAvailability()
  }

  func setHostEnabled(_ enabled: Bool) {
    guard !disposed, enabled != hostEnabled else { return }
    hostEnabled = enabled
    updateAvailability()
  }

  private func updateAvailability() {
    let enabled = hostEnabled && configuration.enabled
    view.isEditable = enabled && !configuration.readOnly
    view.isSelectable = enabled
    if !enabled {
      #if os(macOS)
        if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
      #else
        if view.isFirstResponder { view.resignFirstResponder() }
      #endif
    }
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    view.changed = nil
    view.focusChanged = nil
    view.acceptsInput = nil
    view.delegate = nil
    view.unmarkText()
    #if os(iOS)
      view.resignFirstResponder()
    #endif
    emit = { _ in false }
    failed = { _ in }
  }

  private var nativeText: String {
    #if os(macOS)
      view.string
    #else
      view.text ?? ""
    #endif
  }
  private var markedRange: NSRange? {
    #if os(macOS)
      let range = view.markedRange()
      return range.location == NSNotFound || range.length == 0 ? nil : range
    #else
      guard let range = view.markedTextRange else { return nil }
      let start = view.offset(from: view.beginningOfDocument, to: range.start)
      let end = view.offset(from: view.beginningOfDocument, to: range.end)
      return end > start ? NSRange(location: start, length: end - start) : nil
    #endif
  }
  private var selection: NSRange {
    #if os(macOS)
      let range = view.selectedRange()
    #else
      let range = view.selectedRange
    #endif
    return range.location == NSNotFound
      ? NSRange(location: nativeText.utf16.count, length: 0) : range
  }

  private func capture() {
    guard !applying, !disposed, view.mutationDepth == 0 else { return }
    do {
      let value = try TextValue(text: nativeText, selection: selection, marked: markedRange)
      let previous = session
      switch try session.edit(value, maxUTF8Bytes: configuration.maxUTF8Bytes) {
      case .unchanged: break
      case .edited(let edit):
        if !emit(.textEdit(edit)) {
          session = previous
          replaceNativeValue()
        }
      case .limitReached:
        replaceNativeValue()
        _ = emit(.textLimitReached)
      }
    } catch {
      replaceNativeValue()
      failed(error)
    }
  }

  private func replaceNativeValue() {
    applying = true
    defer { applying = false }
    let value = session.value
    view.unmarkText()
    #if os(macOS)
      view.string = value.text
      if let marked = value.marked {
        let fragment = (value.text as NSString).substring(with: marked)
        let relative = NSRange(
          location: value.selection.location - marked.location, length: value.selection.length)
        view.setMarkedText(fragment, selectedRange: relative, replacementRange: marked)
      }
      view.setSelectedRange(value.selection)
    #else
      view.text = value.text
      if let marked = value.marked {
        view.selectedRange = marked
        let fragment = (value.text as NSString).substring(with: marked)
        let relative = NSRange(
          location: value.selection.location - marked.location, length: value.selection.length)
        view.setMarkedText(fragment, selectedRange: relative)
      }
      view.selectedRange = value.selection
    #endif
  }

  private func shouldReplace(_ range: NSRange, with replacement: String?) -> Bool {
    if applying { return true }
    guard !disposed, hostEnabled, configuration.enabled, !configuration.readOnly else {
      return false
    }
    guard let replacement else { return true }
    let text = nativeText as NSString
    guard range.location >= 0, range.location <= text.length, range.length >= 0,
      range.length <= text.length - range.location
    else { return false }
    let candidate = text.replacingCharacters(in: range, with: replacement)
    guard candidate.utf8.count <= configuration.maxUTF8Bytes ?? ProtocolLimits.maxStringBytes else {
      _ = emit(.textLimitReached)
      return false
    }
    return true
  }

  private func submit() -> Bool {
    guard !disposed, hostEnabled, configuration.enabled, !configuration.readOnly,
      configuration.submitOnReturn, markedRange == nil
    else { return false }
    _ = emit(.textSubmit(session.value.text))
    return true
  }

  private func focus(_ value: Bool) {
    guard !disposed, value != focused else { return }
    focused = value
    _ = emit(.focusChanged(value))
  }
}

#if os(macOS)
  extension NativeTextController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) { capture() }
    func textViewDidChangeSelection(_ notification: Notification) { capture() }
    func textView(
      _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      shouldReplace(affectedCharRange, with: replacementString)
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      commandSelector == #selector(NSResponder.insertNewline(_:)) && submit()
    }
  }

  @MainActor final class NativeEditingTextView: NSTextView {
    var changed: (() -> Void)?
    var focusChanged: ((Bool) -> Void)?
    var acceptsInput: (() -> Bool)?
    private(set) var mutationDepth = 0

    private func mutation(_ action: () -> Void) {
      mutationDepth += 1
      action()
      mutationDepth -= 1
      if mutationDepth == 0 { changed?() }
    }
    override func setSelectedRange(_ charRange: NSRange) {
      mutation { super.setSelectedRange(charRange) }
    }
    override func setSelectedRange(
      _ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
      mutation {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
      }
    }
    override func setSelectedRanges(
      _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
      mutation {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
      }
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
      guard acceptsInput?() == true else { return }
      mutation {
        super.setMarkedText(
          string, selectedRange: selectedRange, replacementRange: replacementRange)
      }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
      guard acceptsInput?() == true else { return }
      mutation { super.insertText(insertString, replacementRange: replacementRange) }
    }
    override func unmarkText() { mutation { super.unmarkText() } }
    override func becomeFirstResponder() -> Bool {
      let accepted = super.becomeFirstResponder()
      if accepted { focusChanged?(true) }
      return accepted
    }
    override func resignFirstResponder() -> Bool {
      let accepted = super.resignFirstResponder()
      if accepted { focusChanged?(false) }
      return accepted
    }
  }
#else
  extension NativeTextController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) { capture() }
    func textViewDidChangeSelection(_ textView: UITextView) { capture() }
    func textView(
      _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
    ) -> Bool {
      if text == "\n" && submit() { return false }
      return shouldReplace(range, with: text)
    }
  }

  @MainActor final class NativeEditingTextView: UITextView {
    var changed: (() -> Void)?
    var focusChanged: ((Bool) -> Void)?
    var acceptsInput: (() -> Bool)?
    private(set) var mutationDepth = 0

    private func mutation(_ action: () -> Void) {
      mutationDepth += 1
      action()
      mutationDepth -= 1
      if mutationDepth == 0 { changed?() }
    }
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
      guard acceptsInput?() == true else { return }
      mutation { super.setMarkedText(markedText, selectedRange: selectedRange) }
    }
    override func insertText(_ text: String) {
      guard acceptsInput?() == true else { return }
      mutation { super.insertText(text) }
    }
    override func deleteBackward() {
      guard acceptsInput?() == true else { return }
      mutation { super.deleteBackward() }
    }
    override func unmarkText() { mutation { super.unmarkText() } }
    override func becomeFirstResponder() -> Bool {
      let accepted = super.becomeFirstResponder()
      if accepted { focusChanged?(true) }
      return accepted
    }
    override func resignFirstResponder() -> Bool {
      let accepted = super.resignFirstResponder()
      if accepted { focusChanged?(false) }
      return accepted
    }
  }
#endif
