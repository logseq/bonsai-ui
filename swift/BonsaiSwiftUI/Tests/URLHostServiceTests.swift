import AppKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

private func urlRequest(_ text: String) throws -> HostRequest {
  let operation = TreeFixture.host(1, kind: 3, text: text)
  var reader = WireReader(operation.body)
  guard case .request(_, let request) = try HostCommand.decode(&reader) else {
    throw WireError.invalidOperation
  }
  return request
}

@MainActor private final class HeldURLService: HostService {
  private let native = NativeHostService()
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var completed = false
  func execute(_ request: HostRequest) async throws -> Data {
    completed = false
    let value = try await native.execute(request)
    completed = true
    await withCheckedContinuation { continuation = $0 }
    return value
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

@Suite(.serialized) @MainActor struct URLHostServiceTests {
  @Test func systemURLDispatchReachesARealRegisteredApplication() async throws {
    let receiver = try URLReceiverFixture()
    defer { receiver.close() }
    try await receiver.waitUntilRegistered()
    let native = NativeHostService()
    for token in ["first", "second"] {
      #expect(try await native.execute(urlRequest(receiver.url(token))) == Data())
    }
    try await receiver.waitForCount(2)
    #expect(receiver.received == [receiver.url("first"), receiver.url("second")])
  }

  @Test func invalidAndUnavailableURLsReturnErrorsWithoutLaunching() async throws {
    let native = NativeHostService()
    for value in ["", "relative/path", "https://[", "1invalid://host", "\u{0}"] {
      let request = try urlRequest(value)
      await #expect(throws: (any Error).self) { try await native.execute(request) }
    }
    let unknown = try urlRequest("bonsai-unregistered-\(UUID().uuidString.lowercased())://message")
    await #expect(throws: (any Error).self) { try await native.execute(unknown) }
  }

  @Test func cancellationBeforeDispatchPreventsLaunchAndFencesRepliesAfterNativeDelivery()
    async throws
  {
    let receiver = try URLReceiverFixture()
    defer { receiver.close() }
    try await receiver.waitUntilRegistered()
    let service = HeldURLService()
    defer { service.release() }
    let dispatcher = HostEffectDispatcher(service: service)
    var replies: [HostResponse] = []
    dispatcher.dispatch([
      .request(1, try urlRequest(receiver.url("never"))), .cancel(1),
    ]) { replies.append($0) }
    for _ in 0..<20 { await Task.yield() }
    #expect(!service.completed)
    #expect(receiver.received.isEmpty)
    #expect(replies.map(\.status) == [.cancelled])
    dispatcher.dispatch([.request(2, try urlRequest(receiver.url("delivered")))]) {
      replies.append($0)
    }
    try await receiver.waitForCount(1)
    for _ in 0..<100 where !service.completed { try await Task.sleep(for: .milliseconds(5)) }
    #expect(service.completed)
    #expect(replies.count == 1)
    dispatcher.dispatch([.cancel(2)]) { replies.append($0) }
    service.release()
    for _ in 0..<20 { await Task.yield() }
    #expect(replies.map(\.status) == [.cancelled, .cancelled])
    #expect(receiver.received == [receiver.url("delivered")])
    dispatcher.dispatch([.request(3, try urlRequest(receiver.url("closed")))]) {
      replies.append($0)
    }
    try await receiver.waitForCount(2)
    for _ in 0..<100 where !service.completed { try await Task.sleep(for: .milliseconds(5)) }
    #expect(service.completed)
    dispatcher.reset()
    service.release()
    for _ in 0..<20 { await Task.yield() }
    #expect(replies.count == 2)
  }
}

extension HostCommandTests {
  @Test func urlCommandsPreservePayloadAndRejectMalformedFramesAtomically() throws {
    let state = try FrameState().staging(
      TreeFixture.frame(TreeFixture.initial.operations + [TreeFixture.environment()]))
    let valid = TreeFixture.host(1, kind: 3, text: "custom://host/%E6%9C%AC?x=%F0%9F%98%80")
    #expect(try state.staging(TreeFixture.frame([valid], base: 1, revision: 2)).tree.revision == 2)
    var invalid = (0..<valid.body.count).map {
      WireOperation(opcode: valid.opcode, body: valid.body.prefix($0))
    }
    invalid.append(WireOperation(opcode: valid.opcode, body: valid.body + Data([0])))
    for command in invalid {
      #expect(throws: (any Error).self) {
        try state.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Partial", update: true), command], base: 1, revision: 2))
      }
      #expect(state.tree.revision == 1)
    }
  }
}
