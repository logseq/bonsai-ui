import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor struct NativeTextEditorTests {
  @Test func appKitMarkedTextSurvivesAckAndRejectsStaleCorrections() throws {
    var events: [NativeEventPayload] = []
    let controller = NativeTextController(
      snapshot: try textSnapshot("Start "),
      configuration: try TextEditorConfiguration(),
      emit: {
        events.append($0)
        return true
      },
      failed: { Issue.record("Unexpected editor failure: \($0)") })
    defer { controller.dispose() }
    let view = controller.view
    view.setMarkedText(
      "拼😀", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(view.string == "Start 拼😀")
    #expect(view.markedRange() == NSRange(location: 6, length: 3))
    let first = try #require(events.last?.textEdit)
    #expect(first.value.marked == view.markedRange() && first.localRevision == 1)
    let ack = try TextSnapshot(
      sessionID: 1, documentRevision: 2, acceptedLocalRevision: 1,
      mode: .ack, value: first.value)
    #expect(try !controller.apply(ack))
    #expect(view.hasMarkedText() && events.count == 1)
    view.setMarkedText(
      "拼😀音", selectedRange: NSRange(location: 4, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(events.last?.textEdit?.localRevision == 2)
    #expect(
      try !controller.apply(textSnapshot("Stale", document: 3, accepted: 1, mode: .correction)))
    #expect(view.string == "Start 拼😀音" && view.hasMarkedText())
    view.insertText("拼音", replacementRange: NSRange(location: NSNotFound, length: 0))
    let committed = try #require(events.last?.textEdit)
    #expect(committed.value.text == "Start 拼音" && committed.value.marked == nil)
    #expect(committed.localRevision == 3 && committed.baseDocumentRevision == 3)
    let count = events.count
    #expect(
      try controller.apply(textSnapshot("Fixed", document: 4, accepted: 3, mode: .correction)))
    #expect(view.string == "Fixed" && !view.hasMarkedText() && events.count == count)
    #expect(
      try controller.apply(
        textSnapshot(
          "中文", document: 5, accepted: 3,
          marked: NSRange(location: 0, length: 2))))
    #expect(view.markedRange() == NSRange(location: 0, length: 2))
    #expect(view.selectedRange() == NSRange(location: 2, length: 0))
    #expect(events.count == count)
  }

  @Test func nativeByteLimitReadOnlySelectionAndDisposalPreserveTheLastValidValue() throws {
    var events: [NativeEventPayload] = []
    weak var retained: NativeTextController?
    var before = 0
    let view = try autoreleasepool { () throws -> NativeEditingTextView in
      var controller: NativeTextController? = NativeTextController(
        snapshot: try textSnapshot(""),
        configuration: try TextEditorConfiguration(maxUTF8Bytes: 7),
        emit: {
          events.append($0)
          return true
        },
        failed: { Issue.record("Unexpected editor failure: \($0)") })
      let view = try #require(controller?.view)
      view.insertText("😀中", replacementRange: NSRange(location: NSNotFound, length: 0))
      #expect(events.last?.textEdit?.value.text == "😀中")
      view.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
      #expect(view.string == "😀中" && events.last == .textLimitReached)
      #expect(controller?.session.localRevision == 1)
      view.setSelectedRange(NSRange(location: 0, length: 2))
      #expect(events.last?.textEdit?.value.selection == NSRange(location: 0, length: 2))
      #expect(controller?.session.localRevision == 2)
      controller?.configure(try TextEditorConfiguration(readOnly: true, maxUTF8Bytes: 7))
      before = events.count
      view.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
      #expect(view.string == "😀中" && events.count == before)
      retained = controller
      controller?.dispose()
      controller = nil
      #expect(view.delegate == nil)
      return view
    }
    #expect(retained == nil)
    view.insertText("After disposal", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(events.count == before)
  }

  @Test func movingNativeSelectionOutsideCompositionCommitsBeforeEmitting() throws {
    var events: [NativeEventPayload] = []
    let controller = NativeTextController(
      snapshot: try textSnapshot("ab"),
      configuration: try TextEditorConfiguration(),
      emit: {
        events.append($0)
        return true
      },
      failed: { Issue.record("Native selection produced an invalid intermediate value: \($0)") })
    defer { controller.dispose() }
    controller.view.setMarkedText(
      "中", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 1, length: 0))
    #expect(controller.session.value.marked == NSRange(location: 1, length: 1))
    controller.view.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(controller.session.value.text == "a中b" && controller.session.value.marked == nil)
    #expect(controller.session.value.selection == NSRange(location: 0, length: 0))
    #expect(controller.session.localRevision == 2 && events.count == 2)
  }

  @Test func contradictoryRemoteSelectionIsRejectedBeforeNativeMutation() throws {
    let controller = NativeTextController(
      snapshot: try textSnapshot("Original"),
      configuration: try TextEditorConfiguration(),
      emit: { _ in
        Issue.record("Unexpected local event")
        return false
      },
      failed: { Issue.record("Unexpected editor failure: \($0)") })
    defer { controller.dispose() }
    #expect(throws: TextSessionError.invalidRange) {
      try TextValue(
        text: "abc", selection: NSRange(location: 2, length: 1),
        marked: NSRange(location: 1, length: 1))
    }
    #expect(controller.view.string == "Original" && controller.session.value.text == "Original")
  }

  @Test func nativeReturnSubmitsOnlyOutsideCompositionAndFocusIsReported() throws {
    var events: [NativeEventPayload] = []
    let controller = NativeTextController(
      snapshot: try textSnapshot("Draft"),
      configuration: try TextEditorConfiguration(submitOnReturn: true),
      emit: {
        events.append($0)
        return true
      },
      failed: { Issue.record("Unexpected editor failure: \($0)") })
    defer { controller.dispose() }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = controller.view
    #expect(window.makeFirstResponder(controller.view))
    #expect(events.contains(.focusChanged(true)))
    controller.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(events.last == .textSubmit("Draft"))
    let submissions = events.filter { if case .textSubmit = $0 { true } else { false } }.count
    controller.view.setMarkedText(
      "中", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    controller.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(events.filter { if case .textSubmit = $0 { true } else { false } }.count == submissions)
    #expect(window.makeFirstResponder(nil))
    #expect(events.contains(.focusChanged(false)))
    window.contentView = nil
  }
}

extension NativeEventPayload {
  var textEdit: TextEdit? { if case .textEdit(let edit) = self { edit } else { nil } }
}
