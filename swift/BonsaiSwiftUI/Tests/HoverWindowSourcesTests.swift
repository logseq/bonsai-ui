import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor struct HoverWindowSourcesTests {
  private final class Source: HoverWindowSource {
    let send: @MainActor (HoverInput.Change) -> Void
    var stops = 0
    init(send: @escaping @MainActor (HoverInput.Change) -> Void) { self.send = send }
    func dispose() {
      stops += 1
      // Native teardown may synchronously deliver a final callback.
      send(
        HoverInput.Change(
          sample: HoverSample(
            id: 0, kind: .mouse,
            position: .zero, buttons: 0), present: false))
    }
  }

  @Test func sharesSourcesRetainsActiveWindowsAndFencesRetiredCallbacks() throws {
    let first = NSObject()
    let second = NSObject()
    var created: [ObjectIdentifier: [Source]] = [:]
    var received: [HoverRouter.Sample] = []
    let sources = HoverWindowSources<NSObject>(
      create: { window, send in
        let source = Source(send: send)
        created[ObjectIdentifier(window), default: []].append(source)
        return source
      }, receive: { received.append($0) })
    let a = ObjectIdentifier(first)
    let b = ObjectIdentifier(second)
    sources.replace([a: first, b: second])
    sources.replace([b: second, a: first])
    #expect(sources.count == 2)
    #expect(created[a]?.count == 1 && created[b]?.count == 1)
    let original = try #require(created[a]?.first)
    let retained = try #require(created[b]?.first)
    let change = HoverInput.Change(
      sample: HoverSample(
        id: 0, kind: .mouse,
        position: CGPoint(x: 10, y: 20), buttons: 3), present: true)
    original.send(change)
    #expect(received.count == 1 && received.first?.window == a)
    sources.replace([b: second])
    #expect(original.stops == 1 && retained.stops == 0)
    original.send(change)
    #expect(received.count == 1)
    sources.replace([a: first, b: second])
    let replacement = try #require(created[a]?.last)
    #expect(replacement !== original && created[a]?.count == 2)
    original.send(change)
    replacement.send(change)
    retained.send(change)
    #expect(received.map(\.window) == [a, a, b])
    sources.replace([:])
    sources.replace([:])
    #expect(sources.count == 0)
    #expect(original.stops == 1 && replacement.stops == 1 && retained.stops == 1)
    replacement.send(change)
    #expect(received.count == 3)
  }

  @Test func sourceDoesNotRetainItsWindowAndOwnerReleaseDisposesSources() async throws {
    var window: NSObject? = NSObject()
    weak var weakWindow = window
    var made: Source?
    var events = 0
    var sources: HoverWindowSources<NSObject>? = HoverWindowSources(
      create: { _, send in
        let source = Source(send: send)
        made = source
        return source
      }, receive: { _ in events += 1 })
    sources?.replace([ObjectIdentifier(window!): window!])
    let source = try #require(made)
    window = nil
    #expect(weakWindow == nil)
    source.send(
      HoverInput.Change(
        sample: HoverSample(
          id: 0, kind: .mouse,
          position: .zero, buttons: 0), present: true))
    #expect(events == 0)
    sources = nil
    for _ in 0..<20 where source.stops == 0 { await Task.yield() }
    #expect(source.stops == 1 && events == 0)
  }

  @Test func aReusedWindowIdentifierCannotReviveThePreviousSource() throws {
    var first: NSObject? = NSObject()
    let id = ObjectIdentifier(first!)
    var created: [Source] = []
    let sources = HoverWindowSources<NSObject>(
      create: { _, send in
        let source = Source(send: send)
        created.append(source)
        return source
      }, receive: { _ in })
    sources.replace([id: first!])
    first = nil
    // Model address reuse deterministically instead of depending on allocator behavior.
    let replacement = NSObject()
    sources.replace([id: replacement])
    #expect(created.count == 2)
    #expect(try #require(created.first).stops == 1)
    sources.replace([:])
  }
}

@MainActor struct NativeHoverHostTests {
  @Test func batchesNativeRegistrationAndReleasesTheLastWindowSource() async throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    window.contentView = root
    window.orderFront(nil)
    defer { window.close() }
    let router = HoverRouter()
    let host = NativeHoverHost(router: router)
    var controllers: [HoverRegionController] = []
    for id in 1...128 {
      let controller = HoverRegionController(
        id: RenderIdentity(epoch: 1, node: UInt64(id)),
        host: host, emit: { _ in true })
      controller.view.frame = CGRect(x: 0, y: 0, width: 100, height: 80)
      root.addSubview(controller.view)
      controller.synchronize([5: UInt64(id * 2), 6: UInt64(id * 2 + 1)])
      controller.setMounted(true)
      controller.setCollecting(true)
      controllers.append(controller)
    }
    defer {
      for controller in controllers { controller.dispose() }
    }
    #expect(host.activeWindowCount == 0)
    for _ in 0..<20 where host.activeWindowCount != 1 { await Task.yield() }
    #expect(host.activeWindowCount == 1)
    for controller in controllers.dropLast() { controller.dispose() }
    await Task.yield()
    #expect(host.activeWindowCount == 1)
    controllers.last?.setCollecting(false)
    for _ in 0..<20 where host.activeWindowCount != 0 { await Task.yield() }
    #expect(host.activeWindowCount == 0)
    controllers.last?.setCollecting(true)
    for _ in 0..<20 where host.activeWindowCount != 1 { await Task.yield() }
    #expect(host.activeWindowCount == 1)
    controllers.last?.dispose()
    for _ in 0..<20 where host.activeWindowCount != 0 { await Task.yield() }
    #expect(host.activeWindowCount == 0)
  }
}
