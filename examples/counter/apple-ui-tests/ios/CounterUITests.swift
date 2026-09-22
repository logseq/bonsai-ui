import XCTest

@MainActor
final class CounterUITests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "org.bonsai-swiftui.example.counter")

  override func setUp() async throws {
    continueAfterFailure = false
    app.launch()
    if !incrementButton.waitForExistence(timeout: 15) {
      print(app.debugDescription)
    }
    XCTAssertTrue(incrementButton.waitForExistence(timeout: 5))
  }

  override func tearDown() async throws {
    app.terminate()
  }

  func testIncrementButtonUpdatesOcamlState() throws {
    XCTAssertTrue(app.staticTexts["Count: 0"].waitForExistence(timeout: 10))
    incrementButton.tap()
    XCTAssertTrue(app.staticTexts["Count: 1"].waitForExistence(timeout: 10))
    incrementButton.tap()
    XCTAssertTrue(app.staticTexts["Count: 2"].waitForExistence(timeout: 10))
  }

  private var incrementButton: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label == %@", "Increment")).firstMatch
  }
}
