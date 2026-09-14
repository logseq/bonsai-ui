import AppKit
import ApplicationServices

// SwiftUI virtual nodes implement the public accessibility selectors without
// declaring NSAccessibilityProtocol conformance. Query those selectors directly.
@MainActor struct AccessibilityElement {
  let object: NSObject
  private func attribute(_ name: String) -> Any? {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector) else { return nil }
    return object.perform(selector)?.takeUnretainedValue()
  }
  private func boolean(_ name: String) -> Bool {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector) else { return false }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
    let implementation = unsafeBitCast(object.method(for: selector), to: Getter.self)
    return implementation(object, selector)
  }
  var identifier: String? { attribute("accessibilityIdentifier") as? String }
  var label: String? {
    attribute("accessibilityLabel") as? String ?? attribute("accessibilityTitle") as? String
  }
  var help: String? { attribute("accessibilityHelp") as? String }
  var value: String? { attribute("accessibilityValue") as? String }
  var role: String? { attribute("accessibilityRole") as? String }
  var valueDescription: String? { attribute("accessibilityValueDescription") as? String }
  var numericValue: Double? { (attribute("accessibilityValue") as? NSNumber)?.doubleValue }
  var minimum: Double? { (attribute("accessibilityMinValue") as? NSNumber)?.doubleValue }
  var maximum: Double? { (attribute("accessibilityMaxValue") as? NSNumber)?.doubleValue }
  var enabled: Bool { boolean("isAccessibilityEnabled") }
  var selected: Bool { boolean("isAccessibilitySelected") }
  var children: [NSObject] { attribute("accessibilityChildren") as? [NSObject] ?? [] }
  var actions: [NSAccessibilityCustomAction] {
    attribute("accessibilityCustomActions") as? [NSAccessibilityCustomAction] ?? []
  }
  func increment() -> Bool { boolean("accessibilityPerformIncrement") }
  func decrement() -> Bool { boolean("accessibilityPerformDecrement") }
  func press() -> Bool { boolean("accessibilityPerformPress") }
}

@MainActor private var accessibilityApplicationReady = false
@MainActor func initializeAccessibilityApplication() {
  guard !accessibilityApplicationReady else { return }
  accessibilityApplicationReady = true
  NSApplication.shared.setActivationPolicy(.accessory)
  NSApplication.shared.finishLaunching()
}

@MainActor func accessibilityElements(_ root: NSObject) -> [AccessibilityElement] {
  var result: [AccessibilityElement] = []
  var pending = [root]
  var visited = Set<ObjectIdentifier>()
  while let object = pending.popLast() {
    guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
    let element = AccessibilityElement(object: object)
    result.append(element)
    pending.append(contentsOf: element.children)
  }
  return result
}

@MainActor func settleAccessibility(_ host: NSView) async throws {
  // A request to the application enables SwiftUI accessibility materialization.
  let pid = ProcessInfo.processInfo.processIdentifier
  _ = await Task.detached {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(
      AXUIElementCreateApplication(pid), kAXRoleAttribute as CFString, &value
    ).rawValue
  }.value
  for _ in 0..<10 {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
  }
}
