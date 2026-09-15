import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@Suite @MainActor struct NativeLayoutRequestsTests {
  private func request(
    _ registry: NativeLayoutRequests, _ target: NodeLayoutTarget
  ) async throws -> Task<CGRect, any Error> {
    let task = Task { try await registry.measure(target, valid: { true }) }
    for _ in 0..<100 {
      if registry.subscriptionCount == 1 { return task }
      await Task.yield()
    }
    task.cancel()
    throw HostServiceError.failed("The measurement did not subscribe")
  }

  @Test func requestsCoalesceAndNeverReuseAnEarlierObservation() async throws {
    let registry = NativeLayoutRequests()
    let target = NodeLayoutTarget(identity: RenderIdentity(epoch: 1, node: 2))
    target.attach(UUID(), registry: registry)
    #expect(registry.subscriptionCount == 0 && target.observation == nil)
    let first = try await request(registry, target)
    let observation = try #require(target.observation)
    let second = Task { try await registry.measure(target, valid: { true }) }
    // Both calls register on the main actor before delivering the observation.
    for _ in 0..<10 { await Task.yield() }
    #expect(target.observation == observation)
    #expect(registry.subscriptionCount == 1)
    let frame = CGRect(x: 12, y: 34, width: 56, height: 78)
    registry.observe([observation: frame])
    #expect(try await first.value == frame)
    #expect(try await second.value == frame)
    #expect(registry.subscriptionCount == 0 && target.observation == nil)
    let next = try await request(registry, target)
    registry.observe([observation: frame])
    #expect(registry.subscriptionCount == 1)
    let updated = CGRect(x: 21, y: 43, width: 65, height: 87)
    registry.observe([try #require(target.observation): updated])
    #expect(try await next.value == updated)
  }

  @Test func changedContentRejectsThePreviousSampleAndCancellationReleasesSubscription()
    async throws
  {
    let registry = NativeLayoutRequests()
    let target = NodeLayoutTarget(identity: RenderIdentity(epoch: 1, node: 2))
    target.attach(UUID(), registry: registry)
    let task = try await request(registry, target)
    let old = try #require(target.observation)
    target.contentChanged()
    registry.observe([old: CGRect(x: 0, y: 0, width: 100, height: 40)])
    #expect(registry.subscriptionCount == 1)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(registry.subscriptionCount == 0 && target.observation == nil)
    // A completion racing cancellation cannot resolve the continuation twice.
    registry.observe([old: .zero])
    registry.reset()
  }

  @Test(arguments: ["detach", "dispose", "reset", "replace"])
  func teardownCompletesPendingRequests(reason: String) async throws {
    let registry = NativeLayoutRequests()
    let target = NodeLayoutTarget(identity: RenderIdentity(epoch: 1, node: 2))
    target.attach(UUID(), registry: registry)
    let task = try await request(registry, target)
    let old = try #require(target.observation)
    switch reason {
    case "detach": target.detach()
    case "dispose": target.dispose()
    case "reset": registry.reset()
    default: target.attach(UUID(), registry: registry)
    }
    await #expect(throws: HostServiceError.self) { try await task.value }
    #expect(registry.subscriptionCount == 0 && target.observation == nil)
    registry.observe([old: .zero])
  }

  @Test func timeoutDiffersFromAnInvalidTargetAndReleasesItsSubscription() async throws {
    let registry = NativeLayoutRequests(timeout: .milliseconds(10))
    let target = NodeLayoutTarget(identity: RenderIdentity(epoch: 1, node: 2))
    do {
      _ = try await registry.measure(target, valid: { true })
      Issue.record("A detached target was measured")
    } catch {
      #expect(error.localizedDescription.contains("attached"))
    }
    target.attach(UUID(), registry: registry)
    do {
      _ = try await registry.measure(target, valid: { true })
      Issue.record("An unresolved measurement did not time out")
    } catch {
      #expect(error.localizedDescription.contains("timed out"))
    }
    #expect(registry.subscriptionCount == 0 && target.observation == nil)
  }

  @Test func oneCancelledWaiterDoesNotCancelTheOther() async throws {
    let registry = NativeLayoutRequests()
    let target = NodeLayoutTarget(identity: RenderIdentity(epoch: 1, node: 2))
    target.attach(UUID(), registry: registry)
    let first = try await request(registry, target)
    let second = Task { try await registry.measure(target, valid: { true }) }
    for _ in 0..<10 { await Task.yield() }
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(registry.subscriptionCount == 1)
    registry.observe([try #require(target.observation): .zero])
    #expect(try await second.value == .zero)
    #expect(registry.subscriptionCount == 0)
  }
}
