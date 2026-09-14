import Foundation
import Testing

@testable import BonsaiSwiftUI

func textValue(_ text: String, caret: Int? = nil, marked: NSRange? = nil) throws -> TextValue {
  try TextValue(
    text: text, selection: NSRange(location: caret ?? text.utf16.count, length: 0), marked: marked)
}
func textSnapshot(
  _ text: String, session: UInt64 = 1, document: UInt64 = 1,
  accepted: UInt64 = 0, mode: TextUpdateMode = .forceReplace,
  marked: NSRange? = nil
) throws -> TextSnapshot {
  try TextSnapshot(
    sessionID: session, documentRevision: document, acceptedLocalRevision: accepted,
    mode: mode, value: textValue(text, marked: marked))
}

struct TextSessionTests {
  @Test func utf16RangesRespectScalarsWithoutNormalizingText() throws {
    let value = try TextValue(
      text: "A😀中é", selection: NSRange(location: 1, length: 2),
      marked: NSRange(location: 0, length: 6))
    #expect(value.selection == NSRange(location: 1, length: 2))
    for range in [
      NSRange(location: 2, length: 0), NSRange(location: 0, length: 7),
      NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: Int.max),
    ] {
      #expect(throws: TextSessionError.invalidRange) {
        try TextValue(text: value.text, selection: range)
      }
    }
    for selection in [NSRange(location: 0, length: 0), NSRange(location: 2, length: 1)] {
      #expect(throws: TextSessionError.invalidRange) {
        try TextValue(text: "abc", selection: selection, marked: NSRange(location: 1, length: 1))
      }
    }
    #expect(try textValue("abc", marked: NSRange(location: 1, length: 0)).marked == nil)
    #expect(try textValue("é", caret: 0) != textValue("é", caret: 0))
    #expect(
      try textValue("a\u{0323}\u{0301}", caret: 0) != textValue("a\u{0301}\u{0323}", caret: 0))
  }

  @Test func acknowledgmentsAndStaleCorrectionsPreserveLocalMarkedText() throws {
    var session = TextSession(try textSnapshot("拼"))
    let first = try textValue("拼😀", marked: NSRange(location: 0, length: 3))
    let second = try textValue("拼😀音", marked: NSRange(location: 0, length: 4))
    let edit1 = try #require(session.edit(first).edit)
    let edit2 = try #require(session.edit(second).edit)
    #expect(edit1.localRevision == 1 && edit2.localRevision == 2)
    #expect(edit1.baseDocumentRevision == 1 && edit2.baseDocumentRevision == 1)
    #expect(try !session.apply(textSnapshot("拼😀", document: 2, accepted: 1, mode: .ack)))
    #expect(session.value == second)
    #expect(
      try !session.apply(textSnapshot("Correction", document: 3, accepted: 1, mode: .correction)))
    #expect(session.value == second && session.documentRevision == 3)
    #expect(
      try session.apply(textSnapshot("Corrected", document: 4, accepted: 2, mode: .correction)))
    #expect(session.value.marked == nil && session.value.text == "Corrected")
    let edit3 = try #require(session.edit(textValue("Corrected!")).edit)
    #expect(edit3.baseDocumentRevision == 4 && edit3.localRevision == 3)
  }

  @Test func repeatedAndOldForceUpdatesCannotRollbackLaterTyping() throws {
    let initial = try textSnapshot("Initial")
    var session = TextSession(initial)
    _ = try session.edit(textValue("Typed"))
    #expect(try !session.apply(initial))
    #expect(session.value.text == "Typed")
    #expect(try session.apply(textSnapshot("Reset", document: 2)))
    #expect(session.localRevision == 1)
    let edit = try #require(session.edit(textValue("Reset+typed")).edit)
    #expect(edit.localRevision == 2)
    #expect(try !session.apply(initial))
    #expect(session.value.text == "Reset+typed")
    #expect(try session.apply(textSnapshot("New session", session: 2, document: 0)))
    #expect(session.sessionID == 2 && session.localRevision == 0 && session.documentRevision == 0)
  }

  @Test func aNewSessionRequiresNativeResetEvenWhenItsTextIsIdentical() throws {
    var session = TextSession(try textSnapshot("Same"))
    #expect(try session.apply(textSnapshot("Same", session: 2)))
    #expect(session.sessionID == 2 && session.localRevision == 0)
  }

  @Test func byteLimitAndDuplicateNotificationsDoNotConsumeRevisions() throws {
    var session = TextSession(try textSnapshot(""))
    let accepted = try textValue("😀中", marked: NSRange(location: 0, length: 3))
    #expect(try session.edit(accepted, maxUTF8Bytes: 7).edit?.localRevision == 1)
    #expect(try session.edit(textValue("😀中a"), maxUTF8Bytes: 7) == .limitReached)
    #expect(session.value == accepted && session.localRevision == 1)
    #expect(try session.edit(accepted, maxUTF8Bytes: 7) == .unchanged)
    #expect(try session.edit(textValue("😀中", caret: 0), maxUTF8Bytes: 7).edit?.localRevision == 2)
  }

  @Test func invalidAcknowledgmentsAndExhaustedCountersDoNotMutateSession() throws {
    var session = TextSession(try textSnapshot("Value"))
    let snapshot = session
    for mode in [TextUpdateMode.ack, .correction] {
      #expect(throws: TextSessionError.invalidRevision) {
        try session.apply(textSnapshot("Future", document: 2, accepted: 1, mode: mode))
      }
      #expect(session == snapshot)
    }
    #expect(throws: TextSessionError.invalidRevision) {
      try textSnapshot("Bad", session: UInt64.max)
    }
    var exhausted = TextSession(try textSnapshot("Last", accepted: UInt64(Int64.max)))
    #expect(throws: TextSessionError.invalidRevision) { try exhausted.edit(textValue("Overflow")) }
    #expect(exhausted.value.text == "Last")
  }
}
