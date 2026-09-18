import Foundation
import SwiftUI

struct RenderTextEditor: Equatable, Sendable {
  let snapshot: TextSnapshot
  let configuration: TextEditorConfiguration
  var autofocus = false

  static func decode(_ reader: inout WireReader) throws -> Self {
    let session = try reader.integer(UInt64.self)
    let document = try reader.integer(UInt64.self)
    let accepted = try reader.integer(UInt64.self)
    let mode = TextUpdateMode(rawValue: try reader.choice(2))!
    let text = try reader.string()
    func range(_ reader: inout WireReader) throws -> NSRange {
      let start = Int(try reader.integer(UInt32.self))
      let end = Int(try reader.integer(UInt32.self))
      guard start <= end else { throw TextSessionError.invalidRange }
      return NSRange(location: start, length: end - start)
    }
    let selection = try range(&reader)
    let marked = try reader.flag() ? range(&reader) : nil
    let value = try TextValue(text: text, selection: selection, marked: marked)
    let enabled = try reader.flag()
    let readOnly = try reader.flag()
    let submit = try reader.flag()
    let maximum = try reader.flag() ? Int(reader.integer(UInt32.self)) : nil
    return try Self(
      snapshot: TextSnapshot(
        sessionID: session, documentRevision: document,
        acceptedLocalRevision: accepted, mode: mode, value: value),
      configuration: TextEditorConfiguration(
        enabled: enabled, readOnly: readOnly,
        submitOnReturn: submit, maxUTF8Bytes: maximum))
  }
}

#if os(macOS)
  import AppKit

  struct NativeTextEditorView: NSViewRepresentable {
    let controller: NativeTextController
    var maximumLines: Int? = nil
    @Environment(\.bonsaiToolbarFocus) private var toolbarFocus
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.bonsaiFontFamily) private var fontFamily
    @Environment(\.bonsaiDefaults) private var defaults

    func makeNSView(context: Context) -> NativeControlMount { controller.attachment.makeMount() }
    func updateNSView(_ mount: NativeControlMount, context: Context) {
      mount.onMounted = toolbarFocus?.mounted
      controller.attachment.attach(mount)
      controller.setHostEnabled(isEnabled)
      controller.view.font = defaults.bodyFont(
        family: fontFamily, legibility: context.environment.legibilityWeight)
      controller.view.textColor = NSColor(defaults.color(defaults.defaultForeground()))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeControlMount, context: Context)
      -> CGSize?
    {
      if let maximumLines {
        let view = controller.view
        let font = view.font ?? NSFont.preferredFont(forTextStyle: .body)
        return composerEditorSize(
          text: view.string, font: font,
          lineHeight: NSLayoutManager().defaultLineHeight(for: font),
          horizontalInset: view.textContainerInset.width * 2
            + (view.textContainer?.lineFragmentPadding ?? 0) * 2,
          verticalInset: view.textContainerInset.height * 2, width: proposal.width ?? 320,
          maximumLines: maximumLines)
      }
      return CGSize(width: proposal.width ?? 320, height: proposal.height ?? 120)
    }

  }
#else
  import UIKit

  struct NativeTextEditorView: UIViewRepresentable {
    let controller: NativeTextController
    var maximumLines: Int? = nil
    @Environment(\.bonsaiToolbarFocus) private var toolbarFocus
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.bonsaiFontFamily) private var fontFamily
    @Environment(\.bonsaiDefaults) private var defaults

    func makeUIView(context: Context) -> NativeControlMount { controller.attachment.makeMount() }
    func updateUIView(_ mount: NativeControlMount, context: Context) {
      mount.onMounted = toolbarFocus?.mounted
      controller.attachment.attach(mount)
      let view = controller.view
      controller.setHostEnabled(isEnabled)
      view.font = defaults.bodyFont(
        family: fontFamily, legibility: context.environment.legibilityWeight,
        dynamicTypeSize: context.environment.dynamicTypeSize)
      view.adjustsFontForContentSizeCategory = true
      view.textColor = UIColor(defaults.color(defaults.defaultForeground()))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeControlMount, context: Context)
      -> CGSize?
    {
      if let maximumLines {
        let uiView = controller.view
        let font = uiView.font ?? UIFont.preferredFont(forTextStyle: .body)
        return composerEditorSize(
          text: uiView.text ?? "", font: font, lineHeight: font.lineHeight,
          horizontalInset: uiView.textContainerInset.left + uiView.textContainerInset.right + uiView
            .textContainer.lineFragmentPadding * 2,
          verticalInset: uiView.textContainerInset.top + uiView.textContainerInset.bottom,
          width: proposal.width ?? 320, maximumLines: maximumLines)
      }
      return CGSize(width: proposal.width ?? 320, height: proposal.height ?? 120)
    }
  }
#endif

@MainActor private func composerEditorSize(
  text: String, font: Any, lineHeight: CGFloat,
  horizontalInset: CGFloat, verticalInset: CGFloat, width: CGFloat, maximumLines: Int
) -> CGSize {
  let measured = text.isEmpty || text.hasSuffix("\n") ? text + " " : text
  #if os(macOS)
    let bounds = (measured as NSString).boundingRect(
      with: CGSize(width: max(1, width - horizontalInset), height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
  #else
    let bounds = (measured as NSString).boundingRect(
      with: CGSize(width: max(1, width - horizontalInset), height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
  #endif
  let lines = min(CGFloat(maximumLines), max(1, ceil(bounds.height / lineHeight)))
  return CGSize(width: width, height: ceil(lines * lineHeight + verticalInset))
}
