import BonsaiSwiftUI
import Foundation
import XCTest

#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor @Observable private final class EditorPresentation {
    var isPresented = true
  }

  @MainActor private struct EditorHost: View {
    let presentation: EditorPresentation

    var body: some View {
      if presentation.isPresented {
        BonsaiApplicationView(entrypoint: "text_input")
          .environment(\.scenePhase, .active)
      }
    }
  }

  @MainActor final class TextInputRuntimeTests: XCTestCase {
    func testPhysicalUIKitCompositionSelectionAndRemount() async throws {
      XCTAssertEqual(Bundle.main.developmentLocalization, "en")
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
      let previous = scene.windows.first(where: \.isKeyWindow)
      let presentation = EditorPresentation()
      let host = UIHostingController(rootView: EditorHost(presentation: presentation))
      let window = UIWindow(windowScene: scene)
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer {
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
      }

      func editors(_ view: UIView) -> [UITextView] {
        (view as? UITextView).map { [$0] } ?? view.subviews.flatMap(editors)
      }
      func settle() async throws {
        for _ in 0..<40 {
          window.layoutIfNeeded()
          try await Task.sleep(for: .milliseconds(25))
        }
      }
      func attach(_ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
      }

      try await settle()
      let editor = try XCTUnwrap(editors(host.view).first)
      XCTAssertEqual(editor.text, "Type here")
      XCTAssertTrue(editor.becomeFirstResponder())
      editor.selectedRange = NSRange(location: 0, length: editor.text.utf16.count)
      editor.insertText("A😀e\u{301}")
      try await settle()
      XCTAssertEqual(Array(editor.text.utf8), Array("A😀e\u{301}".utf8))
      XCTAssertEqual(editor.selectedRange, NSRange(location: 5, length: 0))

      editor.setMarkedText("拼😀", selectedRange: NSRange(location: 3, length: 0))
      try await settle()
      XCTAssertTrue(editors(host.view).first === editor)
      XCTAssertEqual(Array(editor.text.utf8), Array("A😀e\u{301}拼😀".utf8))
      var marked = try XCTUnwrap(editor.markedTextRange)
      XCTAssertEqual(editor.offset(from: editor.beginningOfDocument, to: marked.start), 5)
      XCTAssertEqual(editor.offset(from: marked.start, to: marked.end), 3)
      XCTAssertEqual(editor.selectedRange, NSRange(location: 8, length: 0))

      editor.setMarkedText("拼😀音", selectedRange: NSRange(location: 4, length: 0))
      try await settle()
      marked = try XCTUnwrap(editor.markedTextRange)
      XCTAssertEqual(editor.offset(from: marked.start, to: marked.end), 4)
      XCTAssertEqual(editor.selectedRange, NSRange(location: 9, length: 0))
      attach("text-input-composition")

      editor.insertText("拼音")
      try await settle()
      XCTAssertNil(editor.markedTextRange)
      XCTAssertEqual(Array(editor.text.utf8), Array("A😀e\u{301}拼音".utf8))
      editor.selectedRange = NSRange(location: 1, length: 2)
      editor.insertText("中")
      try await settle()
      XCTAssertEqual(Array(editor.text.utf8), Array("A中e\u{301}拼音".utf8))
      XCTAssertEqual(editor.selectedRange, NSRange(location: 2, length: 0))
      XCTAssertTrue(editor.isFirstResponder)
      attach("text-input-committed")

      XCTAssertTrue(editor.resignFirstResponder())
      presentation.isPresented = false
      try await settle()
      XCTAssertTrue(editors(host.view).isEmpty)
      presentation.isPresented = true
      try await settle()
      let replacement = try XCTUnwrap(editors(host.view).first)
      XCTAssertFalse(replacement === editor)
      XCTAssertEqual(replacement.text, "Type here")
      presentation.isPresented = false
      try await settle()
      XCTAssertTrue(editors(host.view).isEmpty)
    }
  }
#endif
