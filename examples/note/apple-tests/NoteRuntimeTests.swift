import BonsaiSwiftUI
import Foundation
import XCTest

@MainActor final class NoteRuntimeTests: XCTestCase {
  func testPackagedNoteStartsPresentsAndRestarts() async throws {
    for _ in 0..<2 {
      let runtime = try await NativeRuntime.open(entrypoint: "note")
      do {
        let frame = try await runtime.pump(monotonicNanoseconds: 0)
        XCTAssertEqual(frame.status, 0)
        XCTAssertGreaterThan(frame.presentationID, 0)
        XCTAssertNotNil(frame.bytes.range(of: Data("Cornell Note Template".utf8)))
        try await runtime.acknowledge(frame, monotonicNanoseconds: 1)
        let next = try await runtime.pump(monotonicNanoseconds: 2)
        XCTAssertEqual(next.status, 0)
        try await runtime.acknowledge(next, monotonicNanoseconds: 3)
        await runtime.close()
      } catch {
        await runtime.close()
        throw error
      }
    }
  }
}

#if os(iOS)
  import SwiftUI
  import UIKit

  @MainActor @Observable private final class NoteTypeSettings {
    var category = DynamicTypeSize.large
    var mounted = true
  }

  @MainActor private struct NoteTypeHost: View {
    let settings: NoteTypeSettings
    var body: some View {
      if settings.mounted {
        BonsaiApplicationView(entrypoint: "note")
          .dynamicTypeSize(settings.category)
          .environment(\.scenePhase, .active)
          .frame(width: 320, height: 640)
      }
    }
  }

  extension NoteRuntimeTests {
    func testNarrowDocumentGrowsWithLargerText() async throws {
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
      let previous = scene.windows.first(where: \.isKeyWindow)
      let settings = NoteTypeSettings()
      let host = UIHostingController(rootView: NoteTypeHost(settings: settings))
      let window = UIWindow(windowScene: scene)
      window.rootViewController = host
      window.makeKeyAndVisible()
      defer {
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
      }
      func scrolls(_ view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
      }
      func settle() async throws {
        for _ in 0..<60 {
          window.layoutIfNeeded()
          try await Task.sleep(for: .milliseconds(25))
        }
      }
      func capture(_ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      try await settle()
      let viewport = try XCTUnwrap(
        scrolls(host.view).max { $0.contentSize.height < $1.contentSize.height })
      let normal = viewport.contentSize.height
      XCTAssertGreaterThan(normal, 640)
      XCTAssertLessThanOrEqual(viewport.contentSize.width, 321)
      capture("note-narrow-normal")
      settings.category = .accessibility2
      try await settle()
      XCTAssertGreaterThan(viewport.contentSize.height, normal + 100)
      XCTAssertLessThanOrEqual(viewport.contentSize.width, 321)
      capture("note-narrow-larger-text")
      settings.mounted = false
      try await settle()
      XCTAssertTrue(scrolls(host.view).isEmpty)
    }
  }
#endif
