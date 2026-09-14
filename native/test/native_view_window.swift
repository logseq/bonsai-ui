import AppKit
import Observation
import SwiftUI

@MainActor @Observable private final class CardResource {
  var showsChild = true
}
@MainActor private final class CardLifetime {
  var created = 0
  var disposed = 0
  var retained: (() -> Bool)?
  func registry() throws -> BonsaiNativeViews {
    var registry = BonsaiNativeViews()
    try registry.register(
      kind: 1001, version: 1, capabilities: [.stateful, .resource, .semantics],
      decode: { bytes -> String in
        guard let value = String(data: bytes, encoding: .utf8) else {
          throw WireError.invalidHeader
        }
        return value
      },
      encodeEvent: { (_: Bool) in BonsaiNativeEvent(id: 1) },
      makeResource: {
        self.created += 1
        return CardResource()
      },
      dispose: { _ in self.disposed += 1 },
      content: { context in
        self.retained = { context.emit(true) }
        return CardContent(context: context)
      })
    return registry
  }
}
private struct CardContent: View {
  let context: BonsaiNativeContext<String, Bool, CardResource>
  @State private var localCount = 0
  var body: some View {
    VStack {
      Text(context.properties)
      Button("Native activation") { _ = context.emit(true) }
      Button("Local count: \(localCount)") { localCount += 1 }
      Button("Toggle native child") { context.resource.showsChild.toggle() }
      if context.resource.showsChild { ForEach(context.children) { $0 } }
    }
  }
}
@main private struct NativeViewWindowAcceptance: App {
  private let lifetime: CardLifetime
  @State private var session: BonsaiSession
  init() {
    let lifetime = CardLifetime()
    self.lifetime = lifetime
    do { _session = State(initialValue: BonsaiSession(nativeViews: try lifetime.registry())) } catch
    { fatalError("Invalid acceptance registration: \(error)") }
  }
  var body: some Scene {
    Window("Native View", id: "native-view") {
      BonsaiApplicationView(entrypoint: "native-view", session: session)
        .task { await verify(session, lifetime) }
    }.defaultSize(width: 600, height: 700)
  }
}
@MainActor private func verify(_ session: BonsaiSession, _ lifetime: CardLifetime) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing window") }
    func wait(_ title: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if accessibilityElements(window).contains(where: { $0.label == title || $0.value == title }
        ),
          session.ticket == nil
        {
          return
        }
      }
      throw failure("Missing presented content: \(title)")
    }
    func press(_ title: String) throws {
      guard
        let button = accessibilityElements(window).first(where: {
          $0.role == "AXButton" && $0.label == title
        }), button.press()
      else { throw failure("Missing actionable button: \(title)") }
    }
    try await wait("Native card: 0")
    guard lifetime.created == 1 else { throw failure("Resource was not created once") }
    try press("Native activation")
    try await wait("Native events: 1")
    try press("Native child")
    try await wait("Child events: 1")
    try press("Local count: 0")
    try await wait("Local count: 1")
    let old = lifetime.retained
    try press("Change native properties")
    try await wait("Native card: 1")
    try await wait("Local count: 1")
    guard old?() == false else { throw failure("Stale event survived property replacement") }
    try press("Toggle native card")
    for _ in 0..<100 {
      try await settleAccessibility(host)
      if lifetime.disposed == 1 && session.ticket == nil { break }
    }
    guard lifetime.disposed == 1 else { throw failure("Removed resource was not disposed") }
    try press("Toggle native card")
    try await wait("Native card: 1")
    try await wait("Local count: 0")
    guard lifetime.created == 2 else { throw failure("Reinserted view did not own a new resource") }
    await session.close()
    guard lifetime.disposed == 2 else { throw failure("Session did not dispose its resource") }
    print(
      "PASS: actual native view window dispatches OCaml events and retains SwiftUI state until removal"
    )
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}
private func failure(_ message: String) -> NSError {
  NSError(domain: "NativeViewAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
