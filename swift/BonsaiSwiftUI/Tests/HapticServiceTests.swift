import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor private final class HapticScene {
  let session = BonsaiSession()
  let owner = NSObject()
  let window: NSWindow
  init() {
    initializeAccessibilityApplication()
    window = NSWindow(
      contentRect: CGRect(x: 40, y: 40, width: 400, height: 320),
      styleMask: [.titled], backing: .buffered, defer: false)
  }
  func start() async throws {
    window.orderFront(nil)
    session.windowHost.attach(window: window, title: "Haptics", owner: owner)
    session.isVisible = true
    session.isActive = true
    try await session.start(entrypoint: "native-haptic-service")
    try await acknowledge()
  }
  var status: String {
    session.tree.nodes.values.compactMap {
      if case .text(let text) = $0.properties, text.value.hasPrefix("Haptics:") {
        return text.value
      }
      return nil
    }.first ?? ""
  }
  func button(_ label: String) throws -> RenderNodeState {
    try #require(
      session.tree.nodes.values.first { node in
        guard case .button = node.properties else { return false }
        return node.children.contains {
          if case .text(let text) = $0.properties { return text.value == label }
          return false
        }
      })
  }
  func press(_ label: String) throws { #expect(session.activate(try button(label))) }
  func acknowledge() async throws {
    guard session.isVisible, session.isActive else { return }
    if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
  }
  func tick() async throws {
    try await Task.sleep(for: .milliseconds(10))
    _ = try await session.refresh()
    try await acknowledge()
  }
  func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await tick()
    }
    try #require(condition(), "Haptic result: \(status)")
  }
  func close() async {
    await session.close()
    window.orderOut(nil)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeHapticsRecheckActivityAtExecutionTime() async throws {
    let scene = HapticScene()
    do {
      try await scene.start()
      var writer = WireWriter()
      writer.integer(UInt64(1))
      writer.integer(UInt16(12))
      writer.integer(UInt8(0))
      var reader = WireReader(writer.bytes)
      guard case .request(_, let request) = try HostCommand.decode(&reader) else { return }
      let service = NativeHostService(windowHost: scene.session.windowHost)
      scene.session.isActive = false
      await #expect(throws: CancellationError.self) { _ = try await service.execute(request) }
      scene.session.isActive = true
      scene.session.isVisible = false
      await #expect(throws: CancellationError.self) { _ = try await service.execute(request) }
      scene.session.isVisible = true
      scene.window.orderOut(nil)
      await #expect(throws: CancellationError.self) { _ = try await service.execute(request) }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }

  @Test @MainActor func hapticRequestsCompleteActualOcamlAndPreserveRepeatedEffects() async throws {
    let scene = HapticScene()
    do {
      try await scene.start()
      for kind in ["light", "medium", "heavy", "selection"] {
        try scene.press(kind)
        try await scene.wait { scene.status.contains("\(kind)=ok;") }
      }
      try scene.press("burst")
      try await scene.wait { scene.status.components(separatedBy: "burst=ok;").count == 9 }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
  @Test @MainActor func hapticsWaitForPresentationActivationAndVisibility() async throws {
    let scene = HapticScene()
    do {
      try await scene.start()
      try scene.press("light")
      _ = try await scene.session.refresh()
      try await Task.sleep(for: .milliseconds(30))
      #expect(scene.status == "Haptics:")
      scene.session.isActive = false
      if let ticket = scene.session.ticket { #expect(try await !scene.session.presented(ticket)) }
      try await scene.acknowledge()
      for _ in 0..<4 { try await scene.tick() }
      #expect(scene.status == "Haptics:")
      scene.session.isVisible = false
      scene.session.isActive = true
      for _ in 0..<4 { try await scene.tick() }
      #expect(scene.status == "Haptics:")
      scene.session.isVisible = true
      try await scene.wait { scene.status == "Haptics:light=ok;" }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
  @Test @MainActor func hapticCancellationMissingWindowAndRestartResolveThroughOcaml() async throws
  {
    let scene = HapticScene()
    do {
      try await scene.start()
      try scene.press("cancel")
      try await scene.wait { scene.status == "Haptics:cancel=cancelled;" }
      scene.session.windowHost.detach(owner: scene.owner)
      try scene.press("heavy")
      try await scene.wait { scene.status.contains("heavy=error;") }
      scene.session.windowHost.attach(window: scene.window, title: "Haptics", owner: scene.owner)
      try scene.press("medium")
      _ = try await scene.session.refresh()
      let retired = try scene.button("selection")
      await scene.close()
      try await scene.start()
      #expect(!scene.session.activate(retired))
      #expect(scene.status == "Haptics:")
      try scene.press("selection")
      try await scene.wait { scene.status == "Haptics:selection=ok;" }
      await scene.close()
    } catch {
      await scene.close()
      throw error
    }
  }
}

struct HapticWireTests {
  @Test func hapticKindsValidateAtomicallyWithTheViewTransaction() throws {
    let state = try FrameState().staging(
      TreeFixture.frame(TreeFixture.initial.operations + [TreeFixture.environment()]))
    func request(_ byte: UInt8) -> WireOperation {
      TreeFixture.operation(OperationId.hostRequest) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(12))
        $0.integer(byte)
      }
    }
    for kind: UInt8 in 0...3 {
      _ = try state.staging(TreeFixture.frame([request(kind)], base: 1, revision: 2))
    }
    let valid = request(0)
    var invalid = (0..<valid.body.count).map {
      WireOperation(opcode: valid.opcode, body: valid.body.prefix($0))
    }
    invalid += [
      WireOperation(opcode: valid.opcode, body: valid.body + Data([0])), request(4), request(255),
    ]
    for operation in invalid {
      #expect(throws: (any Error).self) {
        _ = try state.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Uncommitted", update: true), operation], base: 1, revision: 2))
      }
      #expect(state.tree.revision == 1)
    }
  }
}
