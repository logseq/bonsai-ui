import AppKit
import SwiftUI

@main struct OpacityWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Opacity Acceptance", id: "opacity-acceptance") {
      BonsaiApplicationView(entrypoint: "native-opacity", session: session)
        .padding(20).frame(minWidth: 360, minHeight: 480)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 540)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing opacity window") }
    func has(_ title: String) -> Bool {
      accessibilityElements(host).contains {
        $0.label == title || ($0.role == "AXStaticText" && $0.value == title)
      }
    }
    func settled(_ title: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(host)
        if session.ticket == nil && has(title) { return }
      }
      throw failure("Missing displayed animation result: \(title)")
    }
    func press(_ title: String) throws {
      guard
        let control = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        }), control.press()
      else { throw failure("Cannot press \(title)") }
    }
    try await settled("Completed: none")
    try await Task.sleep(for: .milliseconds(200))
    guard has("Completed: none") else { throw failure("Initial mount emitted completion") }
    let firstStart = ContinuousClock.now
    try press("Fade out")
    try await settled("Completed: 1")
    guard firstStart.duration(to: .now) >= .milliseconds(800) else {
      throw failure("Animation completed before its native duration")
    }
    try press("Restore opacity")
    try await settled("Opacity request: 2")
    try press("Fade out")
    try await settled("Completed: 1,3")
    try press("Repeat opacity target")
    try await settled("Completed: 1,3,4")
    try press("Instant opacity")
    try await settled("Completed: 1,3,4,5")
    try press("Fade out")
    try await settled("Opacity request: 6")
    try press("Remove animation")
    try await settled("Animation removed")
    try await Task.sleep(for: .milliseconds(1400))
    guard has("Completed: 1,3,4,5") else { throw failure("Removed animation completed") }
    try press("Restore animation")
    try await settled("Remove animation")
    guard let motion = session.tree.nodes.values.compactMap({ $0.opacityController }).first
    else { throw failure("Missing native opacity motion context") }
    try press("Restore opacity")
    try await settled("Opacity request: 7")
    try await Task.sleep(for: .milliseconds(200))
    guard has("Completed: 1,3,4,5") else {
      throw failure("Animation completed before the mid-flight motion change")
    }
    // Supply the same signal used by the native View's read-only OS environment.
    let reducedStart = ContinuousClock.now
    motion.setReducedMotion(true)
    try await settled("Completed: 1,3,4,5,7")
    guard reducedStart.duration(to: .now) < .milliseconds(900) else {
      throw failure("Reduced-motion signal retained the full animation")
    }
    motion.setReducedMotion(false)
    try await settleAccessibility(host)
    try press("Fade out")
    try await settled("Opacity request: 8")
    try await Task.sleep(for: .milliseconds(200))
    session.isVisible = false
    try await Task.sleep(for: .milliseconds(80))
    guard has("Completed: 1,3,4,5,7") else { throw failure("Hidden session emitted completion") }
    let restoredStart = ContinuousClock.now
    session.isVisible = true
    try await settled("Completed: 1,3,4,5,7,8")
    guard restoredStart.duration(to: .now) < .milliseconds(600) else {
      throw failure("Restoration retained the interrupted animation duration")
    }
    window.setContentSize(CGSize(width: 360, height: 540))
    try press("Restore opacity")
    try await settled("Completed: 1,3,4,5,7,8,9")
    await session.close()
    print(
      "PASS: actual Gallery opacity native completions preserve duration, interrupt, repeat, removal, reduced motion and hidden-session behavior"
    )
    fflush(stdout)
    exit(0)
  } catch {
    await session.close()
    print("FAIL: \(error)")
    fflush(stdout)
    exit(1)
  }
}

private func failure(_ text: String) -> NSError {
  NSError(domain: "OpacityWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
