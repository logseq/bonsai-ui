import Foundation

/// Application-owned opaque requests and events for one SwiftUI host.
@MainActor public struct BonsaiApplicationBridge {
  public static let maximumPayloadBytes = ProtocolLimits.maxApplicationPayloadBytes

  let request: @MainActor (Data) async throws -> Data
  let connected: @MainActor (BonsaiApplicationEvents) -> Void
  let disconnected: @MainActor () -> Void

  /// Callbacks run on MainActor. Start native event sources in `connected`
  /// and stop them in `disconnected`. Request handlers may suspend for I/O.
  public init(
    request: @escaping @MainActor (Data) async throws -> Data,
    connected: @escaping @MainActor (BonsaiApplicationEvents) -> Void = { _ in },
    disconnected: @escaping @MainActor () -> Void = {}
  ) {
    self.request = request
    self.connected = connected
    self.disconnected = disconnected
  }
}

/// An ordered event source tied to one running OCaml application.
@MainActor public final class BonsaiApplicationEvents {
  public enum SendError: Error, Equatable, Sendable {
    case closed
    case payloadTooLarge
    case backpressure
  }

  var shutdown:
    (@MainActor (BonsaiApplicationShutdown.Configuration) throws -> BonsaiApplicationShutdown)?
  private var receive: (@MainActor (Data) throws -> Void)?

  init(receive: @escaping @MainActor (Data) throws -> Void) { self.receive = receive }

  /// Copies the payload before returning. A failed send does not consume
  /// sequence space or alter events already queued. Retry backpressure later.
  public func send(_ payload: Data) throws {
    guard let receive else { throw SendError.closed }
    guard payload.count <= ProtocolLimits.maxApplicationPayloadBytes else {
      throw SendError.payloadTooLarge
    }
    try receive(payload)
  }

  /// Starts a bounded exchange without requiring an active or presented window.
  /// Only requests explicitly selected by `accepting` enter `request`.
  public func beginShutdown(
    event: Data, timeout: Duration,
    accepting: @escaping @MainActor (Data) -> Bool,
    request: @escaping @MainActor (Data) async throws -> BonsaiApplicationShutdown.Response
  ) throws -> BonsaiApplicationShutdown {
    guard let shutdown else { throw SendError.closed }
    return try shutdown(
      .init(event: event, timeout: timeout, accepting: accepting, request: request))
  }

  func close() {
    receive = nil
    shutdown = nil
  }
}

@MainActor final class ApplicationBridgeConnection {
  private let bridge: BonsaiApplicationBridge?
  private var generation = UUID()
  private var sender: BonsaiApplicationEvents?
  private var deliver: (@MainActor (NativeEventPayload) -> Bool)?
  private var tasks: [UInt64: Task<Void, Never>] = [:]
  private var replies: [NativeEventPayload] = []

  init(bridge: BonsaiApplicationBridge?) { self.bridge = bridge }

  func connect(
    send: @escaping @MainActor (Data) throws -> Void,
    shutdown:
      @escaping @MainActor (BonsaiApplicationShutdown.Configuration) throws ->
      BonsaiApplicationShutdown,
    deliver: @escaping @MainActor (NativeEventPayload) -> Bool
  ) {
    guard sender == nil else { return }
    let sender = BonsaiApplicationEvents(receive: send)
    sender.shutdown = shutdown
    self.sender = sender
    self.deliver = deliver
    bridge?.connected(sender)
  }

  func dispatch(_ requests: [ApplicationRequest]) {
    for request in requests {
      guard let bridge, tasks.count + replies.count < 256 else {
        replies.append(.applicationRequestError(request.requestID, .unavailable))
        continue
      }
      let identity = generation
      let handler = bridge.request
      tasks[request.requestID] = Task { [weak self] in
        let response: NativeEventPayload
        do {
          try Task.checkCancellation()
          let value = try await handler(request.payload)
          try Task.checkCancellation()
          response =
            value.count <= ProtocolLimits.maxApplicationPayloadBytes
            ? .applicationResponse(request.requestID, value).owningApplicationBytes
            : .applicationRequestError(request.requestID, .payloadTooLarge)
        } catch {
          let failure: BonsaiApplicationError
          if error is CancellationError {
            failure = .cancelled
          } else if let known = error as? BonsaiApplicationError {
            failure = known.bounded
          } else {
            failure = BonsaiApplicationError.handlerFailed(error.localizedDescription).bounded
          }
          response = .applicationRequestError(request.requestID, failure)
        }
        guard let self, self.generation == identity else { return }
        self.tasks.removeValue(forKey: request.requestID)
        self.replies.append(response)
        self.drain()
      }
    }
    drain()
  }

  func drain() {
    guard let deliver else { return }
    var admitted = 0
    for reply in replies {
      guard deliver(reply) else { break }
      admitted += 1
    }
    replies.removeFirst(admitted)
  }

  func reset() {
    generation = UUID()
    let connected = sender != nil
    sender?.close()
    sender = nil
    deliver = nil
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
    replies.removeAll()
    if connected { bridge?.disconnected() }
  }
}

extension BonsaiApplicationError {
  var bounded: BonsaiApplicationError {
    func truncate(_ value: String) -> String {
      guard value.utf8.count > 4096 else { return value }
      var result = String(decoding: value.utf8.prefix(4096), as: UTF8.self)
      while result.utf8.count > 4096 { result.removeLast() }
      return result
    }
    switch self {
    case .handlerFailed(let message): return .handlerFailed(truncate(message))
    case .invalidResponse(let message): return .invalidResponse(truncate(message))
    default: return self
    }
  }
}
