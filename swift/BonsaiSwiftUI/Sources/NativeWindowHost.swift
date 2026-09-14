import Foundation

#if os(macOS)
  import AppKit
  typealias HostPlatformWindow = NSWindow
#else
  import UIKit
  typealias HostPlatformWindow = UIWindow
#endif

/// The presentation view binds its own window; services never select a global key window.
@MainActor final class NativeWindowHost {
  let fileDialogs = NativeFileDialogs()
  let notices = NativeNotices()
  let dialogs = NativeHostDialogs()
  #if os(iOS)
    let feedbackGenerators = NativeFeedbackGenerators()
  #endif
  var allowsFeedback: (() -> Bool)?
  var hasModalContent: (() -> Bool)?
  var resolveNode: ((UInt64, Bool) -> RenderNodeState?)?
  private weak var window: HostPlatformWindow?
  private weak var owner: AnyObject?
  private var inheritedTitle: String?
  private var applicationTitle: String?
  private var requestedTitle: String?
  private var effectiveTitle: String { requestedTitle ?? applicationTitle ?? inheritedTitle ?? "" }

  func owns(_ owner: AnyObject) -> Bool { self.owner === owner && window != nil }

  func attach(window: HostPlatformWindow?, title: String?, owner: AnyObject) {
    guard let window else {
      detach(owner: owner)
      return
    }
    if self.window !== window {
      reset()
      self.window = window
      inheritedTitle = readTitle(window)
    }
    self.owner = owner
    if applicationTitle != title {
      applicationTitle = title
      requestedTitle = nil
    }
    writeTitle(effectiveTitle, to: window)
  }

  func detach(owner: AnyObject) {
    guard self.owner === owner else { return }
    reset()
  }

  func reset() {
    #if os(iOS)
      feedbackGenerators.reset()
    #endif
    fileDialogs.cancelPending()
    notices.cancelAll()
    dialogs.cancelAll()
    if let window, readTitle(window) == effectiveTitle {
      writeTitle(inheritedTitle ?? "", to: window)
    }
    window = nil
    owner = nil
    inheritedTitle = nil
    applicationTitle = nil
    requestedTitle = nil
  }

  func requireModalPresentation() throws {
    let window = try boundWindow()
    guard fileDialogs.presentation == nil, !dialogs.blocksBackgroundInput,
      hasModalContent?() != true
    else {
      throw HostServiceError.failed("Another modal presentation is already open")
    }
    #if os(macOS)
      let occupied = window.attachedSheet != nil
    #else
      let occupied = window.rootViewController?.presentedViewController != nil
    #endif
    guard !occupied else {
      throw HostServiceError.failed("The application window already presents a modal")
    }
  }

  func setTitle(_ title: String) throws {
    guard title.utf8.count <= ProtocolLimits.maxStringBytes else {
      throw HostServiceError.failed("Window title exceeds the transfer limit")
    }
    let window = try boundWindow()
    #if os(iOS)
      guard window.windowScene != nil else {
        throw HostServiceError.failed("The application window has no attached scene")
      }
    #endif
    requestedTitle = title
    writeTitle(title, to: window)
  }

  func setSize(width: Double, height: Double) throws {
    guard width.isFinite, height.isFinite, width > 0, height > 0 else {
      throw HostServiceError.failed("Window content size must be finite and positive")
    }
    let window = try boundWindow()
    #if os(macOS)
      window.setContentSize(CGSize(width: width, height: height))
    #else
      _ = window
      throw HostServiceError.failed("Window resizing is not supported on iOS")
    #endif
  }

  func close() {
    reset()
    fileDialogs.reset()
  }

  func boundWindow() throws -> HostPlatformWindow {
    guard owner != nil, let window else {
      throw HostServiceError.failed("No application window is attached")
    }
    return window
  }

  private func readTitle(_ window: HostPlatformWindow) -> String? {
    #if os(macOS)
      window.title
    #else
      window.windowScene?.title
    #endif
  }

  private func writeTitle(_ title: String, to window: HostPlatformWindow) {
    #if os(macOS)
      if window.title != title { window.title = title }
    #else
      if window.windowScene?.title != title { window.windowScene?.title = title }
    #endif
  }
}
