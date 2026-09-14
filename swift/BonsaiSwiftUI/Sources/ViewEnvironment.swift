import Foundation

struct ViewEnvironment: Equatable, Sendable {
  var mode: Int = 0
  var tint: UInt32?
  var fontFamily: String?
  var controlSize: Int = 2

  static func decode(_ reader: inout WireReader) throws -> ViewEnvironment {
    let mode = try reader.choice(2)
    let tint = try reader.flag() ? reader.integer(UInt32.self) : nil
    let font = try reader.flag() ? reader.string() : nil
    if let font {
      guard !font.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !font.contains("\0")
      else { throw TreeError.invalidProperties }
    }
    let size = try reader.choice(4)
    return ViewEnvironment(mode: mode, tint: tint, fontFamily: font, controlSize: size)
  }
}

struct ApplicationMetadata: Equatable, Sendable {
  let title: String?
  let environment: ViewEnvironment
}

struct FrameState: Equatable, Sendable {
  var tree = NodeStore()
  var application: ApplicationMetadata?
  var statistics: RuntimeStatistics?
  var hostCommands: [HostCommand] = []
  var applicationRequests: [ApplicationRequest] = []
  var applicationRequestHighWater: UInt64 = 0
  var hostRequestHighWater: UInt64 = 0

  func staging(_ frame: WireFrame) throws -> FrameState {
    let transaction = try tree.staging(frame)
    var metadata = frame.kind == FrameKindId.fullSnapshot ? nil : application
    var statistics: RuntimeStatistics?
    var sawMetadata = false
    // OCaml allocates increasing request IDs. Retain the accepted high-water
    // mark across same-epoch resyncs without keeping an unbounded seen-ID set.
    let previousHostID = tree.epoch == frame.epoch ? hostRequestHighWater : 0
    var nextHostID = previousHostID
    var newHostIDs = Set<UInt64>()
    var hostCommands: [HostCommand] = []
    let previousApplicationID = tree.epoch == frame.epoch ? applicationRequestHighWater : 0
    var nextApplicationID = previousApplicationID
    var applicationIDs = Set<UInt64>()
    var applicationRequests: [ApplicationRequest] = []
    for operation in transaction.ancillaryOperations {
      var reader = WireReader(operation.body)
      switch operation.opcode {
      case OperationId.setApplicationTheme:
        guard !sawMetadata else { throw WireError.invalidOperation }
        sawMetadata = true
        let title = try reader.flag() ? reader.string() : nil
        metadata = ApplicationMetadata(
          title: title, environment: try ViewEnvironment.decode(&reader))
      case OperationId.hostRequest:
        let command = try HostCommand.decode(&reader)
        if case .request(let id, _) = command {
          guard id > previousHostID, newHostIDs.insert(id).inserted else {
            throw WireError.invalidOperation
          }
          nextHostID = max(nextHostID, id)
        }
        hostCommands.append(command)
      case OperationId.applicationRequest:
        let request = try ApplicationRequest.decode(&reader)
        guard request.requestID > previousApplicationID,
          applicationIDs.insert(request.requestID).inserted
        else { throw WireError.invalidOperation }
        nextApplicationID = max(nextApplicationID, request.requestID)
        applicationRequests.append(request)
      case OperationId.runtimeNotification:
        guard statistics == nil else { throw WireError.invalidOperation }
        statistics = try RuntimeStatistics.decode(&reader)
      default:
        // Host services must be decoded and staged before they can join a
        // committed transaction. An unsupported request is never discarded.
        throw WireError.invalidOperation
      }
      guard reader.remaining == 0 else { throw WireError.invalidLength }
    }
    guard let metadata else { throw WireError.invalidOperation }
    return FrameState(
      tree: transaction.tree, application: metadata, statistics: statistics,
      hostCommands: hostCommands, applicationRequests: applicationRequests,
      applicationRequestHighWater: nextApplicationID, hostRequestHighWater: nextHostID)
  }
}

struct RuntimeStatistics: Equatable, Sendable {
  let eventCount: UInt32
  let flushNanoseconds: UInt64
  let readNanoseconds: UInt64
  let reconcileNanoseconds: UInt64
  let encodeNanoseconds: UInt64
  let patchCount: UInt32
  let patchBytes: UInt32
  let lifecycleNanoseconds: UInt64
  let fullSnapshots: UInt32
  let resyncs: UInt32

  static func decode(_ reader: inout WireReader) throws -> RuntimeStatistics {
    let events = try reader.integer(UInt32.self)
    var durations: [UInt64] = []
    for _ in 0..<4 { durations.append(try reader.integer(UInt64.self)) }
    let patches = try reader.integer(UInt32.self)
    let bytes = try reader.integer(UInt32.self)
    let lifecycle = try reader.integer(UInt64.self)
    let snapshots = try reader.integer(UInt32.self)
    let resyncs = try reader.integer(UInt32.self)
    guard events <= ProtocolLimits.maxOperations, patches <= ProtocolLimits.maxOperations,
      bytes <= ProtocolLimits.maxFrameBytes, lifecycle <= UInt64(Int64.max),
      durations.allSatisfy({ $0 <= UInt64(Int64.max) })
    else { throw WireError.limitExceeded }
    return RuntimeStatistics(
      eventCount: events, flushNanoseconds: durations[0],
      readNanoseconds: durations[1], reconcileNanoseconds: durations[2],
      encodeNanoseconds: durations[3], patchCount: patches, patchBytes: bytes,
      lifecycleNanoseconds: lifecycle, fullSnapshots: snapshots, resyncs: resyncs)
  }
}
