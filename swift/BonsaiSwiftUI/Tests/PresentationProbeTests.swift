import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor
struct PresentationProbeTests {
  @Test func replacedProbeCannotHideOrAcknowledgeTheNewWindowOwner() async throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 160, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = try #require(window.contentView)
    let first = NativePresentationView(frame: root.bounds)
    let second = NativePresentationView(frame: root.bounds)
    let windowHost = NativeWindowHost()
    var visible = false
    var oldAcknowledgments = 0
    var newAcknowledgments = 0
    let ticket = PresentationTicket(session: UUID(), epoch: 1, presentation: 1, revision: 1)
    first.configure(
      ticket: nil, windowHost: windowHost, onVisibility: { visible = $0 },
      onPresented: { _ in
        oldAcknowledgments += 1
        return true
      })
    root.addSubview(first)
    window.orderFront(nil)
    for _ in 0..<50 where !visible { try await Task.sleep(for: .milliseconds(5)) }
    #expect(visible)
    first.configure(
      ticket: ticket, windowHost: windowHost, onVisibility: { visible = $0 },
      onPresented: { _ in
        oldAcknowledgments += 1
        return true
      })
    first.layoutSubtreeIfNeeded()
    second.configure(
      ticket: ticket, windowHost: windowHost, onVisibility: { visible = $0 },
      onPresented: { _ in
        newAcknowledgments += 1
        return true
      })
    root.addSubview(second)
    second.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    for _ in 0..<50 where newAcknowledgments == 0 {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(newAcknowledgments == 1)
    #expect(oldAcknowledgments == 0)
    first.removeFromSuperview()
    first.dismantle()
    try await Task.sleep(for: .milliseconds(30))
    #expect(visible)
    second.dismantle()
    #expect(!visible)
  }

  @Test func visibleWindowAcknowledgesOnlyCurrentTicketOnce() async throws {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 80, y: 80, width: 160, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let probe = NativePresentationView(frame: window.contentView!.bounds)
    var callbacks: [PresentationTicket] = []
    let first = PresentationTicket(session: UUID(), epoch: 1, presentation: 1, revision: 1)
    let second = PresentationTicket(session: first.session, epoch: 1, presentation: 2, revision: 2)
    probe.configure(
      ticket: first, onVisibility: { _ in },
      onPresented: {
        callbacks.append($0)
        return true
      })
    probe.layoutSubtreeIfNeeded()
    #expect(callbacks.isEmpty)
    window.contentView = probe
    window.orderFront(nil)
    probe.configure(
      ticket: second, onVisibility: { _ in },
      onPresented: {
        callbacks.append($0)
        return true
      })
    probe.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    for _ in 0..<50 where callbacks.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(callbacks == [second])
    probe.needsLayout = true
    probe.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    #expect(callbacks == [second])
    window.orderOut(nil)
    probe.configure(
      ticket: first, onVisibility: { _ in },
      onPresented: {
        callbacks.append($0)
        return true
      })
    probe.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    #expect(callbacks == [second])
  }
}
