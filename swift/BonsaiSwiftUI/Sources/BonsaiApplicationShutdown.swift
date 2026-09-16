import Foundation

/// A terminal, generation-bound application exchange. Cancellation also closes
/// the runtime; it never resumes an application with partially released resources.
@MainActor public final class BonsaiApplicationShutdown {
  public enum StartError: Error, Equatable { case invalidTimeout }
  public enum Outcome: Equatable, Sendable {
    case completed, timedOut, cancelled, closed
    case failed(String)
  }
  public enum Response: Sendable {
    case reply(Data)
    /// Complete only after OCaml accepts this response and native teardown finishes.
    case finish(Data)
  }

  struct Configuration {
    let event: Data
    let timeout: Duration
    let accepting: @MainActor (Data) -> Bool
    let request: @MainActor (Data) async throws -> Response
  }
  private var configuration: Configuration?
  let deadline: ContinuousClock.Instant
  var initialEvent: Data?
  var sendEvent: (@MainActor (Data) throws -> Void)?
  var stopReason: Outcome?
  private var timer: Task<Void, Never>?
  var provider: Task<Void, Never>?
  var reply: (payload: NativeEventPayload, finish: Bool)?
  var finalSequence: UInt64?
  private var outcome: Outcome?
  private var waiters: [CheckedContinuation<Outcome, Never>] = []

  init(_ configuration: Configuration) {
    self.configuration = Configuration(
      event: Data(), timeout: configuration.timeout,
      accepting: configuration.accepting, request: configuration.request)
    deadline = .now + configuration.timeout
    initialEvent = Data(Array(configuration.event))
    timer = Task { [weak self, deadline] in
      do { try await ContinuousClock().sleep(until: deadline) } catch { return }
      self?.stop(.timedOut)
    }
  }

  /// Waiting-task cancellation cancels the terminal exchange for all observers.
  public var result: Outcome {
    get async {
      await withTaskCancellationHandler {
        if let outcome { return outcome }
        return await withCheckedContinuation { waiters.append($0) }
      } onCancel: {
        Task { @MainActor [weak self] in self?.cancel() }
      }
    }
  }

  public func cancel() { stop(.cancelled) }

  /// Additional ordered lifecycle events use bounded admission. Retry backpressure.
  public func send(_ payload: Data) throws {
    if ContinuousClock.now >= deadline { stop(.timedOut) }
    guard stopReason == nil, let sendEvent else { throw BonsaiApplicationEvents.SendError.closed }
    guard payload.count <= BonsaiApplicationBridge.maximumPayloadBytes else {
      throw BonsaiApplicationEvents.SendError.payloadTooLarge
    }
    // Do not overtake the reserved initial event while the previous queue drains.
    guard initialEvent == nil else { throw BonsaiApplicationEvents.SendError.backpressure }
    try sendEvent(payload)
  }

  func stop(_ reason: Outcome) {
    guard stopReason == nil else { return }
    stopReason = reason
    sendEvent = nil
    timer?.cancel()
    timer = nil
    provider?.cancel()
    provider = nil
    reply = nil
  }

  func resolve() {
    guard outcome == nil, let stopReason else { return }
    outcome = stopReason
    initialEvent = nil
    configuration = nil
    for waiter in waiters { waiter.resume(returning: stopReason) }
    waiters.removeAll()
  }

  func dispatch(_ request: ApplicationRequest) {
    guard stopReason == nil, let configuration else { return }
    guard configuration.accepting(request.payload) else {
      reply = (.applicationRequestError(request.requestID, .shutdown), false)
      return
    }
    let handler = configuration.request
    provider = Task { [weak self] in
      let response: NativeEventPayload
      var finish = false
      do {
        try Task.checkCancellation()
        let result = try await handler(request.payload)
        try Task.checkCancellation()
        let bytes: Data
        switch result {
        case .reply(let value): bytes = value
        case .finish(let value):
          bytes = value
          finish = true
        }
        if bytes.count > BonsaiApplicationBridge.maximumPayloadBytes {
          response = .applicationRequestError(request.requestID, .payloadTooLarge)
          finish = false
        } else {
          response = .applicationResponse(request.requestID, bytes).owningApplicationBytes
        }
      } catch {
        let failure =
          (error as? BonsaiApplicationError)
          ?? (error is CancellationError ? .cancelled : .handlerFailed(error.localizedDescription))
        response = .applicationRequestError(request.requestID, failure.bounded)
      }
      guard let self, self.stopReason == nil else { return }
      self.provider = nil
      self.reply = (response, finish)
    }
  }
}
