import Foundation

enum TextSessionError: Error, Equatable { case invalidRange, invalidRevision, invalidLimit }
enum TextUpdateMode: Int, Equatable, Sendable { case ack, correction, forceReplace }

struct TextValue: Equatable, Sendable {
  let text: String
  let selection: NSRange
  let marked: NSRange?
  init(text: String, selection: NSRange, marked: NSRange? = nil) throws {
    let units = Array(text.utf16)
    func valid(_ range: NSRange) -> Bool {
      guard range.location >= 0, range.location <= units.count, range.length >= 0,
        range.length <= units.count - range.location
      else { return false }
      func boundary(_ position: Int) -> Bool {
        position == 0 || position == units.count
          || !(0xD800...0xDBFF).contains(units[position - 1])
          || !(0xDC00...0xDFFF).contains(units[position])
      }
      return boundary(range.location) && boundary(range.location + range.length)
    }
    guard valid(selection), marked.map(valid) ?? true else { throw TextSessionError.invalidRange }
    if let marked, marked.length > 0 {
      guard selection.location >= marked.location,
        selection.location + selection.length <= marked.location + marked.length
      else { throw TextSessionError.invalidRange }
    }
    self.text = text
    self.selection = selection
    self.marked = marked.flatMap { $0.length == 0 ? nil : $0 }
  }
  static func == (left: Self, right: Self) -> Bool {
    left.selection == right.selection && left.marked == right.marked
      && left.text.utf8.elementsEqual(right.text.utf8)
  }
}
struct TextSnapshot: Equatable, Sendable {
  let sessionID: UInt64
  let documentRevision: UInt64
  let acceptedLocalRevision: UInt64
  let mode: TextUpdateMode
  let value: TextValue
  init(
    sessionID: UInt64, documentRevision: UInt64, acceptedLocalRevision: UInt64,
    mode: TextUpdateMode, value: TextValue
  ) throws {
    guard
      [sessionID, documentRevision, acceptedLocalRevision].allSatisfy({ $0 <= UInt64(Int64.max) })
    else { throw TextSessionError.invalidRevision }
    self.sessionID = sessionID
    self.documentRevision = documentRevision
    self.acceptedLocalRevision = acceptedLocalRevision
    self.mode = mode
    self.value = value
  }
}
struct TextEdit: Equatable, Sendable {
  let sessionID: UInt64
  let localRevision: UInt64
  let baseDocumentRevision: UInt64
  let value: TextValue
}
enum TextChange: Equatable {
  case unchanged, limitReached
  case edited(TextEdit)
  var edit: TextEdit? { if case .edited(let edit) = self { edit } else { nil } }
}
struct TextSession: Equatable {
  private(set) var value: TextValue
  private(set) var sessionID: UInt64
  private(set) var documentRevision: UInt64
  private(set) var localRevision: UInt64
  private var remote: TextSnapshot
  init(_ snapshot: TextSnapshot) {
    value = snapshot.value
    sessionID = snapshot.sessionID
    documentRevision = snapshot.documentRevision
    localRevision = snapshot.acceptedLocalRevision
    remote = snapshot
  }
  mutating func apply(_ snapshot: TextSnapshot) throws -> Bool {
    if snapshot.sessionID != sessionID {
      self = TextSession(snapshot)
      return true
    }
    guard snapshot != remote, snapshot.documentRevision >= documentRevision else { return false }
    if snapshot.mode != .forceReplace && snapshot.acceptedLocalRevision > localRevision {
      throw TextSessionError.invalidRevision
    }
    remote = snapshot
    documentRevision = snapshot.documentRevision
    if snapshot.mode == .ack { return false }
    if snapshot.mode == .correction && snapshot.acceptedLocalRevision != localRevision {
      return false
    }
    if snapshot.mode == .forceReplace {
      localRevision = max(localRevision, snapshot.acceptedLocalRevision)
    }
    let changed = value != snapshot.value
    value = snapshot.value
    return changed
  }
  mutating func edit(_ value: TextValue, maxUTF8Bytes: Int? = nil) throws -> TextChange {
    let limit = maxUTF8Bytes ?? ProtocolLimits.maxStringBytes
    guard limit > 0, limit <= ProtocolLimits.maxStringBytes else {
      throw TextSessionError.invalidLimit
    }
    guard value != self.value else { return .unchanged }
    guard value.text.utf8.count <= limit else { return .limitReached }
    guard localRevision < UInt64(Int64.max) else { throw TextSessionError.invalidRevision }
    localRevision += 1
    self.value = value
    return .edited(
      TextEdit(
        sessionID: sessionID, localRevision: localRevision,
        baseDocumentRevision: documentRevision, value: value))
  }
}
