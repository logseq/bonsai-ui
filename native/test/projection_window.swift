import AppKit
import SwiftUI

@main struct ProjectionWindowAcceptance: App {
  @State private var session = BonsaiSession()
  var body: some Scene {
    Window("Projection Acceptance", id: "projection-acceptance") {
      BonsaiApplicationView(entrypoint: "native-projection", session: session)
        .padding(30).frame(minWidth: 360, minHeight: 360)
        .task { await verify(session) }
    }.defaultSize(width: 640, height: 480)
  }
}

@MainActor private func verify(_ session: BonsaiSession) async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let host = window.contentView
    else { throw failure("Missing projection window") }
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
      throw failure("Missing displayed projection result: \(title)")
    }
    func press(_ title: String) throws {
      guard
        let element = accessibilityElements(host).first(where: {
          $0.role == "AXButton" && $0.label == title
        }),
        element.enabled, element.press()
      else { throw failure("Cannot press projected native control: \(title)") }
    }
    try await settled("Projected actions: 0")
    var actions = 0
    for width in [640.0, 360.0] {
      window.setContentSize(CGSize(width: width, height: 480))
      for mode in [1, 2, 3, 0] {
        try press("Next projection")
        try await settled("Projection mode: \(mode)")
        try press("Projected action")
        actions += 1
        try await settled("Projected actions: \(actions)")
      }
    }
    await session.close()
    print(
      "PASS: actual Gallery projection native actions retain accessible labels across affine and perspective updates at both widths"
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
  NSError(
    domain: "ProjectionWindowAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}
