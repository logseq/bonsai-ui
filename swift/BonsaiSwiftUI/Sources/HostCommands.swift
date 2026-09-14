import Foundation

enum HostRequest: Equatable, Sendable {
  case pickCivil(HostPickerContent)
  case hapticFeedback(NativeHapticKind)
  case showNativeMenu(HostMenuContent)
  case showNotice(NoticeContent)
  case platformInformation
  case clipboardRead
  case clipboardWrite(String)
  case openURL(String)
  case pickFiles(allowedExtensions: [String], allowMultiple: Bool)
  case saveFile(suggestedName: String?, data: Data)
  case requestFocus(UInt64)
  case clearFocus
  case measureLayout(UInt64)
  case scrollTo(node: UInt64, alignment: Double, animated: Bool)
  case setWindowTitle(String)
  case setWindowSize(width: Double, height: Double)
}

enum HostCommand: Equatable, Sendable {
  case request(UInt64, HostRequest)
  case cancel(UInt64)

  static func decode(_ reader: inout WireReader) throws -> Self {
    let id = try reader.identity()
    let kind = Int(try reader.integer(UInt16.self))
    switch kind {
    case 0: return .cancel(id)
    case HostRequestId.pickDate, HostRequestId.pickDateRange, HostRequestId.pickTime:
      // Read the kind once, then validate the entire civil domain before presentation.
      return .request(id, .pickCivil(try HostPickerContent.decode(kind: kind, reader: &reader)))
    case HostRequestId.hapticFeedback:
      guard let kind = NativeHapticKind(rawValue: try reader.integer(UInt8.self)) else {
        throw WireError.invalidOperation
      }
      return .request(id, .hapticFeedback(kind))
    case HostRequestId.showNativeMenu:
      let count = Int(try reader.integer(UInt16.self))
      guard count > 0, count <= 1024 else { throw WireError.invalidOperation }
      var items: [HostMenuItem] = []
      for _ in 0..<count {
        items.append(
          HostMenuItem(
            id: try reader.string(), label: try reader.string(), enabled: try reader.flag()))
      }
      return .request(id, .showNativeMenu(try HostMenuContent(items: items)))
    case HostRequestId.showNotice:
      let message = try reader.string()
      let action = try reader.flag() ? reader.string() : nil
      return .request(
        id,
        .showNotice(
          try NoticeContent(
            message: message, actionLabel: action,
            durationMilliseconds: reader.integer(UInt32.self))))
    case HostRequestId.platformInformation: return .request(id, .platformInformation)
    case HostRequestId.clipboardRead: return .request(id, .clipboardRead)
    case HostRequestId.clipboardWrite: return .request(id, .clipboardWrite(try reader.string()))
    case HostRequestId.openUrl: return .request(id, .openURL(try reader.string()))
    case HostRequestId.requestFocus: return .request(id, .requestFocus(try reader.identity()))
    case HostRequestId.clearFocus: return .request(id, .clearFocus)
    case HostRequestId.scrollTo:
      return .request(
        id,
        .scrollTo(
          node: try reader.identity(),
          alignment: try reader.finiteDouble(), animated: try reader.flag()))
    case HostRequestId.measureLayout: return .request(id, .measureLayout(try reader.identity()))
    case HostRequestId.pickFiles:
      let count = Int(try reader.integer(UInt16.self))
      var extensions: [String] = []
      for _ in 0..<count { extensions.append(try reader.string()) }
      return .request(
        id, .pickFiles(allowedExtensions: extensions, allowMultiple: try reader.flag()))
    case HostRequestId.saveFile:
      let name = try reader.flag() ? reader.string() : nil
      let count = Int(try reader.integer(UInt32.self))
      guard count <= ProtocolLimits.maxFrameBytes else { throw WireError.limitExceeded }
      return .request(id, .saveFile(suggestedName: name, data: try reader.data(count)))
    case HostRequestId.setWindowTitle: return .request(id, .setWindowTitle(try reader.string()))
    case HostRequestId.setWindowSize:
      let width = try reader.finiteDouble()
      let height = try reader.finiteDouble()
      guard width > 0, height > 0 else { throw WireError.invalidOperation }
      return .request(id, .setWindowSize(width: width, height: height))
    default: throw WireError.invalidOperation
    }
  }
}
