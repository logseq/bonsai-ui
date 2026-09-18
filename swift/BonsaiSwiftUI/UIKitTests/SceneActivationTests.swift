import SwiftUI
import UIKit
import XCTest

@testable import BonsaiSwiftUI

@MainActor final class SceneActivationTests: XCTestCase {
  func testWindowAttachmentSynchronizesSceneAdmission() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    for _ in 0..<200 {
      if scene.activationState == .foregroundActive { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertEqual(scene.activationState, .foregroundActive)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    let session = BonsaiSession()
    let center = NotificationCenter()
    let attachment = UIKitEnvironmentAttachmentView(notificationCenter: center)
    let preferences = NativeHostEnvironment(
      viewportWidth: 390, viewportHeight: 844, devicePixelRatio: 3, textScale: 1,
      brightness: .light, platform: .ios, locale: "en-US", safeArea: .init(),
      keyboardInsets: .init(), accessibleNavigation: false, boldText: false,
      invertColors: false, disableAnimations: false, reducedMotion: false,
      highContrast: false, orientation: .portrait, pointerKinds: 15)
    attachment.configure(session: session, source: UUID(), preferences: preferences)
    window.rootViewController!.view.addSubview(attachment)
    defer {
      attachment.invalidate()
      window.isHidden = true
      window.rootViewController = nil
      previous?.makeKeyAndVisible()
    }
    XCTAssertTrue(session.isActive)
    center.post(name: UIScene.willDeactivateNotification, object: scene)
    XCTAssertFalse(session.isActive, "Input must stop synchronously when this scene deactivates")
    center.post(name: UIScene.didActivateNotification, object: NSObject())
    XCTAssertFalse(session.isActive, "An unrelated notification must not activate this session")
    center.post(name: UIScene.didActivateNotification, object: scene)
    XCTAssertTrue(session.isActive, "Input must resume before a delayed SwiftUI scenePhase update")
    attachment.removeFromSuperview()
    XCTAssertFalse(session.isActive, "A detached window must not accept input")
    center.post(name: UIScene.didActivateNotification, object: scene)
    XCTAssertFalse(session.isActive, "Detached observation must be retired")
    window.rootViewController!.view.addSubview(attachment)
    XCTAssertTrue(session.isActive, "Reattachment samples its actual scene state")
    center.post(name: UIScene.didDisconnectNotification, object: scene)
    XCTAssertFalse(session.isActive, "Disconnected scenes must not accept input")
  }
}
