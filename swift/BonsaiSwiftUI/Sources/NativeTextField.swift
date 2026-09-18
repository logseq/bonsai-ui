import Foundation
import SwiftUI

enum FieldKeyboard: Int, Equatable, Sendable { case text, number, email, phone, url }
enum FieldSubmitLabel: Int, Equatable, Sendable { case done, next, search, send, go, `continue` }
enum FieldAppearance: Int, Equatable, Sendable { case rounded, plain }
struct TextFieldTraits: Equatable, Sendable {
  var keyboard: FieldKeyboard = .text
  var submitLabel: FieldSubmitLabel = .done
  var autofocus = false
  var appearance: FieldAppearance = .rounded
}

struct RenderTextField: Equatable, Sendable {
  let editing: RenderTextEditor
  let label: String
  let prompt: String
  let secure: Bool
  let traits: TextFieldTraits

  static func decode(_ reader: inout WireReader, secure: Bool) throws -> Self {
    try Self(
      editing: RenderTextEditor.decode(&reader), label: reader.string(),
      prompt: reader.string(), secure: secure,
      traits: TextFieldTraits(
        keyboard: FieldKeyboard(rawValue: reader.choice(4))!,
        submitLabel: FieldSubmitLabel(rawValue: reader.choice(5))!, autofocus: reader.flag(),
        appearance: FieldAppearance(rawValue: reader.choice(1))!))
  }
}

#if os(macOS)
  import AppKit

  private final class FieldInputFormatter: Formatter {
    let validate: @MainActor (String) -> Bool
    init(validate: @escaping @MainActor (String) -> Bool) {
      self.validate = validate
      super.init()
    }
    required init?(coder: NSCoder) { return nil }
    override func string(for obj: Any?) -> String? { obj as? String }
    override func getObjectValue(
      _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
      for string: String,
      errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
      obj?.pointee = string as NSString
      return true
    }
    override func isPartialStringValid(
      _ partialString: String,
      newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
      errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
      let validate = validate
      return MainActor.assumeIsolated { validate(partialString) }
    }
  }

  @MainActor private final class PlainField: NSTextField {
    var attached: (() -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      attached?()
    }
    override func layout() {
      super.layout()
      attached?()
    }
    var focused: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
      let accepted = super.becomeFirstResponder()
      if accepted { focused?() }
      return accepted
    }
    override func selectText(_ sender: Any?) {
      super.selectText(sender)
      focused?()
    }
  }
  @MainActor private final class SecureField: NSSecureTextField {
    var attached: (() -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      attached?()
    }
    override func layout() {
      super.layout()
      attached?()
    }
    var focused: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
      let accepted = super.becomeFirstResponder()
      if accepted { focused?() }
      return accepted
    }
    override func selectText(_ sender: Any?) {
      super.selectText(sender)
      focused?()
    }
  }

  @MainActor final class NativeTextFieldController: NSObject, NSTextFieldDelegate {
    let field: NSTextField
    private(set) var session: TextSession
    private var configuration: TextEditorConfiguration
    private var emit: (NativeEventPayload) -> Bool
    private var failed: (any Error) -> Void
    private var hostEnabled = true
    private var contentActive = true
    private var retainingFocus = false
    private var applying = false
    private var disposed = false
    private var focused = false
    private var traits = TextFieldTraits()
    private var presentationActive = false
    private var autofocusPending = false
    private var captureTask: Task<Void, Never>?

    init(
      snapshot: TextSnapshot, secure: Bool, configuration: TextEditorConfiguration,
      label: String, prompt: String, emit: @escaping (NativeEventPayload) -> Bool,
      failed: @escaping (any Error) -> Void
    ) {
      field = secure ? SecureField() : PlainField()
      session = TextSession(snapshot)
      self.configuration = configuration
      self.emit = emit
      self.failed = failed
      super.init()
      field.delegate = self
      field.stringValue = snapshot.value.text
      field.placeholderString = prompt
      field.setAccessibilityLabel(label)
      field.font = .preferredFont(forTextStyle: .body)
      field.maximumNumberOfLines = 1
      field.usesSingleLineMode = true
      field.formatter = FieldInputFormatter { [weak self] in self?.accepts($0) ?? false }
      (field as? PlainField)?.attached = { [weak self] in self?.attemptAutofocus() }
      (field as? SecureField)?.attached = { [weak self] in self?.attemptAutofocus() }
      (field as? PlainField)?.focused = { [weak self] in self?.focus(true) }
      (field as? SecureField)?.focused = { [weak self] in self?.focus(true) }
      NotificationCenter.default.addObserver(
        self, selector: #selector(selectionChanged(_:)),
        name: NSTextView.didChangeSelectionNotification, object: nil)
      updateAvailability()
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
    func configureTraits(_ traits: TextFieldTraits) {
      guard !disposed else { return }
      if !traits.autofocus {
        autofocusPending = false
      } else if !self.traits.autofocus {
        autofocusPending = true
      }
      self.traits = traits
      field.isBordered = false
      field.isBezeled = traits.appearance == .rounded
      field.drawsBackground = traits.appearance == .rounded
      field.focusRingType = traits.appearance == .plain ? .none : .default
      attemptAutofocus()
    }
    func setPresentationActive(_ active: Bool) {
      guard !disposed else { return }
      presentationActive = active
      attemptAutofocus()
    }
    private func attemptAutofocus() {
      guard !disposed, presentationActive, autofocusPending, hostEnabled, contentActive,
        configuration.enabled, let window = field.window, window.isVisible,
        !field.isHiddenOrHasHiddenAncestor
      else { return }
      autofocusPending = false
      if !window.makeFirstResponder(field) { autofocusPending = true }
    }

    func setLabels(label: String, prompt: String) {
      guard !disposed else { return }
      field.placeholderString = prompt
      field.setAccessibilityLabel(label)
    }
    func setContentActive(_ active: Bool, retainingFocus: Bool = false) {
      guard !disposed, active != contentActive || retainingFocus != self.retainingFocus else { return }
      contentActive = active
      self.retainingFocus = retainingFocus
      updateAvailability()
    }
    var retainsEditingFocus: Bool { retainingFocus && focused && !disposed }
    private var acceptsEdits: Bool {
      !disposed && hostEnabled && (contentActive || retainsEditingFocus)
        && configuration.enabled && !configuration.readOnly
    }
    func setHostEnabled(_ enabled: Bool) {
      guard !disposed else { return }
      hostEnabled = enabled
      updateAvailability()
    }
    private func updateAvailability() {
      let enabled = hostEnabled && (contentActive || retainsEditingFocus) && configuration.enabled
      let editable = enabled && !configuration.readOnly
      if field.isEnabled != enabled { field.isEnabled = enabled }
      if field.isEditable != editable { field.isEditable = editable }
      if field.isSelectable != enabled { field.isSelectable = enabled }
      if !enabled { releaseFocus() }
      attemptAutofocus()
    }
    private func releaseFocus() {
      if let editor = field.currentEditor(), field.window?.firstResponder === editor {
        field.window?.makeFirstResponder(nil)
      }
    }
    func dispose() {
      guard !disposed else { return }
      disposed = true
      captureTask?.cancel()
      captureTask = nil
      releaseFocus()
      NotificationCenter.default.removeObserver(self)
      field.delegate = nil
      (field as? PlainField)?.attached = nil
      (field as? SecureField)?.attached = nil
      (field as? PlainField)?.focused = nil
      (field as? SecureField)?.focused = nil
      field.isEnabled = false
      emit = { _ in false }
      failed = { _ in }
    }
    private var editor: NSTextView? { field.currentEditor() as? NSTextView }

    private func accepts(_ candidate: String) -> Bool {
      if applying { return true }
      guard acceptsEdits else {
        return false
      }
      guard candidate.utf8.count <= configuration.maxUTF8Bytes ?? ProtocolLimits.maxStringBytes
      else {
        _ = emit(.textLimitReached)
        return false
      }
      return true
    }

    @objc private func selectionChanged(_ notification: Notification) {
      guard let changed = notification.object as? NSTextView, changed === editor else { return }
      focus(true)
      scheduleCapture()
    }
    private func scheduleCapture() {
      guard !disposed, !applying, captureTask == nil else { return }
      // A selection notification can occur inside a marked-text mutation. Read its completed state.
      captureTask = Task { @MainActor [weak self] in
        guard let self else { return }
        captureTask = nil
        if !Task.isCancelled { capture() }
      }
    }
    private func capture() {
      guard !disposed, !applying else { return }
      do {
        let text = editor?.string ?? field.stringValue
        let range =
          editor?.selectedRange()
          ?? (text == session.value.text
            ? session.value.selection : NSRange(location: text.utf16.count, length: 0))
        let marked = editor?.markedRange()
        let value = try TextValue(
          text: text,
          selection: range.location == NSNotFound
            ? NSRange(location: text.utf16.count, length: 0) : range,
          marked: marked.flatMap { $0.location == NSNotFound || $0.length == 0 ? nil : $0 })
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
      let current = editor
      current?.unmarkText()
      field.stringValue = value.text
      if let current {
        current.string = value.text
        if let marked = value.marked {
          let fragment = (value.text as NSString).substring(with: marked)
          current.setMarkedText(
            fragment,
            selectedRange: NSRange(
              location: value.selection.location - marked.location, length: value.selection.length),
            replacementRange: marked)
        }
        current.setSelectedRange(value.selection)
      }
    }
    private func focus(_ value: Bool) {
      guard !disposed, value != focused else { return }
      focused = value
      _ = emit(.focusChanged(value))
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      focus(true)
      scheduleCapture()
    }
    func controlTextDidChange(_ notification: Notification) { scheduleCapture() }
    func controlTextDidEndEditing(_ notification: Notification) {
      capture()
      focus(false)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool
    {
      guard selector == #selector(NSResponder.insertNewline(_:)), !disposed, hostEnabled,
        configuration.enabled, !configuration.readOnly, configuration.submitOnReturn,
        !textView.hasMarkedText()
      else { return false }
      capture()
      _ = emit(.textSubmit(session.value.text))
      return true
    }
  }

  struct NativeTextFieldView: NSViewRepresentable {
    let controller: NativeTextFieldController
    @Environment(\.isEnabled) private var enabled
    @Environment(\.bonsaiFontFamily) private var fontFamily
    @Environment(\.bonsaiDefaults) private var defaults
    @Environment(\.controlSize) private var controlSize
    func makeNSView(context: Context) -> NSTextField { controller.field }
    func updateNSView(_ view: NSTextField, context: Context) {
      controller.setHostEnabled(enabled)
      view.font = defaults.bodyFont(
        family: fontFamily, legibility: context.environment.legibilityWeight)
      view.textColor = NSColor(defaults.color(defaults.defaultForeground()))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context)
      -> CGSize?
    {
      CGSize(width: proposal.width ?? 240, height: max(28, nsView.intrinsicContentSize.height))
    }
  }
#else
  import UIKit

  @MainActor private final class EditingField: UITextField {
    var attached: (() -> Void)?
    override func didMoveToWindow() {
      super.didMoveToWindow()
      attached?()
    }
    override func layoutSubviews() {
      super.layoutSubviews()
      attached?()
    }
    var changed: (() -> Void)?
    var focusChanged: ((Bool) -> Void)?
    var acceptsInput: (() -> Bool)?
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
      guard acceptsInput?() == true else { return }
      super.setMarkedText(markedText, selectedRange: selectedRange)
      changed?()
    }
    override func insertText(_ text: String) {
      guard acceptsInput?() == true else { return }
      super.insertText(text)
      changed?()
    }
    override func deleteBackward() {
      guard acceptsInput?() == true else { return }
      super.deleteBackward()
      changed?()
    }
    override func unmarkText() {
      super.unmarkText()
      changed?()
    }
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

  @MainActor final class NativeTextFieldController: NSObject, UITextFieldDelegate {
    private let input = EditingField()
    var field: UITextField { input }
    private(set) var session: TextSession
    private var configuration: TextEditorConfiguration
    private var emit: (NativeEventPayload) -> Bool
    private var failed: (any Error) -> Void
    private var hostEnabled = true
    private var contentActive = true
    private var retainingFocus = false
    private var applying = false
    private var disposed = false
    private var focused = false
    private var traits = TextFieldTraits()
    private var presentationActive = false
    private var autofocusPending = false
    private var captureTask: Task<Void, Never>?
    private let readOnlyKeyboard = UIView(frame: .zero)

    init(
      snapshot: TextSnapshot, secure: Bool, configuration: TextEditorConfiguration,
      label: String, prompt: String, emit: @escaping (NativeEventPayload) -> Bool,
      failed: @escaping (any Error) -> Void
    ) {
      session = TextSession(snapshot)
      self.configuration = configuration
      self.emit = emit
      self.failed = failed
      super.init()
      input.delegate = self
      input.isSecureTextEntry = secure
      input.placeholder = prompt
      input.accessibilityLabel = label
      input.font = .preferredFont(forTextStyle: .body)
      input.adjustsFontForContentSizeCategory = true
      input.borderStyle = .roundedRect
      input.returnKeyType = .done
      input.attached = { [weak self] in self?.attemptAutofocus() }
      input.changed = { [weak self] in self?.scheduleCapture() }
      input.focusChanged = { [weak self] in self?.focus($0) }
      input.acceptsInput = { [weak self] in
        guard let self, !disposed else { return false }
        return applying || acceptsEdits
      }
      input.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
      updateAvailability()
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
    func configureTraits(_ traits: TextFieldTraits) {
      guard !disposed else { return }
      if !traits.autofocus {
        autofocusPending = false
      } else if !self.traits.autofocus {
        autofocusPending = true
      }
      let changed =
        traits.keyboard != self.traits.keyboard || traits.submitLabel != self.traits.submitLabel
      self.traits = traits
      input.borderStyle = traits.appearance == .plain ? .none : .roundedRect
      switch traits.keyboard {
      case .text: input.keyboardType = .default
      case .number: input.keyboardType = .decimalPad
      case .email: input.keyboardType = .emailAddress
      case .phone: input.keyboardType = .phonePad
      case .url: input.keyboardType = .URL
      }
      switch traits.submitLabel {
      case .done: input.returnKeyType = .done
      case .next: input.returnKeyType = .next
      case .search: input.returnKeyType = .search
      case .send: input.returnKeyType = .send
      case .go: input.returnKeyType = .go
      case .continue: input.returnKeyType = .continue
      }
      if changed && input.isFirstResponder { input.reloadInputViews() }
      attemptAutofocus()
    }
    func setPresentationActive(_ active: Bool) {
      guard !disposed else { return }
      presentationActive = active
      attemptAutofocus()
    }
    private func attemptAutofocus() {
      guard !disposed, presentationActive, autofocusPending, hostEnabled, contentActive,
        configuration.enabled, input.window != nil, !input.isHidden
      else { return }
      autofocusPending = false
      if !input.becomeFirstResponder() { autofocusPending = true }
    }

    func setLabels(label: String, prompt: String) {
      guard !disposed else { return }
      input.placeholder = prompt
      input.accessibilityLabel = label
    }
    func setContentActive(_ active: Bool, retainingFocus: Bool = false) {
      guard !disposed, active != contentActive || retainingFocus != self.retainingFocus else { return }
      contentActive = active
      self.retainingFocus = retainingFocus
      updateAvailability()
    }
    var retainsEditingFocus: Bool { retainingFocus && focused && !disposed }
    private var acceptsEdits: Bool {
      !disposed && hostEnabled && (contentActive || retainsEditingFocus)
        && configuration.enabled && !configuration.readOnly
    }
    func setHostEnabled(_ enabled: Bool) {
      guard !disposed else { return }
      hostEnabled = enabled
      updateAvailability()
    }
    private func updateAvailability() {
      let enabled = hostEnabled && (contentActive || retainsEditingFocus) && configuration.enabled
      if input.isEnabled != enabled { input.isEnabled = enabled }
      let keyboard = configuration.readOnly ? readOnlyKeyboard : nil
      if input.inputView !== keyboard {
        input.inputView = keyboard
        if input.isFirstResponder { input.reloadInputViews() }
      }
      if !input.isEnabled { input.resignFirstResponder() }
      attemptAutofocus()
    }
    func dispose() {
      guard !disposed else { return }
      disposed = true
      captureTask?.cancel()
      captureTask = nil
      input.resignFirstResponder()
      input.attached = nil
      input.delegate = nil
      input.removeTarget(self, action: nil, for: .allEvents)
      input.changed = nil
      input.focusChanged = nil
      input.acceptsInput = nil
      input.isEnabled = false
      emit = { _ in false }
      failed = { _ in }
    }
    @objc private func editingChanged() { scheduleCapture() }
    private func scheduleCapture() {
      guard !disposed, !applying, captureTask == nil else { return }
      captureTask = Task { @MainActor [weak self] in
        guard let self else { return }
        captureTask = nil
        if !Task.isCancelled { capture() }
      }
    }
    private func nativeRange(_ range: UITextRange) -> NSRange {
      NSRange(
        location: input.offset(from: input.beginningOfDocument, to: range.start),
        length: input.offset(from: range.start, to: range.end))
    }
    private func textRange(_ range: NSRange) -> UITextRange? {
      guard let start = input.position(from: input.beginningOfDocument, offset: range.location),
        let end = input.position(from: start, offset: range.length)
      else { return nil }
      return input.textRange(from: start, to: end)
    }
    private func capture() {
      guard !disposed, !applying else { return }
      do {
        let text = input.text ?? ""
        let value = try TextValue(
          text: text,
          selection: input.selectedTextRange.map(nativeRange)
            ?? NSRange(location: text.utf16.count, length: 0),
          marked: input.markedTextRange.map(nativeRange))
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
      input.unmarkText()
      input.text = value.text
      if let marked = value.marked {
        input.selectedTextRange = textRange(marked)
        input.setMarkedText(
          (value.text as NSString).substring(with: marked),
          selectedRange: NSRange(
            location: value.selection.location - marked.location,
            length: value.selection.length))
      }
      input.selectedTextRange = textRange(value.selection)
    }
    private func focus(_ value: Bool) {
      guard !disposed, value != focused else { return }
      focused = value
      _ = emit(.focusChanged(value))
    }
    func textFieldDidChangeSelection(_ textField: UITextField) { scheduleCapture() }
    func textFieldDidEndEditing(_ textField: UITextField) {
      capture()
      focus(false)
    }
    func textField(
      _ textField: UITextField, shouldChangeCharactersIn range: NSRange,
      replacementString string: String
    ) -> Bool {
      guard acceptsEdits else {
        return false
      }
      let text = input.text ?? ""
      guard range.location >= 0, range.length >= 0, range.location <= text.utf16.count,
        range.length <= text.utf16.count - range.location
      else { return false }
      let next = (text as NSString).replacingCharacters(in: range, with: string)
      if next.utf8.count > configuration.maxUTF8Bytes ?? ProtocolLimits.maxStringBytes {
        _ = emit(.textLimitReached)
        return false
      }
      return true
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      guard !disposed, hostEnabled, contentActive, configuration.enabled, !configuration.readOnly,
        configuration.submitOnReturn, input.markedTextRange == nil
      else { return false }
      capture()
      _ = emit(.textSubmit(session.value.text))
      return false
    }
  }

  struct NativeTextFieldView: UIViewRepresentable {
    let controller: NativeTextFieldController
    @Environment(\.isEnabled) private var enabled
    @Environment(\.bonsaiFontFamily) private var fontFamily
    @Environment(\.bonsaiDefaults) private var defaults
    @Environment(\.controlSize) private var controlSize
    func makeUIView(context: Context) -> UITextField { controller.field }
    func updateUIView(_ view: UITextField, context: Context) {
      controller.setHostEnabled(enabled)
      view.font = defaults.bodyFont(
        family: fontFamily, legibility: context.environment.legibilityWeight,
        dynamicTypeSize: context.environment.dynamicTypeSize)
      view.adjustsFontForContentSizeCategory = true
      view.textColor = UIColor(defaults.color(defaults.defaultForeground()))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context)
      -> CGSize?
    {
      CGSize(
        width: proposal.width ?? 240,
        height: max(
          controlSize == .mini || controlSize == .small ? 0 : defaults.metric(2),
          uiView.intrinsicContentSize.height))
    }
  }
#endif
