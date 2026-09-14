import Foundation

public enum WireError: Error, Equatable {
  case truncated
  case invalidMagic
  case incompatibleVersion
  case invalidHeader
  case invalidLength
  case invalidFrameKind
  case invalidOperation
  case invalidOrder
  case limitExceeded
}

public struct WireOperation: Equatable, Sendable {
  public let opcode: Int
  public let body: Data
}

struct WireReader {
  private let bytes: [UInt8]
  private(set) var position = 0

  init(_ data: Data) { bytes = Array(data) }

  var remaining: Int { bytes.count - position }

  mutating func data(_ count: Int) throws -> Data {
    guard count >= 0, count <= remaining else { throw WireError.truncated }
    defer { position += count }
    return Data(bytes[position..<(position + count)])
  }

  mutating func integer<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type) throws -> T {
    let count = MemoryLayout<T>.size
    guard count <= remaining else { throw WireError.truncated }
    var value: T = 0
    for offset in 0..<count {
      value |= T(bytes[position + offset]) << (offset * 8)
    }
    position += count
    return value
  }
}

public struct WireFrame: Equatable, Sendable {
  public let kind: Int
  public let epoch: UInt64
  public let baseRevision: UInt64
  public let revision: UInt64
  public let operations: [WireOperation]

  public static func decode(_ bytes: Data) throws -> WireFrame {
    guard bytes.count <= ProtocolLimits.maxFrameBytes else { throw WireError.limitExceeded }
    guard bytes.count >= ProtocolLimits.headerBytes else { throw WireError.truncated }
    var reader = WireReader(bytes)
    guard try reader.data(4) == Data("BSFR".utf8) else { throw WireError.invalidMagic }
    let major = try reader.integer(UInt16.self)
    let minor = try reader.integer(UInt16.self)
    guard major == ProtocolVersion.protocolMajor, minor == ProtocolVersion.protocolMinor
    else { throw WireError.incompatibleVersion }
    guard try reader.integer(UInt16.self) == ProtocolLimits.headerBytes
    else { throw WireError.invalidHeader }
    let kind = Int(try reader.integer(UInt8.self))
    guard kind == FrameKindId.fullSnapshot || kind == FrameKindId.incrementalFrame
    else { throw WireError.invalidFrameKind }
    guard try reader.integer(UInt8.self) == 0 else { throw WireError.invalidHeader }
    let epoch = try reader.integer(UInt64.self)
    let base = try reader.integer(UInt64.self)
    let revision = try reader.integer(UInt64.self)
    guard epoch > 0, epoch <= UInt64(Int64.max), base <= UInt64(Int64.max),
      revision > 0, revision <= UInt64(Int64.max)
    else { throw WireError.invalidHeader }
    let length = Int(try reader.integer(UInt32.self))
    let checksum = try reader.integer(UInt32.self)
    let reserved = try reader.integer(UInt32.self)
    guard checksum == 0, reserved == 0 else { throw WireError.invalidHeader }
    guard length == reader.remaining else { throw WireError.invalidLength }

    var operations: [WireOperation] = []
    var count = 0
    var began = false
    var ended = false
    while reader.remaining > 0 {
      count += 1
      guard count <= ProtocolLimits.maxOperations else { throw WireError.limitExceeded }
      let opcode = Int(try reader.integer(UInt8.self))
      let length = Int(try reader.integer(UInt32.self))
      let body = try reader.data(length)
      if opcode == OperationId.beginFrame {
        guard count == 1, !began, body.isEmpty else { throw WireError.invalidOrder }
        began = true
      } else if opcode == OperationId.endFrame {
        guard began, !ended, body.isEmpty, reader.remaining == 0
        else { throw WireError.invalidOrder }
        ended = true
      } else {
        guard began, !ended else { throw WireError.invalidOrder }
        guard OperationId.debugName(opcode) != nil else { throw WireError.invalidOperation }
        operations.append(WireOperation(opcode: opcode, body: body))
      }
    }
    guard began, ended else { throw WireError.invalidOrder }
    return WireFrame(
      kind: kind, epoch: epoch, baseRevision: base, revision: revision,
      operations: operations
    )
  }
}
