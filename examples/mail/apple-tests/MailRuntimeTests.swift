import BonsaiSwiftUI
import Foundation
import XCTest

@MainActor
final class MailRuntimeTests: XCTestCase {
  func testPackagedMailStartsPresentsAndRestarts() async throws {
    for _ in 0..<2 {
      let runtime = try await NativeRuntime.open(entrypoint: "mail")
      do {
        let frame = try await runtime.pump(monotonicNanoseconds: 0)
        XCTAssertEqual(frame.status, 0)
        XCTAssertGreaterThan(frame.presentationID, 0)
        XCTAssertNotNil(frame.bytes.range(of: Data("Mara Vale".utf8)))
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

  @MainActor @Observable private final class MailTypeSettings {
    var category = DynamicTypeSize.large
    var presentsMail = true
  }

  @MainActor private struct MailTypeHost: View {
    let settings: MailTypeSettings
    var body: some View {
      if settings.presentsMail {
        BonsaiApplicationView(entrypoint: "mail")
          .dynamicTypeSize(settings.category)
          .environment(\.scenePhase, .active)
      }
    }
  }

  extension MailRuntimeTests {
    func testMailRowsGrowWithPhysicalDynamicType() async throws {
      let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
      let previous = scene.windows.first(where: \.isKeyWindow)
      let settings = MailTypeSettings()
      let host = UIHostingController(rootView: MailTypeHost(settings: settings))
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
      func attach(_ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
          window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      try await settle()
      let list = try XCTUnwrap(
        scrolls(host.view).max { $0.contentSize.height < $1.contentSize.height })
      let normal = list.contentSize.height
      XCTAssertGreaterThan(normal, 1000, "Mail did not load the inbox")
      attach("mail-normal-type")
      settings.category = .accessibility3
      try await settle()
      attach("mail-accessibility-type")
      let enlarged = list.contentSize.height
      XCTAssertGreaterThan(
        enlarged, normal + 100,
        "Visible Mail rows kept fixed heights under accessibility Dynamic Type")
      settings.category = .large
      try await settle()
      XCTAssertLessThan(
        list.contentSize.height, enlarged - 100,
        "Returning to standard text size did not invalidate measured heights")
      XCTAssertEqual(list.contentOffset.y + list.adjustedContentInset.top, 0, accuracy: 1)
      // Remove the SwiftUI tree while this test still owns the window, allowing
      // its cancelled application task to finish before the next test starts.
      settings.presentsMail = false
      try await settle()
      XCTAssertTrue(scrolls(host.view).isEmpty, "Mail remained mounted during teardown")
    }
  }
#endif
