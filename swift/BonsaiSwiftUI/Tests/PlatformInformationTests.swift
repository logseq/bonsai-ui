import AppKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class DelayedPlatformService: HostService {
  private let native: NativeHostService
  var hold = true
  private(set) var started = 0
  private var waits: [CheckedContinuation<Void, Never>] = []
  init(pasteboard: NSPasteboard) { native = NativeHostService(pasteboard: pasteboard) }
  func execute(_ request: HostRequest) async throws -> Data {
    started += 1
    if hold { await withCheckedContinuation { waits.append($0) } }
    try Task.checkCancellation()
    return try await native.execute(request)
  }
  func release() {
    let waiting = waits
    waits = []
    for continuation in waiting { continuation.resume() }
  }
}

@MainActor struct PlatformInformationTests {
  @Test func platformRequestReturnsActualNativeValuesAndHonorsCancellation() async throws {
    var writer = WireWriter()
    writer.integer(UInt64(1))
    writer.integer(UInt16(HostRequestId.platformInformation))
    var command = WireReader(writer.bytes)
    guard case .request(let id, let request) = try HostCommand.decode(&command) else {
      Issue.record("Platform request decoded as cancellation")
      return
    }
    #expect(id == 1 && command.remaining == 0)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Keep clipboard", forType: .string)
    let service = NativeHostService(pasteboard: pasteboard)
    for _ in 0..<2 {
      var response = WireReader(try await service.execute(request))
      #expect(try response.string() == "macos")
      #expect(try response.string() == ProcessInfo.processInfo.operatingSystemVersionString)
      #expect(try response.string() == Locale.autoupdatingCurrent.identifier)
      #expect(response.remaining == 0)
    }
    let task = Task { try await service.execute(request) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(pasteboard.string(forType: .string) == "Keep clipboard")
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualPlatformInformationWaitsForPresentationAndCannotCrossRestart()
    async throws
  {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let service = DelayedPlatformService(pasteboard: pasteboard)
    let session = BonsaiSession(hostService: service)
    session.isVisible = true
    func button() throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          node.kind == NodeKindId.button
            && node.children.contains {
              if case .text(let value) = $0.properties {
                return value.value == "Read platform information"
              }
              return false
            }
        })
    }
    func contains(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    func settle(_ condition: () -> Bool) async throws {
      for _ in 0..<100 {
        if let ticket = session.ticket { _ = try await session.presented(ticket) }
        _ = try await session.refresh()
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
      }
      Issue.record("Platform information did not settle")
    }
    let expected =
      "Platform: macos\nOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)\nLocale: \(Locale.autoupdatingCurrent.identifier)"
    do {
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try button()))
      #expect(try await session.refresh())
      #expect(service.started == 0)
      session.isActive = false
      #expect(!(try await session.presented(#require(session.ticket))))
      #expect(service.started == 0)
      session.isActive = true
      try await settle { service.started == 1 }
      #expect(!contains(expected))
      service.release()
      try await settle { contains(expected) }
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      #expect(session.activate(try button()))
      try await settle { service.started == 2 }
      await session.close()
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      service.release()
      try await settle { true }
      #expect(contains("No host request has run"))
      service.hold = false
      #expect(session.activate(try button()))
      try await settle { contains(expected) }
      #expect(service.started == 3)
      await session.close()
    } catch {
      service.release()
      await session.close()
      throw error
    }
  }
}
