import Foundation
import Observation

struct RenderConfirmation: Equatable, Sendable {
  struct Action: Equatable, Sendable {
    let key: String
    let title: String
    let role: Int
    let enabled: Bool
    var id: Data { Data(key.utf8) }
    static func == (lhs: Self, rhs: Self) -> Bool {
      Data(lhs.key.utf8) == Data(rhs.key.utf8) && lhs.title == rhs.title
        && lhs.role == rhs.role && lhs.enabled == rhs.enabled
    }
  }
  struct Request: Equatable, Sendable {
    let token: Int64
    var title: String
    let message: String?
    let actions: [Action]
  }
  let style: Int
  var request: Request?

  static func decode(_ reader: inout WireReader) throws -> Self {
    let style = try reader.choice(1)
    let token = try reader.flag() ? Int64(bitPattern: reader.integer(UInt64.self)) : nil
    let title = try reader.string()
    let message = try reader.flag() ? reader.string() : nil
    let count = Int(try reader.integer(UInt16.self))
    guard count <= 64 else { throw TreeError.invalidProperties }
    var actions: [Action] = []
    for _ in 0..<count {
      let key = try reader.string()
      let title = try reader.string()
      let enabled = try reader.flag()
      let role = try reader.choice(2)
      actions.append(Action(key: key, title: title, role: role, enabled: enabled))
    }
    guard token != nil || (title.isEmpty && message == nil && actions.isEmpty) else {
      throw TreeError.invalidProperties
    }
    let value = Self(
      style: style,
      request: token.map {
        Request(token: $0, title: title, message: message, actions: actions)
      })
    try value.validate()
    return value
  }

  func validate() throws {
    guard (0...1).contains(style) else { throw TreeError.invalidProperties }
    guard let request else { return }
    guard request.token > 0, !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !request.actions.isEmpty, request.actions.count <= 64,
      Set(request.actions.map { Data($0.key.utf8) }).count == request.actions.count,
      request.actions.filter({ $0.role == 1 }).count <= 1,
      request.actions.allSatisfy({
        !$0.key.isEmpty && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && (0...2).contains($0.role)
      })
    else { throw TreeError.invalidProperties }
  }
}

@MainActor @Observable final class ConfirmationController {
  enum Result: Equatable, Sendable {
    case action(String)
    case dismissed
    static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
      case (.action(let lhs), .action(let rhs)): Data(lhs.utf8) == Data(rhs.utf8)
      case (.dismissed, .dismissed): true
      default: false
      }
    }
  }
  struct Response: Equatable, Sendable {
    let serial: UUID
    let token: Int64
    let handler: UInt64
    let result: Result
  }
  @MainActor final class Opening {
    let request: RenderConfirmation.Request
    let identity: UInt64
    let handler: UInt64
    fileprivate let emit: (Response) -> Bool
    fileprivate init(
      request: RenderConfirmation.Request, identity: UInt64, handler: UInt64,
      emit: @escaping (Response) -> Bool
    ) {
      self.request = request
      self.identity = identity
      self.handler = handler
      self.emit = emit
    }
  }

  private(set) var properties: RenderConfirmation
  private(set) var active = false
  private(set) var presented = false {
    didSet { if oldValue != presented { onPresentationChange?() } }
  }
  private(set) var presentationIdentity: UInt64 = 0
  private(set) var pending: Response?
  private(set) var dispatching: Response?
  @ObservationIgnored var onPresentationChange: (() -> Void)?
  private var highWater: Int64
  private var consumed: Int64?
  private(set) var current: Opening?
  private var queuedDismissal: Opening?
  private var disposed = false

  init(_ properties: RenderConfirmation) {
    self.properties = properties
    highWater = properties.request?.token ?? 0
  }

  var blocksBackground: Bool { active && properties.request != nil }
  var hasResponded: Bool { properties.request.map { consumed == $0.token } ?? false }

  func validate(_ next: RenderConfirmation) throws {
    try next.validate()
    if let token = next.request?.token, token != properties.request?.token, token <= highWater {
      throw TreeError.invalidProperties
    }
  }

  func synchronize(_ next: RenderConfirmation) {
    guard !disposed, next != properties else { return }
    properties = next
    highWater = max(highWater, next.request?.token ?? 0)
    invalidateBinding()
  }

  func setActive(_ value: Bool) {
    guard !disposed, active != value else { return }
    active = value
    invalidateBinding()
  }

  func invalidateBinding() {
    presentationIdentity += 1
    current = nil
    queuedDismissal = nil
    pending = nil
    presented = !disposed && active && properties.request != nil
  }

  func opening(handler: UInt64, emit: @escaping (Response) -> Bool) -> Opening? {
    guard !disposed, active, let request = properties.request else { return nil }
    if let current, current.handler == handler { return current }
    if current != nil { invalidateBinding() }
    let opening = Opening(
      request: request, identity: presentationIdentity, handler: handler, emit: emit)
    current = opening
    return opening
  }

  private func admits(_ opening: Opening) -> Bool {
    !disposed && active && current === opening
      && opening.identity == presentationIdentity
      && properties.request?.token == opening.request.token
  }

  func choose(_ key: String, in opening: Opening) {
    guard admits(opening), consumed != opening.request.token,
      opening.request.actions.contains(where: { Data($0.key.utf8) == Data(key.utf8) && $0.enabled })
    else { return }
    settle(.action(key), opening: opening)
  }

  func dismissed(_ opening: Opening) {
    guard admits(opening), queuedDismissal !== opening else { return }
    presented = false
    queuedDismissal = opening
    // Native button activation and the binding setter can arrive in either order
    // in one callback turn. Defer only the dismissal; a button settles immediately.
    DispatchQueue.main.async { [weak self, weak opening] in
      guard let self, let opening, self.queuedDismissal === opening, self.admits(opening) else {
        return
      }
      self.queuedDismissal = nil
      if self.consumed == opening.request.token {
        if self.pending == nil { self.restore(opening.request.token) }
      } else {
        self.settle(.dismissed, opening: opening)
      }
    }
  }

  private func settle(_ result: Result, opening: Opening) {
    guard admits(opening), consumed != opening.request.token else { return }
    consumed = opening.request.token
    queuedDismissal = nil
    let response = Response(
      serial: UUID(), token: opening.request.token, handler: opening.handler, result: result)
    pending = response
    dispatching = response
    presented = false
    let accepted = opening.emit(response)
    dispatching = nil
    if !accepted, pending == response {
      pending = nil
      restore(response.token)
    }
  }

  func resolve(_ response: Response) {
    guard pending == response else { return }
    pending = nil
    restore(response.token)
  }

  private func restore(_ token: Int64) {
    guard !disposed, active, properties.request?.token == token else { return }
    presentationIdentity += 1
    current = nil
    queuedDismissal = nil
    presented = true
  }

  func dispose() {
    disposed = true
    active = false
    invalidateBinding()
    onPresentationChange = nil
  }
}
