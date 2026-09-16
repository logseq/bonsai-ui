import CBonsaiSwiftUI
import Foundation

public struct NativeOutput: Equatable, Sendable {
  public let bytes: Data
  public let presentationID: UInt64
  public let revision: UInt64
  public let status: Int32
  public let errorCode: Int32
}

public enum NativeRuntimeError: Error, Equatable {
  case startupFailed
  case disposed
  case presentationPending
  case invalidPresentation
  case invalidClock
  case incompatibleVersion
  case malformedOutput
  case nativeFailure(status: Int32, code: Int32)
}

public final class NativeRuntime: Sendable {
  // Every C call, including startup and teardown, runs on this process-wide
  // serial queue. A transaction never suspends while it owns native state.
  private static let queue = DispatchQueue(label: "org.bonsai-swiftui.runtime")

  private final class State: @unchecked Sendable {
    var handle: OpaquePointer?
    var pending: (id: UInt64, revision: UInt64)?
    var lastTime: Int64 = 0
    var draining = false

    func requireHandle() throws -> OpaquePointer {
      guard let handle else { throw NativeRuntimeError.disposed }
      return handle
    }

    func validateClock(_ time: Int64) throws {
      guard time >= lastTime else { throw NativeRuntimeError.invalidClock }
    }

    func validatePresentation(_ output: NativeOutput) throws {
      guard let pending, pending.id == output.presentationID,
        pending.revision == output.revision
      else { throw NativeRuntimeError.invalidPresentation }
    }

    func close() {
      if let handle { bs_runtime_destroy(handle) }
      handle = nil
      pending = nil
    }

    func copyOutput(
      _ output: bs_output_buffer,
      status: Int32,
      handle: OpaquePointer
    ) throws -> NativeOutput {
      defer { bs_buffer_free(handle, output.data) }
      guard output.status == status, (0...2).contains(status),
        output.length <= ProtocolLimits.maxFrameBytes,
        output.length == 0 || output.data != nil,
        output.presentation_id <= UInt64(Int64.max),
        output.revision <= UInt64(Int64.max)
      else { throw NativeRuntimeError.malformedOutput }
      let bytes = output.data.map { Data(bytes: $0, count: output.length) } ?? Data()
      return NativeOutput(
        bytes: bytes,
        presentationID: output.presentation_id,
        revision: output.revision,
        status: status,
        errorCode: output.error_code
      )
    }
  }

  private let state = State()

  private init() {}

  deinit {
    let state = state
    Self.queue.async { state.close() }
  }

  private func perform<T: Sendable>(
    _ operation: @escaping @Sendable (State) throws -> T
  ) async throws -> T {
    let state = state
    return try await withCheckedThrowingContinuation { continuation in
      Self.queue.async {
        continuation.resume(with: Result { try operation(state) })
      }
    }
  }

  public static func open(entrypoint: String, payload: Data = Data()) async throws -> NativeRuntime
  {
    let name = Data(entrypoint.utf8)
    guard !name.isEmpty, name.count <= 255, !name.contains(0),
      payload.count <= 1024 * 1024
    else { throw NativeRuntimeError.startupFailed }
    let runtime = NativeRuntime()
    try await runtime.perform { state in
      guard bs_abi_version_major() == 4, bs_abi_version_minor() == 0,
        bs_protocol_version_major() == ProtocolVersion.protocolMajor,
        bs_protocol_version_minor() == ProtocolVersion.protocolMinor
      else { throw NativeRuntimeError.incompatibleVersion }
      var config = Data([0x42, 0x53, 0x52, 0x31, 1, 0, 0, 0, 0, 0, 0, 0])
      for length in [name.count, payload.count] {
        var littleEndian = UInt32(length).littleEndian
        withUnsafeBytes(of: &littleEndian) { config.append(contentsOf: $0) }
      }
      config.append(name)
      config.append(payload)
      state.handle = config.withUnsafeBytes {
        bs_runtime_create($0.bindMemory(to: UInt8.self).baseAddress, $0.count)
      }
      guard state.handle != nil else { throw NativeRuntimeError.startupFailed }
    }
    return runtime
  }

  public func pump(monotonicNanoseconds: Int64, events: Data = Data()) async throws -> NativeOutput
  {
    try await perform { state in
      let handle = try state.requireHandle()
      guard !state.draining else { throw NativeRuntimeError.disposed }
      guard state.pending == nil else { throw NativeRuntimeError.presentationPending }
      try state.validateClock(monotonicNanoseconds)
      var output = bs_output_buffer()
      let status = events.withUnsafeBytes {
        bs_runtime_pump(
          handle, monotonicNanoseconds,
          $0.bindMemory(to: UInt8.self).baseAddress, $0.count, &output
        )
      }
      let result = try state.copyOutput(output, status: status, handle: handle)
      state.lastTime = monotonicNanoseconds
      if status == BS_STATUS_FATAL_ERROR {
        state.close()
      } else {
        guard result.presentationID > 0 else {
          state.close()
          throw NativeRuntimeError.malformedOutput
        }
        state.pending = (result.presentationID, result.revision)
      }
      return result
    }
  }

  func shutdownPump(monotonicNanoseconds: Int64, events: Data) async throws -> NativeOutput {
    try await perform { state in
      let handle = try state.requireHandle()
      try state.validateClock(monotonicNanoseconds)
      var output = bs_output_buffer()
      let status = events.withUnsafeBytes {
        bs_runtime_shutdown_pump(
          handle, monotonicNanoseconds,
          $0.bindMemory(to: UInt8.self).baseAddress, $0.count, &output)
      }
      let result = try state.copyOutput(output, status: status, handle: handle)
      guard status != BS_STATUS_FATAL_ERROR else {
        state.close()
        throw NativeRuntimeError.nativeFailure(status: status, code: result.errorCode)
      }
      guard result.presentationID == 0 else { throw NativeRuntimeError.malformedOutput }
      if status == BS_STATUS_OK {
        state.pending = nil
        state.draining = true
        state.lastTime = monotonicNanoseconds
      }
      return result
    }
  }

  public func acknowledge(_ output: NativeOutput, monotonicNanoseconds: Int64) async throws {
    try await perform { state in
      let handle = try state.requireHandle()
      try state.validatePresentation(output)
      try state.validateClock(monotonicNanoseconds)
      var nativeOutput = bs_output_buffer()
      let status = bs_runtime_presentation_succeeded(
        handle, output.presentationID, output.revision, monotonicNanoseconds, &nativeOutput
      )
      let result = try state.copyOutput(nativeOutput, status: status, handle: handle)
      guard status == BS_STATUS_OK else {
        state.close()
        throw NativeRuntimeError.nativeFailure(status: status, code: result.errorCode)
      }
      state.pending = nil
      state.lastTime = monotonicNanoseconds
    }
  }

  public func reject(_ output: NativeOutput) async throws {
    try await perform { state in
      let handle = try state.requireHandle()
      try state.validatePresentation(output)
      var nativeOutput = bs_output_buffer()
      let status = bs_runtime_presentation_rejected(
        handle, output.presentationID, output.revision,
        BS_REJECTION_FRAME_VALIDATION_FAILED, &nativeOutput
      )
      let result = try state.copyOutput(nativeOutput, status: status, handle: handle)
      guard status == BS_STATUS_OK else {
        state.close()
        throw NativeRuntimeError.nativeFailure(status: status, code: result.errorCode)
      }
      state.pending = nil
    }
  }

  public func close() async {
    let state = state
    await withCheckedContinuation { continuation in
      Self.queue.async {
        state.close()
        continuation.resume()
      }
    }
  }
}
