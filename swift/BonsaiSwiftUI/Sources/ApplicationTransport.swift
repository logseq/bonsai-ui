import Foundation

struct ApplicationRequest: Equatable, Sendable {
  let requestID: UInt64
  let payload: Data

  static func decode(_ reader: inout WireReader) throws -> ApplicationRequest {
    let id = try reader.integer(UInt64.self)
    guard id > 0, id <= UInt64(Int64.max) else { throw WireError.invalidHeader }
    let count = Int(try reader.integer(UInt32.self))
    guard count <= ProtocolLimits.maxApplicationPayloadBytes else { throw WireError.limitExceeded }
    return ApplicationRequest(requestID: id, payload: try reader.data(count))
  }
}

public enum BonsaiApplicationError: Error, Equatable, Sendable {
  case unavailable
  case payloadTooLarge
  case handlerFailed(String)
  case cancelled
  case shutdown
  case runtimeReplaced
  case invalidResponse(String)
}

extension BonsaiApplicationError {
  var code: UInt8 {
    switch self {
    case .unavailable: 1
    case .payloadTooLarge: 2
    case .handlerFailed: 3
    case .cancelled: 4
    case .shutdown: 5
    case .runtimeReplaced: 6
    case .invalidResponse: 7
    }
  }

  var message: String {
    switch self {
    case .handlerFailed(let message), .invalidResponse(let message): message
    default: ""
    }
  }
}
