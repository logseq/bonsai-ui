import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum HostResponseStatus: UInt8, Equatable, Sendable { case ok, error, cancelled }
struct HostResponse: Equatable, Sendable {
  let requestID: UInt64
  let status: HostResponseStatus
  let value: Data
}

@MainActor protocol HostService: AnyObject {
  func execute(_ request: HostRequest) async throws -> Data
}

enum HostServiceError: Error, LocalizedError {
  case failed(String)
  var errorDescription: String? {
    switch self {
    case .failed(let message): message
    }
  }
}

@MainActor final class NativeHostService: HostService {
  private let windowHost: NativeWindowHost
  #if os(macOS)
    private let pasteboard: NSPasteboard
    init(pasteboard: NSPasteboard = .general, windowHost: NativeWindowHost? = nil) {
      self.pasteboard = pasteboard
      self.windowHost = windowHost ?? NativeWindowHost()
    }
  #else
    private let pasteboard: UIPasteboard
    init(pasteboard: UIPasteboard = .general, windowHost: NativeWindowHost? = nil) {
      self.pasteboard = pasteboard
      self.windowHost = windowHost ?? NativeWindowHost()
    }
  #endif
  func execute(_ request: HostRequest) async throws -> Data {
    try Task.checkCancellation()
    switch request {
    case .pickCivil(let content):
      try windowHost.requireModalPresentation()
      return try await windowHost.dialogs.execute(.picker(content))
    case .hapticFeedback(let kind):
      try windowHost.performFeedback(kind)
      return Data()
    case .showNativeMenu(let content):
      try windowHost.requireModalPresentation()
      return try await windowHost.dialogs.execute(.menu(content))
    case .showNotice(let content):
      _ = try windowHost.boundWindow()
      return try await windowHost.notices.enqueue(content)
    case .requestFocus(let id):
      let window = try windowHost.boundWindow()
      guard let node = windowHost.resolveNode?(id, true) else {
        throw HostServiceError.failed("The focus target is not presented in active content")
      }
      if let field = node.fieldController?.field {
        guard field.window === window, field.isEnabled else {
          throw HostServiceError.failed("The text field is disabled or detached")
        }
        #if os(macOS)
          guard !field.isHiddenOrHasHiddenAncestor, window.makeFirstResponder(field) else {
            throw HostServiceError.failed("The text field refused focus")
          }
        #else
          guard !field.isHidden, field.becomeFirstResponder() else {
            throw HostServiceError.failed("The text field refused focus")
          }
        #endif
      } else if let editor = node.textController?.view {
        guard editor.window === window, editor.isSelectable else {
          throw HostServiceError.failed("The text editor is disabled or detached")
        }
        #if os(macOS)
          guard !editor.isHiddenOrHasHiddenAncestor, window.makeFirstResponder(editor) else {
            throw HostServiceError.failed("The text editor refused focus")
          }
        #else
          guard !editor.isHidden, editor.becomeFirstResponder() else {
            throw HostServiceError.failed("The text editor refused focus")
          }
        #endif
      } else {
        throw HostServiceError.failed("The target has no text input focus resource")
      }
      return Data()
    case .clearFocus:
      let window = try windowHost.boundWindow()
      #if os(macOS)
        guard window.makeFirstResponder(nil) else {
          throw HostServiceError.failed("The current input refused to release focus")
        }
      #else
        if let responder = Self.firstResponder(in: window), !responder.resignFirstResponder() {
          throw HostServiceError.failed("The current input refused to release focus")
        }
      #endif
      return Data()
    case .scrollTo(let id, let alignment, let animated):
      _ = try windowHost.boundWindow()
      guard let node = windowHost.resolveNode?(id, false), let command = node.scrollCommand else {
        throw HostServiceError.failed("The target has no presented scroll resource")
      }
      try await command.scroll(alignment: alignment, animated: animated)
      return Data()
    case .measureLayout(let id):
      _ = try windowHost.boundWindow()
      guard let node = windowHost.resolveNode?(id, false), node.layoutOwner != nil,
        let frame = node.layoutFrame, frame.width >= 0, frame.height >= 0,
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite })
      else { throw HostServiceError.failed("The target has no presented layout") }
      var response = WireWriter()
      for value in [frame.minX, frame.minY, frame.width, frame.height] {
        response.integer(Double(value).bitPattern)
      }
      return response.bytes
    case .pickFiles, .saveFile:
      try windowHost.requireModalPresentation()
      return try await windowHost.fileDialogs.execute(request)
    case .openURL(let text):
      guard text.utf8.count <= ProtocolLimits.maxStringBytes,
        let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty
      else {
        throw HostServiceError.failed("An absolute URL within the transfer limit is required")
      }
      #if os(macOS)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = false
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          NSWorkspace.shared.open(url, configuration: configuration) { application, error in
            if let error {
              continuation.resume(throwing: error)
            } else if application != nil {
              continuation.resume()
            } else {
              continuation.resume(throwing: HostServiceError.failed("Unable to open URL"))
            }
          }
        }
      #else
        guard await UIApplication.shared.open(url) else {
          throw HostServiceError.failed("Unable to open URL")
        }
      #endif
      try Task.checkCancellation()
      return Data()
    case .setWindowTitle(let title):
      try windowHost.setTitle(title)
      return Data()
    case .setWindowSize(let width, let height):
      try windowHost.setSize(width: width, height: height)
      return Data()
    case .platformInformation:
      var response = WireWriter()
      #if os(macOS)
        try response.string("macos")
      #else
        try response.string("ios")
      #endif
      try response.string(ProcessInfo.processInfo.operatingSystemVersionString)
      try response.string(Locale.autoupdatingCurrent.identifier)
      return response.bytes
    case .clipboardRead:
      #if os(macOS)
        let text = pasteboard.string(forType: .string) ?? ""
      #else
        let text = pasteboard.string ?? ""
      #endif
      let value = Data(text.utf8)
      guard value.count <= ProtocolLimits.maxStringBytes else {
        throw HostServiceError.failed("Clipboard text exceeds the transfer limit")
      }
      return value
    case .clipboardWrite(let text):
      guard text.utf8.count <= ProtocolLimits.maxStringBytes else {
        throw HostServiceError.failed("Clipboard text exceeds the transfer limit")
      }
      #if os(macOS)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
          throw HostServiceError.failed("Unable to write clipboard text")
        }
      #else
        pasteboard.string = text
      #endif
      return Data()
    }
  }

  #if os(iOS)
    private static func firstResponder(in view: UIView) -> UIView? {
      if view.isFirstResponder { return view }
      for child in view.subviews {
        if let responder = firstResponder(in: child) { return responder }
      }
      return nil
    }
  #endif
}

@MainActor final class HostEffectDispatcher {
  private struct Pending {
    let identity: UUID
    let task: Task<Void, Never>
  }
  private let service: any HostService
  private let maximumPending: Int
  private var pending: [UInt64: Pending] = [:]

  init(service: any HostService, maximumPending: Int = 256) {
    precondition(maximumPending > 0 && maximumPending <= ProtocolLimits.maxOperations)
    self.service = service
    self.maximumPending = maximumPending
  }

  func dispatch(_ commands: [HostCommand], respond: @escaping @MainActor (HostResponse) -> Void) {
    for command in commands {
      switch command {
      case .cancel(let id):
        guard let operation = pending.removeValue(forKey: id) else { continue }
        operation.task.cancel()
        respond(HostResponse(requestID: id, status: .cancelled, value: Data()))
      case .request(let id, let request):
        precondition(pending[id] == nil)
        guard pending.count < maximumPending else {
          respond(
            HostResponse(
              requestID: id, status: .error,
              value: Data("Too many outstanding host requests".utf8)))
          continue
        }
        let identity = UUID()
        let task = Task { [weak self] in
          guard let self else { return }
          let response: HostResponse
          do {
            try Task.checkCancellation()
            let value = try await service.execute(request)
            try Task.checkCancellation()
            guard value.count <= ProtocolLimits.maxStringBytes else {
              throw HostServiceError.failed("Host response exceeds the transfer limit")
            }
            response = HostResponse(requestID: id, status: .ok, value: value)
          } catch is CancellationError {
            response = HostResponse(requestID: id, status: .cancelled, value: Data())
          } catch {
            let message = Data(error.localizedDescription.utf8)
            response = HostResponse(
              requestID: id, status: .error,
              value: message.count <= ProtocolLimits.maxStringBytes
                ? message : Data("Host service failed".utf8))
          }
          guard pending[id]?.identity == identity else { return }
          pending.removeValue(forKey: id)
          respond(response)
        }
        pending[id] = Pending(identity: identity, task: task)
      }
    }
  }

  func reset() {
    for operation in pending.values { operation.task.cancel() }
    pending.removeAll()
  }
}
