import SwiftUI
import UIKit
import XCTest

@testable import BonsaiSwiftUI

@MainActor @Observable private final class InputStyle {
  var size: DynamicTypeSize = .large
  var bold = false
  var customFont = false
}

@MainActor final class InputDynamicTypeTests: XCTestCase {
  private func snapshot() throws -> TextSnapshot {
    try TextSnapshot(
      sessionID: 1, documentRevision: 1, acceptedLocalRevision: 0, mode: .forceReplace,
      value: TextValue(text: "Draft", selection: NSRange(location: 5, length: 0)))
  }

  func testInputsFollowInheritedSizeWithoutLosingEditingState() async throws {
    let editor = NativeTextController(
      snapshot: try snapshot(), configuration: try TextEditorConfiguration(),
      emit: { _ in true }, failed: { XCTFail("Unexpected editor failure: \($0)") })
    let plain = NativeTextFieldController(
      snapshot: try snapshot(), secure: false, configuration: try TextEditorConfiguration(),
      label: "Plain", prompt: "", emit: { _ in true },
      failed: { XCTFail("Unexpected plain field failure: \($0)") })
    let secure = NativeTextFieldController(
      snapshot: try snapshot(), secure: true, configuration: try TextEditorConfiguration(),
      label: "Secure", prompt: "", emit: { _ in true },
      failed: { XCTFail("Unexpected secure field failure: \($0)") })
    let style = InputStyle()
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let host = UIHostingController(
      rootView: InputHost(
        style: style, editor: editor, plain: plain, secure: secure))
    let window = UIWindow(windowScene: scene)
    window.rootViewController = host
    window.makeKeyAndVisible()
    editor.setPresentationActive(true)
    plain.setPresentationActive(true)
    secure.setPresentationActive(true)
    defer {
      editor.dispose()
      plain.dispose()
      secure.dispose()
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKeyAndVisible()
    }
    func settle() async throws {
      for _ in 0..<8 {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(25))
      }
    }
    try await settle()
    // A custom keyboard isolates UIKit marked-text storage from asynchronous
    // system candidate updates; actual keyboard composition is device acceptance.
    editor.view.inputView = UIView()
    XCTAssertTrue(editor.view.becomeFirstResponder())
    try await settle()
    editor.view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
    let text = editor.view.text
    let selection = editor.view.selectedRange
    let marked = try XCTUnwrap(editor.view.markedTextRange)
    let markedStart = editor.view.offset(from: editor.view.beginningOfDocument, to: marked.start)
    let markedLength = editor.view.offset(from: marked.start, to: marked.end)
    let sizes: [(DynamicTypeSize, UIContentSizeCategory)] = [
      (.large, .large), (.accessibility5, .accessibilityExtraExtraExtraLarge),
      (.small, .small), (.accessibility3, .accessibilityExtraLarge), (.large, .large),
    ]
    for customFont in [false, true] {
      style.customFont = customFont
      for (size, category) in sizes {
        for bold in [false, true] {
          style.size = size
          style.bold = bold
          try await settle()
          let traits = UITraitCollection(preferredContentSizeCategory: category)
          let expected =
            customFont
            ? UIFontMetrics(forTextStyle: .body).scaledFont(
              for: try XCTUnwrap(UIFont(name: "Courier", size: 23)), compatibleWith: traits
            ).pointSize
            : UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize
          for (name, font) in [
            ("editor", editor.view.font), ("plain", plain.field.font),
            ("secure", secure.field.font),
          ] {
            let font = try XCTUnwrap(font)
            XCTAssertEqual(
              font.pointSize, expected, accuracy: 0.01, "\(name), \(size), bold=\(bold)")
            if customFont { XCTAssertTrue(font.fontName.hasPrefix("Courier")) }
            let weight =
              (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[
                .weight] as? NSNumber
            if bold {
              XCTAssertTrue(
                try XCTUnwrap(weight).doubleValue > 0
                  || font.fontDescriptor.symbolicTraits.contains(.traitBold),
                "Bold font: \(font.fontName), \(font.fontDescriptor)")
            }
          }
          XCTAssertTrue(editor.view.isFirstResponder)
          XCTAssertEqual(editor.view.text, text)
          XCTAssertEqual(editor.view.selectedRange, selection)
          let current = try XCTUnwrap(editor.view.markedTextRange)
          XCTAssertEqual(
            editor.view.offset(from: editor.view.beginningOfDocument, to: current.start),
            markedStart)
          XCTAssertEqual(editor.view.offset(from: current.start, to: current.end), markedLength)
          XCTAssertEqual(plain.field.text, "Draft")
          XCTAssertEqual(secure.field.text, "Draft")
          XCTAssertTrue(secure.field.isSecureTextEntry)
        }
      }
    }
  }
}

@MainActor private struct InputHost: View {
  let style: InputStyle
  let editor: NativeTextController
  let plain: NativeTextFieldController
  let secure: NativeTextFieldController

  var body: some View {
    var defaults = SharedUIDefaults()
    if style.customFont { defaults.textSizes[0] = 23 }
    return VStack {
      NativeTextEditorView(controller: editor).frame(height: 200)
      NativeTextFieldView(controller: plain)
      NativeTextFieldView(controller: secure)
    }
    .environment(\.bonsaiDefaults, defaults)
    .environment(\.bonsaiFontFamily, style.customFont ? "Courier" : nil)
    .dynamicTypeSize(style.size)
    .environment(\.legibilityWeight, style.bold ? .bold : .regular)
  }
}
