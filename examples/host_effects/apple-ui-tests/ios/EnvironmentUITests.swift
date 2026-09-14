import XCTest

@MainActor
final class EnvironmentUITests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "org.bonsai-swiftui.example.host-effects")
  private var environment: XCUIElement {
    app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Environment: platform=ios|")
    ).firstMatch
  }
  override func setUp() async throws {
    continueAfterFailure = false
    app.launch()
    XCTAssertTrue(environment.waitForExistence(timeout: 15))
  }
  override func tearDown() async throws { app.terminate() }
  private func fields() -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: environment.label.replacingOccurrences(of: "Environment: ", with: "")
        .split(separator: "|").compactMap {
          let values = $0.split(separator: "=", maxSplits: 1).map(String.init)
          return values.count == 2 ? (values[0], values[1]) : nil
        })
  }
  private func waitForKeyboard(_ shown: Bool) async throws {
    for _ in 0..<100 {
      if ((Double(fields()["keyboard"] ?? "") ?? 0) > 0) == shown { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual((Double(fields()["keyboard"] ?? "") ?? 0) > 0, shown)
  }
  func testKeyboardOcclusionReturnsThroughOcamlWithoutShrinkingViewport() async throws {
    let initial = fields()
    XCTAssertEqual(initial["keyboard"], "0")
    XCTAssertGreaterThan(try XCTUnwrap(Double(initial["width"] ?? "")), 0)
    XCTAssertGreaterThan(try XCTUnwrap(Double(initial["height"] ?? "")), 0)
    let input = app.textFields.firstMatch
    for _ in 0..<8 {
      if input.isHittable { break }
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(input.isHittable)
    input.tap()
    XCTAssertTrue(
      app.keyboards.firstMatch.waitForExistence(timeout: 10),
      "This acceptance test requires the device software keyboard")
    try await waitForKeyboard(true)
    XCTAssertEqual(fields()["width"], initial["width"])
    XCTAssertEqual(fields()["height"], initial["height"])
    let clear = app.buttons["Clear focus"]
    for _ in 0..<8 {
      if clear.isHittable { break }
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(clear.isHittable)
    clear.tap()
    try await waitForKeyboard(false)
    XCTAssertEqual(fields()["width"], initial["width"])
    XCTAssertEqual(fields()["height"], initial["height"])
    app.terminate()
    app.launch()
    XCTAssertTrue(environment.waitForExistence(timeout: 15))
    XCTAssertEqual(fields()["keyboard"], "0")
  }
}
